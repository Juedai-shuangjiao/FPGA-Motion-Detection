//========================================================
// tb：canny_imp 改进 Canny 全套仿真
// 场景（帧 32×16，每帧独立注入）：
//   帧1 水平线强弱混合（x8~11 强差255 / x12~15 弱差120）——验证行内滞后：
//       无滞后弱段断链（最长 4 连）；有滞后弱段接强段（最长 8 连）
//   帧2 45° 斜线（对角渐变）——验证 8 方向 Sobel 斜边响应（自适应阈值后检出）
//   帧3 小噪点（差 20）+ 平坦——双阈值滤除（统计帧）
//   帧4 暗场景局部弱边缘（差 16）——自适应阈值检出（固定 40 必漏）
//========================================================
`timescale 1ns/1ps
module tb_canny_imp;
    parameter W = 32, H = 16;
    reg clk, rst_n;
    reg [7:0] gray; reg vld; reg fs;
    wire Oe; wire Ov;
    integer fails = 0;

    canny_imp #(.IMG_W(W), .IMG_H(H)) u_dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_gray(gray), .I_vld(vld), .I_fs(fs),
        .O_edge(Oe), .O_vld(Ov)
    );
    initial begin clk=0; forever #5 clk=~clk; end

    // 输出收集
    reg [31:0] row_out [0:H-1];     //每行输出 1bit 串（32 像素全宽）
    integer ox, oy;
    integer dbg_ocnt;               //O_vld 总拍计数
    integer dbg_ecnt;               //Oe=1 拍计数
    always @(posedge clk) begin
        if(Ov) begin
            dbg_ocnt <= dbg_ocnt + 1;
            if(Oe) dbg_ecnt <= dbg_ecnt + 1;
            row_out[oy] <= (row_out[oy] << 1) | Oe;
            if(ox == W-1) begin ox<=0; if(oy==H-1) oy<=0; else oy<=oy+1; end
            else ox<=ox+1;
        end
        if(fs) begin ox<=0; oy<=0; dbg_ocnt<=0; dbg_ecnt<=0; end
    end

    //---------- 帧注入 task ----------
    task inject_frame(input integer fid);
        integer px, py;
        reg [7:0] pv;
        begin
            // 帧开始
            @(posedge clk); fs <= 1'b1; vld <= 1'b0; @(posedge clk); fs <= 1'b0;
            @(posedge clk);
            for(py=0; py<H; py=py+1) begin
                for(px=0; px<W; px=px+1) begin
                    pv = frame_val(fid, px, py);
                    gray <= pv; vld <= 1'b1; @(posedge clk);
                end
            end
            vld <= 1'b0;
            // 帧间间隔
            repeat(4) @(posedge clk);
        end
    endtask

    //---------- 场景像素生成 ----------
    function [7:0] frame_val(input integer fid, px, py);
        begin
            case(fid)
            1: begin   //水平线 y=5：x8~11 强(255 vs 0)、x12~15 弱(120 vs 0)
                if(py==5 && px>=8 && px<=11) frame_val = 8'd255;
                else if(py==5 && px>=12 && px<=15) frame_val = 8'd120;
                else frame_val = 8'd0;
            end
            2: begin   //45° 斜线：主对角方向渐变带（x+y 附近阶跃）
                if(px>=10 && px<=16 && py>=4 && py<=10 && (px-10)==(py-4))
                    frame_val = 8'd200;
                else if(px>=10 && px<=16 && py>=4 && py<=10 && (px-11)==(py-4))
                    frame_val = 8'd64;
                else frame_val = 8'd0;
            end
            3: begin   //孤立小噪点（差 20）：x=5,y=5 与 x=25,y=12
                if((px==5 && py==5) || (px==25 && py==12)) frame_val = 8'd20;
                else frame_val = 8'd0;
            end
            4: begin   //暗场景局部弱边缘（差 16）：竖线 x=8, y=3~10，其余平坦 8
                if(px==8 && py>=3 && py<=10) frame_val = 8'd24;
                else frame_val = 8'd8;
            end
            default: frame_val = 8'd0;
            endcase
        end
    endfunction

    //---------- 行内最长 1 连段统计 ----------
    function [15:0] row_maxrun(input integer ry);
        integer b, run, mx;
        begin
            run=0; mx=0;
            for(b=0; b<W; b=b+1) begin
                if(row_out[ry] & (32'h1 << b)) run=run+1; else begin if(run>mx) mx=run; run=0; end
            end
            if(run>mx) mx=run;
            row_maxrun = mx;
        end
    endfunction

    integer r; reg found;
    initial begin
        rst_n = 0; gray=0; vld=0; fs=0; ox=0; oy=0;
        for(r=0;r<H;r=r+1) row_out[r] <= 32'd0;
        #30 rst_n = 1;
        repeat(3) @(posedge clk);

        //---------- 场景1：行内滞后（默认阈值 40/20）----------
        inject_frame(1);
        // 等输出收集完成（输出延迟若干拍，注入结束 + 输出流水落后）
        repeat(40) @(posedge clk);
        
        for(r=0; r<H; r=r+1) $display("DBG row_out[%0d]=%h", r, row_out[r]);
        found = 0;
        begin : s1max
            integer mrun;
            mrun = 0;
            for(r=0; r<H; r=r+1) if(row_maxrun(r) > mrun) mrun = row_maxrun(r);
            $display("场景1 滞后连接：全局最长连段 = %0d（无滞后应<=4，有滞后>=6）", mrun);
            if(mrun >= 6) found = 1;
        end
        if(!found) begin
            $display("FAIL: 弱边缘未接上强边缘（无滞后断链）"); fails = fails+1;
        end else $display("PASS: 弱边缘经行内滞后接上强段（8 连）");

        //---------- 场景2：45° 斜线（8 方向）----------
        inject_frame(2);
        repeat(40) @(posedge clk);
        found = 0;
        for(r=0; r<H; r=r+1) begin
            if(row_out[r] != 32'h0) found = 1;
        end
        
        $display("场景2 斜边检测：任一输出 = %0d", found);
        if(!found) begin $display("FAIL: 45° 斜线未检出（8 方向响应失效）"); fails = fails+1; end
        else $display("PASS: 45° 斜线检出（8 方向 Sobel 生效）");

        //---------- 场景3：噪点滤除（统计帧，阈值仍为帧2 自适应值或默认）----------
        inject_frame(3);
        repeat(40) @(posedge clk);
        found = 0;
        for(r=0; r<H; r=r+1) if(row_out[r] != 16'h0000) found = 1;
        $display("场景3 噪点滤除：任一输出 = %0d", found);
        if(found) begin $display("FAIL: 小噪点未被滤除"); fails = fails+1; end
        else $display("PASS: 小噪点滤除");

        //---------- 场景4：暗场景弱边缘（自适应阈值，帧3 统计→帧4 应用）----------
        inject_frame(4);
        repeat(40) @(posedge clk);
        found = 0;
        for(r=0; r<H; r=r+1) if(row_out[r] != 16'h0000) found = 1;
        $display("场景4 暗场景自适应：任一输出 = %0d（固定 40 必漏）", found);
        if(!found) begin $display("FAIL: 自适应阈值未生效（弱边缘漏检）"); fails = fails+1; end
        else $display("PASS: 自适应阈值检出暗场景弱边缘");

        $display("===== 结束：%0d 失败 =====", fails);
        $finish;
    end
endmodule
