// tb_mark_smooth：验证 hdmi_mixer 撕裂平滑行缓冲（1650 拍对齐账）
// 模型与 hdmi_mixer.v 的行缓冲块完全一致（复制），验证：
//   1. prev(T) = comb(T-1650) = 上一行同列
//   2. smooth = 本行 | 上一行（交界断口填补）
module tb_mark_smooth;
    reg        clk;
    reg        rst_n;
    reg        de;         //显示期（1280 拍/行）
    reg        mark_comb;  //当前行当前列 mark（x_2d 域注入）

    // —— 与 hdmi_mixer.v 相同的行缓冲块（mark_comb 为寄存器注入，x 拍稳定，无竞争）——
    reg [1649:0] S_mark_line;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            S_mark_line <= 1650'd0;
        else
            S_mark_line <= {S_mark_line[1648:0], de ? mark_comb : 1'b0};
    end
    wire S_mark_prev = S_mark_line[1649];
    wire mark_smooth = mark_comb | S_mark_prev;

    // 行周期模型：1650 拍/行（de 1280 + 消隐 370）
    reg [10:0] x;
    reg [10:0] y;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x <= 11'd0;
            y <= 11'd0;
        end else begin
            if(x == 11'd1649) begin
                x <= 11'd0;
                y <= y + 11'd1;
            end else
                x <= x + 11'd1;
        end
    end
    always @(*) de = (x < 11'd1280);

    // mark 注入（posedge 更新：x=99 拍置位 → x=100 拍稳定，与真实 ERAM 寄存器路径同拍）：
    // 行 1 第 100 列 = 1；行 2 第 100 列 = 0（交界断口）；行 3 第 100 列 = 1；行 4 第 101 列 = 1
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            mark_comb <= 1'b0;
        else begin
            if(y == 11'd1 && x == 11'd99)
                mark_comb <= 1'b1;
            else if(y == 11'd3 && x == 11'd99)
                mark_comb <= 1'b1;
            else if(y == 11'd4 && x == 11'd100)
                mark_comb <= 1'b1;
            else
                mark_comb <= 1'b0;
        end
    end

    integer fails;
    initial begin
        fails = 0;
        clk = 1'b0;
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // 场景1：行2 第100列（断口）→ smooth 应 = 1（上一行同列 1 填补）
        while(!(y == 11'd2 && x == 11'd99)) @(posedge clk);
        @(negedge clk);   //x=100 拍内采样（mark_comb 已稳定）
        if(mark_smooth !== 1'b1) begin
            $display("FAIL 场景1: 行2列100 smooth=%b（期望1，上一行填补）", mark_smooth);
            fails = fails + 1;
        end else
            $display("PASS 场景1: 断口被上一行填补 smooth=1");

        // 场景2：行2 第101列（断口行非断口列）→ smooth 应 = 0（无串列污染）
        while(!(y == 11'd2 && x == 11'd100)) @(posedge clk);
        @(negedge clk);
        if(mark_smooth !== 1'b0) begin
            $display("FAIL 场景2: 行2列101 smooth=%b（期望0，列对齐无串列）", mark_smooth);
            fails = fails + 1;
        end else
            $display("PASS 场景2: 列对齐正确无串列");

        // 场景3：行3 第100列（本行有 mark）→ smooth = 1（本行）
        while(!(y == 11'd3 && x == 11'd99)) @(posedge clk);
        @(negedge clk);
        if(mark_smooth !== 1'b1) begin
            $display("FAIL 场景3: 行3列100 smooth=%b（期望1，本行mark）", mark_smooth);
            fails = fails + 1;
        end else
            $display("PASS 场景3: 本行 mark 正常");

        // 场景4：行4 第100列（无 mark 且上一行同列=1）→ smooth = 1（严格同列填补）
        while(!(y == 11'd4 && x == 11'd99)) @(posedge clk);
        @(negedge clk);
        if(mark_smooth !== 1'b1) begin
            $display("FAIL 场景4: 行4列100 smooth=%b（期望1，行3同列填补）", mark_smooth);
            fails = fails + 1;
        end else
            $display("PASS 场景4: 严格同列填补");

        // 场景5：行4 第99列（无 mark 且行3第99列=0）→ smooth = 0
        while(!(y == 11'd4 && x == 11'd98)) @(posedge clk);
        @(negedge clk);
        if(mark_smooth !== 1'b0) begin
            $display("FAIL 场景5: 行4列99 smooth=%b（期望0）", mark_smooth);
            fails = fails + 1;
        end else
            $display("PASS 场景5: 无 mark 区不误涂白");

        if(fails == 0)
            $display("=== tb_mark_smooth 全绿 ===");
        else
            $display("=== tb_mark_smooth 失败 %0d 项 ===", fails);
        $finish;
    end

    always #6.734 clk = ~clk;   //74.25MHz
endmodule
