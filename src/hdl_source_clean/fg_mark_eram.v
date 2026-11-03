//========================================================
// 模块：fg_mark_eram —— 前景标记片内 ERAM（主线：全分辨率 1×1 前景检测）
// 功能：40bit × 23040 深真双口 ERAM，存全帧前景标记（1bit/像素 × 1280×720 = 921600bit）。
//       A 口（DDR 域 usr_clk 100M）：消隐期写前景标记；B 口（HDMI 域 75M）：显示期读前景标记。
// 布局：1280×720，每行 1280 像素 = 32 字（1280/40 整除），整帧 720×32 = 23040 字。
//       字地址 = y*32 + w（y = 行 0~719，w = 行内字 0~31）。
//       字内位序：bit0 = 该字最左像素（字内第 0 个），bit39 = 该字最右像素（字内第 39 个）。
// 资源：ERAM「512×40」配置，23040 = 45×512 精确整除 → 恰好 45 块（零浪费，占 108 块的 42%）。
//       深度必须精确 23040，取 2 的幂 32768 会白费 19 块（见《消隐期读+前景标记片内方案.md》第四节）。
// 延迟：B 口同步读（NOREG）延迟 1 拍。
//========================================================
module fg_mark_eram (
    input  wire        I_clka,    //写时钟（DDR 域 usr_clk 100M，消隐期写前景标记）
    input  wire [14:0] I_addra,   //写地址 0~23039（每地址 40 像素前景标记）
    input  wire [39:0] I_dia,     //写数据（40 像素前景标记）
    input  wire        I_wea,     //写使能
    input  wire        I_clkb,    //读时钟（HDMI 域 75M，显示期读前景标记）
    input  wire [14:0] I_addrb,   //读地址 0~23039
    output wire [39:0] O_dob      //读数据（同步读，延迟 1 拍）
);

    // PH1P_LOGIC_ERAM 原语直接例化：位宽 40 正好匹配「512×40」配置，
    // 深度 23040 由 TD mapper 自动级联 45 块（与 GUI 生成 IP 的 RTL 同结构）。
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(40),
        .DATA_WIDTH_B(40),
        .ADDR_WIDTH_A(15),
        .ADDR_WIDTH_B(15),
        .DATA_DEPTH_A(23040),
        .DATA_DEPTH_B(23040),

        .MODE("DP"),
        .REGMODE_A("NOREG"),
        .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),

        .IMPLEMENT("20K"),

        .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"),

        .CLKMODE("ASYNC"),

        .SSROVERCE("DISABLE"),

        .OREGSET_A("RESET"),
        .OREGSET_B("RESET"),

        .RESETMODE_A("ASYNC"),
        .RESETMODE_B("ASYNC"),

        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC"),

        .INIT_FILE("NONE"),
        .FILL_ALL("NONE")
    ) u_ph1p_logic_eram (
        .dia(I_dia),
        .dib(40'b0),
        .addra(I_addra),
        .addrb(I_addrb),

        .cea(1'b1),
        .ceb(1'b1),
        .ocea(1'b0),
        .oceb(1'b0),
        .clka(I_clka),
        .clkb(I_clkb),

        .wea(I_wea),
        .web(1'b0),
        .bea(1'b0),
        .beb(1'b0),

        .rsta(1'b0),
        .rstb(1'b0),

        .doa(),
        .ecc_sbiterr(),
        .ecc_dbiterr(),
        .ecc_sbiterrinj(1'b0),
        .ecc_dbiterrinj(1'b0),
        .dob(O_dob)
    );

endmodule
