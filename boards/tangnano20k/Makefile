# Tang Nano 20K — Yosys + nextpnr-himbaechel + Apicula (gowin_pack) + openFPGALoader
#
# Toolchain: Yosys (synthesis) → nextpnr-himbaechel (P&R) → gowin_pack from Project Apicula (.fs)
#
# Usage (repo root):
#   make -C boards/tangnano20k HW=uart_tx_example          # build .fs then flash
#   make -C boards/tangnano20k HW=uart_tx_example bitstream # build only
#   make -C boards/tangnano20k HW=uart_tx_example flash    # flash existing .fs
#
# Overrides: YOSYS, NEXTPNR, GOWIN_PACK, SOURCES, CST, DEVICE, FAMILY, GOWIN_PACK_DEVICE

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

HW ?=

# Allow `make help` / `make clean` without HW=...
ALLOW_NO_HW := $(filter help clean,$(MAKECMDGOALS))
ifeq ($(ALLOW_NO_HW),)
$(if $(strip $(HW)),,$(error HW is required, e.g. make HW=uart_tx_example (see: make help)))
endif

BOARD ?= tangnano20k
OPENFPGALOADER ?= openFPGALoader

YOSYS ?= yosys
NEXTPNR ?= nextpnr-himbaechel
GOWIN_PACK ?= gowin_pack

# Tang Nano 20K (GW2AR-18C) — device/family below; default pins in boards/tangnano20k/constraints.cst
DEVICE ?= GW2AR-LV18QN88C8/I7
FAMILY ?= GW2A-18C
GOWIN_PACK_DEVICE ?= GW2A-18C

BUILD_DIR := $(REPO_ROOT)/build/$(HW)
JSON_SYNTH := $(BUILD_DIR)/$(HW)-syn.json
JSON_PNR := $(BUILD_DIR)/$(HW)-pnr.json
BITSTREAM ?= $(BUILD_DIR)/$(HW).fs

RECEIPT := $(REPO_ROOT)/hw/$(HW)/receipt.txt
# Cannot write '#' inside $(shell …); it starts a Make comment. Use printf '\043' for #.
SOURCES ?= $(foreach _w,$(shell grep -v "^$$(printf '\043')" "$(RECEIPT)" | awk 'NF'),$(REPO_ROOT)/$(_w))
CST ?= $(REPO_ROOT)/boards/tangnano20k/constraints.cst

.PHONY: all flash bitstream help clean

all: flash

help:
	@echo "Yosys + nextpnr-himbaechel + Apicula gowin_pack → .fs, then openFPGALoader"
	@echo ""
	@echo "  make HW=uart_tx_example           build $(REPO_ROOT)/build/uart_tx_example/uart_tx_example.fs and flash"
	@echo "  make HW=uart_tx_example bitstream   build .fs only"
	@echo "  make HW=uart_tx_example flash       build .fs if needed, then flash"
	@echo ""
	@echo "Overrides: SOURCES CST BITSTREAM DEVICE FAMILY YOSYS NEXTPNR GOWIN_PACK"

# Bitstream: Yosys synth_gowin → nextpnr-himbaechel → gowin_pack (Apicula)
$(BITSTREAM): $(SOURCES) $(CST)
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -p "read_verilog -I $(REPO_ROOT) $(SOURCES); hierarchy -check -top top; synth_gowin -top top -json $(JSON_SYNTH)"
	$(NEXTPNR) --json $(JSON_SYNTH) --write $(JSON_PNR) \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)
	$(GOWIN_PACK) --device $(GOWIN_PACK_DEVICE) --output $(BITSTREAM) $(JSON_PNR)

bitstream: $(BITSTREAM)

flash: $(BITSTREAM)
	$(OPENFPGALOADER) -f -b $(BOARD) "$(BITSTREAM)"

clean:
	rm -rf $(REPO_ROOT)/build
