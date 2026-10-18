SHELLCHECK ?= shellcheck
.PHONY: check sources verify build-kernel build-m1n1

check:
	python3 scripts/sources.py lock
	python3 -m py_compile scripts/sources.py
	bash -n scripts/build-kernel.sh
	bash -n scripts/build-m1n1.sh
	$(SHELLCHECK) scripts/build-kernel.sh scripts/build-m1n1.sh

sources:
	python3 scripts/sources.py fetch all

verify:
	python3 scripts/sources.py verify all

build-kernel:
	bash scripts/build-kernel.sh

build-m1n1:
	bash scripts/build-m1n1.sh
