/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 14 2026 16:56:19
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module blk_mem_gen_motion_hist
(
  output  [0:0]                 doa,
  input   [0:0]                 dia,
  input   [15:0]                addra,
  input                         wea,
  input                         cea,
  input                         clka,
  output  [0:0]                 dob,
  input   [15:0]                addrb,
  input                         clkb,
  input   [0:0]                 dib,
  input                         web
);

  ram_3d187d2d083c
  #(
      .DATA_WIDTH_A(1),
      .ADDR_WIDTH_A(16),
      .DATA_DEPTH_A(65535),
      .DATA_WIDTH_B(1),
      .ADDR_WIDTH_B(16),
      .DATA_DEPTH_B(65535),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("READBEFOREWRITE"),
      .RESETMODE_B("ASYNC")
  )ram_3d187d2d083c_Inst
  (
      .doa(doa),
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .cea(cea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb),
      .clkb(clkb),
      .dib(dib),
      .web(web)
  );
endmodule
