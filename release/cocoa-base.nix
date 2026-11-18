# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Cocoa still carries its patch series against the earlier upstream base.
import ./base-tree.nix {
  sourceName = "upstream-cocoa";
  corecryptoName = "corecrypto-pin";
}
