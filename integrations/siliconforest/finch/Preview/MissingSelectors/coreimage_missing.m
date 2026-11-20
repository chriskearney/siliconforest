/* CIKernel, CIColorKernel, CISampler and CICGContext from Finch CoreImage/CIMisc.m.
   The loaded CoreImage image does not export CIContext, so CICGContext is an NSObject
   the way Finch's empty CIContext subclass carries no extra methods of its own.
   Kernel compilation still fails closed: Finch has no Core Image kernel compiler. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#define SF_EXPORT __attribute__((visibility("default")))

@interface CIKernel : NSObject
@end
@implementation CIKernel {
@protected
    NSString *_name;
}
+ (NSArray *)kernelsWithString:(NSString *)string {
    (void)string;
    return nil;
}
+ (NSArray *)kernelsWithMetalString:(NSString *)source error:(NSError **)error {
    if (error)
        *error = [NSError errorWithDomain:@"CIKernel" code:1
                                 userInfo:@{NSLocalizedDescriptionKey : @"Metal kernels aren't available on Finch yet."}];
    (void)source;
    return nil;
}
+ (instancetype)kernelWithString:(NSString *)string {
    (void)string;
    return nil;
}
+ (instancetype)kernelWithFunctionName:(NSString *)name fromMetalLibraryData:(NSData *)data error:(NSError **)error {
    (void)name;
    (void)data;
    return [self kernelsWithMetalString:@"" error:error].firstObject;
}
+ (NSArray *)kernelNamesFromMetalLibraryData:(NSData *)data {
    (void)data;
    return @[];
}
- (void)dealloc {
    [_name release];
    [super dealloc];
}
- (NSString *)name { return _name ?: @""; }
- (void)setROISelector:(SEL)method { (void)method; }
- (id)applyWithExtent:(CGRect)extent roiCallback:(id)callback arguments:(NSArray *)args {
    (void)extent;
    (void)callback;
    (void)args;
    return nil;
}
@end

@interface CIColorKernel : CIKernel
@end
@implementation CIColorKernel
- (id)applyWithExtent:(CGRect)extent arguments:(NSArray *)args {
    (void)extent;
    (void)args;
    return nil;
}
- (id)applyWithExtent:(CGRect)extent roiCallback:(id)callback inputImage:(id)image {
    (void)extent;
    (void)callback;
    (void)image;
    return nil;
}
@end

@interface CIFilterShape : NSObject
+ (instancetype)shapeWithRect:(CGRect)rect;
- (CGRect)extent;
@end
@implementation CIFilterShape {
    CGRect _extent;
}
+ (instancetype)shapeWithRect:(CGRect)r { return [[[self alloc] initWithRect:r] autorelease]; }
- (instancetype)initWithRect:(CGRect)r {
    if ((self = [super init]))
        _extent = r;
    return self;
}
- (CGRect)extent { return _extent; }
- (CIFilterShape *)transformBy:(CGAffineTransform)m interior:(BOOL)flag {
    (void)flag;
    return [CIFilterShape shapeWithRect:CGRectApplyAffineTransform(_extent, m)];
}
- (CIFilterShape *)insetByX:(int)dx Y:(int)dy { return [CIFilterShape shapeWithRect:CGRectInset(_extent, dx, dy)]; }
- (CIFilterShape *)unionWith:(CIFilterShape *)other { return [CIFilterShape shapeWithRect:CGRectUnion(_extent, other.extent)]; }
- (CIFilterShape *)unionWithRect:(CGRect)r { return [CIFilterShape shapeWithRect:CGRectUnion(_extent, r)]; }
- (CIFilterShape *)intersectWith:(CIFilterShape *)other {
    return [CIFilterShape shapeWithRect:CGRectIntersection(_extent, other.extent)];
}
- (CIFilterShape *)intersectWithRect:(CGRect)r { return [CIFilterShape shapeWithRect:CGRectIntersection(_extent, r)]; }
- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}
@end

@interface CISampler : NSObject
@end
@implementation CISampler {
    id _image;
    NSDictionary *_options;
}
+ (instancetype)samplerWithImage:(id)image { return [[[self alloc] initWithImage:image] autorelease]; }
+ (instancetype)samplerWithImage:(id)image options:(NSDictionary *)options {
    return [[[self alloc] initWithImage:image options:options] autorelease];
}
- (instancetype)initWithImage:(id)image { return [self initWithImage:image options:nil]; }
- (instancetype)initWithImage:(id)image options:(NSDictionary *)options {
    if ((self = [super init])) {
        _image = [image retain];
        _options = [options copy];
    }
    return self;
}
- (void)dealloc {
    [_image release];
    [_options release];
    [super dealloc];
}
- (id)image { return _image; }
- (NSDictionary *)options { return _options; }
- (CIFilterShape *)definition {
    CGRect extent = CGRectNull;
    if ([_image respondsToSelector:@selector(extent)]) {
        NSMethodSignature *sig = [_image methodSignatureForSelector:@selector(extent)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:@selector(extent)];
        [inv invokeWithTarget:_image];
        [inv getReturnValue:&extent];
    }
    return [CIFilterShape shapeWithRect:extent];
}
- (CGRect)extent {
    return [[self definition] extent];
}
- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}
@end

/* Finch CICGContext: a context subclass with no methods of its own (CIMisc.m). */
@interface CICGContext : NSObject
@end
@implementation CICGContext
@end

