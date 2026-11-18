/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <PDFKit/Numeric.h>
#import <PDFKit/KNumeric.h>
typedef NSString *PDFDocumentAttribute,*PDFDocumentWriteOption,*PDFAnnotationSubtype,*PDFAnnotationKey,*PDFBorderKey;
typedef NSRect PDFRect;
typedef NSPoint PDFPoint;
typedef NSSize PDFSize;
typedef NSInteger PDFDisplayBox,PDFBorderStyle,PDFDocumentPermissions,PDFPrintScalingMode;
typedef NSUInteger PDFAccessPermissions,PDFSelectionGranularity;
typedef NSInteger PDFDisplayMode, PDFDisplayDirection, PDFInterpolationQuality;
typedef NSUInteger PDFAreaOfInterest;
typedef NSEdgeInsets PDFEdgeInsets;
enum {
    kPDFNoArea = 0,
    kPDFInterpolationQualityHigh = 2,
};
@protocol PDFDocumentDelegate <NSObject>
@end
@protocol PDFViewDelegate <NSObject>
@end
@protocol PDFPageOverlayViewProvider <NSObject>
@end
