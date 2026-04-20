UART_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SBY      ?= sby
MODULES  := uart_tx uart_rx

.PHONY: all
all: check

# check: Runs sby for all modules in $(MODULES)
.PHONY: check formal
check formal: $(addprefix check-,$(MODULES))

# Pattern rule to run a specific module: e.g., 'make check-uart_rx'
# The '$*' matches the module name from the '%' part
check-%:
	@command -v "$(SBY)" >/dev/null 2>&1 || { echo "Missing $(SBY) (SymbiYosys)."; exit 1; }
	@echo "--- RUNNING FORMAL CHECK FOR $* ---"
	cd "$(UART_DIR)" && $(SBY) -f $*.sby

.PHONY: clean
clean:
	@echo "Cleaning up formal work directories..."
	@for mod in $(MODULES); do \
		rm -rf "$(UART_DIR)/$$mod" "$(UART_DIR)/$${mod}_bmc" "$(UART_DIR)/$${mod}_prove" "$(UART_DIR)/$${mod}_cover"; \
	done

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make check        - Run formal verification for ALL modules ($(MODULES))"
	@echo "  make check-uart_tx - Run formal verification for uart_tx only"
	@echo "  make check-uart_rx - Run formal verification for uart_rx only"
	@echo "  make clean        - Remove all SBY work directories"
