// VideoToolbox.c - decompression sessions on the Apple Video Decoder (and in software)
// SPDX-License-Identifier: MPL-2.0 OR BSD-2-Clause
//
// Replaces src/Frameworks/VideoToolbox/VideoToolbox.c of the SiliconForest tree ("sessions over
// the codecs this system has, which is none"). A decompression session is a libavcodec
// decoder: with the `sfavd` hwaccel (the hardware decoder through /dev/sfavd) when the device
// is there and the stream is one it decodes, otherwise libavcodec's software decoder. The
// compression side is unchanged: there is no encoder.
//
// What a session takes: CMSampleBuffers of one sample each, the sample in the stream's
// length-prefixed form (avcC / hvcC framing for H.264 and HEVC), with a format description
// made by CMVideoFormatDescriptionCreate and the sample description atom ("avcC", "hvcC")
// in its SampleDescriptionExtensionAtoms. What it gives: CVPixelBuffers,
// kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ('420v') or ...FullRange ('420f') as the
// stream says (or the planar 'y420'/'f420' when the destination attributes ask for it), with
// the colour attachments of the stream, the picture copied out of the decoder's buffer.
//
// Order of the output: with the hardware decoder every picture is handed to the callback as
// soon as it is decoded, in decode order, inside the DecodeFrame call of its sample, as
// Apple's decoder does (callers reorder by presentation time). FinishDelayedFrames and
// WaitForAsynchronousFrames then have nothing to wait for.
//
// Differences from Apple's implementation that a caller can see:
//   - the software decoder (no /dev/sfavd, or a stream the hardware does not take) gives
//     H.264 and HEVC pictures in presentation order, after the decoder's reordering delay,
//     each with the sourceFrameRefCon and times of its own sample; the pictures it still
//     holds come out with FinishDelayedFrames, after which decoding continues only from the
//     next key frame.
//   - the callback always runs on the thread that calls into the session.
//   - the picture is copied into the pixel buffer. The buffer is an IOSurface when the
//     destination attributes carry kCVPixelBufferIOSurfacePropertiesKey, or ask for GL, GLES,
//     Metal or Core Animation texture compatibility, and CoreVideo can make one; plain memory
//     otherwise (Apple's are always IOSurfaces).
//
// Links FFmpeg (LGPL-2.1-or-later) statically; build-videotoolbox.nix has the recipe to
// relink it.

#include <CoreFoundation/CFRuntime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CMSampleBuffer.h>
#include <CoreVideo/CVPixelBuffer.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_sfavd.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>

#include "VideoToolbox.h"

typedef struct OpaqueVTCompressionSession *VTCompressionSessionRef;
typedef uint32_t VTEncodeInfoFlags;
enum { kVTCouldNotFindVideoEncoderErr = -12908 };

#define KEY(name) const CFStringRef name = CFSTR(#name);
KEY(kVTCompressionPropertyKey_AllowFrameReordering)
KEY(kVTCompressionPropertyKey_AverageBitRate)
KEY(kVTCompressionPropertyKey_BaseLayerFrameRateFraction)
KEY(kVTCompressionPropertyKey_ConstantBitRate)
KEY(kVTCompressionPropertyKey_ColorPrimaries)
KEY(kVTCompressionPropertyKey_ExpectedFrameRate)
KEY(kVTCompressionPropertyKey_MaxFrameDelayCount)
KEY(kVTCompressionPropertyKey_MaxKeyFrameInterval)
KEY(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality)
KEY(kVTCompressionPropertyKey_ProfileLevel)
KEY(kVTCompressionPropertyKey_RealTime)
KEY(kVTCompressionPropertyKey_TransferFunction)
KEY(kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder)
KEY(kVTCompressionPropertyKey_YCbCrMatrix)
KEY(kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder)
KEY(kVTDecompressionPropertyKey_RealTime)
KEY(kVTDecompressionPropertyKey_ThreadCount)
KEY(kVTEncodeFrameOptionKey_ForceKeyFrame)
KEY(kVTProfileLevel_H264_Baseline_AutoLevel)
KEY(kVTProfileLevel_H264_Main_AutoLevel)
KEY(kVTProfileLevel_H264_High_AutoLevel)
KEY(kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder)
KEY(kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder)
KEY(kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder)
KEY(kVTVideoEncoderSpecification_EnableLowLatencyRateControl)
KEY(kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder)

// ---- the session ---------------------------------------------------------------------------

// what belongs to one sample on its way through the decoder (AVPacket.opaque_ref)
struct SampleInfo {
    void *refCon;
    CMTime pts, duration;
    VTDecodeFrameFlags flags;
};

struct OpaqueVTDecompressionSession {
    CFRuntimeBase base;
    pthread_mutex_t lock;
    AVCodecContext *avctx;
    AVBufferRef *device;                 // the sfavd device, NULL for software
    AVPacket *packet;
    AVFrame *frame, *software;
    VTDecompressionOutputCallbackRecord callback;
    CMVideoFormatDescriptionRef format;
    OSType wanted;                       // pixel format asked for, 0: bi-planar as the stream says
    CFDictionaryRef surface;             // { IOSurfaceProperties: ... } when the caller asked for IOSurfaces
    Boolean hardware;                    // the decoder chose the hardware format
    Boolean direct;                      // hardware pictures are emitted as they are decoded
    Boolean invalid;
    uint64_t decoded, emitted;
    Boolean timing;                      // VT_AVD_TIMING=1: where the time goes, printed at teardown
    uint64_t send_us, create_us, copy_us, callback_us;
};

