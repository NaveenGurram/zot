.PHONY: all clean install test

PREFIX ?= /usr/local/bin
ZIG ?= zig

all: zig-out/bin/zot zig-out/bin/zot-remind

zig-out/bin/zot zig-out/lib/libzot.dylib:
	$(ZIG) build

zig-out/bin/zot-remind: scripts/ZotRemind.swift
	swiftc -o $@ $< -framework SwiftUI -framework AppKit -parse-as-library -O

test:
	$(ZIG) build test

install: all
	install -d $(PREFIX)
	install zig-out/bin/zot $(PREFIX)/zot
	install zig-out/bin/zot-remind $(PREFIX)/zot-remind
	@echo "Installed to $(PREFIX)"

clean:
	rm -rf zig-out .zig-cache
