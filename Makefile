UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
MODULE_EXT := dylib
else
MODULE_EXT := so
endif

.PHONY: build yml.so clean

build: yml.so

yml.so:
	cargo build --release
	ln -sfn target/release/libyml.$(MODULE_EXT) yml.so

clean:
	cargo clean
	rm -f yml.so
