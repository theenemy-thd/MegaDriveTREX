#!/bin/sh
# vbuild.sh <objdir> <verilator -G/-D args...>   (run from MSYS2 UCRT64)
O=$1; shift
N=../../rtl/nuked-md
verilator --binary --timing -j 12 -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
 --top-module tb -DEXT_CLOCKS -DM68K_CHEAT -DZ80_CHEAT -I$N tb.sv ../../rtl/m68k_clkgen.sv $N/md_board.v $N/fc1004.v $N/68k.v $N/z80.v \
 $N/ym7101.v $N/ym6045.v $N/ym6046.v $N/ym_lib.v $N/tmss.v $N/vram.v $N/ym3438*.v ../../rtl/ram_md.v spram.v -MAKEFLAGS "OPT_GLOBAL=-O2 OPT_FAST=-O2 OPT_SLOW=-O1" -Mdir $O "$@" 2>&1 \
 | grep -E "%Error" | head
