`timescale 1ns/1ps
module tb_geometry_oracle;
    `include "count.vh"
    reg [71:0] vectors [0:COUNT-1];
    reg signed [15:0] proposed_x, proposed_y, velocity_x, velocity_y;
    reg signed [15:0] previous_x, previous_y;
    reg in_lane = 0;
    reg [2:0] left_angle = 0, right_angle = 0;
    reg left_pressed = 0, right_pressed = 0, left_moving = 0, right_moving = 0;
    reg signed [15:0] moving_bumper_previous_y = 5632, moving_bumper_next_y = 5632;
    reg signed [15:0] moving_bumper_velocity_y = 0;
    reg signed [15:0] moving_bumper_previous_x = 14848, moving_bumper_next_x = 14848;
    reg signed [15:0] moving_bumper_velocity_x = 0;
    wire signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy;
    wire [13:0] hit_events;
    integer i;
    pinball_collision dut (.*);
    initial begin
        $readmemh("octagon.hex", vectors);
        for (i=0; i<COUNT; i=i+1) begin
            previous_x=16'sd10752+$signed(vectors[i][71:56]);
            previous_y=16'sd8960+$signed(vectors[i][55:40]);
            velocity_x=$signed(vectors[i][39:24]);
            velocity_y=$signed(vectors[i][23:8]);
            proposed_x=previous_x+velocity_x;
            proposed_y=previous_y+velocity_y;
            #1;
            if (hit_events[2] !== vectors[i][0]) begin
                $display("FAIL vector=%0d old=(%0d,%0d) v=(%0d,%0d) expected=%b hits=%h", i,
                    previous_x-10752, previous_y-8960, velocity_x, velocity_y, vectors[i][0], hit_events);
                $fatal(1);
            end
        end
        $display("PASS tb_geometry_oracle (%0d exact segment checks)", COUNT);
        $finish;
    end
endmodule