static void picture_decoded(void *opaque, const AVFrame *frame);

static uint64_t now_us(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000u + ts.tv_nsec / 1000;
}

static CFTypeID sSessionID;
static pthread_once_t sSessionOnce = PTHREAD_ONCE_INIT;

static void session_teardown(VTDecompressionSessionRef s)
{
    if (s->timing && s->emitted)
        fprintf(stderr, "VT_AVD_TIMING pictures %llu hardware %d per picture: decoder %llu us, pixel buffer create %llu us, "
                "copy %llu us, caller's callback %llu us\n", (unsigned long long)s->emitted, (int)s->hardware,
                (unsigned long long)((s->send_us - s->create_us - s->copy_us - s->callback_us) / s->emitted),
                (unsigned long long)(s->create_us / s->emitted), (unsigned long long)(s->copy_us / s->emitted),
                (unsigned long long)(s->callback_us / s->emitted));
    s->timing = false;
    if (s->avctx)
        avcodec_free_context(&s->avctx);
    av_buffer_unref(&s->device);
    av_packet_free(&s->packet);
    av_frame_free(&s->frame);
    av_frame_free(&s->software);
    if (s->format) {
        CFRelease(s->format);
        s->format = NULL;
    }
    if (s->surface) {
        CFRelease(s->surface);
        s->surface = NULL;
    }
}

static void session_finalize(CFTypeRef cf)
{
    VTDecompressionSessionRef s = (VTDecompressionSessionRef)cf;

    session_teardown(s);
    pthread_mutex_destroy(&s->lock);
}

static const CFRuntimeClass sSessionClass = { 0, "VTDecompressionSession", NULL, NULL, session_finalize, NULL, NULL, NULL, NULL };

static void session_register(void)
{
    sSessionID = _CFRuntimeRegisterClass(&sSessionClass);
}

CFTypeID VTDecompressionSessionGetTypeID(void)
{
    pthread_once(&sSessionOnce, session_register);
    return sSessionID;
}

static Boolean is_session(CFTypeRef cf)
{
    return cf != NULL && CFGetTypeID(cf) == VTDecompressionSessionGetTypeID();
}

static enum AVCodecID codec_of(CMVideoCodecType type)
{
    switch (type) {
    case kCMVideoCodecType_H264: return AV_CODEC_ID_H264;
    case 'avc3': return AV_CODEC_ID_H264;
    case kCMVideoCodecType_HEVC: return AV_CODEC_ID_HEVC;
    case 'hev1': return AV_CODEC_ID_HEVC;
    case kCMVideoCodecType_VP9: return AV_CODEC_ID_VP9;
    default: return AV_CODEC_ID_NONE;
    }
}

// the hardware decoder, when this system has one that answers
static AVBufferRef *open_device(void)
{
    enum AVHWDeviceType type = av_hwdevice_find_type_by_name("sfavd");
    AVBufferRef *device = NULL;

    if (type == AV_HWDEVICE_TYPE_NONE || av_hwdevice_ctx_create(&device, type, NULL, NULL, 0) < 0)
        return NULL;
    return device;
}

static Boolean codec_has_hardware(const AVCodec *codec)
{
    enum AVHWDeviceType type = av_hwdevice_find_type_by_name("sfavd");

    for (int i = 0; type != AV_HWDEVICE_TYPE_NONE; i++) {
        const AVCodecHWConfig *config = avcodec_get_hw_config(codec, i);
        if (config == NULL)
            break;
        if (config->device_type == type && (config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX))
            return true;
    }
    return false;
}

Boolean VTIsHardwareDecodeSupported(CMVideoCodecType codecType)
{
    const AVCodec *codec = avcodec_find_decoder(codec_of(codecType));
    AVBufferRef *device;

    if (codec == NULL || !codec_has_hardware(codec))
        return false;
    device = open_device();
    if (device == NULL)
        return false;
    av_buffer_unref(&device);
    return true;
}

// VP9 is decoded like the others; there is nothing to register
void VTRegisterSupplementalVideoDecoderIfAvailable(CMVideoCodecType codecType)
{
    (void)codecType;
}

static enum AVPixelFormat choose_format(AVCodecContext *avctx, const enum AVPixelFormat *formats)
{
    VTDecompressionSessionRef s = avctx->opaque;
    enum AVPixelFormat hw = av_get_pix_fmt("sfavd");

    s->hardware = false;
    if (s->device != NULL && hw != AV_PIX_FMT_NONE) {
        for (const enum AVPixelFormat *f = formats; *f != AV_PIX_FMT_NONE; f++) {
            if (*f == hw) {
                s->hardware = true;
                return hw;
            }
        }
    }
    for (const enum AVPixelFormat *f = formats; *f != AV_PIX_FMT_NONE; f++) {
        const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(*f);
        if (desc != NULL && !(desc->flags & AV_PIX_FMT_FLAG_HWACCEL))
            return *f;
    }
    return AV_PIX_FMT_NONE;
}

