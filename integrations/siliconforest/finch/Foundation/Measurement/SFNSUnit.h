/* SPDX-License-Identifier: MIT OR Apache-2.0
 * Declarations Finch's NSUnit.m implements. This SDK has no NSUnit.h.
 * The conversion factors and methods stay in that pinned file.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUnitConverter : NSObject <NSCopying>
- (double)baseUnitValueFromValue:(double)value;
- (double)valueFromBaseUnitValue:(double)baseUnitValue;
@end

@interface NSUnitConverterLinear : NSUnitConverter <NSSecureCoding> {
    double _coefficient;
    double _constant;
}
- (instancetype)initWithCoefficient:(double)coefficient;
- (instancetype)initWithCoefficient:(double)coefficient constant:(double)constant;
@property (readonly) double coefficient;
@property (readonly) double constant;
@end

@interface NSUnit : NSObject <NSCopying, NSSecureCoding> {
    NSString *_symbol;
}
- (instancetype)initWithSymbol:(NSString *)symbol;
@property (readonly, copy) NSString *symbol;
@end

@interface NSDimension : NSUnit <NSSecureCoding> {
    NSUnitConverter *_converter;
}
@property (readonly, copy) NSUnitConverter *converter;
+ (instancetype)baseUnit;
- (instancetype)initWithSymbol:(NSString *)symbol converter:(NSUnitConverter *)converter;
@end

@interface NSMeasurement : NSObject <NSCopying, NSSecureCoding> {
    double _doubleValue;
    NSUnit *_unit;
}
- (instancetype)initWithDoubleValue:(double)doubleValue unit:(NSUnit *)unit;
@property (readonly) double doubleValue;
@property (readonly, copy) NSUnit *unit;
- (BOOL)canBeConvertedToUnit:(NSUnit *)unit;
- (NSMeasurement *)measurementByConvertingToUnit:(NSUnit *)unit;
@end

#define SF_UNIT(Name) @interface Name : NSDimension @end
SF_UNIT(NSUnitAcceleration)
SF_UNIT(NSUnitAngle)
SF_UNIT(NSUnitArea)
SF_UNIT(NSUnitConcentrationMass)
SF_UNIT(NSUnitDispersion)
SF_UNIT(NSUnitDuration)
SF_UNIT(NSUnitElectricCharge)
SF_UNIT(NSUnitElectricCurrent)
SF_UNIT(NSUnitElectricPotentialDifference)
SF_UNIT(NSUnitElectricResistance)
SF_UNIT(NSUnitEnergy)
SF_UNIT(NSUnitFrequency)
SF_UNIT(NSUnitFuelEfficiency)
SF_UNIT(NSUnitIlluminance)
SF_UNIT(NSUnitInformationStorage)
SF_UNIT(NSUnitMass)
SF_UNIT(NSUnitPower)
SF_UNIT(NSUnitPressure)
SF_UNIT(NSUnitSpeed)
SF_UNIT(NSUnitTemperature)
SF_UNIT(NSUnitVolume)
#undef SF_UNIT

@interface NSUnitLength : NSDimension
+ (NSUnitLength *)meters;
+ (NSUnitLength *)centimeters;
+ (NSUnitLength *)millimeters;
+ (NSUnitLength *)kilometers;
+ (NSUnitLength *)inches;
+ (NSUnitLength *)feet;
+ (NSUnitLength *)yards;
+ (NSUnitLength *)miles;
@end

NSMeasurement *SFMeasurementByConverting(NSMeasurement *measurement, NSUnit *unit);

NS_ASSUME_NONNULL_END
