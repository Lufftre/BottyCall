BIN_DIR    := $(HOME)/.local/bin
LOG_DIR    := $(HOME)/.local/var/log
PLIST_DIR  := $(HOME)/Library/LaunchAgents
PLIST_NAME := com.bottycall.daemon.plist

.PHONY: build install install-bin install-service uninstall logs

build:
	cargo build --release

install: install-bin install-service

install-bin: build
	install -d $(BIN_DIR)
	install -m 755 target/release/bottycall $(BIN_DIR)/bottycall
	@echo "bottycall binary installed to $(BIN_DIR)"
	@case ":$$PATH:" in *":$(BIN_DIR):"*) ;; *) \
		echo ""; \
		echo "WARNING: $(BIN_DIR) is not in your PATH"; \
		echo "Add this to your shell profile:"; \
		echo "  export PATH=\"$(BIN_DIR):\$$PATH\""; \
	esac

install-service:
	install -d $(LOG_DIR)
	sed -e 's|__BIN_DIR__|$(BIN_DIR)|g' -e 's|__LOG_DIR__|$(LOG_DIR)|g' \
		$(PLIST_NAME).in > $(PLIST_DIR)/$(PLIST_NAME)
	launchctl bootout gui/$$(id -u) $(PLIST_DIR)/$(PLIST_NAME) 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(PLIST_DIR)/$(PLIST_NAME)
	@echo "bottycall daemon started"

uninstall:
	launchctl bootout gui/$$(id -u) $(PLIST_DIR)/$(PLIST_NAME) 2>/dev/null || true
	rm -f $(BIN_DIR)/bottycall
	rm -f $(PLIST_DIR)/$(PLIST_NAME)
	rm -f $(LOG_DIR)/bottycall.log
	@echo "bottycall uninstalled"

logs:
	tail -f $(LOG_DIR)/bottycall.log