static Boolean dictionary_true(CFDictionaryRef d, CFStringRef key)
{
    CFTypeRef v = d ? CFDictionaryGetValue(d, key) : NULL;

    return v != NULL && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
}

// (IOSURF) Apple's decoder always hands out IOSurface-backed pixel buffers. A caller that asks
// for buffers it can make GL, GLES, Metal or Core Animation textures from, without naming
// kCVPixelBufferIOSurfacePropertiesKey, reads them with CVPixelBufferGetIOSurface, which plain
// memory cannot answer: VLC (kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey) got NULL,
// CGLTexImageIOSurface2D refused it and the picture stayed green. Such a request gets an
// IOSurface too. The keys are looked up by name, so a CoreVideo without one of them is fine.
static Boolean wants_texture_surface(CFDictionaryRef attributes)
{
    static const char *const names[] = {
        "kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey", "kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey",
        "kCVPixelBufferIOSurfaceOpenGLESTextureCompatibilityKey", "kCVPixelBufferIOSurfaceOpenGLESFBOCompatibilityKey",
        "kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey", "kCVPixelBufferOpenGLCompatibilityKey",
        "kCVPixelBufferOpenGLESCompatibilityKey", "kCVPixelBufferMetalCompatibilityKey",
    };

    if (attributes == NULL)
        return false;
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        const CFStringRef *key = dlsym(RTLD_DEFAULT, names[i]);

        if (key != NULL && *key != NULL && dictionary_true(attributes, *key))
            return true;
    }
    return false;
}

