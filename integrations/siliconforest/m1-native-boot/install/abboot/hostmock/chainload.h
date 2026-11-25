/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/* Host stand-in for the m1n1 header of this name, for test_sf_ab_stage1.c only. */
#ifndef SF_MOCK_CHAINLOAD_H
#define SF_MOCK_CHAINLOAD_H
#include "types.h"
/* as patches/stage1-v2/0002 declares them in m1n1's src/chainload.h */
int chainload_load(const char *spec, char **vars, size_t *var_cnt, size_t var_capacity);
int chainload_read_file(const char *spec, void **image, size_t *size);
void chainload_free_file(void *image, size_t size);
int chainload_load_slot(const char *spec, char **vars, size_t *var_cnt, size_t var_capacity,
                        bool check, u32 bytes, u32 crc32);
int sf_ab_stage1_chainload(const char *spec, char **vars, size_t *var_cnt, size_t var_capacity);
#endif
