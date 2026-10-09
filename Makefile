UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
MODULE_EXT := dylib
else
MODULE_EXT := so
endif

.PHONY: build yamlmod.so clean

build: yamlmod.so

yamlmod.so:
	cargo build --release
	ln -sfn target/release/libyamlmod.$(MODULE_EXT) yamlmod.so

clean:
	cargo clean
	rm -f yamlmod.so
