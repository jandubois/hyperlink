.PHONY: build release test clean version

VERSION := $(shell V=$$(git describe --tags --dirty 2>/dev/null | sed 's/^v//'); echo "$${V:-dev}")
VERSION_FILE := Sources/Hyperlink/Version.swift

build: version
	swift build

release: version
	swift build -c release --arch arm64

test: version
	swift test

clean:
	swift package clean
	rm -f $(VERSION_FILE)

version:
	@echo "// Auto-generated - do not edit" > $(VERSION_FILE)
	@echo "let appVersion = \"$(VERSION)\"" >> $(VERSION_FILE)
	@echo "Version: $(VERSION)"
