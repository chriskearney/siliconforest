# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Cocoa still carries its patch series against the earlier upstream base.
import ./base-tree.nix {
  sourceName = "upstream-cocoa";
  corecryptoName = "corecrypto-pin";
  forkRev = "04b6ecb44f8d6d8c650b8e3e1912bc57b881265d";
}
