/* SPDX-License-Identifier: MIT */
/* Checks original reader semantics, not compatibility with an Apple archive. */
#import "AnnotationKit.h"
#import <stdio.h>
#import <stdlib.h>
static void require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr,"FAIL %s\n",message); exit(1); }
}
static BOOL hasUnsupportedError(NSException *exception) {
    NSError *error=[exception.userInfo objectForKey:NSUnderlyingErrorKey];
    return [exception.name isEqualToString:@"SFAnnotationUnsupportedOperation"] &&
        [error isKindOfClass:[NSError class]] && error.code==1 &&
        [error.domain isEqualToString:@"org.siliconforest.AnnotationKit.Unsupported"] &&
        error.localizedDescription.length>0;
}
@interface SFReaderProbe : NSObject<SFAnnotationReaderDelegate>
@property NSUInteger changes, selections;
@end
@implementation SFReaderProbe
- (CGRect)maxPageRectWithPageIndex:(NSUInteger)i forAnnotationController:(AKController *)c { return CGRectMake(0,0,80,60); }
- (CGPoint)convertPoint:(CGPoint)p fromModelToOverlayWithPageIndex:(NSUInteger)i forAnnotationController:(AKController *)c { return p; }
- (double)modelBaseScaleFactorOfPageAtIndex:(NSUInteger)i forAnnotationController:(AKController *)c { return 2; }
- (void)changed:(NSNotification *)n { self.changes++; }
- (void)selected:(NSNotification *)n { self.selections++; }
@end
int main(void) { @autoreleasepool {
    SFReaderProbe *d=[SFReaderProbe new];
    NSNotificationCenter *nc=[NSNotificationCenter defaultCenter];
    [nc addObserver:d selector:@selector(changed:) name:AKAnnotationPropertiesChangedNotification object:nil];
    [nc addObserver:d selector:@selector(selected:) name:AKSelectionChangedNotification object:nil];
    AKRectangularShapeAnnotation *a=[AKRectangularShapeAnnotation new];
    a.rectangle=CGRectMake(10,10,20,20); a.fillColor=[NSColor colorWithDeviceRed:1 green:0 blue:0 alpha:1]; a.strokeColor=nil;
    NSString *uuid=a.UUID;
    [a translateBy:CGPointMake(2,3)];
    require(CGRectEqualToRect(a.drawingBounds,CGRectMake(12,13,20,20)),"translation");
    require([uuid isEqual:a.UUID] && uuid.length>0 && a.isEdited && d.changes==1,"identity/edit notification");
    AKNoteAnnotation *note=[AKNoteAnnotation new]; note.rectangle=CGRectMake(1,2,3,4); note.contents=@"field notes";
    require(![uuid isEqual:note.UUID],"distinct identity");
    AKPageModelController *page=[AKPageModelController new];
    NSMutableArray *input=[NSMutableArray arrayWithObjects:a,note,nil];
    [page sfSetAnnotations:input]; [input removeAllObjects];
    require(page.annotations.count==2,"model owns immutable array");
    [page selectAnnotationsAtIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [page selectAnnotationsAtIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:YES];
    require(page.selectedAnnotations.count==2 && d.selections==3,"extended selection/notifications");
    BOOL rejected=NO;
    @try { [page selectAnnotationsAtIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO]; }
    @catch(NSException *e) { rejected=[e.name isEqual:NSRangeException]; }
    require(rejected && page.selectedAnnotations.count==2,"invalid selection atomicity");
    [page sfSetAnnotations:@[a]];
    require(page.selectedAnnotations.count==1,"removed annotation prunes selection");
    AKController *c=[AKController controllerWithDelegate:d];
    [c.modelController sfSetPageModelControllers:@[page]];
    require([c.modelController pageModelControllerForAnnotation:a]==page && [c.modelController pageModelControllerForPage:1]==nil,"page lookup");
    require([[c.modelController allSelectedAnnotations] count]==1,"selection aggregation");
    require(c.allEditingDisabled && !c.annotationEditingEnabled && !c.supportsFormFill && !c.supportsImageDescriptionEditing,"reader capabilities");
    require([c currentModelBaseScaleFactorForPageAtIndex:0]==2,"delegate scale");
    require(CGRectEqualToRect([c contentAlignedRectForRect:CGRectMake(70,50,20,20) onPageAtIndex:0],CGRectMake(70,50,10,10)),"content bounds intersection");
    [c prepareOverlayAtIndex:0];
    NSView *overlay=[c overlayViewAtIndex:0];
    require(overlay && [c isOverlayViewLoadedAtIndex:0] && !overlay.isOpaque && [overlay hitTest:NSMakePoint(20,20)]==nil,"transparent noninteractive reader overlay");
    [c prepareOverlayAtIndex:0]; require([c overlayViewAtIndex:0]==overlay,"overlay identity");
    [c relinquishOverlayAtIndex:0]; require(![c isOverlayViewLoadedAtIndex:0],"overlay relinquish");
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(NULL,64,64,8,64*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    require(ctx!=NULL,"bitmap context");
    [AKController renderAnnotation:a inContext:ctx];
    unsigned char *actual=CGBitmapContextGetData(ctx);
    require(actual!=NULL,"bitmap readback");
    size_t stride=CGBitmapContextGetBytesPerRow(ctx);
    /* The retained Onyx bitmap exposes top-to-bottom memory rows while
     * Quartz drawing uses the bottom-left document coordinate system. */
    size_t pos=((64-1-20)*stride+20*4);
    fprintf(stderr,"bitmap stride=%zu logical-center=%u,%u,%u,%u\n",
        stride,actual[pos],actual[pos+1],actual[pos+2],actual[pos+3]);
    require(actual[pos]>240 && actual[pos+1]<10 && actual[pos+2]<10 && actual[pos+3]>240,"actual rectangle red pixels");
    require(actual[0]==0 && actual[3]==0,"outside unchanged");
    CGContextRelease(ctx); CGColorSpaceRelease(space);
    NSUInteger errors=0;
    @try { [a dataRepresentation]; } @catch(NSException *e) { if(hasUnsupportedError(e)) errors++; }
    @try { [page archivableRepresentation]; } @catch(NSException *e) { if(hasUnsupportedError(e)) errors++; }
    @try { [c paste:nil]; } @catch(NSException *e) { if(hasUnsupportedError(e)) errors++; }
    @try { c.toolMode=5; } @catch(NSException *e) { if(hasUnsupportedError(e)) errors++; }
    require(errors==4 && c.toolMode==0 && ![c validatePaste:nil],"explicit unsupported, no edit state change");
    [c teardown]; [c teardown]; require(c.delegate==nil,"teardown clears delegate");
    require([AKThoughtBubbleAnnotation isSubclassOfClass:[AKRectangularShapeAnnotation class]] && [AKArrowShapeAnnotation isSubclassOfClass:[AKArrowAnnotation class]],"class hierarchy");
    [nc removeObserver:d];
    puts("ANNOTATIONKIT PASS geometry selection atomicity notifications hierarchy transparent-overlay red-pixels unsupported=4");
} return 0; }