OSStatus VTDecompressionSessionCreate(CFAllocatorRef allocator, CMVideoFormatDescriptionRef format,
                                      CFDictionaryRef specification, CFDictionaryRef destinationAttributes,
                                      const VTDecompressionOutputCallbackRecord *outputCallback,
                                      VTDecompressionSessionRef *sessionOut)
{
    VTDecompressionSessionRef s;
    const AVCodec *codec;
    CMVideoDimensions size;
    CFDictionaryRef atoms;
    CFTypeRef wanted;
    Boolean require, enable = true;
    CFTypeRef flag;

    if (sessionOut == NULL || format == NULL)
        return kVTParameterErr;
    *sessionOut = NULL;
    codec = avcodec_find_decoder(codec_of(CMFormatDescriptionGetMediaSubType(format)));
    if (codec == NULL)
        return kVTCouldNotFindVideoDecoderErr;
    require = dictionary_true(specification, kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder);
    // hardware is used when it is there, unless the caller says no (Enable... = false)
    flag = specification ? CFDictionaryGetValue(specification, kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder) : NULL;
    if (flag != NULL && CFGetTypeID(flag) == CFBooleanGetTypeID() && !CFBooleanGetValue(flag) && !require)
        enable = false;

    s = (VTDecompressionSessionRef)_CFRuntimeCreateInstance(allocator, VTDecompressionSessionGetTypeID(),
                                                             sizeof(*s) - sizeof(CFRuntimeBase), NULL);
    if (s == NULL)
        return kVTAllocationFailedErr;
    memset((char *)s + sizeof(CFRuntimeBase), 0, sizeof(*s) - sizeof(CFRuntimeBase));
    pthread_mutex_init(&s->lock, NULL);
    s->timing = getenv("VT_AVD_TIMING") != NULL;
    if (outputCallback)
        s->callback = *outputCallback;
    s->format = (CMVideoFormatDescriptionRef)CFRetain(format);

    // the pixel format asked for: one type, or the first of an array that this can make
    wanted = destinationAttributes ? CFDictionaryGetValue(destinationAttributes, kCVPixelBufferPixelFormatTypeKey) : NULL;
    if (wanted != NULL) {
        CFIndex n = CFGetTypeID(wanted) == CFArrayGetTypeID() ? CFArrayGetCount(wanted) : 1;
        Boolean any = false;

        for (CFIndex i = 0; i < n && !any; i++) {
            CFTypeRef one = CFGetTypeID(wanted) == CFArrayGetTypeID() ? CFArrayGetValueAtIndex(wanted, i) : wanted;
            int32_t type = 0;

            if (one == NULL || CFGetTypeID(one) != CFNumberGetTypeID() || !CFNumberGetValue(one, kCFNumberSInt32Type, &type))
                continue;
            switch ((OSType)type) {
            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            case kCVPixelFormatType_420YpCbCr8Planar:
            case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
                s->wanted = (OSType)type;
                any = true;
                break;
            default:
                break;
            }
        }
        if (!any) {
            CFRelease(s);
            return kVTCouldNotFindVideoDecoderErr;
        }
    }

    // IOSurface-backed pixel buffers when the caller asks for them (kCVPixelBufferIOSurfacePropertiesKey)
    if (destinationAttributes != NULL && CFDictionaryContainsKey(destinationAttributes, kCVPixelBufferIOSurfacePropertiesKey)) {
        const void *key = kCVPixelBufferIOSurfacePropertiesKey;
        const void *value = CFDictionaryGetValue(destinationAttributes, kCVPixelBufferIOSurfacePropertiesKey);

        s->surface = CFDictionaryCreate(NULL, &key, &value, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    } else if (wants_texture_surface(destinationAttributes)) {
        const void *key = kCVPixelBufferIOSurfacePropertiesKey;
        CFDictionaryRef none = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        const void *value = none;

        s->surface = CFDictionaryCreate(NULL, &key, &value, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(none);
    }

    s->avctx = avcodec_alloc_context3(codec);
    s->packet = av_packet_alloc();
    s->frame = av_frame_alloc();
    s->software = av_frame_alloc();
    if (s->avctx == NULL || s->packet == NULL || s->frame == NULL || s->software == NULL) {
        CFRelease(s);
        return kVTAllocationFailedErr;
    }
    size = CMVideoFormatDescriptionGetDimensions(format);
    s->avctx->width = size.width;
    s->avctx->height = size.height;
    s->avctx->opaque = s;
    s->avctx->get_format = choose_format;
    s->avctx->flags |= AV_CODEC_FLAG_COPY_OPAQUE;
    s->avctx->thread_count = 1;
    s->avctx->pkt_timebase = (AVRational){ 1, 1000000 };

    // the sample description atom is the decoder's extradata
    atoms = CMFormatDescriptionGetExtension(format, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
    if (atoms != NULL && CFGetTypeID(atoms) == CFDictionaryGetTypeID()) {
        static const char *const names[] = { "avcC", "hvcC", "vpcC" };

        for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
            CFStringRef key = CFStringCreateWithCString(NULL, names[i], kCFStringEncodingASCII);
            CFTypeRef atom = key ? CFDictionaryGetValue(atoms, key) : NULL;

            if (key)
                CFRelease(key);
            if (atom == NULL || CFGetTypeID(atom) != CFDataGetTypeID() || i == 2)
                continue;       // vpcC carries nothing the VP9 decoder needs
            s->avctx->extradata_size = (int)CFDataGetLength(atom);
            s->avctx->extradata = av_mallocz(s->avctx->extradata_size + AV_INPUT_BUFFER_PADDING_SIZE);
            if (s->avctx->extradata == NULL) {
                CFRelease(s);
                return kVTAllocationFailedErr;
            }
            memcpy(s->avctx->extradata, CFDataGetBytePtr(atom), s->avctx->extradata_size);
            break;
        }
    }

    if (enable && codec_has_hardware(codec)) {
        s->device = open_device();
        if (s->device != NULL) {
            // the first field of the device's context is the library handle, then the hook
            AVHWDeviceContext *device = (AVHWDeviceContext *)s->device->data;
            AVPDAVDDeviceContext *avd = device->hwctx;

            // VP9 has no reordering and shows frames it does not decode: its pictures are
            // taken from the decoder's output instead
            s->direct = codec->id != AV_CODEC_ID_VP9;
            avd->picture_decoded = picture_decoded;
            avd->picture_decoded_opaque = s;
            s->avctx->hw_device_ctx = av_buffer_ref(s->device);
        }
    }
    if (s->device == NULL && require) {
        CFRelease(s);
        return kVTCouldNotFindVideoDecoderErr;
    }
    if (avcodec_open2(s->avctx, codec, NULL) < 0) {
        CFRelease(s);
        return kVTCouldNotCreateInstanceErr;
    }
    *sessionOut = s;
    return noErr;
}

static void set_attachment(CVPixelBufferRef buffer, CFStringRef key, CFStringRef value)
{
    if (value != NULL)
        CVBufferSetAttachment(buffer, key, value, kCVAttachmentMode_ShouldPropagate);
}

static void attach_colour(CVPixelBufferRef buffer, const AVFrame *frame)
{
    CFStringRef v = NULL;

    switch (frame->colorspace) {
    case AVCOL_SPC_BT709: v = kCVImageBufferYCbCrMatrix_ITU_R_709_2; break;
    case AVCOL_SPC_BT470BG:
    case AVCOL_SPC_SMPTE170M: v = kCVImageBufferYCbCrMatrix_ITU_R_601_4; break;
    case AVCOL_SPC_SMPTE240M: v = kCVImageBufferYCbCrMatrix_SMPTE_240M_1995; break;
    case AVCOL_SPC_BT2020_NCL:
    case AVCOL_SPC_BT2020_CL: v = kCVImageBufferYCbCrMatrix_ITU_R_2020; break;
    default: break;
    }
    set_attachment(buffer, kCVImageBufferYCbCrMatrixKey, v);
    v = NULL;
    switch (frame->color_primaries) {
    case AVCOL_PRI_BT709: v = kCVImageBufferColorPrimaries_ITU_R_709_2; break;
    case AVCOL_PRI_BT470BG: v = kCVImageBufferColorPrimaries_EBU_3213; break;
    case AVCOL_PRI_SMPTE170M:
    case AVCOL_PRI_SMPTE240M: v = kCVImageBufferColorPrimaries_SMPTE_C; break;
    case AVCOL_PRI_BT2020: v = kCVImageBufferColorPrimaries_ITU_R_2020; break;
    default: break;
    }
    set_attachment(buffer, kCVImageBufferColorPrimariesKey, v);
    v = NULL;
    switch (frame->color_trc) {
    case AVCOL_TRC_BT709:
    case AVCOL_TRC_SMPTE170M: v = kCVImageBufferTransferFunction_ITU_R_709_2; break;
    case AVCOL_TRC_SMPTE240M: v = kCVImageBufferTransferFunction_SMPTE_240M_1995; break;
    case AVCOL_TRC_IEC61966_2_1: v = kCVImageBufferTransferFunction_sRGB; break;
    case AVCOL_TRC_BT2020_10:
    case AVCOL_TRC_BT2020_12: v = kCVImageBufferTransferFunction_ITU_R_2020; break;
    case AVCOL_TRC_SMPTE2084: v = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ; break;
    case AVCOL_TRC_ARIB_STD_B67: v = kCVImageBufferTransferFunction_ITU_R_2100_HLG; break;
    default: break;
    }
    set_attachment(buffer, kCVImageBufferTransferFunctionKey, v);
}

// ---- memory for pixel buffers -----------------------------------------------------------------
// CVPixelBufferCreate allocates and clears a new block per picture (17 ms for 1920x1080 on
// the M1 in boot av11, five times the decode itself). Pictures of one size follow each other,
// so released blocks are kept and handed out again; the pixel buffer wraps the block
// (CVPixelBufferCreateWithPlanarBytes) and its release callback brings it back.
#define POOL_KEEP 12
static pthread_mutex_t sPoolLock = PTHREAD_MUTEX_INITIALIZER;
static struct { void *block; size_t size; } sPool[POOL_KEEP];

static void *pool_take(size_t size)
{
    void *block = NULL;

    pthread_mutex_lock(&sPoolLock);
    for (int i = 0; i < POOL_KEEP && block == NULL; i++) {
        if (sPool[i].block != NULL && sPool[i].size == size) {
            block = sPool[i].block;
            sPool[i].block = NULL;
        }
    }
    pthread_mutex_unlock(&sPoolLock);
    return block ? block : malloc(size);
}

static void pool_give(void *block, size_t size)
{
    int slot = -1;

    pthread_mutex_lock(&sPoolLock);
    for (int i = 0; i < POOL_KEEP && slot < 0; i++)
        if (sPool[i].block == NULL)
            slot = i;
    if (slot < 0) {
        // full: a block of another size makes room, else this one goes
        for (int i = 0; i < POOL_KEEP && slot < 0; i++)
            if (sPool[i].size != size)
                slot = i;
        if (slot >= 0)
            free(sPool[slot].block);
    }
    if (slot >= 0) {
        sPool[slot].block = block;
        sPool[slot].size = size;
        block = NULL;
    }
    pthread_mutex_unlock(&sPoolLock);
    free(block);
}

static void pool_release(void *refCon, const void *dataPtr, size_t dataSize, size_t numberOfPlanes, const void *planeAddresses[])
{
    (void)refCon;
    (void)numberOfPlanes;
    (void)planeAddresses;
    pool_give((void *)dataPtr, dataSize);
}

// A pixel buffer of this type on pooled memory; NULL when it cannot be made.
static CVPixelBufferRef pooled_buffer(int w, int h, OSType type, Boolean planar)
{
    size_t cw = (size_t)(w + 1) / 2, ch = (size_t)(h + 1) / 2;
    size_t stride = ((size_t)w + 63) & ~(size_t)63, cstride = planar ? ((cw + 63) & ~(size_t)63) : stride;
    size_t planes = planar ? 3 : 2;
    size_t size = stride * h + (planes - 1) * cstride * ch;
    void *base[3];
    size_t pw[3] = { (size_t)w, cw, cw }, ph[3] = { (size_t)h, ch, ch }, bpr[3] = { stride, cstride, cstride };
    CVPixelBufferRef buffer = NULL;
    uint8_t *block = pool_take(size);

    if (block == NULL)
        return NULL;
    base[0] = block;
    base[1] = block + stride * h;
    base[2] = block + stride * h + cstride * ch;
    if (CVPixelBufferCreateWithPlanarBytes(NULL, w, h, type, block, size, planes, base, pw, ph, bpr, pool_release, NULL, NULL,
                                           &buffer) != kCVReturnSuccess || buffer == NULL) {
        pool_give(block, size);
        return NULL;
    }
    return buffer;
}

// The decoded picture as a CVPixelBuffer of the session's format; NULL when it cannot be made.
static CVPixelBufferRef make_image(VTDecompressionSessionRef s, AVFrame *decoded)
{
    AVFrame *frame = decoded;
    Boolean full, planar;
    CVPixelBufferRef buffer = NULL;
    OSType type;
    int w, h, cw, ch;
    uint64_t t0 = s->timing ? now_us() : 0, t1;

    if (decoded->hw_frames_ctx != NULL) {
        // the decoder's own buffer (read-only mapping), viewed as an NV12 frame: one copy, below
        AVHWFramesContext *frames = (AVHWFramesContext *)decoded->hw_frames_ctx->data;
        const AVPDAVDFramesContext *layout = frames->hwctx;
        const AVPDAVDFrame *picture = (const AVPDAVDFrame *)decoded->data[0];

        if (picture == NULL || picture->data == NULL || frames->sw_format != AV_PIX_FMT_NV12)
            return NULL;       // 10 bit and 4:2:2 are not delivered yet
        av_frame_unref(s->software);
        av_frame_copy_props(s->software, decoded);
        s->software->format = AV_PIX_FMT_NV12;
        s->software->width = decoded->width;
        s->software->height = decoded->height;
        s->software->data[0] = (uint8_t *)picture->data;
        s->software->data[1] = (uint8_t *)picture->data + layout->uv_offset;
        s->software->linesize[0] = s->software->linesize[1] = (int)layout->bytesperline;
        frame = s->software;
    }
    if (frame->format != AV_PIX_FMT_NV12 && frame->format != AV_PIX_FMT_YUV420P && frame->format != AV_PIX_FMT_YUVJ420P)
        return NULL;       // 10 bit and 4:2:2 are not delivered yet
    full = frame->color_range == AVCOL_RANGE_JPEG || frame->format == AV_PIX_FMT_YUVJ420P;
    planar = s->wanted == kCVPixelFormatType_420YpCbCr8Planar || s->wanted == kCVPixelFormatType_420YpCbCr8PlanarFullRange;
    type = planar ? (full ? kCVPixelFormatType_420YpCbCr8PlanarFullRange : kCVPixelFormatType_420YpCbCr8Planar)
                  : (full ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
    // the visible picture: the decoder's cropping is applied here
    w = frame->width - (int)frame->crop_left - (int)frame->crop_right;
    h = frame->height - (int)frame->crop_top - (int)frame->crop_bottom;
    if (w <= 0 || h <= 0)
        return NULL;
    // on an IOSurface when asked for and the surface can be made, else in (pooled) plain memory
    if (s->surface == NULL || CVPixelBufferCreate(NULL, w, h, type, s->surface, &buffer) != kCVReturnSuccess || buffer == NULL) {
        buffer = pooled_buffer(w, h, type, planar);
        if (buffer == NULL && (CVPixelBufferCreate(NULL, w, h, type, NULL, &buffer) != kCVReturnSuccess || buffer == NULL))
            return NULL;
    }
    cw = (w + 1) / 2;
    ch = (h + 1) / 2;
    t1 = s->timing ? now_us() : 0;

    CVPixelBufferLockBaseAddress(buffer, 0);
    {
        const uint8_t *sy = frame->data[0] + frame->crop_top * frame->linesize[0] + frame->crop_left;
        uint8_t *dy = CVPixelBufferGetBaseAddressOfPlane(buffer, 0);
        size_t dys = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
        int cx = (int)frame->crop_left / 2, cy = (int)frame->crop_top / 2;

        for (int y = 0; y < h; y++)
            memcpy(dy + y * dys, sy + y * frame->linesize[0], w);
        if (frame->format == AV_PIX_FMT_NV12 && !planar) {
            uint8_t *dc = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
            size_t dcs = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
            for (int y = 0; y < ch; y++)
                memcpy(dc + y * dcs, frame->data[1] + (y + cy) * frame->linesize[1] + 2 * cx, 2 * cw);
        } else if (frame->format == AV_PIX_FMT_NV12) {
            uint8_t *du = CVPixelBufferGetBaseAddressOfPlane(buffer, 1), *dv = CVPixelBufferGetBaseAddressOfPlane(buffer, 2);
            size_t dus = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1), dvs = CVPixelBufferGetBytesPerRowOfPlane(buffer, 2);
            for (int y = 0; y < ch; y++) {
                const uint8_t *sc = frame->data[1] + (y + cy) * frame->linesize[1] + 2 * cx;
                for (int x = 0; x < cw; x++) {
                    du[y * dus + x] = sc[2 * x];
                    dv[y * dvs + x] = sc[2 * x + 1];
                }
            }
        } else if (!planar) {
            uint8_t *dc = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
            size_t dcs = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
            for (int y = 0; y < ch; y++) {
                const uint8_t *su = frame->data[1] + (y + cy) * frame->linesize[1] + cx;
                const uint8_t *sv = frame->data[2] + (y + cy) * frame->linesize[2] + cx;
                for (int x = 0; x < cw; x++) {
                    dc[y * dcs + 2 * x] = su[x];
                    dc[y * dcs + 2 * x + 1] = sv[x];
                }
            }
        } else {
            for (int p = 1; p < 3; p++) {
                uint8_t *d = CVPixelBufferGetBaseAddressOfPlane(buffer, p);
                size_t ds = CVPixelBufferGetBytesPerRowOfPlane(buffer, p);
                for (int y = 0; y < ch; y++)
                    memcpy(d + y * ds, frame->data[p] + (y + cy) * frame->linesize[p] + cx, cw);
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    attach_colour(buffer, frame);
    if (s->timing) {
        s->copy_us += now_us() - t1;
        s->create_us += t1 - t0;
    }
    return buffer;
}

// One picture to the callback.
static void emit_one(VTDecompressionSessionRef s, AVFrame *frame)
{
    struct SampleInfo *info = frame->opaque_ref ? (struct SampleInfo *)frame->opaque_ref->data : NULL;
    CVPixelBufferRef image = NULL;
    OSStatus status = noErr;

    if (info == NULL || !(info->flags & kVTDecodeFrame_DoNotOutputFrame)) {
        image = make_image(s, frame);
        if (image == NULL)
            status = kVTVideoDecoderUnsupportedDataFormatErr;
    }
    s->emitted++;
    if (s->callback.decompressionOutputCallback != NULL && info != NULL) {
        uint64_t t0 = s->timing ? now_us() : 0;

        s->callback.decompressionOutputCallback(s->callback.decompressionOutputRefCon, info->refCon, status,
                                                image == NULL && status == noErr ? kVTDecodeInfo_FrameDropped : 0, image,
                                                info->pts, info->duration);
        if (s->timing)
            s->callback_us += now_us() - t0;
    }
    if (image != NULL)
        CVPixelBufferRelease(image);
}

// The hardware decoder finished a picture (libavutil/hwcontext_sfavd.h): decode order.
static void picture_decoded(void *opaque, const AVFrame *frame)
{
    VTDecompressionSessionRef s = opaque;

    if (s->direct)
        emit_one(s, (AVFrame *)frame);
}

// Hands every picture the decoder has ready to the callback. s->lock held.
static OSStatus emit_frames(VTDecompressionSessionRef s)
{
    OSStatus result = noErr;

    for (;;) {
        int ret = avcodec_receive_frame(s->avctx, s->frame);

        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            break;
        if (ret < 0) {
            result = kVTVideoDecoderBadDataErr;
            break;
        }
        // hardware pictures of a direct session went out when they were decoded
        if (!(s->direct && s->frame->hw_frames_ctx != NULL))
            emit_one(s, s->frame);
        av_frame_unref(s->frame);
    }
    return result;
}

static int64_t microseconds(CMTime t)
{
    if (!(t.flags & kCMTimeFlags_Valid) || t.timescale == 0)
        return AV_NOPTS_VALUE;
    return av_rescale(t.value, 1000000, t.timescale);
}

OSStatus VTDecompressionSessionDecodeFrame(VTDecompressionSessionRef s, CMSampleBufferRef sample, VTDecodeFrameFlags flags,
                                           void *sourceFrameRefCon, VTDecodeInfoFlags *infoFlagsOut)
{
    struct SampleInfo *info;
    CMBlockBufferRef data;
    OSStatus status = noErr;
    size_t length;
    uint64_t t0;
    int ret;

    if (infoFlagsOut)
        *infoFlagsOut = 0;
    if (!is_session(s) || s->invalid)
        return kVTInvalidSessionErr;
    data = sample ? CMSampleBufferGetDataBuffer(sample) : NULL;
    length = data ? CMBlockBufferGetDataLength(data) : 0;
    if (length == 0 || length > INT32_MAX / 2)
        return kVTParameterErr;

    pthread_mutex_lock(&s->lock);
    av_packet_unref(s->packet);
    if (av_new_packet(s->packet, (int)length) < 0) {
        pthread_mutex_unlock(&s->lock);
        return kVTAllocationFailedErr;
    }
    if (CMBlockBufferCopyDataBytes(data, 0, length, s->packet->data) != noErr) {
        pthread_mutex_unlock(&s->lock);
        return kVTParameterErr;
    }
    s->packet->opaque_ref = av_buffer_allocz(sizeof(*info));
    if (s->packet->opaque_ref == NULL) {
        pthread_mutex_unlock(&s->lock);
        return kVTAllocationFailedErr;
    }
    info = (struct SampleInfo *)s->packet->opaque_ref->data;
    info->refCon = sourceFrameRefCon;
    info->pts = CMSampleBufferGetPresentationTimeStamp(sample);
    info->duration = CMSampleBufferGetDuration(sample);
    info->flags = flags;
    s->packet->pts = microseconds(info->pts);
    s->packet->dts = microseconds(CMSampleBufferGetDecodeTimeStamp(sample));

    t0 = s->timing ? now_us() : 0;
    ret = avcodec_send_packet(s->avctx, s->packet);
    if (ret == AVERROR(EAGAIN)) {
        // the decoder wants its output taken first
        status = emit_frames(s);
        ret = avcodec_send_packet(s->avctx, s->packet);
    }
    av_packet_unref(s->packet);
    if (ret < 0) {
        // the sample produced nothing: its callback says so, as Apple's decoder does
        if (s->callback.decompressionOutputCallback != NULL)
            s->callback.decompressionOutputCallback(s->callback.decompressionOutputRefCon, sourceFrameRefCon,
                                                    kVTVideoDecoderBadDataErr, kVTDecodeInfo_FrameDropped, NULL,
                                                    CMSampleBufferGetPresentationTimeStamp(sample),
                                                    CMSampleBufferGetDuration(sample));
        status = kVTVideoDecoderBadDataErr;
    } else {
        s->decoded++;
        if (status == noErr)
            status = emit_frames(s);
    }
    if (s->timing)
        s->send_us += now_us() - t0;
    pthread_mutex_unlock(&s->lock);
    return status;
}

// The pictures the software decoder holds back for reordering come out; it then continues
// from the next key frame. A session on the hardware decoder holds nothing back.
OSStatus VTDecompressionSessionFinishDelayedFrames(VTDecompressionSessionRef s)
{
    OSStatus status;

    if (!is_session(s) || s->invalid)
        return kVTInvalidSessionErr;
    pthread_mutex_lock(&s->lock);
    if (s->direct && s->hardware) {
        status = emit_frames(s);
    } else {
        avcodec_send_packet(s->avctx, NULL);
        status = emit_frames(s);
        avcodec_flush_buffers(s->avctx);
    }
    pthread_mutex_unlock(&s->lock);
    return status;
}

// Nothing is decoded asynchronously: every callback has run when DecodeFrame returns.
OSStatus VTDecompressionSessionWaitForAsynchronousFrames(VTDecompressionSessionRef s)
{
    if (!is_session(s) || s->invalid)
        return kVTInvalidSessionErr;
    return noErr;
}

Boolean VTDecompressionSessionCanAcceptFormatDescription(VTDecompressionSessionRef s, CMFormatDescriptionRef format)
{
    if (!is_session(s) || s->invalid || format == NULL)
        return false;
    // the same description, or one that is equal: anything else needs a new session
    return format == (CMFormatDescriptionRef)s->format || CFEqual(format, s->format);
}

void VTDecompressionSessionInvalidate(VTDecompressionSessionRef s)
{
    if (!is_session(s) || s->invalid)
        return;
    pthread_mutex_lock(&s->lock);
    s->invalid = true;
    session_teardown(s);
    pthread_mutex_unlock(&s->lock);
}

OSStatus VTSessionSetProperty(VTSessionRef session, CFStringRef propertyKey, CFTypeRef propertyValue)
{
    (void)propertyValue;
    if (!is_session(session))
        return session ? kVTInvalidSessionErr : kVTParameterErr;
    if (propertyKey != NULL && (CFEqual(propertyKey, kVTDecompressionPropertyKey_RealTime) ||
                                CFEqual(propertyKey, kVTDecompressionPropertyKey_ThreadCount)))
        return noErr;       // accepted; neither changes what this decoder does
    return kVTPropertyNotSupportedErr;
}

OSStatus VTSessionCopyProperty(VTSessionRef session, CFStringRef propertyKey, CFAllocatorRef allocator, void *propertyValueOut)
{
    VTDecompressionSessionRef s = (VTDecompressionSessionRef)session;

    (void)allocator;
    if (propertyValueOut)
        *(CFTypeRef *)propertyValueOut = NULL;
    if (!is_session(session))
        return session ? kVTInvalidSessionErr : kVTParameterErr;
    if (propertyKey != NULL && propertyValueOut != NULL &&
        CFEqual(propertyKey, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder)) {
        // true once the decoder has chosen the hardware format; before the first sample, whether it can
        *(CFTypeRef *)propertyValueOut = CFRetain(s->hardware || (s->decoded == 0 && s->device != NULL) ? kCFBooleanTrue
                                                                                                          : kCFBooleanFalse);
        return noErr;
    }
    return kVTPropertyNotSupportedErr;
}

OSStatus VTSessionCopySupportedPropertyDictionary(VTSessionRef session, CFDictionaryRef *supportedPropertyDictionaryOut)
{
    if (supportedPropertyDictionaryOut)
        *supportedPropertyDictionaryOut = NULL;
    if (!is_session(session))
        return session ? kVTInvalidSessionErr : kVTParameterErr;
    if (supportedPropertyDictionaryOut) {
        const void *keys[] = { kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
                               kVTDecompressionPropertyKey_RealTime, kVTDecompressionPropertyKey_ThreadCount };
        const void *values[] = { kCFBooleanTrue, kCFBooleanTrue, kCFBooleanTrue };

        *supportedPropertyDictionaryOut = CFDictionaryCreate(NULL, keys, values, 3, &kCFTypeDictionaryKeyCallBacks,
                                                             &kCFTypeDictionaryValueCallBacks);
    }
    return noErr;
}

// ---- compression: there is no encoder (as in the tree's VideoToolbox.c) ---------------------

OSStatus VTCompressionSessionCreate(CFAllocatorRef allocator, int32_t width, int32_t height, CMVideoCodecType codecType,
                                    CFDictionaryRef encoderSpecification, CFDictionaryRef sourceImageBufferAttributes,
                                    CFAllocatorRef compressedDataAllocator, const void *outputCallback, void *outputCallbackRefCon,
                                    VTCompressionSessionRef *compressionSessionOut)
{
    (void)allocator;
    (void)codecType;
    (void)encoderSpecification;
    (void)sourceImageBufferAttributes;
    (void)compressedDataAllocator;
    (void)outputCallback;
    (void)outputCallbackRefCon;
    if (compressionSessionOut == NULL || width <= 0 || height <= 0)
        return kVTParameterErr;
    *compressionSessionOut = NULL;
    return kVTCouldNotFindVideoEncoderErr;
}

OSStatus VTCompressionSessionEncodeFrame(VTCompressionSessionRef session, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp,
                                         CMTime duration, CFDictionaryRef frameProperties, void *sourceFrameRefcon,
                                         VTEncodeInfoFlags *infoFlagsOut)
{
    (void)imageBuffer;
    (void)presentationTimeStamp;
    (void)duration;
    (void)frameProperties;
    (void)sourceFrameRefcon;
    if (infoFlagsOut)
        *infoFlagsOut = 0;
    return session ? kVTInvalidSessionErr : kVTParameterErr;
}

OSStatus VTCompressionSessionCompleteFrames(VTCompressionSessionRef session, CMTime completeUntilPresentationTimeStamp)
{
    (void)completeUntilPresentationTimeStamp;
    return session ? kVTInvalidSessionErr : kVTParameterErr;
}

void VTCompressionSessionInvalidate(VTCompressionSessionRef session)
{
    (void)session;
}
