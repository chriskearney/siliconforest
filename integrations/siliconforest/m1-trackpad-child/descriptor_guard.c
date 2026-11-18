/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 SiliconForest contributors */
#include "descriptor_guard.h"
#include "trackpad_reference.h"
#if defined(KERNEL) && KERNEL
#include <libkern/crypto/sha2.h>
#elif defined(SF_TRACKPAD_GUARD_HOST_TEST)
#include <openssl/sha.h>
#else
#include <CommonCrypto/CommonDigest.h>
#endif

int sf_trackpad_descriptor_digest(const uint8_t *descriptor, size_t n, uint8_t out[32])
{
    if (!descriptor || !out || n != SF_TRACKPAD_DESCRIPTOR_LENGTH)
        return 0;
#if defined(KERNEL) && KERNEL
    SHA256_CTX context;
    SHA256_Init(&context);
    SHA256_Update(&context, descriptor, n);
    SHA256_Final(out, &context);
#elif defined(SF_TRACKPAD_GUARD_HOST_TEST)
    if (!SHA256(descriptor, n, out))
        return 0;
#else
    if (!CC_SHA256(descriptor, (CC_LONG)n, out))
        return 0;
#endif
    return 1;
}

int sf_trackpad_descriptor_matches(const uint8_t *descriptor, size_t n,
                                  const uint8_t expected[32])
{
    uint8_t actual[32];
    unsigned i, different = 0;
    if (!expected || !sf_trackpad_descriptor_digest(descriptor, n, actual))
        return 0;
    for (i = 0; i < sizeof(actual); ++i)
        different |= actual[i] ^ expected[i];
    return different == 0;
}
