/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * (IOSURF) VLC's IOSurface route to OpenGL, without VLC: a 420v (NV12 bi-planar) CVPixelBuffer on an IOSurface,
 * made as our VideoToolbox makes its pictures (CVPixelBufferCreate with IOSurface properties) and filled with known
 * Y and CbCr values through CoreVideo's plane addresses, as our VideoToolbox fills them. Both planes are bound as
 * rectangle textures with CGLTexImageIOSurface2D exactly as VLC's cvpx converter binds them (texture unit i, plane
 * i, VLC's format/type pairs), in a context made with VLC's caopengllayer pixel format. Then, per plane:
 *   - the layout CoreVideo and IOSurface each report (plane base, row bytes, element bytes, size);
 *   - glGetTexImage of the texture, compared with the bytes written;
 *   - a shader read-back (sampler2DRect, VLC's swizzles) into an RGBA8 framebuffer, compared per pixel.
 * Arguments: [width height [variant]], variant rg (GL_RED/GL_RG, what VLC picks when GL_ARB_texture_rg is
 * advertised), la (GL_LUMINANCE/GL_LUMINANCE_ALPHA) or both (default). SFIOSURF_CGL names another OpenGL to load.
 * Prints IOSURFNV12 lines; exit status 0 only when every comparison matches.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void *IOSurfaceRef, *CVPixelBufferRef, *CGLContextObj, *CGLPixelFormatObj;
typedef unsigned GLenum, GLuint, GLbitfield;
typedef int GLint, GLsizei;
typedef unsigned char GLboolean;
typedef char GLchar;

#define GL_TEXTURE_RECTANGLE 0x84F5
#define GL_TEXTURE_2D 0x0DE1
#define GL_RED 0x1903
#define GL_RG 0x8227
#define GL_LUMINANCE 0x1909
#define GL_LUMINANCE_ALPHA 0x190A
#define GL_RGBA 0x1908
#define GL_RGBA8 0x8058
#define GL_UNSIGNED_BYTE 0x1401
#define GL_TEXTURE0 0x84C0
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_NEAREST 0x2600
#define GL_LINEAR 0x2601
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_FRAMEBUFFER 0x8D40
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_VERTEX_SHADER 0x8B31
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02
#define GL_EXTENSIONS 0x1F03
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#define GL_TRIANGLE_STRIP 0x0005
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_PACK_ALIGNMENT 0x0D05
#define GL_PACK_ROW_LENGTH 0x0D02
#define GL_TEXTURE_WIDTH 0x1000
#define GL_TEXTURE_HEIGHT 0x1001
#define GL_TEXTURE_INTERNAL_FORMAT 0x1003
#define GL_TEXTURE_RED_SIZE 0x805C
#define GL_TEXTURE_GREEN_SIZE 0x805D
#define GL_TEXTURE_ALPHA_SIZE 0x805F
#define GL_TEXTURE_LUMINANCE_SIZE 0x8060

static void *must(void *lib, const char *name)
{
	void *f = lib ? dlsym(lib, name) : NULL;

	if (f == NULL) {
		printf("IOSURFNV12 missing %s\n", name);
		exit(2);
	}
	return f;
}
#define FN(lib, ret, name, args) ret (*name) args = must(lib, #name)

/* the known picture: a value per pixel that differs between neighbours and between planes */
static uint8_t yAt(int x, int y) { return (uint8_t)(16 + (x * 3 + y * 7) % 220); }
static uint8_t cbAt(int x, int y) { return (uint8_t)(40 + (x * 5 + y * 3) % 170); }
static uint8_t crAt(int x, int y) { return (uint8_t)(200 - (x * 2 + y * 9) % 150); }

int main(int argc, char **argv)
{
	int W = argc > 2 ? atoi(argv[1]) : 1920, H = argc > 2 ? atoi(argv[2]) : 1080;
	const char *variant = argc > 3 ? argv[3] : "both";
	const char *cglPath = getenv("SFIOSURF_CGL");
	void *cv = dlopen("/System/Library/Frameworks/CoreVideo.framework/CoreVideo", RTLD_NOW | RTLD_GLOBAL);
	void *ios = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_NOW | RTLD_GLOBAL);
	void *gl = dlopen(cglPath && *cglPath ? cglPath : "/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL",
	    RTLD_NOW | RTLD_GLOBAL);
	int failures = 0;

	setvbuf(stdout, NULL, _IOLBF, 0);
	if (!cv || !ios || !gl) {
		printf("IOSURFNV12 dlopen %s\n", dlerror());
		return 2;
	}
	FN(cv, int, CVPixelBufferCreate, (CFAllocatorRef, size_t, size_t, uint32_t, CFDictionaryRef, CVPixelBufferRef *));
	FN(cv, IOSurfaceRef, CVPixelBufferGetIOSurface, (CVPixelBufferRef));
	FN(cv, int, CVPixelBufferLockBaseAddress, (CVPixelBufferRef, uint64_t));
	FN(cv, int, CVPixelBufferUnlockBaseAddress, (CVPixelBufferRef, uint64_t));
	FN(cv, void *, CVPixelBufferGetBaseAddressOfPlane, (CVPixelBufferRef, size_t));
	FN(cv, size_t, CVPixelBufferGetBytesPerRowOfPlane, (CVPixelBufferRef, size_t));
	FN(cv, size_t, CVPixelBufferGetWidthOfPlane, (CVPixelBufferRef, size_t));
	FN(cv, size_t, CVPixelBufferGetHeightOfPlane, (CVPixelBufferRef, size_t));
	FN(cv, size_t, CVPixelBufferGetPlaneCount, (CVPixelBufferRef));
	CFStringRef *ioKey = must(cv, "kCVPixelBufferIOSurfacePropertiesKey");
	FN(ios, void *, IOSurfaceGetBaseAddress, (IOSurfaceRef));
	FN(ios, void *, IOSurfaceGetBaseAddressOfPlane, (IOSurfaceRef, size_t));
	FN(ios, size_t, IOSurfaceGetBytesPerRowOfPlane, (IOSurfaceRef, size_t));
	FN(ios, size_t, IOSurfaceGetBytesPerElementOfPlane, (IOSurfaceRef, size_t));
	FN(ios, size_t, IOSurfaceGetWidthOfPlane, (IOSurfaceRef, size_t));
	FN(ios, size_t, IOSurfaceGetHeightOfPlane, (IOSurfaceRef, size_t));
	FN(ios, size_t, IOSurfaceGetPlaneCount, (IOSurfaceRef));
	FN(ios, size_t, IOSurfaceGetAllocSize, (IOSurfaceRef));
	FN(ios, uint32_t, IOSurfaceGetPixelFormat, (IOSurfaceRef));
	FN(gl, int, CGLChoosePixelFormat, (const int *, CGLPixelFormatObj *, int *));
	FN(gl, int, CGLCreateContext, (CGLPixelFormatObj, CGLContextObj, CGLContextObj *));
	FN(gl, int, CGLSetCurrentContext, (CGLContextObj));
	FN(gl, int, CGLTexImageIOSurface2D, (CGLContextObj, GLenum, GLenum, GLsizei, GLsizei, GLenum, GLenum, IOSurfaceRef, GLuint));
	FN(gl, const char *, glGetString, (GLenum));
	FN(gl, GLenum, glGetError, (void));
	FN(gl, void, glGenTextures, (GLsizei, GLuint *));
	FN(gl, void, glBindTexture, (GLenum, GLuint));
	FN(gl, void, glActiveTexture, (GLenum));
	FN(gl, void, glTexParameteri, (GLenum, GLenum, GLint));
	FN(gl, void, glGetTexImage, (GLenum, GLint, GLenum, GLenum, void *));
	FN(gl, void, glGetTexLevelParameteriv, (GLenum, GLint, GLenum, GLint *));
	FN(gl, void, glPixelStorei, (GLenum, GLint));
	FN(gl, void, glTexImage2D, (GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *));
	FN(gl, void, glGenFramebuffers, (GLsizei, GLuint *));
	FN(gl, void, glBindFramebuffer, (GLenum, GLuint));
	FN(gl, void, glFramebufferTexture2D, (GLenum, GLenum, GLenum, GLuint, GLint));
	FN(gl, GLenum, glCheckFramebufferStatus, (GLenum));
	FN(gl, void, glViewport, (GLint, GLint, GLsizei, GLsizei));
	FN(gl, GLuint, glCreateShader, (GLenum));
	FN(gl, void, glShaderSource, (GLuint, GLsizei, const GLchar *const *, const GLint *));
	FN(gl, void, glCompileShader, (GLuint));
	FN(gl, void, glGetShaderiv, (GLuint, GLenum, GLint *));
	FN(gl, void, glGetShaderInfoLog, (GLuint, GLsizei, GLsizei *, GLchar *));
	FN(gl, GLuint, glCreateProgram, (void));
	FN(gl, void, glAttachShader, (GLuint, GLuint));
	FN(gl, void, glLinkProgram, (GLuint));
	FN(gl, void, glGetProgramiv, (GLuint, GLenum, GLint *));
	FN(gl, void, glUseProgram, (GLuint));
	FN(gl, GLint, glGetUniformLocation, (GLuint, const GLchar *));
	FN(gl, void, glUniform1i, (GLint, GLint));
	FN(gl, void, glBegin, (GLenum));
	FN(gl, void, glEnd, (void));
	FN(gl, void, glVertex2f, (float, float));
	FN(gl, void, glClearColor, (float, float, float, float));
	FN(gl, void, glClear, (GLbitfield));
	FN(gl, void, glReadPixels, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *));
	FN(gl, void, glFinish, (void));
	void (*stats)(uint64_t[4]) = dlsym(gl, "CGLSFFXTransferStats");

	/* the picture, as our VideoToolbox makes it */
	CFDictionaryRef empty = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks,
	    &kCFTypeDictionaryValueCallBacks);
	const void *keys[] = { *ioKey }, *values[] = { empty };
	CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks,
	    &kCFTypeDictionaryValueCallBacks);
	CVPixelBufferRef buffer = NULL;
	int status = CVPixelBufferCreate(NULL, (size_t)W, (size_t)H, 0x34323076 /* 420v */, attributes, &buffer);
	IOSurfaceRef surface = buffer ? CVPixelBufferGetIOSurface(buffer) : NULL;

	if (status != 0 || surface == NULL) {
		printf("IOSURFNV12 no surface: CVPixelBufferCreate %d surface %p\n", status, surface);
		return 3;
	}
	CVPixelBufferLockBaseAddress(buffer, 0);
	uint8_t *cvBase[2], *ioBase = IOSurfaceGetBaseAddress(surface);
	printf("IOSURFNV12 surface %dx%d format %08x planes cv=%zu io=%zu alloc=%zu\n", W, H, IOSurfaceGetPixelFormat(surface),
	    CVPixelBufferGetPlaneCount(buffer), IOSurfaceGetPlaneCount(surface), IOSurfaceGetAllocSize(surface));
	for (size_t p = 0; p < 2; p++) {
		cvBase[p] = CVPixelBufferGetBaseAddressOfPlane(buffer, p);
		uint8_t *io = IOSurfaceGetBaseAddressOfPlane(surface, p);
		printf("IOSURFNV12 plane %zu cv: offset=%td rowbytes=%zu %zux%zu | io: offset=%td rowbytes=%zu element=%zu %zux%zu%s\n", p,
		    cvBase[p] - ioBase, CVPixelBufferGetBytesPerRowOfPlane(buffer, p), CVPixelBufferGetWidthOfPlane(buffer, p),
		    CVPixelBufferGetHeightOfPlane(buffer, p), io - ioBase, IOSurfaceGetBytesPerRowOfPlane(surface, p),
		    IOSurfaceGetBytesPerElementOfPlane(surface, p), IOSurfaceGetWidthOfPlane(surface, p),
		    IOSurfaceGetHeightOfPlane(surface, p), io == cvBase[p] ? "" : "  <-- CoreVideo and IOSurface differ");
		failures += io != cvBase[p];
	}
	size_t cvRow[2] = { CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) };
	int cw = (W + 1) / 2, ch = (H + 1) / 2;
	for (int y = 0; y < H; y++)
		for (int x = 0; x < W; x++)
			cvBase[0][y * cvRow[0] + x] = yAt(x, y);
	for (int y = 0; y < ch; y++)
		for (int x = 0; x < cw; x++) {
			cvBase[1][y * cvRow[1] + 2 * x] = cbAt(x, y);
			cvBase[1][y * cvRow[1] + 2 * x + 1] = crAt(x, y);
		}
	CVPixelBufferUnlockBaseAddress(buffer, 0);

	/* VLC's caopengllayer pixel format */
	int pfa[] = { 96, 5, 73, 72, 8, 24, 11, 8, 12, 24, 0 }, count = 0;
	CGLPixelFormatObj pf = NULL;
	CGLContextObj ctx = NULL;
	status = CGLChoosePixelFormat(pfa, &pf, &count);
	if (!status)
		status = CGLCreateContext(pf, NULL, &ctx);
	if (!status)
		status = CGLSetCurrentContext(ctx);
	if (status || !ctx) {
		printf("IOSURFNV12 context error %d\n", status);
		return 3;
	}
	const char *ext = glGetString(GL_EXTENSIONS);
	printf("IOSURFNV12 gl renderer=\"%s\" version=\"%s\" glsl=\"%s\" ARB_texture_rg=%d ARB_texture_rectangle=%d\n",
	    glGetString(GL_RENDERER), glGetString(GL_VERSION), glGetString(GL_SHADING_LANGUAGE_VERSION),
	    ext && strstr(ext, "GL_ARB_texture_rg") != NULL, ext && strstr(ext, "GL_ARB_texture_rectangle") != NULL);

	uint8_t *got = malloc((size_t)W * H * 4);
	for (int v = 0; v < 2; v++) {
		int rg = v == 0;
		if ((rg && !strcmp(variant, "la")) || (!rg && !strcmp(variant, "rg")))
			continue;
		const char *name = rg ? "rg" : "la";
		GLenum fmt[2] = { rg ? GL_RED : GL_LUMINANCE, rg ? GL_RG : GL_LUMINANCE_ALPHA };
		GLsizei tw[2] = { W, W / 2 }, th[2] = { H, H / 2 };   /* VLC: visible size times the plane's ratio */
		GLuint tex[2];
		uint64_t before[4] = { 0 }, after[4] = { 0 };

		if (stats)
			stats(before);
		while (glGetError() != 0) {
		}
		glGenTextures(2, tex);
		for (int i = 0; i < 2; i++) {
			glBindTexture(GL_TEXTURE_RECTANGLE, tex[i]);
			glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		}
		/* converter_cvpx.c tc_cvpx_update: unit i, plane i, internal = format */
		for (int i = 0; i < 2; i++) {
			glActiveTexture(GL_TEXTURE0 + i);
			glBindTexture(GL_TEXTURE_RECTANGLE, tex[i]);
			int e = CGLTexImageIOSurface2D(ctx, GL_TEXTURE_RECTANGLE, fmt[i], tw[i], th[i], fmt[i], GL_UNSIGNED_BYTE, surface,
			    (GLuint)i);
			GLint w = 0, h = 0, internal = 0, r = 0, g = 0, a = 0, l = 0;
			glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE, 0, GL_TEXTURE_WIDTH, &w);
			glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE, 0, GL_TEXTURE_HEIGHT, &h);
			glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE, 0, GL_TEXTURE_INTERNAL_FORMAT, &internal);
			glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE, 0, GL_TEXTURE_RED_SIZE, &r);
			glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE, 0, GL_TEXTURE_GREEN_SIZE, &g);
			glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE, 0, GL_TEXTURE_ALPHA_SIZE, &a);
			glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE, 0, GL_TEXTURE_LUMINANCE_SIZE, &l);
			printf("IOSURFNV12 %s bind plane %d: CGLTexImageIOSurface2D=%d gl_error=%x texture %dx%d internal=%x sizes r%d g%d a%d l%d\n",
			    name, i, e, glGetError(), w, h, internal, r, g, a, l);
			failures += e != 0;
		}
		if (stats)
			stats(after);
		if (stats)
			printf("IOSURFNV12 %s transfer cpu_upload=%llu gpu_blit=%llu\n", name,
			    (unsigned long long)(after[0] - before[0]), (unsigned long long)(after[2] - before[2]));

		/* 1. the textures' own contents */
		for (int i = 0; i < 2; i++) {
			int channels = i ? 2 : 1, bad = 0, firstX = -1, firstY = -1, wantv = 0, gotv = 0;
			glActiveTexture(GL_TEXTURE0 + i);
			glPixelStorei(GL_PACK_ALIGNMENT, 1);
			glPixelStorei(GL_PACK_ROW_LENGTH, 0);
			memset(got, 0xEE, (size_t)W * H * 4);
			glGetTexImage(GL_TEXTURE_RECTANGLE, 0, fmt[i], GL_UNSIGNED_BYTE, got);
			for (int y = 0; y < th[i]; y++)
				for (int x = 0; x < tw[i] * channels; x++) {
					int want = i == 0 ? yAt(x, y) : (x & 1 ? crAt(x / 2, y) : cbAt(x / 2, y));
					int have = got[(size_t)y * tw[i] * channels + x];
					if (have != want && bad++ == 0) {
						firstX = x, firstY = y, wantv = want, gotv = have;
					}
				}
			printf("IOSURFNV12 %s texture plane %d: %d of %d bytes differ (first at byte %d row %d: want %d got %d) gl_error=%x\n",
			    name, i, bad, tw[i] * th[i] * channels, firstX, firstY, wantv, gotv, glGetError());
			failures += bad != 0;
		}

		/* 2. what a shader samples, with VLC's swizzles: r / rg, or x / xw */
		const char *vs = "#version 120\nvoid main(){gl_Position=gl_Vertex;}\n";
		char fs[1024];
		snprintf(fs, sizeof(fs),
		    "#version 120\nuniform sampler2DRect Texture0;\nuniform sampler2DRect Texture1;\n"
		    "void main(){\n vec2 p=gl_FragCoord.xy;\n vec4 c0=texture2DRect(Texture0,p);\n"
		    " vec4 c1=texture2DRect(Texture1,floor(p*0.5)+0.5);\n gl_FragColor=vec4(c0.%c,c1.%c,c1.%c,1.0);\n}\n",
		    rg ? 'r' : 'x', rg ? 'r' : 'x', rg ? 'g' : 'w');
		GLuint sh[2] = { glCreateShader(GL_VERTEX_SHADER), glCreateShader(GL_FRAGMENT_SHADER) }, prog = glCreateProgram();
		const char *src[2] = { vs, fs };
		for (int i = 0; i < 2; i++) {
			GLint ok = 0;
			char logText[512] = "";
			glShaderSource(sh[i], 1, &src[i], NULL);
			glCompileShader(sh[i]);
			glGetShaderiv(sh[i], GL_COMPILE_STATUS, &ok);
			if (!ok) {
				glGetShaderInfoLog(sh[i], sizeof(logText), NULL, logText);
				printf("IOSURFNV12 %s shader %d: %s\n", name, i, logText);
			}
			glAttachShader(prog, sh[i]);
		}
		GLint linked = 0;
		glLinkProgram(prog);
		glGetProgramiv(prog, GL_LINK_STATUS, &linked);
		GLuint target = 0, fbo = 0;
		glActiveTexture(GL_TEXTURE0 + 2);
		glGenTextures(1, &target);
		glBindTexture(GL_TEXTURE_2D, target);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, target, 0);
		GLenum complete = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		glViewport(0, 0, W, H);
		glClearColor(1, 0, 1, 1);
		glClear(GL_COLOR_BUFFER_BIT);
		glUseProgram(prog);
		glUniform1i(glGetUniformLocation(prog, "Texture0"), 0);
		glUniform1i(glGetUniformLocation(prog, "Texture1"), 1);
		glBegin(GL_TRIANGLE_STRIP);
		glVertex2f(-1, -1);
		glVertex2f(1, -1);
		glVertex2f(-1, 1);
		glVertex2f(1, 1);
		glEnd();
		glFinish();
		memset(got, 0xEE, (size_t)W * H * 4);
		glPixelStorei(GL_PACK_ALIGNMENT, 1);
		glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, got);
		long bad[3] = { 0, 0, 0 }, sum[3] = { 0, 0, 0 };
		int first[3][4];
		for (int c = 0; c < 3; c++)
			first[c][0] = -1;
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++) {
				uint8_t *px = got + ((size_t)y * W + x) * 4;
				int want[3] = { yAt(x, y), cbAt(x / 2, y / 2), crAt(x / 2, y / 2) };
				for (int c = 0; c < 3; c++) {
					sum[c] += px[c];
					if (px[c] != want[c] && bad[c]++ == 0) {
						first[c][0] = x, first[c][1] = y, first[c][2] = want[c], first[c][3] = px[c];
					}
				}
			}
		printf("IOSURFNV12 %s shader linked=%d fbo=%x gl_error=%x: Y %ld differ (mean %.1f), Cb %ld differ (mean %.1f), Cr %ld differ (mean %.1f) of %d pixels\n",
		    name, linked, complete, glGetError(), bad[0], sum[0] / (double)(W * H), bad[1], sum[1] / (double)(W * H), bad[2],
		    sum[2] / (double)(W * H), W * H);
		for (int c = 0; c < 3; c++)
			if (first[c][0] >= 0)
				printf("IOSURFNV12 %s shader first %s difference at %d,%d: want %d got %d\n", name, (const char *[]){ "Y", "Cb", "Cr" }[c],
				    first[c][0], first[c][1], first[c][2], first[c][3]);
		failures += bad[0] != 0 || bad[1] != 0 || bad[2] != 0 || !linked || complete != GL_FRAMEBUFFER_COMPLETE;
		glUseProgram(0);
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}
	printf("IOSURFNV12 failures=%d\n", failures);
	return failures ? 1 : 0;
}
