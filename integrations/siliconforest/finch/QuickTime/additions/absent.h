/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * Shared by the QuickTime additions. An "absence" is a symbol that exists so that a program
 * binds, and that, when used, does nothing it cannot do properly, returns the failure its
 * interface documents (or nil), and says what is missing once on stderr. */
#ifndef SF_QT_ABSENT_H
#define SF_QT_ABSENT_H
#include <stdio.h>
#define SF_EXPORT __attribute__((visibility("default")))
#define SF_ABSENT(message) \
    do { \
        static int sfSaid; \
        if (!sfSaid) { \
            sfSaid = 1; \
            fputs("SiliconForest: " message "\n", stderr); \
        } \
    } while (0)
#endif
