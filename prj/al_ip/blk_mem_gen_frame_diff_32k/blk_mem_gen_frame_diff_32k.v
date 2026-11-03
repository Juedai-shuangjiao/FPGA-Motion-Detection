/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 16 2026 18:19:35
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module blk_mem_gen_frame_diff_32k
(
  output  [7:0]                 doa,
  input   [7:0]                 dia,
  input   [14:0]                addra,
  input                         wea,
  input                         clka,
  output  [7:0]                 dob,
  input   [14:0]                addrb,
  input                         clkb,
  input   [7:0]                 dib,
  input                         web
);

  ram_39e934858901
  #(
      .DATA_WIDTH_A(8),
      .ADDR_WIDTH_A(15),
      .DATA_DEPTH_A(32768),
      .DATA_WIDTH_B(8),
      .ADDR_WIDTH_B(15),
      .DATA_DEPTH_B(32768),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("READBEFOREWRITE"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("READBEFOREWRITE"),
      .RESETMODE_B("ASYNC")
  )ram_39e934858901_Inst
  (
      .doa(doa),
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb),
      .clkb(clkb),
      .dib(dib),
      .web(web)
  );
endmodule
