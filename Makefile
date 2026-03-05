PREFIX ?= $(HOME)/.local
BINDIR = $(PREFIX)/bin
LOGDIR = $(PREFIX)/log
PLIST_DIR = $(HOME)/Library/LaunchAgents
LABEL = com.elomid.clipboard-bridge

.PHONY: build install uninstall start stop restart status log clean release

build: clipboard-bridge

clipboard-bridge: clipboard-bridge.m
	clang -O2 -fobjc-arc -framework AppKit -arch arm64 -arch x86_64 \
		-mmacosx-version-min=11.0 -o $@ $<

install: build
	mkdir -p $(BINDIR) $(LOGDIR)
	cp clipboard-bridge $(BINDIR)/
	@sed 's|__BINDIR__|$(BINDIR)|g; s|__LOGDIR__|$(LOGDIR)|g; s|__LABEL__|$(LABEL)|g' \
		launchagent.plist.template > $(PLIST_DIR)/$(LABEL).plist

uninstall: stop
	rm -f $(BINDIR)/clipboard-bridge
	rm -f $(PLIST_DIR)/$(LABEL).plist
	@echo "Uninstalled. Log file kept at $(LOGDIR)/clipboard-bridge.log"

start:
	launchctl load $(PLIST_DIR)/$(LABEL).plist

stop:
	-launchctl unload $(PLIST_DIR)/$(LABEL).plist 2>/dev/null

restart: stop start

status:
	@launchctl list | grep $(LABEL) && \
		ps -p $$(launchctl list | grep $(LABEL) | awk '{print $$1}') -o pid,rss,%cpu,%mem,etime || \
		echo "Not running"

log:
	tail -f $(LOGDIR)/clipboard-bridge.log

release:
	./scripts/release.sh

clean:
	rm -f clipboard-bridge
	rm -rf build
