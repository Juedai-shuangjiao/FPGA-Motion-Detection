//========================================================
// tb：motion_detect SW3/SW4 组合模式 + 背景采集状态机仿真
// 覆盖场景（2026-11-02 用户要求）：
//   1. 上电 SW=00 不采集、门控保持关
//   2. 拨到 01（模式2）：防抖 6 帧内不采 → 第 6 帧 tuser 后采 → 采满 1 帧
//   3. 采集帧期间 bg_captured 保持 0（修复验证：背景写完才开门）
//   4. 采集帧结束后 bg_captured=1
//   5. 冷却 180 帧内拨码不重复触发
//   6. 冷却后拨 10（模式3）、11（模式4）都触发
//   7. 模式 00 拨码变化不触发（不需要背景）
// 帧结构简化：FRAME_PERIOD=100 拍/帧（tuser 每 100 拍 1 拍），逻辑与帧周期无关
//========================================================
`timescale 1ns/1ps
module tb_sw34_capture;
    reg         clk, rst_n;
    reg         tuser, tvalid;
    reg [95:0]  tdata;
    reg         sw3, sw4;
    reg [95:0]  bg_data;
    reg         bg_valid, bg_frame_start;
    wire        o_capture, o_captured;

    localparam FRAME_PERIOD = 100;

    motion_detect u_dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tdata(tdata), .I_tvalid(tvalid), .I_tlast(1'b0), .I_tuser(tuser),
        .I_sw4(sw4), .I_sw3(sw3),
        .I_bg_data(bg_data), .I_bg_valid(bg_valid), .I_bg_frame_start(bg_frame_start),
        .O_tvalid(), .O_tlast(), .O_tuser(),
        .O_bg_capture(o_capture), .O_bg_captured(o_captured)
    );

    integer t;          //全局时间
    integer fails = 0;
    integer cap_rise_t, cap_fall_t, captured_rise_t;
    integer cap_cnt = 0;

    task check(input name, input cond);
        begin
            if(!cond) begin
                $display("FAIL @ %0d : %0s", t, name);
                fails = fails + 1;
            end else
                $display("PASS @ %0d : %0s", t, name);
        end
    endtask

    // 帧产生器：tuser 每 FRAME_PERIOD 拍 1 拍
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tuser <= 1'b0; tvalid <= 1'b0;
        end else begin
            if((t % FRAME_PERIOD) == 0)
                tuser <= 1'b1;
            else
                tuser <= 1'b0;
            tvalid <= 1'b1;
        end
    end

    initial begin
        clk = 0; forever #5 clk = ~clk;   //100MHz
    end

    initial begin
        // 初始化
        t = 0;
        rst_n = 0; sw3 = 0; sw4 = 0; tdata = 0; bg_data = 0; bg_valid = 0; bg_frame_start = 0;
        #50 rst_n = 1;
        #20;   //t=70

        // 场景1：上电 SW=00，5 帧不采集
        #(5 * FRAME_PERIOD * 10);
        check("场景1: 上电00不采集", (o_capture == 1'b0) && (o_captured == 1'b0));

        // 场景2：拨到 01（模式2 涂白）——防抖 6 帧
        sw4 = 1'b1;   //SW4 拨下 → 01
        #(2 * FRAME_PERIOD * 10);
        check("场景2a: 防抖2帧后未采", o_capture == 1'b0);
        check("场景2b: 防抖期门控关(bg_captured=0)", o_captured == 1'b0);
        #(3 * FRAME_PERIOD * 10);
        check("场景2c: 防抖5帧后未采", o_capture == 1'b0);
        #(2 * FRAME_PERIOD * 10);
        // 第 7 帧 tuser 后应已进入采集（防抖 6 帧：tuser 计 1~6，第 6 帧 tuser 时 cnt>=6 → 采集）
        // 采样：等第 7 帧末
        #(FRAME_PERIOD * 10);

        // 场景3/4：采集帧期间 captured=0；采完 captured=1
        check("场景3: 采满1帧后 capture 回落", o_capture == 1'b0);
        check("场景4: 采集完成后 captured=1", o_captured == 1'b1);

        // 场景5：冷却期（180帧）内拨码不触发——拨回 00 再拨 01
        sw4 = 0;   //00
        #(2 * FRAME_PERIOD * 10);
        sw4 = 1'b1;   //01 再拨（距上次采集约 2 帧 << 180 冷却）
        #(10 * FRAME_PERIOD * 10);
        check("场景5: 冷却期重拨不重复采", o_capture == 1'b0);
        sw4 = 0;

        // 场景6：冷却过后拨 10（模式3 外接框）触发
        #(200 * FRAME_PERIOD * 10);   //等冷却 180 帧过
        sw3 = 1'b1;   //10
        #(12 * FRAME_PERIOD * 10);
        check("场景6: 模式3触发采集后完成", o_captured == 1'b1);

        // 场景7：冷却后再拨 11（模式4 区域填充）也触发（模式4修正验证）
        #(200 * FRAME_PERIOD * 10);
        sw4 = 1'b1;   //11
        #(12 * FRAME_PERIOD * 10);
        check("场景7: 模式4也触发采集(修正)", o_captured == 1'b1);

        // 场景8：拨回 00 不触发（不需要背景）
        sw3 = 0; sw4 = 0;
        #(5 * FRAME_PERIOD * 10);
        check("场景8: 00模式不触发", o_capture == 1'b0);

        $display("===== 仿真结束：%0d 个失败 =====", fails);
        $finish;
    end

    // 采集帧内 captured 保持 0 的实时检查（修复核心验证）
    always @(posedge clk) begin
        t = t + 1;
        if(o_capture && o_captured) begin
            $display("FAIL @ %0d : 采集帧期间 bg_captured 提前置1（背景未写完就开门）", t);
            fails = fails + 1;
        end
    end
endmodule
