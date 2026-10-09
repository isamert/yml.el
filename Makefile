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
