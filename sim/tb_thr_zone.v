//========================================================
// tb_thr_zone —— 帧级自适应阈值 v2 三区间查表逻辑验证
// 把 canny_top 里的统计+查表逻辑摘出来单独仿真：
//   输入：一帧内 c_lo(1~31)/c_mid(32~95)/c_hi(>=96) 三个计数
//   帧尾：强边缘主导→40、中等主导→48、噪声主导→64、全零→32
//========================================================
`timescale 1ns/1ps
module tb_thr_zone;
    reg          clk, rst_n, tuser;
    reg [7:0]    m8;                    //每拍喂一个 mag8 样本
    reg          valid;
    wire [7:0]   thr;

    reg [19:0] c_lo, c_mid, c_hi;
    reg [7:0]  T;
    integer fails, i;

    // 与 canny_top 相同的统计+查表逻辑（只支持单路，计数规则一致）
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            c_lo <= 20'd0; c_mid <= 20'd0; c_hi <= 20'd0; T <= 8'd48;
        end else begin
            if(tuser) begin
                if((c_lo + c_mid + c_hi) == 20'd0)  T <= 8'd32;
                else if({c_hi, 2'b00} >= c_lo)      T <= 8'd40;
                else if(c_mid >= c_lo)              T <= 8'd48;
                else                                T <= 8'd64;
                c_lo <= 20'd0; c_mid <= 20'd0; c_hi <= 20'd0;
            end
            if(valid) begin
                c_lo  <= c_lo  + ((m8 > 8'd0 && m8 < 8'd32));
                c_mid <= c_mid + ((m8 >= 8'd32 && m8 < 8'd96));
                c_hi  <= c_hi  + (m8 >= 8'd96);
            end
        end
    end
    assign thr = T;

    task check(input integer idx, input integer exp);
        begin
            #10;
            if(thr !== exp) begin
                $display("FAIL %0d: thr=%0d（期望 %0d）", idx, thr, exp);
                fails = fails + 1;
            end else
                $display("PASS %0d: thr=%0d", idx, thr);
        end
    endtask

    initial begin
        clk = 0; forever #5 clk = ~clk;
    end

    initial begin
        fails = 0; rst_n = 0; tuser = 0; valid = 0; m8 = 0;
        #20 rst_n = 1; #10;

        // ===== 场景 1：纹理丰富画面（强边缘主导：hi*4 >= lo）→ 期望 40 =====
        for(i=0; i<100; i=i+1) begin @(posedge clk); valid=1; m8=8'd100; end   //100 个强边缘
        for(i=0; i<50;  i=i+1) begin @(posedge clk); valid=1; m8=8'd10;  end   //50 个弱噪声
        for(i=0; i<30;  i=i+1) begin @(posedge clk); valid=1; m8=8'd50;  end   //30 个中等
        @(posedge clk); valid=0; tuser=1; @(posedge clk); tuser=0;
        check(1, 40);

        // ===== 场景 2：中等主导（hi*4 < lo 且 mid >= lo）→ 期望 48 =====
        for(i=0; i<5;  i=i+1) begin @(posedge clk); valid=1; m8=8'd100; end
        for(i=0; i<40; i=i+1) begin @(posedge clk); valid=1; m8=8'd50;  end
        for(i=0; i<30; i=i+1) begin @(posedge clk); valid=1; m8=8'd10;  end
        @(posedge clk); valid=0; tuser=1; @(posedge clk); tuser=0;
        check(2, 48);

        // ===== 场景 3：噪声主导（lo 最多）→ 期望 64 =====
        for(i=0; i<20; i=i+1) begin @(posedge clk); valid=1; m8=8'd100; end
        for(i=0; i<20; i=i+1) begin @(posedge clk); valid=1; m8=8'd50;  end
        for(i=0; i<100;i=i+1) begin @(posedge clk); valid=1; m8=8'd8;   end
        @(posedge clk); valid=0; tuser=1; @(posedge clk); tuser=0;
        check(3, 64);

        // ===== 场景 4：全零帧 → 期望 32 =====
        @(posedge clk); tuser=1; @(posedge clk); tuser=0;
        check(4, 32);

        // ===== 场景 5：边界——hi*4 == lo（强边缘主导成立）→ 期望 40 =====
        for(i=0; i<10; i=i+1) begin @(posedge clk); valid=1; m8=8'd100; end
        for(i=0; i<40; i=i+1) begin @(posedge clk); valid=1; m8=8'd10;  end
        @(posedge clk); valid=0; tuser=1; @(posedge clk); tuser=0;
        check(5, 40);

        // ===== 场景 6：边界——hi*4 < lo 且 mid == lo（中等主导）→ 期望 48 =====
        for(i=0; i<9;  i=i+1) begin @(posedge clk); valid=1; m8=8'd100; end
        for(i=0; i<40; i=i+1) begin @(posedge clk); valid=1; m8=8'd10;  end
        for(i=0; i<40; i=i+1) begin @(posedge clk); valid=1; m8=8'd50;  end
        @(posedge clk); valid=0; tuser=1; @(posedge clk); tuser=0;
        check(6, 48);

        $display("===== 结束：%0d 失败 =====", fails);
        $finish;
    end
endmodule
