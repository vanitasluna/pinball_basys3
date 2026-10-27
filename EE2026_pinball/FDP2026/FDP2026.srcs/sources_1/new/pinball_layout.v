`timescale 1ns / 1ps
`default_nettype none

// Four formations with independent lower-table profiles: 64 safe layouts.
// Bits3:2 select the formation, bits1:0 its variant, bit4 the diamond slots,
// and bit5 the outer/inner rectangle tracks. Every coordinate is shared.
// This one definition drives physics, collision and BOTH display renderers.
module pinball_layout (
    input wire [5:0] layout_id,
    output reg [6:0] bumper_left_x, bumper_center_x, bank_x0, bank_x1, bank_x2, spinner_x,
    output reg [5:0] bumper_right_y, bumper_center_y, bank_y, bank_y1, bank_y2, spinner_y, rollover_y,
    output reg [5:0] bumper_y_min, bumper_y_max,
    output reg [6:0] bumper_x_min, bumper_x_max,
    output wire [6:0] sling_left_x, sling_right_x, side_left_x, side_right_x,
    output wire [5:0] sling_left_y, sling_right_y,
    output wire [5:0] side_left_y_min, side_left_y_max, side_right_y_min, side_right_y_max
);
    wire inner_rectangles=layout_id[5];
    wire inner_diamonds=layout_id[4];
    wire cascade=layout_id[3:2]==2'd2;
    assign sling_left_x=inner_diamonds ? 7'd26 : 7'd16;
    assign sling_left_y=inner_diamonds ? 6'd44 : 6'd40;
    assign sling_right_x=inner_diamonds ? 7'd60 : inner_rectangles ? 7'd63 : 7'd69;
    assign sling_right_y=inner_diamonds ? 6'd44 : inner_rectangles ? 6'd43 : 6'd41;
    assign side_left_x=inner_rectangles ? (cascade ? 7'd9 : 7'd12) : 7'd6;
    assign side_right_x=inner_rectangles ? 7'd72 : 7'd78;
    assign side_left_y_min=inner_rectangles ? 6'd23 : 6'd15;
    assign side_left_y_max=inner_rectangles ?
        (cascade ? 6'd35 : inner_diamonds ? 6'd39 : 6'd33) : 6'd36;
    assign side_right_y_min=inner_rectangles ?
        (layout_id[2] ? 6'd15 : 6'd32) : 6'd31;
    assign side_right_y_max=inner_rectangles ?
        (layout_id[2] ? (layout_id[3] ? 6'd19 : 6'd22) : 6'd40) : 6'd37;
    always @* begin
        bumper_left_x=layout_id[0] ? 7'd26 : 7'd22;
        bumper_right_y=layout_id[0] ? 6'd22 : 6'd20;
        bumper_center_x=layout_id[1] ? 7'd46 : 7'd42;
        bumper_center_y=6'd37;
        bank_x0=layout_id[1] ? 7'd36 : 7'd32;
        bank_x1=bank_x0+7'd8; bank_x2=bank_x0+7'd16;
        bank_y=6'd19; bank_y1=6'd19; bank_y2=6'd19;
        spinner_x=layout_id[1] ? 7'd38 : 7'd46;
        spinner_y=6'd27; rollover_y=6'd13;
        bumper_y_min=6'd23; bumper_y_max=6'd34;
        bumper_x_min=7'd60; bumper_x_max=7'd78;
        case(layout_id[3:2])
            2'd1: begin // Inverted triangle: center high, outer pair low.
                bumper_center_y=6'd22;
                bumper_right_y=layout_id[0] ? 6'd32 : 6'd31;
                bumper_y_min=6'd28;
                bumper_x_max=7'd68;
                bank_x0=7'd34; bank_x1=7'd42; bank_x2=7'd50;
                bank_y=6'd31; bank_y1=6'd31; bank_y2=6'd31;
                spinner_x=7'd42; spinner_y=6'd37;
            end
            2'd2: begin // Cascade: left outer lane and a vertical bank.
                bumper_left_x=layout_id[0] ? 7'd20 : 7'd16;
                bumper_y_min=6'd22; bumper_y_max=6'd30;
                bank_x0=layout_id[1] ? 7'd36 : 7'd34;
                bank_x1=bank_x0; bank_x2=bank_x0;
                bank_y=6'd20; bank_y1=6'd27; bank_y2=6'd34;
                spinner_x=7'd52; spinner_y=6'd26;
            end
            2'd3: begin // Staircase: three targets descend across the table.
                bumper_left_x=layout_id[0] ? 7'd28 : 7'd26;
                bumper_right_y=layout_id[0] ? 6'd30 : 6'd28;
                bumper_y_min=6'd22; bumper_y_max=6'd28;
                bumper_x_max=7'd68;
                bank_x0=7'd34; bank_x1=7'd42; bank_x2=7'd50;
                bank_y=6'd16; bank_y1=6'd23; bank_y2=6'd30;
                spinner_x=7'd34; spinner_y=6'd33;
            end
            default: begin end
        endcase
    end
endmodule

// Player start timing samples a free-running, maximal-length 16-bit LFSR.
// This is pseudo-random variation, not a source of cryptographic entropy.
// It never reseeds at a life/save. Consecutive games always use DIFFERENT
// formations AND lower-table profiles, not merely small variants.
module pinball_map_select (
    input wire clk, reset, new_game,
    output reg [5:0] selected_layout
);
    reg [15:0] rng;
    wire [5:0] candidate = {rng[1],rng[5],rng[3],rng[7],rng[11],rng[15]};
    always @(posedge clk) begin
        if (reset) begin
            rng <= 16'hACE1;
            selected_layout <= 6'd0;
        end else begin
            rng <= {rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};
            if (new_game)
                selected_layout <= {candidate[5:4] == selected_layout[5:4] ?
                    selected_layout[5:4] + 2'd1 : candidate[5:4],
                    candidate[3:2] == selected_layout[3:2] ?
                    selected_layout[3:2] + 2'd1 : candidate[3:2], candidate[1:0]};
        end
    end
endmodule
`default_nettype wire
