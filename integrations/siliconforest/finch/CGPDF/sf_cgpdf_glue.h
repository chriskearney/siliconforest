/* SPDX-License-Identifier: MIT OR Apache-2.0 */
#ifndef SF_CGPDF_GLUE_H
#define SF_CGPDF_GLUE_H
#include <stddef.h>
#include <stdint.h>

int sf_copy_provider(void *provider, uint8_t **bytes, size_t *n);
int sf_bitmap(void *context, uint8_t **data, size_t *width, size_t *height, size_t *stride, double ctm[6]);

void *sf_cf_empty_string(void);
void *sf_cf_string_utf8(const char *bytes, size_t n);
void *sf_cf_data(const uint8_t *bytes, size_t n);
void *sf_cf_dict(void);
void *sf_cf_array(void);
void *sf_cf_number_long(long value);
void sf_cf_dict_set(void *dict, const char *key, void *value);
void sf_cf_array_add(void *array, void *value);
void sf_cf_release(void *object);

int sf_cf_string_get_utf8(void *string, char *buf, size_t n);
void *sf_cf_dict_get(void *dict, const char *key);
long sf_cf_number_value(void *number);
size_t sf_cf_array_count(void *array);
void *sf_cf_array_at(void *array, size_t index);

#endif
