// SPDX-License-Identifier: MIT
#import <Accessibility/Accessibility.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        AXCategoricalDataAxisDescriptor *x = [[AXCategoricalDataAxisDescriptor alloc]
            initWithTitle:@"Pages" categoryOrder:@[@"One", @"Two"]];
        AXNumericDataAxisDescriptor *y = [[AXNumericDataAxisDescriptor alloc]
            initWithTitle:@"Zoom" lowerBound:0 upperBound:200 gridlinePositions:@[@0, @100, @200]
            valueDescriptionProvider:nil];
        AXDataPoint *point = [[AXDataPoint alloc] initWithX:[AXDataPointValue valueWithCategory:@"Two"]
                                                       y:[AXDataPointValue valueWithNumber:125]];
        point.label = @"Second page";
        AXDataSeriesDescriptor *series = [[AXDataSeriesDescriptor alloc]
            initWithName:@"PDF zoom" isContinuous:NO dataPoints:@[point]];
        AXChartDescriptor *chart = [[AXChartDescriptor alloc] initWithTitle:@"Preview"
            summary:@"Reading" xAxisDescriptor:x yAxisDescriptor:y additionalAxes:nil series:@[series]];
        chart.contentDirection = AXChartDescriptorContentDirectionRightToLeft;
        chart.contentFrame = CGRectMake(2, 3, 700, 300);
        NSDictionary *archive = [chart dictionaryRepresentation];
        AXChartDescriptor *copy = [[AXChartDescriptor alloc] initWithDictionary:archive];
        AXChartDescriptor *bad = [[AXChartDescriptor alloc] initWithDictionary:@{ @"SFChartVersion": @1 }];
        AXCustomContent *extra = [AXCustomContent customContentWithLabel:@"Pages" value:@"Two"];
        extra.importance = AXCustomContentImportanceHigh;
        BOOL correct = copy && !bad && [copy.title isEqualToString:@"Preview"] &&
            [copy.summary isEqualToString:@"Reading"] && copy.yAxis.upperBound == 200 &&
            copy.contentDirection == AXChartDescriptorContentDirectionRightToLeft &&
            copy.contentFrame.size.width == 700 && [archive isEqual:[copy dictionaryRepresentation]] &&
            [extra.label isEqualToString:@"Pages"] && [extra.value isEqualToString:@"Two"] &&
            extra.importance == AXCustomContentImportanceHigh;
        [bad release];
        [copy release];
        [chart release];
        [series release];
        [point release];
        [y release];
        [x release];
        if (!correct) return 1;
        puts("Accessibility PASS: chart, axes, frame, points, archive validation and custom content");
    }
    return 0;
}
