# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
req "list $T-l0\n" > /dev/null; grep -v '^window' $D/$T-l0.txt | cut -c1-200 | head -20; grep -c '^window' $D/$T-l0.txt; cap $T-now 100
