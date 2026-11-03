#!/bin/bash
# tb_bg_line 编译运行（verilator，WSL）
set -e
cd "$(dirname "$0")"
ROOT=/mnt/e/FPGA_Code/FPGACompetition_bugfix
SRC=$ROOT/src
export VERILATOR_ROOT=$HOME/verilator_local/usr/share/verilator
rm -rf obj_dir
~/verilator_local/usr/bin/verilator_bin --binary --timing -Wno-fatal --public-flat-rw \
    --top-module tb_bg_line tb_bg_line.v \
    $SRC/hdl_source_clean/bg_read.v \
    $SRC/hdl_source_clean/morph_filter.v \
    $SRC/hdl_source_clean/isp/data96_128/data_128bit_to_96bit.v \
    $SRC/ip_source/w128_d512_fifo/w128_d512_fifo.v \
    $SRC/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v 2>&1 | grep -E '^%Error' | head -5
./obj_dir/Vtb_bg_line
