`timescale 1ns/1ps
// VESA 800x600: 40 MHz, 1056x628 total, positive sync, 60.317 Hz.
module pinball_vga(input clk,reset,input [15:0] pixel,
    output [6:0] x,output [5:0] y,output frame_begin,
    output [9:0] pixel_x,pixel_y,
    output reg [3:0] red,green,blue,output reg hsync,vsync);
    reg [10:0] h;
    reg [9:0] v;
    wire in_table=h>=16 && h<784 && v>=32 && v<544;
    wire visible=h<800 && v<600;
    // Coordinates outside active video are clamped, avoiding 10-bit wrap.
    assign pixel_x=h<800 ? h[9:0] : 10'd0;
    assign pixel_y=v<600 ? v : 10'd0;
    assign x=in_table ? (h-11'd16)>>3 : 0;
    assign y=in_table ? (v-10'd32)>>3 : 0;
    assign frame_begin=h==0 && v==0;
    always @(posedge clk or posedge reset) begin
        if(reset) begin h<=0;v<=0;red<=0;green<=0;blue<=0;hsync<=0;vsync<=0;end
        else begin
            if(h==1055) begin h<=0;v<=v==627 ? 0 : v+1'b1;end
            else h<=h+1'b1;
            hsync<=h>=840 && h<968;
            vsync<=v>=601 && v<605;
            red<=visible ? pixel[15:12] : 0;
            green<=visible ? pixel[10:7] : 0;
            blue<=visible ? pixel[4:1] : 0;
        end
    end
endmodule
