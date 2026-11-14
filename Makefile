PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
CODESIGN_CMD := codesign --force --sign - --identifier com.aklkbqx.snapclip
VERSION ?= $(shell sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' Sources/SnapClipCLI/SnapClipCLI.swift)

.PHONY: test build install verify package publish-homebrew-tap media clean

test:
	swift test

build:
	swift build -c release
	mkdir -p dist
	cp "$$(swift build -c release --show-bin-path)/snapclip" dist/snapclip
	chmod 755 dist/snapclip
	$(CODESIGN_CMD) dist/snapclip

install: build
	mkdir -p "$(DESTDIR)$(BINDIR)"
	install -m 755 dist/snapclip "$(DESTDIR)$(BINDIR)/snapclip"

verify:
	sh scripts/verify.sh

package:
	sh scripts/package.sh

publish-homebrew-tap:
	sh scripts/update-homebrew-tap.sh "$(VERSION)" "dist/packages/$(VERSION)" --publish

media:
	sh scripts/record-media.sh

clean:
	swift package clean
	rm -rf dist .build-universal
