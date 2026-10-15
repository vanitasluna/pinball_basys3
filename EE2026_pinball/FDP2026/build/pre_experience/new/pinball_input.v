`timescale 1ns / 1ps
`default_nettype none
// Two-stage synchronization and independent debounce channels.
// STABLE_CYCLES must be positive: default 10 ms, board configuration 5 ms.
module pinball_input #(parameter integer STABLE_CYCLES = 1000000)(
    input wire clk, reset, input wire [4:0] raw,
    output reg [4:0] down, output reg [4:0] pressed
);
    (* ASYNC_REG = "TRUE" *) reg [4:0] sync1, sync2;
    // Size to the selected interval. A fixed 20-bit count silently wraps for
    // intervals above 2^20 clocks; retain one bit for the one-sample boundary.
    localparam integer COUNT_WIDTH = STABLE_CYCLES > 1 ? $clog2(STABLE_CYCLES) : 1;
    localparam [COUNT_WIDTH-1:0] LAST_STABLE_COUNT = STABLE_CYCLES-1;
    reg [COUNT_WIDTH-1:0] count [0:4];
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            sync1 <= 0; sync2 <= 0; down <= 0; pressed <= 0;
            for (i=0; i<5; i=i+1) count[i] <= 0;
        end else begin
            sync1 <= raw; sync2 <= sync1; pressed <= 0;
            for (i=0; i<5; i=i+1) begin
                if (sync2[i] == down[i]) count[i] <= 0;
                else if (count[i] == LAST_STABLE_COUNT) begin
                    down[i] <= sync2[i];
                    pressed[i] <= sync2[i];
                    count[i] <= 0;
                end else count[i] <= count[i]+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
