VERILATOR ?= verilator
TOP       ?= ppu
SRC        = ppu.sv
OBJ_DIR    = obj_dir
CXXFLAGS  ?=

all: sim

sim: $(OBJ_DIR)/V$(TOP)

$(OBJ_DIR)/V$(TOP): $(SRC) main.cpp
	$(VERILATOR) --cc $(SRC) \
		--top-module $(TOP) \
		--Mdir $(OBJ_DIR) \
		--trace \
		--exe main.cpp \
		-CFLAGS "$(CXXFLAGS)" \
		--build

clean:
	rm -rf $(OBJ_DIR) frame.ppm

.PHONY: all sim clean
