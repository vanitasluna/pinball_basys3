`timescale 1ns / 1ps
module pinball_sevenseg(input clk, reset, input [15:0] bcd,
    output reg [6:0] seg, output reg [3:0] an, output dp);
    reg [16:0] scan;
    reg [3:0] digit;
    assign dp=1'b1;
    always @(posedge clk) if(reset) scan<=0; else scan<=scan+1'b1;
    always @* begin
        case(scan[16:15])
            0: begin an=4'b1110; digit=bcd[3:0]; end
            1: begin an=4'b1101; digit=bcd[7:4]; end
            2: begin an=4'b1011; digit=bcd[11:8]; end
            default: begin an=4'b0111; digit=bcd[15:12]; end
        endcase
        case(digit)
            0:seg=7'b1000000; 1:seg=7'b1111001; 2:seg=7'b0100100;
            3:seg=7'b0110000; 4:seg=7'b0011001; 5:seg=7'b0010010;
            6:seg=7'b0000010; 7:seg=7'b1111000; 8:seg=7'b0000000;
            9:seg=7'b0010000; default:seg=7'b1111111;
        endcase
    end
endmodule
