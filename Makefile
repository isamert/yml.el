EMACS ?= emacs
CARGO ?= cargo
RUSTC ?= rustc
CARGO_FLAGS ?=
TARGET ?= $(shell $(RUSTC) -vV | sed -n 's/^host: //p')
TARGET_DIR ?= $(if $(CARGO_TARGET_DIR),$(CARGO_TARGET_DIR),target)

ifneq (,$(findstring windows,$(TARGET)))
LIBRARY := yml.dll
MODULE := yml-core.dll
else ifneq (,$(findstring apple-darwin,$(TARGET)))
LIBRARY := libyml.dylib
MODULE := yml-core.so
else
LIBRARY := libyml.so
MODULE := yml-core.so
endif

.PHONY: build yml-core.so yml-core.dll clean test

build:
	$(CARGO) build --release --locked --lib --target "$(TARGET)" --target-dir "$(TARGET_DIR)" $(CARGO_FLAGS)
	rm -f "$(MODULE)"
	cp "$(TARGET_DIR)/$(TARGET)/release/$(LIBRARY)" "$(MODULE)"

yml-core.so yml-core.dll: build

clean:
	$(CARGO) clean --target-dir "$(TARGET_DIR)"
	rm -f yml-core.so yml-core.dll

test: build
	$(EMACS) --batch -Q -L . -l tests/yml-tests.el -f ert-run-tests-batch-and-exit
