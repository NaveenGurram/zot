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

install:
	install -d $(PREFIX)
	# Ensure binaries are built (ignore swift failure)
	-$(ZIG) build
	-swiftc -o zig-out/bin/zot-remind scripts/ZotRemind.swift -framework SwiftUI -framework AppKit -parse-as-library -O
	
	install zig-out/bin/zot $(PREFIX)/zot
	# Install the launcher script as the main command
	install scripts/zot-remind.sh $(PREFIX)/zot-remind
	# Install the Swift UI binary if it was successfully built
	if [ -f zig-out/bin/zot-remind ]; then \
		install zig-out/bin/zot-remind $(PREFIX)/zot-remind-ui; \
	fi
	@echo "Installed to $(PREFIX)"

install-local:
	$(MAKE) PREFIX=$(HOME)/.local/bin install

install-agent:
	@mkdir -p $(HOME)/Library/LaunchAgents
	sed 's|/usr/local/bin|$(PREFIX)|g' scripts/com.zot.remind.plist > $(HOME)/Library/LaunchAgents/com.zot.remind.plist
	launchctl load $(HOME)/Library/LaunchAgents/com.zot.remind.plist
	@echo "Launch agent installed and loaded."

clean:
	rm -rf zig-out .zig-cache