#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>

static NSMutableDictionary *g_sf_filter_ctors = nil;
static void sf_cifilter_register(id self, SEL _cmd, NSString *name, id ctor, NSDictionary *attrs) {
    (void)self; (void)_cmd; (void)attrs;
    if (!name || !ctor) return;
    if (!g_sf_filter_ctors) g_sf_filter_ctors = [[NSMutableDictionary alloc] init];
    [g_sf_filter_ctors setObject:ctor forKey:name];
}

static char kSFCIImageCGKey, kSFCIImagePropsKey;
static void *sf_ciimg_get_cg(id self, SEL _cmd) {
    (void)_cmd;
    NSValue *v = objc_getAssociatedObject(self, &kSFCIImageCGKey);
    return v ? [v pointerValue] : NULL;
}
static id sf_ciimg_init_cg_opts(id self, SEL _cmd, void *cg, NSDictionary *opts) {
    (void)_cmd; (void)opts;
    typedef void *(*fn_ret_t)(void *);
    static fn_ret_t f_ret = NULL;
    if (!f_ret) f_ret = (fn_ret_t)dlsym(RTLD_DEFAULT, "CGImageRetain");
    if (cg) {
        if (f_ret) f_ret(cg);
        objc_setAssociatedObject(self, &kSFCIImageCGKey, [NSValue valueWithPointer:cg], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return self;
}
static id sf_ciimg_init_cg(id self, SEL _cmd, void *cg) {
    return sf_ciimg_init_cg_opts(self, _cmd, cg, nil);
}
static id sf_ciimg_with_cg_opts(id self, SEL _cmd, void *cg, NSDictionary *opts) {
    (void)_cmd;
    if (!cg) return nil;
    id inst = [(Class)self alloc];
    if ([inst respondsToSelector:@selector(initWithCGImage:options:)]) {
        inst = ((id (*)(id, SEL, void *, id))objc_msgSend)(inst, @selector(initWithCGImage:options:), cg, opts);
    } else {
        inst = ((id (*)(id, SEL))objc_msgSend)(inst, @selector(init));
        sf_ciimg_init_cg_opts(inst, _cmd, cg, opts);
    }
    return [inst autorelease];
}
static id sf_ciimg_with_cg(id self, SEL _cmd, void *cg) {
    return sf_ciimg_with_cg_opts(self, _cmd, cg, nil);
}
static id sf_ciimg_init_src(id self, SEL _cmd, void *src, size_t idx, NSDictionary *opts) {
    typedef void *(*fn_src_img_t)(void *, size_t, void *);
    typedef void (*fn_rel_t)(void *);
    static fn_src_img_t f_create = NULL;
    static fn_rel_t f_rel = NULL;
    if (!f_create) {
        f_create = (fn_src_img_t)dlsym(RTLD_DEFAULT, "CGImageSourceCreateImageAtIndex");
        f_rel = (fn_rel_t)dlsym(RTLD_DEFAULT, "CGImageRelease");
    }
    void *cg = (src && f_create) ? f_create(src, idx, NULL) : NULL;
    id r = sf_ciimg_init_cg_opts(self, _cmd, cg, opts);
    if (cg && f_rel) f_rel(cg);
    return r;
}
static CGRect sf_ciimg_extent(id self, SEL _cmd) {
    void *cg = sf_ciimg_get_cg(self, _cmd);
    if (!cg) return CGRectZero;
    typedef size_t (*fn_dim_t)(void *);
    static fn_dim_t f_w, f_h;
    if (!f_w) {
        f_w = (fn_dim_t)dlsym(RTLD_DEFAULT, "CGImageGetWidth");
        f_h = (fn_dim_t)dlsym(RTLD_DEFAULT, "CGImageGetHeight");
    }
    return CGRectMake(0, 0, f_w ? (CGFloat)f_w(cg) : 0, f_h ? (CGFloat)f_h(cg) : 0);
}
static id sf_ciimg_passthrough(id self, SEL _cmd) { (void)_cmd; return self; }
static id sf_ciimg_passthrough1(id self, SEL _cmd, id a) { (void)_cmd; (void)a; return self; }
static id sf_ciimg_passthrough2(id self, SEL _cmd, id a, id b) { (void)_cmd; (void)a; (void)b; return self; }
static id sf_ciimg_passthrough_rect(id self, SEL _cmd, CGRect r) { (void)_cmd; (void)r; return self; }
static id sf_ciimg_passthrough_xf(id self, SEL _cmd, CGAffineTransform t) { (void)_cmd; (void)t; return self; }
static id sf_ciimg_passthrough_ptr(id self, SEL _cmd, void *p) { (void)_cmd; (void)p; return self; }
static id sf_ciimg_props(id self, SEL _cmd) { (void)_cmd; return objc_getAssociatedObject(self, &kSFCIImagePropsKey) ?: @{}; }

static void *sf_cictx_create_cg(id self, SEL _cmd, id ciImg, CGRect rect) {
    (void)self; (void)_cmd; (void)rect;
    if (!ciImg) return NULL;
    void *cg = [ciImg respondsToSelector:@selector(CGImage)] ? ((void *(*)(id, SEL))objc_msgSend)(ciImg, @selector(CGImage)) : sf_ciimg_get_cg(ciImg, _cmd);
    if (cg) {
        typedef void *(*fn_ret_t)(void *);
        static fn_ret_t f_ret = NULL;
        if (!f_ret) f_ret = (fn_ret_t)dlsym(RTLD_DEFAULT, "CGImageRetain");
        if (f_ret) f_ret(cg);
    }
    return cg;
}
static void *sf_cictx_create_cg5(id self, SEL _cmd, id ciImg, CGRect rect, int fmt, void *cs, BOOL def) {
    (void)fmt; (void)cs; (void)def;
    return sf_cictx_create_cg(self, _cmd, ciImg, rect);
}

__attribute__((constructor))
static void sf_install_coreimage_compat(void) {
    Class flt = objc_lookUpClass("CIFilter");
    if (flt) {
        Class meta = object_getClass((id)flt);
        if (meta && !class_respondsToSelector(meta, @selector(registerFilterName:constructor:classAttributes:))) {
            class_addMethod(meta, @selector(registerFilterName:constructor:classAttributes:), (IMP)sf_cifilter_register, "v@:@@@");
        }
    }
    Class img = objc_lookUpClass("CIImage");
    if (img) {
        Class meta = object_getClass((id)img);
        if (meta && !class_respondsToSelector(meta, @selector(imageWithCGImage:)))
            class_addMethod(meta, @selector(imageWithCGImage:), (IMP)sf_ciimg_with_cg, "@@:^v");
        if (meta && !class_respondsToSelector(meta, @selector(imageWithCGImage:options:)))
            class_addMethod(meta, @selector(imageWithCGImage:options:), (IMP)sf_ciimg_with_cg_opts, "@@:^v@");
        if (!class_respondsToSelector(img, @selector(initWithCGImage:)))
            class_addMethod(img, @selector(initWithCGImage:), (IMP)sf_ciimg_init_cg, "@@:^v");
        if (!class_respondsToSelector(img, @selector(initWithCGImage:options:)))
            class_addMethod(img, @selector(initWithCGImage:options:), (IMP)sf_ciimg_init_cg_opts, "@@:^v@");
        if (!class_respondsToSelector(img, @selector(initWithCGImageSource:index:options:)))
            class_addMethod(img, @selector(initWithCGImageSource:index:options:), (IMP)sf_ciimg_init_src, "@@:^vQ@");
        if (!class_respondsToSelector(img, @selector(CGImage)))
            class_addMethod(img, @selector(CGImage), (IMP)sf_ciimg_get_cg, "^v@:");
        if (!class_respondsToSelector(img, @selector(extent)))
            class_addMethod(img, @selector(extent), (IMP)sf_ciimg_extent, "{CGRect={CGPoint=dd}{CGSize=dd}}@:");
        if (!class_respondsToSelector(img, @selector(properties)))
            class_addMethod(img, @selector(properties), (IMP)sf_ciimg_props, "@@:");
        if (!class_respondsToSelector(img, @selector(imageByApplyingFilter:)))
            class_addMethod(img, @selector(imageByApplyingFilter:), (IMP)sf_ciimg_passthrough1, "@@:@");
        if (!class_respondsToSelector(img, @selector(imageByApplyingFilter:withInputParameters:)))
            class_addMethod(img, @selector(imageByApplyingFilter:withInputParameters:), (IMP)sf_ciimg_passthrough2, "@@:@@");
        if (!class_respondsToSelector(img, @selector(imageByApplyingTransform:)))
            class_addMethod(img, @selector(imageByApplyingTransform:), (IMP)sf_ciimg_passthrough_xf, "@@:{CGAffineTransform=dddddd}");
        if (!class_respondsToSelector(img, @selector(imageByCroppingToRect:)))
            class_addMethod(img, @selector(imageByCroppingToRect:), (IMP)sf_ciimg_passthrough_rect, "@@:{CGRect={CGPoint=dd}{CGSize=dd}}");
        if (!class_respondsToSelector(img, @selector(imageByColorMatchingWorkingSpaceToColorSpace:)))
            class_addMethod(img, @selector(imageByColorMatchingWorkingSpaceToColorSpace:), (IMP)sf_ciimg_passthrough_ptr, "@@:^v");
        if (!class_respondsToSelector(img, @selector(imageByPremultiplyingAlpha)))
            class_addMethod(img, @selector(imageByPremultiplyingAlpha), (IMP)sf_ciimg_passthrough, "@@:");
        if (!class_respondsToSelector(img, @selector(imageByUnpremultiplyingAlpha)))
            class_addMethod(img, @selector(imageByUnpremultiplyingAlpha), (IMP)sf_ciimg_passthrough, "@@:");
        if (!class_respondsToSelector(img, @selector(imageByApplyingGainMap:)))
            class_addMethod(img, @selector(imageByApplyingGainMap:), (IMP)sf_ciimg_passthrough1, "@@:@");
    }
    Class ctx = objc_lookUpClass("CIContext");
    if (ctx) {
        if (!class_respondsToSelector(ctx, @selector(createCGImage:fromRect:)))
            class_addMethod(ctx, @selector(createCGImage:fromRect:), (IMP)sf_cictx_create_cg, "^v@:@{CGRect={CGPoint=dd}{CGSize=dd}}");
        if (!class_respondsToSelector(ctx, @selector(createCGImage:fromRect:format:colorSpace:deferred:)))
            class_addMethod(ctx, @selector(createCGImage:fromRect:format:colorSpace:deferred:), (IMP)sf_cictx_create_cg5, "^v@:@{CGRect={CGPoint=dd}{CGSize=dd}}i^vB");
    }
}
