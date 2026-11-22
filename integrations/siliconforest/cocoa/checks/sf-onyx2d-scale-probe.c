// Probe for Onyx2D 0363+0373 (the guarded install's probe): status 0 only when the Onyx2D loaded draws an image
// at 1.5 times its size through the table resampler and the pictures match the general path's.
//   sf-onyx2d-scale-probe          the check; each reference picture comes from a child run with
//                                  O2_NO_IMAGE_SCALE_FAST_PATH=1 (the general path of the same library):
//     kind 0  opaque image (alpha skipped), interpolation default: within 3 per channel inside the edge pixels
//     kind 1  premultiplied image, every pixel opaque (ChonkCraft's layer read back from GL): within 3
//     kind 2  premultiplied image, alpha 0..255, over a background: within 4
//     kind 0 with interpolation none: left to the general path, so the same picture exactly
//     and a child with O2_IMAGE_TRACE=1 drawing kind 1 must not say "resampled" (the fast path took it)
//   sf-onyx2d-scale-probe bench    also: ms per 1280x778 -> 1920x1167 draw of kind 1, fast and general
// (0374) and the library has O2ImageScaleThreadCount (the bands on threads), and 1280x778 pictures of kinds 1 and 2
// drawn at 1.5 on its threads are the very bytes drawn on one (children with O2_IMAGE_SCALE_THREADS=1 and 4)
//   sf-onyx2d-scale-probe big K    child: a hash of the 1280x778 picture of kind K at 1.5 and ms per draw
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <time.h>
// the CoreGraphics declarations used (the cross toolchain's SDK has no CoreGraphics headers)
typedef struct CGImage *CGImageRef; typedef struct CGContext *CGContextRef; typedef struct CGColorSpace *CGColorSpaceRef;
typedef struct CGDataProvider *CGDataProviderRef; typedef double CGFloat;
typedef struct { CGFloat x,y; } CGPoint; typedef struct { CGFloat width,height; } CGSize; typedef struct { CGPoint origin; CGSize size; } CGRect;
static inline CGRect CGRectMake(CGFloat x,CGFloat y,CGFloat w,CGFloat h){ CGRect r={{x,y},{w,h}}; return r; }
enum { kCGImageAlphaPremultipliedFirst=2, kCGImageAlphaNoneSkipFirst=6, kCGBitmapByteOrder32Little=(2<<12) };
CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void); void CGColorSpaceRelease(CGColorSpaceRef);
CGDataProviderRef CGDataProviderCreateWithData(void *,const void *,size_t,void (*)(void *,const void *,size_t)); void CGDataProviderRelease(CGDataProviderRef);
CGImageRef CGImageCreate(size_t,size_t,size_t,size_t,size_t,CGColorSpaceRef,uint32_t,CGDataProviderRef,const CGFloat *,bool,int32_t);
CGContextRef CGBitmapContextCreate(void *,size_t,size_t,size_t,size_t,CGColorSpaceRef,uint32_t);
void CGContextScaleCTM(CGContextRef,CGFloat,CGFloat); void CGContextSetInterpolationQuality(CGContextRef,int32_t);
void CGContextDrawImage(CGContextRef,CGRect,CGImageRef); void CGContextRelease(CGContextRef);

