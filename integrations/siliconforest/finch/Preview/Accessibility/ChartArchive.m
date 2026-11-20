// SPDX-License-Identifier: MIT
#import <Accessibility/Accessibility.h>

static id objectOfClass(NSDictionary *dictionary, NSString *key, Class type) {
    id value = [dictionary objectForKey:key];
    return [value isKindOfClass:type] ? value : nil;
}

static NSDictionary *encodeAxis(id<AXDataAxisDescriptor> axis) {
    if ([(id)axis isKindOfClass:[AXCategoricalDataAxisDescriptor class]]) {
        AXCategoricalDataAxisDescriptor *categories = (AXCategoricalDataAxisDescriptor *)axis;
        return @{ @"title": categories.title, @"categories": categories.categoryOrder };
    }
    if ([(id)axis isKindOfClass:[AXNumericDataAxisDescriptor class]]) {
        AXNumericDataAxisDescriptor *numeric = (AXNumericDataAxisDescriptor *)axis;
        return @{ @"title": numeric.title, @"lower": @(numeric.lowerBound), @"upper": @(numeric.upperBound),
                  @"scale": @(numeric.scaleType), @"grid": numeric.gridlinePositions ?: @[] };
    }
    return nil;
}

static id<AXDataAxisDescriptor> decodeAxis(id raw) {
    if (![raw isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *properties = raw;
    NSString *title = objectOfClass(properties, @"title", [NSString class]);
    if (!title) return nil;
    NSArray *categories = objectOfClass(properties, @"categories", [NSArray class]);
    if (categories) {
        for (id item in categories)
            if (![item isKindOfClass:[NSString class]]) return nil;
        return [[[AXCategoricalDataAxisDescriptor alloc] initWithTitle:title categoryOrder:categories] autorelease];
    }
    NSNumber *lower = objectOfClass(properties, @"lower", [NSNumber class]);
    NSNumber *upper = objectOfClass(properties, @"upper", [NSNumber class]);
    if (!lower || !upper) return nil;
    NSArray *grid = objectOfClass(properties, @"grid", [NSArray class]);
    for (id item in grid)
        if (![item isKindOfClass:[NSNumber class]]) return nil;
    AXNumericDataAxisDescriptor *axis = [[[AXNumericDataAxisDescriptor alloc]
        initWithTitle:title lowerBound:[lower doubleValue] upperBound:[upper doubleValue]
        gridlinePositions:grid valueDescriptionProvider:nil] autorelease];
    axis.scaleType = [objectOfClass(properties, @"scale", [NSNumber class]) integerValue];
    return axis;
}

static id encodeValue(AXDataPointValue *value) {
    if (!value) return nil;
    return value.category ?: (id)@(value.number);
}

static AXDataPointValue *decodeValue(id value) {
    if ([value isKindOfClass:[NSString class]]) return [AXDataPointValue valueWithCategory:value];
    if ([value isKindOfClass:[NSNumber class]]) return [AXDataPointValue valueWithNumber:[value doubleValue]];
    return nil;
}

static NSDictionary *encodePoint(AXDataPoint *point) {
    NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithObject:encodeValue(point.xValue) forKey:@"x"];
    if (point.yValue) [properties setObject:encodeValue(point.yValue) forKey:@"y"];
    if (point.label) [properties setObject:point.label forKey:@"label"];
    NSMutableArray *extra = [NSMutableArray array];
    for (AXDataPointValue *value in point.additionalValues) [extra addObject:encodeValue(value)];
    [properties setObject:extra forKey:@"extra"];
    return properties;
}

static AXDataPoint *decodePoint(id raw) {
    if (![raw isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *properties = raw;
    AXDataPointValue *x = decodeValue([properties objectForKey:@"x"]);
    if (!x) return nil;
    AXDataPoint *point = [[[AXDataPoint alloc] initWithX:x y:decodeValue([properties objectForKey:@"y"])] autorelease];
    point.label = objectOfClass(properties, @"label", [NSString class]);
    NSMutableArray *extra = [NSMutableArray array];
    for (id item in objectOfClass(properties, @"extra", [NSArray class])) {
        AXDataPointValue *value = decodeValue(item);
        if (!value) return nil;
        [extra addObject:value];
    }
    point.additionalValues = extra;
    return point;
}

static NSArray *encodeSeries(NSArray *series) {
    NSMutableArray *result = [NSMutableArray array];
    for (AXDataSeriesDescriptor *item in series) {
        NSMutableArray *points = [NSMutableArray array];
        for (AXDataPoint *point in item.dataPoints) [points addObject:encodePoint(point)];
        [result addObject:@{ @"name": item.name, @"continuous": @(item.isContinuous), @"points": points }];
    }
    return result;
}

static NSArray *decodeSeries(NSArray *series) {
    NSMutableArray *result = [NSMutableArray array];
    for (id raw in series) {
        if (![raw isKindOfClass:[NSDictionary class]]) return nil;
        NSString *name = objectOfClass(raw, @"name", [NSString class]);
        if (!name) return nil;
        NSMutableArray *points = [NSMutableArray array];
        for (id item in objectOfClass(raw, @"points", [NSArray class])) {
            AXDataPoint *point = decodePoint(item);
            if (!point) return nil;
            [points addObject:point];
        }
        BOOL continuous = [objectOfClass(raw, @"continuous", [NSNumber class]) boolValue];
        AXDataSeriesDescriptor *item = [[[AXDataSeriesDescriptor alloc]
            initWithName:name isContinuous:continuous dataPoints:points] autorelease];
        [result addObject:item];
    }
    return result;
}

@implementation AXChartDescriptor (ChartArchive)

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    id<AXDataAxisDescriptor> x = decodeAxis([dictionary objectForKey:@"x"]);
    id<AXDataAxisDescriptor> y = decodeAxis([dictionary objectForKey:@"y"]);
    NSArray *series = decodeSeries(objectOfClass(dictionary, @"series", [NSArray class]));
    if (![objectOfClass(dictionary, @"SFChartVersion", [NSNumber class]) isEqual:@1] ||
        !x || (y && ![(id)y isKindOfClass:[AXNumericDataAxisDescriptor class]]) || !series) {
        [self release];
        return nil;
    }
    NSMutableArray *axes = [NSMutableArray array];
    for (id raw in objectOfClass(dictionary, @"extraAxes", [NSArray class])) {
        id<AXDataAxisDescriptor> axis = decodeAxis(raw);
        if (!axis) {
            [self release];
            return nil;
        }
        [axes addObject:axis];
    }
    self = [self initWithTitle:objectOfClass(dictionary, @"title", [NSString class])
                       summary:objectOfClass(dictionary, @"summary", [NSString class])
               xAxisDescriptor:x yAxisDescriptor:(AXNumericDataAxisDescriptor *)y
                additionalAxes:axes series:series];
    if (!self) return nil;
    self.contentDirection = [objectOfClass(dictionary, @"direction", [NSNumber class]) integerValue];
    NSArray *frame = objectOfClass(dictionary, @"frame", [NSArray class]);
    if ([frame count] == 4) {
        for (id value in frame) {
            if (![value isKindOfClass:[NSNumber class]]) {
                [self release];
                return nil;
            }
        }
        self.contentFrame = CGRectMake([[frame objectAtIndex:0] doubleValue], [[frame objectAtIndex:1] doubleValue],
                                       [[frame objectAtIndex:2] doubleValue], [[frame objectAtIndex:3] doubleValue]);
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    CGRect frame = self.contentFrame;
    NSMutableArray *axes = [NSMutableArray array];
    for (id<AXDataAxisDescriptor> item in self.additionalAxes) {
        NSDictionary *encoded = encodeAxis(item);
        if (encoded) [axes addObject:encoded];
    }
    NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithDictionary:@{
        @"SFChartVersion": @1, @"series": encodeSeries(self.series), @"extraAxes": axes,
        @"direction": @(self.contentDirection),
        @"frame": @[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)]
    }];
    NSDictionary *x = encodeAxis(self.xAxis), *y = encodeAxis(self.yAxis);
    if (x) [properties setObject:x forKey:@"x"];
    if (y) [properties setObject:y forKey:@"y"];
    if (self.title) [properties setObject:self.title forKey:@"title"];
    if (self.summary) [properties setObject:self.summary forKey:@"summary"];
    return properties;
}
@end
