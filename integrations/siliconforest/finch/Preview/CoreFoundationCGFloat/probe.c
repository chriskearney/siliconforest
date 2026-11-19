/* Headless client for the Swift CGFloat provider.
   Each named symbol is a two-level bind to libswiftCoreFoundation.
   Multiply and subtract are the dylib bodies: fmul d0,d0,d1 and fsub d0,d0,d1. */
#include <stdio.h>

extern char cgfloat_vmn __asm("_$s12CoreGraphics7CGFloatVMn");
extern char cf_equal __asm("_$s14CoreFoundation9_CFObjectPAAE2eeoiySbx_xtFZ");
extern char cf_hash_into __asm("_$s14CoreFoundation9_CFObjectPAAE4hash4intoys6HasherVz_tF");
extern char cf_hash_value __asm("_$s14CoreFoundation9_CFObjectPAAE9hashValueSivg");
extern char cf_hash_mv __asm("_$s14CoreFoundation9_CFObjectPAAE9hashValueSivpMV");
extern char cf_hashable __asm("_$s14CoreFoundation9_CFObjectPSHTb");
extern char cf_type __asm("_$s14CoreFoundation9_CFObjectTL");
extern char cf_proto __asm("_$s14CoreFoundation9_CFObjectMp");
extern char cf_force __asm("__swift_FORCE_LOAD_$_swiftCoreFoundation");
extern double cgfloat_mul(double, double) __asm("_$s12CoreGraphics7CGFloatV1moiyA2C_ACtFZ");
extern double cgfloat_sub(double, double) __asm("_$s12CoreGraphics7CGFloatV1soiyA2C_ACtFZ");

__attribute__((used))
void *const cgfloat_two_level_symbols[] = {
    &cgfloat_vmn,
    &cf_equal,
    &cf_hash_into,
    &cf_hash_value,
    &cf_hash_mv,
    &cf_hashable,
    &cf_type,
    &cf_proto,
    &cf_force,
};

int main(void) {
    unsigned long address = 0;
    unsigned i;
    double result;
    for (i = 0; i < sizeof cgfloat_two_level_symbols / sizeof cgfloat_two_level_symbols[0]; i++)
        address |= (unsigned long)cgfloat_two_level_symbols[i];
    if (address == 0)
        return 2;
    result = cgfloat_sub(7.5, cgfloat_mul(0.25, 2.0));
    if (result != 7.0)
        return 4;
    printf("Swift CGFloat metadata and arithmetic passed\n");
    return 0;
}