static CGImageRef makeImage(int w,int h,int kind){
    uint32_t *p=malloc((size_t)w*h*4); unsigned s=12345;
    for(int y=0;y<h;y++) for(int x=0;x<w;x++){ s=s*1103515245u+12345u;
        uint32_t r=(x*7+y*3)&255,g=(x*x+y*5)&255,b=((s>>16)&255),a=255;
        if(((x/5)+(y/3))&1) b=(x*y)&255;
        if(kind==2){ a=(x*11+y*29)&255; if((x+y)%9==0) a=0; if((x*y)%7==0) a=255; r=r*a/255; g=g*a/255; b=b*a/255; }
        p[y*w+x]=(a<<24)|(r<<16)|(g<<8)|b; }
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef dp=CGDataProviderCreateWithData(NULL,p,(size_t)w*h*4,NULL);
    uint32_t info=(kind==0 ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst)|kCGBitmapByteOrder32Little;
    CGImageRef im=CGImageCreate(w,h,8,32,w*4,cs,info,dp,NULL,false,0);
    CGDataProviderRelease(dp); CGColorSpaceRelease(cs); return im;
}
static uint32_t *draw(CGImageRef im,int w,int h,int quality,int reps,double *ms){
    int W=(w*3+1)/2,H=(h*3+1)/2;
    uint32_t *d=malloc((size_t)W*H*4);
    for(int i=0;i<W*H;i++) d[i]=0xFF000000u|((i*37)&255)<<16|((i/W*5)&255)<<8|((i*13)&255);   // an opaque background
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(d,W,H,8,W*4,cs,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if(!c){ fprintf(stderr,"no context\n"); exit(4); }
    CGContextScaleCTM(c,1.5,1.5);
    CGContextSetInterpolationQuality(c,quality);
    struct timespec a,b; clock_gettime(CLOCK_MONOTONIC,&a);
    for(int i=0;i<reps;i++) CGContextDrawImage(c,CGRectMake(0,0,w,h),im);
    clock_gettime(CLOCK_MONOTONIC,&b);
    if(ms) *ms=((b.tv_sec-a.tv_sec)*1e3+(b.tv_nsec-a.tv_nsec)/1e6)/reps;
    CGContextRelease(c); return d;
}
enum { w=64, h=40, W=96, H=60 };
// the picture of a child run (env NAME=1) to compare with; returns NULL on failure
static uint32_t *child(const char *self,const char *env,int kind,int quality,char *err,size_t errlen){
    char ks[8],qs[8]; snprintf(ks,sizeof ks,"%d",kind); snprintf(qs,sizeof qs,"%d",quality);
    int out[2],er[2]; if(pipe(out)||pipe(er)) return NULL;
    fflush(stdout);
    pid_t pid=fork();
    if(pid==0){ dup2(out[1],1); dup2(er[1],2); close(out[0]); close(er[0]); setenv(env,"1",1); execl(self,self,"ref",ks,qs,(char*)NULL); _exit(6); }
    close(out[1]); close(er[1]);
    uint32_t *ref=malloc((size_t)W*H*4); size_t got=0,want=(size_t)W*H*4;
    while(got<want){ ssize_t n=read(out[0],(char*)ref+got,want-got); if(n<=0) break; got+=n; }
    size_t e=0; ssize_t n; while(e+1<errlen && (n=read(er[0],err+e,errlen-1-e))>0) e+=n; err[e]=0;
    close(out[0]); close(er[0]); int st=0; waitpid(pid,&st,0);
    if(got!=want){ printf("the reference run gave %zu of %zu bytes (status %d)\n",got,want,st); free(ref); return NULL; }
    return ref;
}
// the largest difference inside the edge pixels; -1 when the run failed or the picture is the background alone
static int compare(const char *self,int kind,int quality,int *same){
    char err[4096];
    CGImageRef im=makeImage(w,h,kind); uint32_t *fast=draw(im,w,h,quality,1,NULL);
    uint32_t *ref=child(self,"O2_NO_IMAGE_SCALE_FAST_PATH",kind,quality,err,sizeof err);
    if(!ref) return -1;
    int maxin=0,maxedge=0; *same=0;
    for(int y=0;y<H;y++) for(int x=0;x<W;x++){ uint32_t a=fast[y*W+x],b=ref[y*W+x]; int m=0;
        for(int k=0;k<32;k+=8){ int d=abs((int)((a>>k)&255)-(int)((b>>k)&255)); if(d>m) m=d; }
        if(a==b) (*same)++;
        if(x==0||y==0||x==W-1||y==H-1){ if(m>maxedge) maxedge=m; } else if(m>maxin) maxin=m; }
    printf("64x40 at 1.5, kind %d, interpolation %d: identical pixels %d/%d, max channel difference inside %d, on the edge %d\n",kind,quality,*same,W*H,maxin,maxedge);
    return maxin;
}
int main(int argc,char **argv){
    if(argc>1 && strcmp(argv[1],"ref")==0){   // child: the picture to stdout
        int kind=argc>2 ? atoi(argv[2]) : 0,quality=argc>3 ? atoi(argv[3]) : 0;
        CGImageRef im=makeImage(w,h,kind); uint32_t *d=draw(im,w,h,quality,1,NULL);
        fwrite(d,4,(size_t)W*H,stdout); return 0;
    }
    if(argc>1 && strcmp(argv[1],"big")==0){   // child: hash of a big picture and its time
        int kind=argc>2 ? atoi(argv[2]) : 1; double ms;
        CGImageRef im=makeImage(1280,778,kind); uint32_t *d=draw(im,1280,778,0,10,&ms);
        uint64_t hsh=1469598103934665603ull; size_t n=(size_t)1920*1167;
        for(size_t i=0;i<n;i++){ hsh^=d[i]; hsh*=1099511628211ull; }
        printf("%016llx %.2f\n",(unsigned long long)hsh,ms); return 0;
    }
    if(argc>1 && strcmp(argv[1],"gbench")==0){
        CGImageRef big=makeImage(1280,778,1); double g; free(draw(big,1280,778,0,5,&g));
        printf("1280x778 premultiplied at 1.5: general %.2f ms per draw\n",g); return 0;
    }
    if(dlsym(RTLD_DEFAULT,"O2ImageGetDirectBytes")==NULL){ printf("this Onyx2D lacks 0363 (no O2ImageGetDirectBytes)\n"); return 3; }
    int ok=1,same;
    { int m=compare(argv[0],0,0,&same); ok&=(m>=0 && m<=3); }
    { int m=compare(argv[0],1,0,&same); ok&=(m>=0 && m<=3); }
    { int m=compare(argv[0],2,0,&same); ok&=(m>=0 && m<=4); }
    { int m=compare(argv[0],0,1,&same); ok&=(m==0 && same==W*H); }
    char err[4096]; uint32_t *t=child(argv[0],"O2_IMAGE_TRACE",1,0,err,sizeof err);
    int traced=(t==NULL || strstr(err,"resampled")!=NULL);
    printf("a premultiplied image at 1.5 in the normal blend mode: %s\n",traced ? "resampled by the general path" : "taken by the fast path");
    ok&=!traced;
    if(dlsym(RTLD_DEFAULT,"O2ImageScaleThreadCount")==NULL){ printf("this Onyx2D lacks 0374 (no O2ImageScaleThreadCount)\n"); return 3; }
    for(int kind=1;kind<=2;kind++){
        char one[64]="",four[64]="";
        for(int k=0;k<2;k++){
            char cmd[1024]; snprintf(cmd,sizeof cmd,"O2_IMAGE_SCALE_THREADS=%d '%s' big %d",k ? 4 : 1,argv[0],kind);
            FILE *f=popen(cmd,"r"); if(f){ if(!fgets(k ? four : one,64,f)) (k ? four : one)[0]=0; pclose(f); }
        }
        for(char *c=one;*c;c++) if(*c=='\n') *c=0;
        for(char *c=four;*c;c++) if(*c=='\n') *c=0;
        int same=(one[0] && strncmp(one,four,16)==0);
        printf("1280x778 kind %d at 1.5, one thread / four: %.*s / %.*s (ms %s / %s): %s\n",kind,16,one,16,four,
               strlen(one)>17 ? one+17 : "?",strlen(four)>17 ? four+17 : "?",same ? "same bytes" : "DIFFERENT");
        ok&=same;
    }
    if(argc>1 && strcmp(argv[1],"bench")==0){
        CGImageRef big=makeImage(1280,778,1); double f; free(draw(big,1280,778,0,20,&f));
        printf("1280x778 premultiplied at 1.5: fast %.2f ms per draw\n",f); fflush(stdout);
        if(fork()==0){ setenv("O2_NO_IMAGE_SCALE_FAST_PATH","1",1); execl(argv[0],argv[0],"gbench",(char*)NULL); _exit(6); }
        wait(NULL);
    }
    return ok ? 0 : 8;
}
