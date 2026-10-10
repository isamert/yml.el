# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Isa Mert Gurbuz
# Copyright (C) 2019 Ayush Goyal (inherited MIT-covered code).
# Modified by Isa Mert Gurbuz in 2026; distributed under GPLv3 or later.
# See LICENSE for the GPL and LICENSES/MIT.txt for the original MIT notice.

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
MODULE_EXT := dylib
else
MODULE_EXT := so
endif

.PHONY: build yml-core.so clean

build: yml-core.so

yml-core.so:
	cargo build --release
	ln -sfn target/release/libyml.$(MODULE_EXT) yml-core.so

clean:
	cargo clean
	rm -f yml-core.so
