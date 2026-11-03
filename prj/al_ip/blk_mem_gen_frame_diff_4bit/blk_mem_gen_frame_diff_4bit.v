/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 16 2026 20:36:30
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module blk_mem_gen_frame_diff_4bit
(
  output  [3:0]                 doa,
  input   [3:0]                 dia,
  input   [15:0]                addra,
  input                         wea,
  input                         clka,
  output  [3:0]                 dob,
  input   [15:0]                addrb,
  input   [3:0]                 dib,
  input                         web
);

  ram_95382a6c57c4
  #(
      .DATA_WIDTH_A(4),
      .ADDR_WIDTH_A(16),
      .DATA_DEPTH_A(65535),
      .DATA_WIDTH_B(4),
      .ADDR_WIDTH_B(16),
      .DATA_DEPTH_B(65535),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("READBEFOREWRITE"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("READBEFOREWRITE"),
      .RESETMODE_B("ASYNC")
  )ram_95382a6c57c4_Inst
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
