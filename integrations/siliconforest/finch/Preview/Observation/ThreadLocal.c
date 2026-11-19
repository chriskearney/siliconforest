// SPDX-License-Identifier: MIT
#include <pthread.h>
#include <stdlib.h>

static pthread_key_t observation_key;
static pthread_once_t observation_once = PTHREAD_ONCE_INIT;

static void create_observation_key(void) {
    if (pthread_key_create(&observation_key, NULL) != 0) {
        abort();
    }
}

static void initialize_observation_key(void) {
    if (pthread_once(&observation_once, create_observation_key) != 0) {
        abort();
    }
}

__attribute__((swiftcall, visibility("hidden")))
void *_swift_observation_tls_get(void) {
    initialize_observation_key();
    return pthread_getspecific(observation_key);
}

__attribute__((swiftcall, visibility("hidden")))
void _swift_observation_tls_set(void *value) {
    initialize_observation_key();
    if (pthread_setspecific(observation_key, value) != 0) {
        abort();
    }
}
