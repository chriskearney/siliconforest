#ifndef M1KBD_HID_H
#define M1KBD_HID_H
#include "native_protocol/dl_spi_hid.h"
#include "m1kbd_boards.h"
#ifdef __cplusplus
extern "C" {
#endif
struct m1kbd_identity {
    uint16_t vendor, product, version, max_input;
    uint8_t country;
};
enum m1kbd_metadata_error {
    M1KBD_META_OK=0, M1KBD_META_ARGUMENT=-1, M1KBD_META_LENGTH=-2,
    M1KBD_META_COUNT=-3, M1KBD_META_VENDOR=-4, M1KBD_META_PRODUCT=-5,
    M1KBD_META_INTERFACE=-6, M1KBD_META_INPUT_SIZE=-7
};
/* Called only on a CRC-validated, semantically matched response.
 * Failure leaves output unchanged and returns a metadata error above.
 * Unused optional strings are never followed, copied, or required.
 * expected_product comes from m1kbd_board_product(); 0 accepts nothing. */
int m1kbd_device_info(const uint8_t *, size_t, uint16_t expected_product, struct m1kbd_identity *);
int m1kbd_interface_info(const uint8_t *, size_t, struct m1kbd_identity *);
/* Fixed numeric headers only, not raw payloads. Device words: unknown0/1,
 * count, vendor, product, version, then vendor/product/serial offset+length.
 * Interface prefix: unknown0, interface, unknown2/3/4, country; words: max
 * input/output/control, name offset+length. Exact sizes are 24 and 16 bytes.
 * Return 1 for a complete bounded header, else zero and clear the output.
 * No optional string or report bytes are accessed, even for invalid spans. */
struct m1kbd_device_metadata { uint16_t words[12]; };
struct m1kbd_interface_metadata { uint8_t prefix[6]; uint16_t words[5]; };
int m1kbd_device_metadata_header(const uint8_t *, size_t, struct m1kbd_device_metadata *);
int m1kbd_interface_metadata_header(const uint8_t *, size_t, struct m1kbd_interface_metadata *);
/* Serialized enumeration only: command is always 0x20. Claim exactly once
 * before incrementing the outbound ID, encoding or sending. Bit 0: 01/d0,
 * bit 1: 02/01, bit 2: 10/01. Zero-init once; never clear/retry a used key.
 * Returns 1 on claim; null/invalid mask, unknown key or repeat returns 0
 * without modifying the mask. This is an attempt limit, not a lock. */
int m1kbd_claim_request(uint8_t *used, uint8_t report, uint8_t subdevice);
/* IDs are per-message-type counters in the reference, not echoed request
 * IDs. Match only a pending, single-use key after CRC/length validation.
 * Response length and both IDs remain diagnostic, not pairing predicates. */
int m1kbd_response_matches(const struct dlsp_message *, uint8_t report, uint8_t subdevice);
/* 1: eligible device-1 input, 0: another message, -1: malformed keyboard input.
 * IOHID still validates the actual descriptor/report relationship. */
int m1kbd_keyboard_input(const struct dlsp_message *, uint16_t max_input);
/* Diagnostic schema v1: fixed u32 fields only, no packet/message payload or
 * borrowed pointer. Outer fields can be untrusted when parser_error != 0.
 * Supply message only after DLSP_MESSAGE (both CRCs/lengths checked). */
struct m1kbd_observation {
    uint32_t packet_available, packet_flags, packet_device, offset, remain, length;
    uint32_t message_available, device, flags, command, report, subdevice, id;
    uint32_t response_length, payload_length, parser_error;
};
void m1kbd_observe(const uint8_t *, size_t, const struct dlsp_message *,
                  unsigned parser_error, struct m1kbd_observation *);
#ifdef __cplusplus
}
#endif
#endif
