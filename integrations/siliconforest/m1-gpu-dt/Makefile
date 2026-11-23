# SPDX-License-Identifier: MIT
# Host test for m1-gpu-dt. Nothing here touches hardware or the network.
#
#   make test                 build, self-test, compare with the Linux ground truth
#   make test ADT=<adt.bin> GT=<gpu-nodes.txt>
#
# build/ holds a fixture generated from a real device tree and is not tracked.

REPO ?= $(abspath ../../..)
ADT  ?= $(shell ls -t $(REPO)/runs/m1-desktop-010/*/guest/original-adt.bin 2>/dev/null | head -1)
GT   ?= $(REPO)/private/linux-dt/gpu-nodes.txt $(wildcard $(REPO)/private/linux-dt/gpu-child-nodes.txt)
# core mask for the predicted kext log; 0xff until the register has been read on the machine
CORE_MASK ?= 0xff
CC   ?= cc
# -ffp-contract=off: the self-test's reference floats must round after every operation
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror -ffp-contract=off

.PHONY: test clean check-inputs freestanding compare-disp

test: build/harness build/fwnode_test build/dispdt_test build/dispdt_board_test freestanding
	./build/harness selftest
	./build/dispdt_test
	./build/dispdt_board_test
	./build/fwnode_test
	python3 test/compare.py ./build/harness $(GT)
	@echo; echo "predicted SFGpuDT kext log for core mask $(CORE_MASK):"
	@./build/harness kextlog --core-mask $(CORE_MASK)

check-inputs:
	@test -n "$(ADT)" -a -f "$(ADT)" || { echo "no saved device tree: set ADT=<original-adt.bin>"; exit 1; }
	@for f in $(GT); do test -f "$$f" || { echo "no ground truth: set GT=<gpu-nodes.txt>"; exit 1; }; done

build/adt_fixture.c: test/gen_fixture.py | check-inputs
	@mkdir -p build
	python3 test/gen_fixture.py $(ADT) $@

build/harness: src/gpudt.c src/gpudt_summary.c src/gpudt.h src/gpudt_fw_table.inc test/harness.c test/fixture.h build/adt_fixture.c
	$(CC) $(CFLAGS) -Isrc -Itest -o $@ src/gpudt.c src/gpudt_summary.c test/harness.c build/adt_fixture.c -lm

# the display nodes (dispdt.c) from the same saved device tree
build/dispdt_test: src/dispdt.c src/dispdt.h src/gpudt.h test/dispdt_test.c test/fixture.h build/adt_fixture.c
	$(CC) $(CFLAGS) -Isrc -Itest -o $@ src/dispdt.c test/dispdt_test.c build/adt_fixture.c

# the per-board panel values and refusal: a synthetic tree, no saved capture needed
build/dispdt_board_test: src/dispdt.c src/dispdt.h src/gpudt.h test/dispdt_board_test.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -o $@ src/dispdt.c test/dispdt_board_test.c

# the display tree against the live Linux tree, when its dump is there (private/, never committed):
#   make compare-disp DISP_ARGS="13 5 0 0xbd5d5c000 2560 1600 10240 0x1001e 0x0 0x300000 0x1318000 0x131c000 0x13dc000"
# (firmware version, boot framebuffer as the boot-args give it, the regions' mapped addresses as boot dc12 measured them)
DISP_GT ?= $(REPO)/private/linux-dt/display-nodes.txt
DISP_ARGS ?= 13 5 0 0xbd5d5c000 2560 1600 10240 0x1001e 0x0 0x300000 0x1318000 0x131c000 0x13dc000
build/dispdt_dump: src/dispdt.c src/dispdt.h test/dispdt_dump.c test/fixture.h build/adt_fixture.c
	$(CC) $(CFLAGS) -Isrc -Itest -o $@ src/dispdt.c test/dispdt_dump.c build/adt_fixture.c
compare-disp: build/dispdt_dump
	python3 test/compare_disp.py ./build/dispdt_dump $(DISP_ARGS) $(DISP_GT)

# the proposed of-layer additions, against stand-ins for the layer's headers (test/stubs)
build/fwnode_test: kernel/sf_linux_fwnode.c test/fwnode_test.c src/gpudt.c src/gpudt.h build/adt_fixture.c $(wildcard test/stubs/linux/*.h)
	$(CC) -std=gnu11 -O2 -Wall -Wextra -Werror -Wno-unused-parameter -Itest/stubs -Isrc -Itest -o $@ kernel/sf_linux_fwnode.c test/fwnode_test.c src/gpudt.c build/adt_fixture.c

# the core must build as kernel code would: no hosted library, no floating point registers
freestanding: src/gpudt.c src/gpudt.h src/gpudt_fw_table.inc
	@mkdir -p build
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector -mgeneral-regs-only -c -o build/gpudt_freestanding.o src/gpudt.c
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector -mgeneral-regs-only -Isrc -c -o build/dispdt_freestanding.o src/dispdt.c
	@if nm -u build/dispdt_freestanding.o | grep -v -E ' (memcpy|memset|memcmp|strcmp|strncmp|strlen)$$'; then \
		echo "unexpected external symbols in dispdt"; exit 1; fi
	@if nm -u build/gpudt_freestanding.o | grep -v -E ' (memcpy|memset|memcmp|strcmp|strncmp|strlen)$$'; then \
		echo "unexpected external symbols in the core"; exit 1; fi

clean:
	rm -rf build
