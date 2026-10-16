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

.PHONY: build yml-core.so yml-core.dll clean test release

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

# Usage: make release VERSION=0.2.0 (or omit VERSION to be prompted).
# Includes all tracked changes; opens the editor for the annotated tag message.
release: export YML_RELEASE_VERSION = $(VERSION)
release:
	@set -eu; \
	version="$$YML_RELEASE_VERSION"; \
	if [ -z "$$version" ]; then printf 'Release version (X.Y.Z): '; read -r version; fi; \
	printf '%s\n' "$$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo 'Expected version X.Y.Z' >&2; exit 1; }; \
	if git show-ref --verify --quiet "refs/tags/v$$version"; then echo "Tag v$$version already exists" >&2; exit 1; fi; \
	export YML_RELEASE_VERSION="$$version"; \
	$(EMACS) --batch -Q -l scripts/release.el; \
	git commit -a -m "Release v$$version"; \
	git tag -a "v$$version" --edit -m "Release v$$version"
