// SPDX-License-Identifier: MIT
#ifndef SF_PREVIEW_ACCESSIBILITY_H
#define SF_PREVIEW_ACCESSIBILITY_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGGeometry.h>

typedef NS_ENUM(NSInteger, AXNumericDataAxisDescriptorScaleType) {
    AXNumericDataAxisDescriptorScaleTypeLinear,
    AXNumericDataAxisDescriptorScaleTypeLog10,
    AXNumericDataAxisDescriptorScaleTypeLn,
};

typedef NS_ENUM(NSInteger, AXChartDescriptorContentDirection) {
    AXChartDescriptorContentDirectionLeftToRight,
    AXChartDescriptorContentDirectionRightToLeft,
    AXChartDescriptorContentDirectionTopToBottom,
    AXChartDescriptorContentDirectionBottomToTop,
};

@protocol AXDataAxisDescriptor <NSObject, NSCopying>
@property(copy) NSString * _Nonnull title;
@property(copy) NSAttributedString * _Nonnull attributedTitle;
@end

@interface AXNumericDataAxisDescriptor : NSObject <AXDataAxisDescriptor>
@property AXNumericDataAxisDescriptorScaleType scaleType;
@property double lowerBound;
@property double upperBound;
@property(copy) NSArray<NSNumber *> * _Nullable gridlinePositions;
@property(copy) NSString * _Nonnull (^ _Nullable valueDescriptionProvider)(double);
- (instancetype _Nullable)initWithTitle:(NSString * _Nonnull)title
                              lowerBound:(double)lowerBound upperBound:(double)upperBound
                       gridlinePositions:(NSArray<NSNumber *> * _Nullable)gridlinePositions
                valueDescriptionProvider:(NSString * _Nonnull (^ _Nullable)(double))provider;
@end

@interface AXCategoricalDataAxisDescriptor : NSObject <AXDataAxisDescriptor>
@property(copy) NSArray<NSString *> * _Nonnull categoryOrder;
- (instancetype _Nullable)initWithTitle:(NSString * _Nonnull)title
                           categoryOrder:(NSArray<NSString *> * _Nonnull)categoryOrder;
@end

@interface AXDataPointValue : NSObject <NSCopying>
@property(readonly) double number;
@property(readonly, copy) NSString * _Nullable category;
+ (instancetype _Nonnull)valueWithNumber:(double)number;
+ (instancetype _Nonnull)valueWithCategory:(NSString * _Nonnull)category;
@end

@interface AXDataPoint : NSObject <NSCopying>
@property(copy) AXDataPointValue * _Nonnull xValue;
@property(copy) AXDataPointValue * _Nullable yValue;
@property(copy) NSArray<AXDataPointValue *> * _Nonnull additionalValues;
@property(copy) NSString * _Nullable label;
@property(copy) NSAttributedString * _Nullable attributedLabel;
- (instancetype _Nullable)initWithX:(AXDataPointValue * _Nonnull)x y:(AXDataPointValue * _Nullable)y;
@end

@interface AXDataSeriesDescriptor : NSObject <NSCopying>
@property(copy) NSString * _Nonnull name;
@property(copy) NSAttributedString * _Nonnull attributedName;
@property BOOL isContinuous;
@property(copy) NSArray<AXDataPoint *> * _Nonnull dataPoints;
- (instancetype _Nullable)initWithName:(NSString * _Nonnull)name isContinuous:(BOOL)continuous
                             dataPoints:(NSArray<AXDataPoint *> * _Nonnull)points;
@end

@interface AXChartDescriptor : NSObject <NSCopying>
@property(copy) NSString * _Nullable title;
@property(copy) NSAttributedString * _Nullable attributedTitle;
@property(copy) NSString * _Nullable summary;
@property(retain) id<AXDataAxisDescriptor> _Nonnull xAxis;
@property(retain) AXNumericDataAxisDescriptor * _Nullable yAxis;
@property(copy) NSArray<id<AXDataAxisDescriptor>> * _Nullable additionalAxes;
@property(copy) NSArray<AXDataSeriesDescriptor *> * _Nonnull series;
@property AXChartDescriptorContentDirection contentDirection;
@property CGRect contentFrame;
- (instancetype _Nullable)initWithTitle:(NSString * _Nullable)title summary:(NSString * _Nullable)summary
                        xAxisDescriptor:(id<AXDataAxisDescriptor> _Nonnull)xAxis
                        yAxisDescriptor:(AXNumericDataAxisDescriptor * _Nullable)yAxis
                         additionalAxes:(NSArray<id<AXDataAxisDescriptor>> * _Nullable)additionalAxes
                                 series:(NSArray<AXDataSeriesDescriptor *> * _Nonnull)series;
@end

@interface AXChartDescriptor (ChartArchive)
- (instancetype _Nullable)initWithDictionary:(NSDictionary * _Nonnull)dictionary;
- (NSDictionary * _Nonnull)dictionaryRepresentation;
@end

typedef NS_ENUM(NSUInteger, AXCustomContentImportance) {
    AXCustomContentImportanceDefault,
    AXCustomContentImportanceHigh,
} __attribute__((swift_name("AXCustomContent.Importance")));

@interface AXCustomContent : NSObject <NSCopying, NSSecureCoding>
@property(readonly, copy) NSString * _Nonnull label;
@property(readonly, copy) NSString * _Nonnull value;
@property(readonly, copy) NSAttributedString * _Nonnull attributedLabel;
@property(readonly, copy) NSAttributedString * _Nonnull attributedValue;
@property AXCustomContentImportance importance;
+ (instancetype _Nonnull)customContentWithLabel:(NSString * _Nonnull)label value:(NSString * _Nonnull)value;
+ (instancetype _Nonnull)customContentWithAttributedLabel:(NSAttributedString * _Nonnull)label
                                         attributedValue:(NSAttributedString * _Nonnull)value;
@end

#endif
