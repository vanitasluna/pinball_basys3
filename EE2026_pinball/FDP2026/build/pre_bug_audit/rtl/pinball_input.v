`timescale 1ns / 1ps
// Two-stage synchronization and independent 10 ms button debouncers.
module pinball_input #(parameter STABLE_CYCLES = 1000000)(
    input clk, reset, input [4:0] raw,
    output reg [4:0] down, output reg [4:0] pressed
);
    (* ASYNC_REG = "TRUE" *) reg [4:0] sync1, sync2;
    reg [19:0] count [0:4];
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            sync1 <= 0; sync2 <= 0; down <= 0; pressed <= 0;
            for (i=0; i<5; i=i+1) count[i] <= 0;
        end else begin
            sync1 <= raw; sync2 <= sync1; pressed <= 0;
            for (i=0; i<5; i=i+1) begin
                if (sync2[i] == down[i]) count[i] <= 0;
                else if (count[i] == STABLE_CYCLES-1) begin
                    down[i] <= sync2[i];
                    pressed[i] <= sync2[i];
                    count[i] <= 0;
                end else count[i] <= count[i]+1'b1;
            end
        end
    end
endmodule
