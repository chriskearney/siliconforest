SHELLCHECK ?= shellcheck
.PHONY: check sources verify build-kernel build-m1n1 build-mesa installer

check:
	python3 scripts/sources.py lock
	python3 -m compileall -q scripts installer
	bash -n scripts/build-kernel.sh
	bash -n scripts/build-m1n1.sh
	bash -n scripts/build-mesa.sh
	$(SHELLCHECK) scripts/build-kernel.sh scripts/build-m1n1.sh scripts/build-mesa.sh
	python3 -m unittest discover -s tests -v

sources:
	python3 scripts/sources.py fetch all

verify:
	python3 scripts/sources.py verify all

build-kernel:
	bash scripts/build-kernel.sh

build-m1n1:
	bash scripts/build-m1n1.sh

build-mesa:
	bash scripts/build-mesa.sh

installer:
	mkdir -p dist
	python3 -c 'import sys; sys.path.insert(0, "scripts"); from package import installer_archive; installer_archive("dist/siliconforest.pyz")'
