/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 13 2026 17:14:59
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module blk_mem_gen_frame_diff
(
  output  [7:0]                 doa,
  input   [7:0]                 dia,
  input   [15:0]                addra,
  input                         wea,
  input                         clka,
  output  [7:0]                 dob,
  input   [15:0]                addrb,
  input   [7:0]                 dib,
  input                         web
);

  ram_8eb6fbd14703
  #(
      .DATA_WIDTH_A(8),
      .ADDR_WIDTH_A(16),
      .DATA_DEPTH_A(65536),
      .DATA_WIDTH_B(8),
      .ADDR_WIDTH_B(16),
      .DATA_DEPTH_B(65536),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("READBEFOREWRITE"),
      .RESETMODE_B("ASYNC")
  )ram_8eb6fbd14703_Inst
  (
      .doa(doa),
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb),
      .dib(dib),
      .web(web)
  );
endmodule
