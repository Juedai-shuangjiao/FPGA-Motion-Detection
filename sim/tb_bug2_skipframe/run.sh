#!/bin/bash
# tb_bug2_skipframe 编译运行（iverilog，WSL）
set -e
cd "$(dirname "$0")"
ROOT=/mnt/e/FPGA_Code/FPGACompetition_bugfix
SRC=$ROOT/src
iverilog -g2012 -o tb_bug2.vvp \
    tb_bug2_skipframe.v \
    $SRC/hdl_source_clean/video_in.v \
    $SRC/ip_source/w128_d512_fifo/w128_d512_fifo.v \
    $SRC/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v
vvp tb_bug2.vvp
