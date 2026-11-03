# ============================================================
#  FPGACompetition timing constraints (SDC)
#  Based on official lab_ex3 camera_to_dsi_display.sdc
# ============================================================

# 1) Main clock: 50MHz onboard crystal (pin C4), 20ns period
create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]

# 1b) DDR reference clock: 复用 C4 的 50MHz 晶振（官方同款接法，见 pin.adc I_sys_clk）
# create_clock -name {ddr_ref_clk_100m} -period 10.000 -waveform {0.000 5.000} [get_ports {I_ddr_ref_clk_p}]

# 2) MIPI HS receive clock (differential pair positive IO_rx_clk_pad_p), 4.167ns ~ 240MHz
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

# 3) Derive output clocks of PLL / MIPI / DDR hard IPs automatically
derive_clocks

# 4) Rename PLL output clocks
#    clkc[0]=100M  clkc[1]=24M  clkc[4]=HDMI pixel 74.25M  clkc[5]=HDMI serial 371.25M
rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

# 5) Rename MIPI recovered byte clock (for CSI / ISP / video_in)
rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]

# 6) Asynchronous clock-domain groups (no cross-domain timing check)
#    Group3 (HDMI domain) is separated from Group2 (PLL low-speed domain) because
#    the 24M->75M config signals cross through 2-stage synchronizers in hdmi_mixer,
#    whose first stage intentionally samples the async signal (metastability allowed).
set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m}] \
    -group [get_clocks {HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/*}]
