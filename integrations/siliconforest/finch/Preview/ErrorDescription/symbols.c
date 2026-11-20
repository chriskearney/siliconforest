// SPDX-License-Identifier: MIT OR Apache-2.0
#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>

int32_t sf_localized_description_symbol(void) {
    return dlsym(RTLD_DEFAULT, "$ss5ErrorP10FoundationE20localizedDescriptionSSvg") != NULL;
}
