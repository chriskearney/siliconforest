/* SPDX-License-Identifier: MIT OR Apache-2.0 */
#import "QuickLookReader.h"
#import <AppKit/NSGraphicsContext.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
static void need(BOOL yes,const char *reason) { if (!yes) { fprintf(stderr,"FAIL %s\n",reason);exit(1); } }
extern CGImageRef QLThumbnailImageCreate(CFAllocatorRef,CFURLRef,CGSize,CFDictionaryRef);
extern NSString *const QLSeamlessOpeningDisplayStateTimeKey;
static BOOL readerError(NSException *e) {
    NSError *error=[e.userInfo objectForKey:NSUnderlyingErrorKey];
    return [error.domain isEqual:@"org.siliconforest.QuickLook.Reader"] && error.code>0 && error.localizedDescription.length>0;
}
static void pixels(QLPreviewDocument *doc,NSUInteger page,unsigned channel) {
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(NULL,240,180,8,240*4,cs,kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);need(c!=NULL,"bitmap context");
    need([doc drawPage:page inRect:CGRectMake(0,0,240,180) context:c],"actual page draw");
    const unsigned char *bytes=CGBitmapContextGetData(c);size_t stride=CGBitmapContextGetBytesPerRow(c);const unsigned char *center=bytes+90*stride+120*4;
    printf("page=%lu center=%u,%u,%u,%u\n",(unsigned long)page,center[0],center[1],center[2],center[3]);
    need(center[channel]==255 && center[(channel+1)%3]==0 && center[(channel+2)%3]==0 && center[3]==255,"decoded/rendered exact RGB center");
    CGContextRelease(c);
}
int main(int argc,char **argv) { @autoreleasepool {
    if (argc!=4) return 2;
    need(dlopen(argv[3],RTLD_NOW|RTLD_GLOBAL)!=NULL,"exact retained PDFKit provider loaded");
    need([QLSeamlessOpeningDisplayStatePageKey isEqual:@"DisplayStatePage"] && [QLSeamlessOpeningDisplayStatePasswordKey isEqual:@"DisplayStatePassword"] && [QLSeamlessOpeningDisplayStateContentsEDRStrengthKey isEqual:@"DisplayStateContentsEDRStrength"],"three real data keys");
    need(QLThumbnailImageCreate(NULL,NULL,CGSizeMake(16,16),NULL)==NULL && [QLSeamlessOpeningDisplayStateTimeKey isEqual:@"QLSeamlessOpeningDisplayStateTime"],"preserved baseline thumbnail absence/time key");
    NSURL *imageURL=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    NSURL *pdfURL=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
    need([QLSeamlessDocumentOpener seamlessDocumentOpenerForURL:imageURL]==nil && [QLSeamlessDocumentCloser seamlessDocumentCloserForWindow:nil]==nil,"no seamless service fabricated");
    QLSeamlessDocumentCloser *closer=[QLSeamlessDocumentCloser new];closer.displayState=@{QLSeamlessOpeningDisplayStatePageKey:@2};
    need(!closer.animating && [[closer.displayState objectForKey:QLSeamlessOpeningDisplayStatePageKey] isEqual:@2],"closer metadata only");
    QLPreviewDocument *image=[[QLPreviewDocument alloc] initWithPreviewItem:(id)imageURL forPreviewView:nil];
    need(!image.isLoaded && image.numberOfPages==0,"no pre-load success");[image startLoading];
    need(image.isLoaded && image.numberOfPages==1 && image.bounds.size.width==240 && image.bounds.size.height==180,"real image decode/state");pixels(image,0,0);
    QLPreviewView *view=[[QLPreviewView alloc] initWithFrame:NSMakeRect(0,0,240,180) style:0];
    view.previewItem=(id)pdfURL;need(view.isLoaded && view.numberOfPages==3 && view.needsPageControl,"actual PDF state");
    for (NSUInteger i=0;i<3;i++) { view.currentPage=i;pixels(view.document,i,(unsigned)i); }
    need([[view.document stringForPage:0] length]>0,"actual PDF text");
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,240,180,8,240*4,space,kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);need(context!=NULL,"view bitmap");
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:context flipped:NO]];
    [view drawRect:view.bounds];
    [NSGraphicsContext restoreGraphicsState];
    const unsigned char *bytes=CGBitmapContextGetData(context);size_t stride=CGBitmapContextGetBytesPerRow(context);
    const unsigned char *center=bytes+90*stride+120*4;
    need(center[0]==0 && center[1]==0 && center[2]==255 && center[3]==255,"actual QLPreviewView -> document draw dispatch");
    CGContextRelease(context);
    view.zoomFactor=2;need(view.previewContentFrame.size.width==480,"real zoom geometry");
    NSUInteger errors=0;
    @try { view.currentPage=3; } @catch(NSException *e) { if(readerError(e)) errors++; }
    need(view.currentPage==2,"page rejection preserves valid selection");
    @try { view.zoomFactor=0; } @catch(NSException *e) { if(readerError(e)) errors++; }
    need(view.zoomFactor==2,"zoom rejection preserves valid zoom");
    QLPreviewDocument *remote=[[QLPreviewDocument alloc] initWithPreviewItem:(id)[NSURL URLWithString:@"https://siliconforest.invalid/owned-probe.pdf"] forPreviewView:nil];
    @try { [remote startLoading]; } @catch(NSException *e) { if(readerError(e)) errors++; }
    need(!remote.isLoaded && remote.numberOfPages==0 && remote.isRemote,"remote rejection is not loaded");
    need(errors==3,"explicit unavailable/bounds errors");
    [image invalidate];need(!image.isLoaded && image.numberOfPages==0,"invalidate releases loaded result");
    [view close];need(!view.isLoaded && view.document==nil && view.previewItem==nil,"close clears owned state");
    [image release];[view release];[remote release];[closer release];
    puts("QUICKLOOK READER PASS keys classes real-image PDF-RGB-pages view-draw text page/zoom errors=3 no-seamless-service");
} return 0; }
