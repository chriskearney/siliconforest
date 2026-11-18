/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 SiliconForest contributors */
#ifndef SF_TRACKPAD_DESCRIPTOR_GUARD_H
#define SF_TRACKPAD_DESCRIPTOR_GUARD_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Identity only: does not publish a child or establish physical input. */
int sf_trackpad_descriptor_digest(const uint8_t *, size_t, uint8_t [32]);
int sf_trackpad_descriptor_matches(const uint8_t *, size_t, const uint8_t [32]);
#ifdef __cplusplus
}
#endif
#endif
