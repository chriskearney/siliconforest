/* SPDX-License-Identifier: MIT */
/*
 * The boards the SPI keyboard and trackpad driver accepts. m1kbd_validate_board() records
 * which one it matched in struct m1kbd_board.qualified; the transport and the device
 * metadata check take their per-board facts from that value.
 *
 * Product IDs: drivers/hid/hid-ids.h of linux-aurora, SPI_DEVICE_ID_APPLE_MACBOOK_PRO13_2020
 * (0x0341, observed on J293) and SPI_DEVICE_ID_APPLE_MACBOOK_AIR_2020 (0x0281, not yet
 * observed from a J313 under this driver).
 */
#ifndef M1KBD_BOARDS_H
#define M1KBD_BOARDS_H
#include <stdint.h>

#define M1KBD_QUALIFIED_J293 0x4a323933u /* "J293" */
#define M1KBD_QUALIFIED_J313 0x4a333133u /* "J313" */

/* The product ID this board's controller must report, or 0 for no accepted board. */
static inline uint16_t m1kbd_board_product(uint32_t qualified)
{
    return qualified == M1KBD_QUALIFIED_J293 ? 0x0341 :
           qualified == M1KBD_QUALIFIED_J313 ? 0x0281 : 0;
}
#endif
