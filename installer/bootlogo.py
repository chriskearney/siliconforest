# SPDX-License-Identifier: MIT
"""m1n1's existing custom-logo payload; no executable loader changes."""
from .release import require

MAGIC = b'm1n1_logo_256128'
SIZE = len(MAGIC) + 4 * (256 * 256 + 128 * 128)


def validate(raw):
    require(len(raw) == SIZE and raw.startswith(MAGIC), 'Invalid stage 2 logo payload')
    require(all(alpha == 255 for alpha in raw[len(MAGIC) + 3::4]),
            'Stage 2 artwork must be opaque RGBA')
    return raw


def compose(retina, standard):
    require(len(retina) == 4 * 256 * 256 and len(standard) == 4 * 128 * 128,
            'Stage 2 artwork dimensions differ')
    return validate(MAGIC + retina + standard)
