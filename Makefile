# MSX-DOS Music Player - Makefile

# Shell (use bash explicitly for Windows compatibility with mingw32-make)
SHELL = bash

# Tools
PYTHON = python
Z80ASM = $(TOOLS_DIR)/z80asm.exe

# Directories
TOOLS_DIR = tools
DATA_DIR = data
VGZ_DIR = vgz
BUILD_DIR = build
MSX_DIR = msx

# Output
MSX_TARGET = $(BUILD_DIR)/MPSPLAY.COM

# Default target
.PHONY: all
all: msx-all

# MSX all-in-one: convert music + build player
.PHONY: msx-all
msx-all: convert-msx msx-player

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Create data directory
$(DATA_DIR):
	mkdir -p $(DATA_DIR)

# Convert VGZ files to 8.3 MSX-DOS filenames (*.MPS)
# Output name: first 6 alphanum chars of title (uppercased) + 2-digit index
# e.g. "01 Usas [Mohenjo daro].vgz" -> USASMO01.MPS
# Usage: make convert-msx [FPS=50|60]
FPS ?= 60

.PHONY: convert-msx
convert-msx:
	$(PYTHON) $(TOOLS_DIR)/convert_msx.py $(VGZ_DIR) $(DATA_DIR) $(FPS)

# Build MSX-DOS player (.COM)
.PHONY: msx-player
msx-player: $(MSX_TARGET)

$(MSX_TARGET): $(MSX_DIR)/player.asm | $(BUILD_DIR)
	$(Z80ASM) -o $@ $<

# Build MSX ROM image (Konami mapper, 128KB)
.PHONY: msx-rom
msx-rom:
	$(PYTHON) $(TOOLS_DIR)/build_msx_rom.py

# Build MSX-DOS disk image with player and music files
MSX_BASE_DSK = $(TOOLS_DIR)/msxdos103-111hf clean.dsk
MSX_DSK      = $(BUILD_DIR)/msx-music.dsk

.PHONY: msx-disk
msx-disk: msx-all
	$(PYTHON) $(TOOLS_DIR)/make_msx_disk.py \
		"$(MSX_BASE_DSK)" \
		"$(MSX_DSK)" \
		$(MSX_TARGET) \
		$(wildcard $(DATA_DIR)/*.MPS) \
		$(wildcard $(MSX_DIR)/SONGLIST.TXT)
	@echo "To test: openmsx -machine Panasonic_FS-A1GT -diska \"$(MSX_DSK)\""

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

# Clean everything including converted files
.PHONY: distclean
distclean: clean
	rm -f $(DATA_DIR)/*.MPS

# Help
.PHONY: help
help:
	@echo "MSX-DOS Music Player"
	@echo ""
	@echo "Usage:"
	@echo "  make / make msx-all   - Convert music + build MPSPLAY.COM"
	@echo "  make convert-msx      - Convert VGZ files to MPS (MSX-DOS)"
	@echo "  make convert-msx FPS=50 - Convert at 50Hz"
	@echo "  make msx-player       - Build MPSPLAY.COM only"
	@echo "  make msx-rom          - Build ROM image (Konami mapper)"
	@echo "  make msx-disk         - Create bootable MSX-DOS disk image"
	@echo "  make clean            - Remove build artifacts"
	@echo "  make distclean        - Remove build + converted MPS files"
