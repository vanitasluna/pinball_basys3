`timescale 1ns/1ps
`default_nettype none
// 100 MHz -> 1 GHz VCO -> 40 MHz, standard 800x600 timing.
module pinball_vga_clock(input wire clk,reset,output wire pixel_clk,locked);
    wire feedback_raw,feedback,clock_raw;
    MMCME2_BASE #(.BANDWIDTH("OPTIMIZED"),.CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1),.CLKFBOUT_MULT_F(10.0),.CLKOUT0_DIVIDE_F(25.0),
        .STARTUP_WAIT("FALSE")) mmcm(
        .CLKIN1(clk),.RST(reset),.PWRDWN(1'b0),.CLKFBIN(feedback),
        .CLKFBOUT(feedback_raw),.CLKOUT0(clock_raw),.LOCKED(locked),
        .CLKFBOUTB(),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
        .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
    BUFG feedback_buffer(.I(feedback_raw),.O(feedback));
    BUFG clock_buffer(.I(clock_raw),.O(pixel_clk));
endmodule
`default_nettype wire
