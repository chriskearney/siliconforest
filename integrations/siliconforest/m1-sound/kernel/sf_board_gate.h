/* SPDX-License-Identifier: MIT */
/*
 * Is this the board a driver was written for? The first string of the device tree root's
 * "compatible" names the board ("J293AP"), and it must be terminated inside the property.
 * Used by SFAppleSound and SFAppleTouchBar, whose buses, parts and tables are J293's.
 */
#ifndef SF_BOARD_GATE_H
#define SF_BOARD_GATE_H

static inline int
sf_board_compatible_is(const void *compatible, unsigned long length, const char *board)
{
	const char *have = (const char *)compatible;
	unsigned long i;

	if (have == 0 || board == 0)
		return 0;
	for (i = 0; i < length; i++) {
		if (have[i] != board[i])
			return 0;
		if (board[i] == 0)
			return 1;
	}
	return 0;
}
#endif
