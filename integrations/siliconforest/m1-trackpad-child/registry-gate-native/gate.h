/* Original read-only T2 registry admission. License pending. */
#ifndef DL_NATIVE_GATE_H
#define DL_NATIVE_GATE_H
#include <stddef.h>
#include <stdint.h>
#define NG_BYTES 704u
#define NG_NO_DEVICE ((int32_t)0xe00002c0u)
#define NG_NAME_BYTES 128u
#define NG_PROPERTY_CAP 4096u
/* Every returned nonzero port is an owned send right, including on failure.
 * release consumes that ownership once; no retries. A null successful matching
 * iterator means empty. A null parent iterator does not establish attribution. */
struct ng_ops {
 int32_t (*master)(void *, uint32_t *);
 int32_t (*matching)(void *, uint32_t, const char *, uint32_t *);
 int32_t (*next)(void *, uint32_t, uint32_t *);
 int32_t (*valid)(void *, uint32_t, int32_t *);
 int32_t (*class_name)(void *, uint32_t, char [NG_NAME_BYTES]);
 int32_t (*entry_id)(void *, uint32_t, uint64_t *);
 int32_t (*parents)(void *, uint32_t, uint32_t *);
 int32_t (*property)(void *, uint32_t, const char *, uint8_t [NG_PROPERTY_CAP], uint32_t *);
 int32_t (*release)(void *, uint32_t);
 /* node: 1 character device, 0 ENOENT, 2 wrong type, -1 other error. */
 int32_t (*node)(void *, const char *, int32_t *);
};
enum ng_offset {
 NG_VERSION=0, NG_SIZE=4, NG_RESULT=8, NG_REASON=12, NG_DETAIL=16,
 NG_QUERY_ERRORS=20, NG_RELEASE_ERRORS=24, NG_COMPLETE=28,
 NG_HIDS=32, NG_HID_DONE=36, NG_SERIALS=40, NG_SERIAL_DONE=44,
 NG_PARENTS=48, NG_PARENT_DONE=52, NG_ITER_VALID=56,
 NG_PARENT_ID=80, NG_CHILD_ID=88, NG_PROVIDER_ID=96,
 NG_CLASSES=104, NG_IDS=488, NG_PROVIDER_IDS=512,
 NG_DESCRIPTOR_LEN=528, NG_INTERFACE_LEN=532, NG_STATE_LEN=536,
 NG_KBD_NODE=540, NG_MOUSE_NODE=544, NG_DESCRIPTOR=548,
 NG_INTERFACE=658, NG_STATE=662
};
enum ng_reason {
 NG_OK=0, NG_RPC=1, NG_NULL_PORT=2, NG_INVALID_ITERATOR=3,
 NG_EXCESS=4, NG_CLASS=5, NG_ID=6, NG_PARENT=7, NG_PROPERTY=8,
 NG_NODE=9, NG_OWNERSHIP=10
};
uint32_t ng_u32(const uint8_t *);
uint64_t ng_u64(const uint8_t *);
void ng_put32(uint8_t *, uint32_t);
void ng_put64(uint8_t *, uint64_t);
int ng_nonce_valid(const char *);
/* The second argument is the expected SHA-256 digest, not descriptor bytes.
 * 0 ready identity only, 77 clean absence/non-ready, 1 malformed/error. */
int ng_classify(const uint8_t [NG_BYTES], const uint8_t [32]);
int ng_collect(const struct ng_ops *, void *, const uint8_t [32], uint8_t [NG_BYTES]);
#endif
