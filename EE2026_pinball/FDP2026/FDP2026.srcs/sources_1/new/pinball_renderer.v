`timescale 1ns / 1ps
`default_nettype none

// Combinational RGB565 scene generator for the 96 x 64 Pmod OLED.
// A single character ROM and 3 x 5 font are shared by every text region.
// Coordinates and physics use the same table landmarks as pinball_game.
module pinball_renderer (
    input wire [6:0] x,
    input wire [5:0] y,
    input wire [2:0] state,
    input wire [6:0] ball_x,
    input wire [5:0] ball_y,
    input wire [6:0] ball2_x,
    input wire [5:0] ball2_y,
    input wire two_ball_mode,
    input wire [1:0] balls_visible,
    input wire [13:0] moving_bumper_y_fp,
    input wire [14:0] moving_bumper_x_fp,
    input wire [13:0] side_left_y_fp,
    input wire [13:0] side_right_y_fp,
    input wire [2:0] left_angle,
    input wire [2:0] right_angle,
    input wire [15:0] score_bcd,
    input wire [15:0] high_bcd,
    input wire [1:0] lives,
    input wire [1:0] difficulty,
    input wire [5:0] charge,
    input wire [13:0] hit_flash,
    input wire [1:0] bonus_target,
    input wire bonus_active,
    input wire [7:0] anim,
    input wire [6:0] cursor_x,
    input wire [5:0] cursor_y,
    input wire cursor_visible,
    input wire [2:0] combo,
    input wire [2:0] mission_progress,
    input wire [1:0] target_progress,
    input wire [5:0] table_progress,
    input wire [3:0] spinner_phase,
    input wire [10:0] save_timer,
    input wire [2:0] feature_event,
    input wire [9:0] feature_timer,
    input wire [15:0] last_award_bcd,
    input wire [55:0] oled_trail_x,
    input wire [47:0] oled_trail_y,
    input wire [7:0] trail_valid,
    output reg [15:0] pixel
);
    localparam [2:0] MENU=3'd0, READY=3'd1, PLAY=3'd2,
                     PAUSE=3'd3, OVER=3'd4;
    localparam [15:0] NIGHT=16'h0843, FIELD=16'h1048, FIELD_LIGHT=16'h188A,
                      CYAN=16'h07FF, RAIL=16'h05D8, GOLD=16'hFEA0,
                      ORANGE=16'hFD20, PINK=16'hF89D, WHITE=16'hFFFF,
                      MUTED=16'h4A8A, RED=16'hF9A8,
                      PANEL=16'h0844, PANEL_LIT=16'h1090,
                      VIOLET=16'h2810, VIOLET_LIT=16'h501B;

    function [14:0] font_3x5;
        input [7:0] character;
        begin
            case (character)
                "A": font_3x5=15'b010_101_111_101_101;
                "B": font_3x5=15'b110_101_110_101_110;
                "C": font_3x5=15'b011_100_100_100_011;
                "D": font_3x5=15'b110_101_101_101_110;
                "E": font_3x5=15'b111_100_110_100_111;
                "F": font_3x5=15'b111_100_110_100_100;
                "G": font_3x5=15'b011_100_101_101_011;
                "H": font_3x5=15'b101_101_111_101_101;
                "I": font_3x5=15'b111_010_010_010_111;
                "J": font_3x5=15'b001_001_001_101_010;
                "K": font_3x5=15'b101_101_110_101_101;
                "L": font_3x5=15'b100_100_100_100_111;
                "M": font_3x5=15'b101_111_111_101_101;
                "N": font_3x5=15'b101_111_111_111_101;
                "O": font_3x5=15'b010_101_101_101_010;
                "P": font_3x5=15'b110_101_110_100_100;
                "Q": font_3x5=15'b010_101_101_111_011;
                "R": font_3x5=15'b110_101_110_101_101;
                "S": font_3x5=15'b011_100_010_001_110;
                "T": font_3x5=15'b111_010_010_010_010;
                "U": font_3x5=15'b101_101_101_101_111;
                "V": font_3x5=15'b101_101_101_101_010;
                "W": font_3x5=15'b101_101_111_111_101;
                "X": font_3x5=15'b101_101_010_101_101;
                "Y": font_3x5=15'b101_101_010_010_010;
                "Z": font_3x5=15'b111_001_010_100_111;
                "0": font_3x5=15'b111_101_101_101_111;
                "1": font_3x5=15'b010_110_010_010_111;
                "2": font_3x5=15'b110_001_010_100_111;
                "3": font_3x5=15'b110_001_010_001_110;
                "4": font_3x5=15'b101_101_111_001_001;
                "5": font_3x5=15'b111_100_110_001_110;
                "6": font_3x5=15'b011_100_111_101_111;
                "7": font_3x5=15'b111_001_010_010_010;
                "8": font_3x5=15'b111_101_111_101_111;
                "9": font_3x5=15'b111_101_111_001_110;
                ":": font_3x5=15'b000_010_000_010_000;
                "/": font_3x5=15'b001_001_010_100_100;
                "<": font_3x5=15'b001_010_100_010_001;
                ">": font_3x5=15'b100_010_001_010_100;
                "-": font_3x5=15'b000_000_111_000_000;
                "+": font_3x5=15'b000_010_111_010_000;
                default: font_3x5=15'd0;
            endcase
        end
    endfunction

    // The compact award badge shares the HUD's existing character ROM.
    // It occupies the combo slot, leaving score and lives visible at all times.
    function [7:0] feature_char;
        input [2:0] event_code;
        input [2:0] index;
        reg [55:0] label;
        begin
            case (event_code)
                3'd1: label="BONUS  ";
                3'd2: label="COMBO  ";
                3'd3: label="JACKPOT";
                3'd4: label="SAVED  ";
                3'd5: label="TARGET ";
                3'd6: label="NUDGE  ";
                3'd7: label="TABLE  ";
                default: label="       ";
            endcase
            case (index)
                3'd0: feature_char=label[55:48];
                3'd1: feature_char=label[47:40];
                3'd2: feature_char=label[39:32];
                3'd3: feature_char=label[31:24];
                3'd4: feature_char=label[23:16];
                3'd5: feature_char=label[15:8];
                default: feature_char=label[7:0];
            endcase
        end
    endfunction

    function [7:0] message_char;
        input [3:0] message;
        input [4:0] index;
        begin
            case (message)
            4'd0: begin
                case (index)
                    5'd0: message_char = 8'd80;
                    5'd1: message_char = 8'd73;
                    5'd2: message_char = 8'd78;
                    5'd3: message_char = 8'd66;
                    5'd4: message_char = 8'd65;
                    5'd5: message_char = 8'd76;
                    5'd6: message_char = 8'd76;
                    default: message_char = 8'd32;
                endcase
            end
            4'd1: begin
                case (index)
                    5'd0: message_char = 8'd65;
                    5'd1: message_char = 8'd82;
                    5'd2: message_char = 8'd67;
                    5'd3: message_char = 8'd65;
                    5'd4: message_char = 8'd68;
                    5'd5: message_char = 8'd69;
                    default: message_char = 8'd32;
                endcase
            end
            4'd2: begin
                case (index)
                    5'd0: message_char = 8'd60;
                    5'd1: message_char = 8'd32;
                    5'd2: message_char = 8'd69;
                    5'd3: message_char = 8'd65;
                    5'd4: message_char = 8'd83;
                    5'd5: message_char = 8'd89;
                    5'd6: message_char = 8'd32;
                    5'd7: message_char = 8'd62;
                    default: message_char = 8'd32;
                endcase
            end
            4'd3: begin
                case (index)
                    5'd0: message_char = 8'd60;
                    5'd1: message_char = 8'd32;
                    5'd2: message_char = 8'd78;
                    5'd3: message_char = 8'd79;
                    5'd4: message_char = 8'd82;
                    5'd5: message_char = 8'd77;
                    5'd6: message_char = 8'd65;
                    5'd7: message_char = 8'd76;
                    5'd8: message_char = 8'd32;
                    5'd9: message_char = 8'd62;
                    default: message_char = 8'd32;
                endcase
            end
            4'd4: begin
                case (index)
                    5'd0: message_char = 8'd60;
                    5'd1: message_char = 8'd32;
                    5'd2: message_char = 8'd72;
                    5'd3: message_char = 8'd65;
                    5'd4: message_char = 8'd82;
                    5'd5: message_char = 8'd68;
                    5'd6: message_char = 8'd32;
                    5'd7: message_char = 8'd62;
                    default: message_char = 8'd32;
                endcase
            end
            4'd5: begin
                case (index)
                    5'd0: message_char = 8'd67;
                    5'd1: message_char = 8'd58;
                    5'd2: message_char = 8'd32;
                    5'd3: message_char = 8'd83;
                    5'd4: message_char = 8'd84;
                    5'd5: message_char = 8'd65;
                    5'd6: message_char = 8'd82;
                    5'd7: message_char = 8'd84;
                    default: message_char = 8'd32;
                endcase
            end
            4'd6: begin
                case (index)
                    5'd0: message_char = 8'd76;
                    5'd1: message_char = 8'd47;
                    5'd2: message_char = 8'd82;
                    5'd3: message_char = 8'd32;
                    5'd4: message_char = 8'd76;
                    5'd5: message_char = 8'd69;
                    5'd6: message_char = 8'd86;
                    5'd7: message_char = 8'd69;
                    5'd8: message_char = 8'd76;
                    default: message_char = 8'd32;
                endcase
            end
            4'd7: begin
                case (index)
                    5'd0: message_char = 8'd66;
                    5'd1: message_char = 8'd69;
                    5'd2: message_char = 8'd83;
                    5'd3: message_char = 8'd84;
                    5'd4: message_char = 8'd32;
                    default: message_char = 8'd32;
                endcase
            end
            4'd8: begin
                case (index)
                    5'd0: message_char = 8'd72;
                    5'd1: message_char = 8'd79;
                    5'd2: message_char = 8'd76;
                    5'd3: message_char = 8'd68;
                    5'd4: message_char = 8'd32;
                    5'd5: message_char = 8'd67;
                    5'd6: message_char = 8'd58;
                    5'd7: message_char = 8'd32;
                    5'd8: message_char = 8'd67;
                    5'd9: message_char = 8'd72;
                    5'd10: message_char = 8'd65;
                    5'd11: message_char = 8'd82;
                    5'd12: message_char = 8'd71;
                    5'd13: message_char = 8'd69;
                    default: message_char = 8'd32;
                endcase
            end
            4'd9: begin
                case (index)
                    5'd0: message_char = 8'd82;
                    5'd1: message_char = 8'd69;
                    5'd2: message_char = 8'd76;
                    5'd3: message_char = 8'd69;
                    5'd4: message_char = 8'd65;
                    5'd5: message_char = 8'd83;
                    5'd6: message_char = 8'd69;
                    5'd7: message_char = 8'd58;
                    5'd8: message_char = 8'd32;
                    5'd9: message_char = 8'd76;
                    5'd10: message_char = 8'd65;
                    5'd11: message_char = 8'd85;
                    5'd12: message_char = 8'd78;
                    5'd13: message_char = 8'd67;
                    5'd14: message_char = 8'd72;
                    default: message_char = 8'd32;
                endcase
            end
            4'd10: begin
                case (index)
                    5'd0: message_char = 8'd80;
                    5'd1: message_char = 8'd65;
                    5'd2: message_char = 8'd85;
                    5'd3: message_char = 8'd83;
                    5'd4: message_char = 8'd69;
                    5'd5: message_char = 8'd68;
                    default: message_char = 8'd32;
                endcase
            end
            4'd11: begin
                case (index)
                    5'd0: message_char = 8'd85;
                    5'd1: message_char = 8'd58;
                    5'd2: message_char = 8'd32;
                    5'd3: message_char = 8'd82;
                    5'd4: message_char = 8'd69;
                    5'd5: message_char = 8'd83;
                    5'd6: message_char = 8'd85;
                    5'd7: message_char = 8'd77;
                    5'd8: message_char = 8'd69;
                    default: message_char = 8'd32;
                endcase
            end
            4'd12: begin
                case (index)
                    5'd0: message_char = 8'd68;
                    5'd1: message_char = 8'd58;
                    5'd2: message_char = 8'd32;
                    5'd3: message_char = 8'd77;
                    5'd4: message_char = 8'd69;
                    5'd5: message_char = 8'd78;
                    5'd6: message_char = 8'd85;
                    default: message_char = 8'd32;
                endcase
            end
            4'd13: begin
                case (index)
                    5'd0: message_char = 8'd71;
                    5'd1: message_char = 8'd65;
                    5'd2: message_char = 8'd77;
                    5'd3: message_char = 8'd69;
                    5'd4: message_char = 8'd32;
                    5'd5: message_char = 8'd79;
                    5'd6: message_char = 8'd86;
                    5'd7: message_char = 8'd69;
                    5'd8: message_char = 8'd82;
                    default: message_char = 8'd32;
                endcase
            end
            4'd14: begin
                case (index)
                    5'd0: message_char = 8'd83;
                    5'd1: message_char = 8'd67;
                    5'd2: message_char = 8'd79;
                    5'd3: message_char = 8'd82;
                    5'd4: message_char = 8'd69;
                    5'd5: message_char = 8'd32;
                    default: message_char = 8'd32;
                endcase
            end
            4'd15: begin
                case (index)
                    5'd0: message_char = 8'd67;
                    5'd1: message_char = 8'd58;
                    5'd2: message_char = 8'd32;
                    5'd3: message_char = 8'd82;
                    5'd4: message_char = 8'd69;
                    5'd5: message_char = 8'd83;
                    5'd6: message_char = 8'd84;
                    5'd7: message_char = 8'd65;
                    5'd8: message_char = 8'd82;
                    5'd9: message_char = 8'd84;
                    default: message_char = 8'd32;
                endcase
            end
                default: message_char = 8'd32;
            endcase
        end
    endfunction

    function [7:0] bcd_char;
        input [15:0] digits;
        input [1:0] index;
        reg [3:0] digit;
        begin
            case (index)
                2'd0: digit=digits[15:12];
                2'd1: digit=digits[11:8];
                2'd2: digit=digits[7:4];
                default: digit=digits[3:0];
            endcase
            bcd_char = 8'd48 + {4'd0,digit};
        end
    endfunction

    function heart;
        input [2:0] hx;
        input [2:0] hy;
        begin
            case (hy)
                3'd0: heart=(hx==3'd1 || hx==3'd3);
                3'd1,3'd2: heart=(hx<=3'd4);
                3'd3: heart=(hx>=3'd1 && hx<=3'd3);
                3'd4: heart=(hx==3'd2);
                default: heart=1'b0;
            endcase
        end
    endfunction

    // Original 12 x 9 circuit-cat silhouette. Row masks share one small
    // constant lookup; expression pixels use the existing event/animation bits.
    function [11:0] cat_head_row;
        input [3:0] row;
        begin
            case (row)
                4'd0: cat_head_row=12'b011000000110;
                4'd1: cat_head_row=12'b011100001110;
                4'd2,4'd6: cat_head_row=12'b011111111110;
                4'd3,4'd4,4'd5: cat_head_row=12'b111111111111;
                4'd7: cat_head_row=12'b001111111100;
                4'd8: cat_head_row=12'b000111111000;
                default: cat_head_row=12'd0;
            endcase
        end
    endfunction

    function [11:0] cat_face_row;
        input [3:0] row;
        begin
            case (row)
                4'd1: cat_face_row=12'b001000000100;
                4'd2,4'd6: cat_face_row=12'b001111111100;
                4'd3,4'd4,4'd5: cat_face_row=12'b011111111110;
                4'd7: cat_face_row=12'b000111111000;
                default: cat_face_row=12'd0;
            endcase
        end
    endfunction

    // The same frame snapshot as the physics positions moves every layer.
    // OLED floors Q8 coordinates; the native renderer keeps fractional motion.
    wire [5:0] moving_bumper_y=moving_bumper_y_fp[13:8];
    wire [6:0] moving_bumper_x=moving_bumper_x_fp[14:8];
    wire [6:0] b0dx = x>=7'd26 ? x-7'd26 : 7'd26-x;
    wire [5:0] b0dy = y>=moving_bumper_y ? y-moving_bumper_y : moving_bumper_y-y;
    wire [6:0] b1dx = x>=moving_bumper_x ? x-moving_bumper_x : moving_bumper_x-x;
    wire [5:0] b1dy = y>=6'd22 ? y-6'd22 : 6'd22-y;
    wire [6:0] b2dx = x>=7'd42 ? x-7'd42 : 7'd42-x;
    wire [5:0] b2dy = y>=6'd35 ? y-6'd35 : 6'd35-y;
    wire [7:0] b0sum = {1'b0,b0dx}+{2'b0,b0dy};
    wire [7:0] b1sum = {1'b0,b1dx}+{2'b0,b1dy};
    wire [7:0] b2sum = {1'b0,b2dx}+{2'b0,b2dy};
    wire in_b0 = (b0dx<=7'd2 && b0dy<=6'd2) ||
                   (b0dx==7'd3 && b0dy==6'd0) || (b0dy==6'd3 && b0dx==7'd0);
    wire in_b1 = (b1dx<=7'd2 && b1dy<=6'd2) ||
                   (b1dx==7'd3 && b1dy==6'd0) || (b1dy==6'd3 && b1dx==7'd0);
    wire in_b2 = (b2dx<=7'd2 && b2dy<=6'd2) ||
                   (b2dx==7'd3 && b2dy==6'd0) || (b2dy==6'd3 && b2dx==7'd0);
    wire [6:0] ball_dx = x>=ball_x ? x-ball_x : ball_x-x;
    wire [5:0] ball_dy = y>=ball_y ? y-ball_y : ball_y-y;
    wire [7:0] ball_sum = {1'b0,ball_dx}+{2'b0,ball_dy};
    wire on_ball = balls_visible[0] && y>=6'd9 && ball_dx<=7'd1 && ball_dy<=6'd1 && ball_sum<=8'd1;
    // The existing frame's save timer protects the complete turn. Blue
    // bodies and their shared fading trail make that state visible at once.
    wire save_protected=save_timer!=11'd0;
    wire [15:0] ball_color = save_protected ?
                           ((x<ball_x || y<ball_y) ? 16'h6EFF :
                            x>ball_x ? 16'h0297 : 16'h05BF) :
                           (x==ball_x && y==ball_y) ? 16'hEF7D :
                           y>ball_y ? 16'h07FF : x>ball_x ? 16'hD69A : WHITE;
    wire [6:0] ball2_dx=x>=ball2_x ? x-ball2_x : ball2_x-x;
    wire [5:0] ball2_dy=y>=ball2_y ? y-ball2_y : ball2_y-y;
    wire [7:0] ball2_sum={1'b0,ball2_dx}+{2'b0,ball2_dy};
    wire on_ball2=two_ball_mode && balls_visible[1] && y>=6'd9 &&
                  ball2_dx<=7'd1 && ball2_dy<=6'd1 && ball2_sum<=8'd1;
    wire [15:0] ball2_color=save_protected ?
                            ((x<ball2_x || y<ball2_y) ? 16'h6EFF :
                             x>ball2_x ? 16'h0297 : 16'h05BF) :
                            (x==ball2_x && y==ball2_y) ? GOLD :
                            y>ball2_y ? ORANGE : x>ball2_x ? 16'hB260 : WHITE;
    wire [3:0] ring_radius = 4'd4+{2'd0,anim[3:2]};
    wire [7:0] ring_edge = {4'd0,ring_radius}+8'd1;
    wire [6:0] sling_x=x<7'd42 ? 7'd17 : 7'd69;
    wire [6:0] sling_dx=x>=sling_x ? x-sling_x : sling_x-x;
    wire [5:0] sling_dy=y>=6'd41 ? y-6'd41 : 6'd41-y;
    wire [7:0] sling_sum={1'b0,sling_dx}+{2'b0,sling_dy};
    wire sling_flash=x<7'd42 ? hit_flash[9] : hit_flash[10];
    wire [6:0] spinner_dx=x>=7'd42 ? x-7'd42 : 7'd42-x;
    wire [5:0] spinner_dy=y>=6'd27 ? y-6'd27 : 6'd27-y;

    // Distance from each flipper's line, scaled by its 18-pixel length.
    // Small signed products avoid full-width division or trigonometry.
    reg signed [4:0] left_slope, right_slope;
    always @* begin
        case (left_angle)
            3'd0: left_slope=5'sd5;
            3'd1: left_slope=5'sd3;
            3'd2: left_slope=5'sd1;
            3'd3: left_slope=-5'sd2;
            default: left_slope=-5'sd4;
        endcase
        case (right_angle)
            3'd0: right_slope=5'sd5;
            3'd1: right_slope=5'sd3;
            3'd2: right_slope=5'sd1;
            3'd3: right_slope=-5'sd2;
            default: right_slope=-5'sd4;
        endcase
    end
    wire signed [7:0] flipper_y = $signed({2'b00,y})-8'sd53;
    wire signed [7:0] left_dx = $signed({1'b0,x})-8'sd21;
    wire signed [7:0] right_dx = 8'sd65-$signed({1'b0,x});
    wire signed [12:0] left_distance = flipper_y*6'sd18-left_dx*left_slope;
    wire signed [12:0] right_distance = flipper_y*6'sd18-right_dx*right_slope;
    wire [10:0] left_guide_height = {4'd0,x-7'd5}*5'd10;
    wire [10:0] right_guide_height = {4'd0,7'd81-x}*5'd10;
    wire [5:0] left_guide_y = 6'd43+left_guide_height[9:4];
    wire [5:0] right_guide_y = 6'd43+right_guide_height[9:4];

    // Hover predicates use the same logical rectangles as Top's mouse actions.
    wire action_column=cursor_x>=7'd24 && cursor_x<=7'd72;
    wire mode_hover=cursor_visible && action_column &&
                    cursor_y>=6'd22 && cursor_y<=6'd29;
    wire level_hover=cursor_visible && cursor_x>=7'd22 && cursor_x<=7'd73 &&
                     cursor_y>=6'd30 && cursor_y<=6'd39;
    wire action_hover=cursor_visible && action_column &&
        ((state==MENU && cursor_y>=6'd43 && cursor_y<=6'd47) ||
         (state==PAUSE && cursor_y>=6'd39 && cursor_y<=6'd45) ||
         (state==OVER && cursor_y>=6'd49 && cursor_y<=6'd53));
    // Protection runs at 240 Hz. Ceiling seconds use threshold comparators,
    // avoiding a divider in the tiny-display path (six is the maximum save).
    wire [2:0] save_seconds=save_timer==11'd0 ? 3'd0 :
                            save_timer<=11'd240 ? 3'd1 :
                            save_timer<=11'd480 ? 3'd2 :
                            save_timer<=11'd720 ? 3'd3 :
                            save_timer<=11'd960 ? 3'd4 :
                            save_timer<=11'd1200 ? 3'd5 : 3'd6;

    // Persistent mascot stays in empty margins. Fresh events briefly override
    // idle expressions; a retained event code never pins its expression.
    localparam [2:0] CAT_IDLE=3'd0, CAT_HAPPY=3'd1, CAT_WINK=3'd2,
                     CAT_PANIC=3'd3, CAT_SAD=3'd4, CAT_SLEEPY=3'd5;
    wire cat_fresh=feature_timer>10'd120;
    wire cat_relief=cat_fresh && feature_event==3'd4 && (state==PLAY || state==READY);
    wire cat_panic=cat_fresh && feature_event==3'd6 && state==PLAY;
    wire cat_reward=cat_fresh && state==PLAY &&
        (feature_event==3'd1 || feature_event==3'd3 || feature_event==3'd5 || feature_event==3'd7);
    wire [2:0] cat_mood=state==OVER ? CAT_SAD : state==PAUSE ? CAT_SLEEPY :
        cat_panic ? CAT_PANIC : cat_relief ? CAT_WINK : cat_reward ? CAT_HAPPY :
        anim[7:5]==3'd3 ? CAT_WINK : anim[7:5]==3'd5 ? CAT_HAPPY : CAT_IDLE;
    wire cat_blink=anim[6:2]==5'd0;
    wire cat_visible=state<=OVER;
    wire [6:0] cat_left=(state==READY || state==PAUSE || state==OVER) ? 7'd10 : 7'd5;
    wire [5:0] cat_top=(state==READY ? 6'd20 : state==MENU ? 6'd23 :
                         state==PAUSE ? 6'd21 : state==OVER ? 6'd34 : 6'd12)+{5'd0,anim[5]};
    wire [3:0] cat_x=x-cat_left;
    wire [3:0] cat_y=y-cat_top;
    wire cat_box=x>=cat_left && x<cat_left+7'd14 && y>=cat_top && y<cat_top+6'd9;
    wire [11:0] cat_head_mask=cat_head_row(cat_y);
    wire [11:0] cat_face_mask=cat_face_row(cat_y);
    reg cat_ink;
    reg [15:0] cat_pixel;
    wire [5:0] side_left_y=side_left_y_fp[13:8];
    wire [5:0] side_right_y=side_right_y_fp[13:8];

    always @* begin
        cat_ink=1'b0;
        cat_pixel=CYAN;
        if(cat_visible && cat_box) begin
            if(cat_x<4'd12 && cat_head_mask[4'd11-cat_x]) begin
                cat_ink=1'b1;
                if(cat_face_mask[4'd11-cat_x]) cat_pixel=VIOLET;
                if(cat_y==4'd1 && (cat_x==4'd2 || cat_x==4'd9)) cat_pixel=PINK;
                if(cat_mood==CAT_SLEEPY || cat_blink) begin
                    if(cat_y==4'd4 && ((cat_x>=4'd2 && cat_x<=4'd4) ||
                       (cat_x>=4'd7 && cat_x<=4'd9))) cat_pixel=WHITE;
                end else if(cat_mood==CAT_HAPPY || cat_mood==CAT_WINK) begin
                    if((cat_y==4'd3 && (cat_x==4'd3 || cat_x==4'd8)) ||
                       (cat_y==4'd4 && (cat_x==4'd2 || cat_x==4'd4 ||
                                       cat_x==4'd7 || cat_x==4'd9))) cat_pixel=WHITE;
                    if(cat_mood==CAT_WINK && cat_x==4'd8 && cat_y==4'd4) cat_pixel=GOLD;
                end else if((cat_y==4'd3 || cat_y==4'd4) && (cat_x==4'd3 || cat_x==4'd8))
                    cat_pixel=cat_mood==CAT_SAD ? 16'h05BF : WHITE;
                if(cat_y==4'd5 && (cat_x==4'd1 || cat_x==4'd2 || cat_x==4'd9 || cat_x==4'd10))
                    cat_pixel=PINK;
                if(cat_mood==CAT_PANIC) begin
                    if((cat_y==4'd6 || cat_y==4'd7) && (cat_x==4'd5 || cat_x==4'd6)) cat_pixel=WHITE;
                end else if(cat_mood==CAT_SAD) begin
                    if((cat_y==4'd6 && (cat_x==4'd5 || cat_x==4'd6)) ||
                       (cat_y==4'd7 && (cat_x==4'd4 || cat_x==4'd7))) cat_pixel=WHITE;
                end else if(cat_mood==CAT_SLEEPY) begin
                    if(cat_y==4'd7 && (cat_x==4'd5 || cat_x==4'd6)) cat_pixel=PINK;
                end else if((cat_y==4'd6 && (cat_x==4'd4 || cat_x==4'd7)) ||
                            (cat_y==4'd7 && (cat_x==4'd5 || cat_x==4'd6))) cat_pixel=WHITE;
            end
            if(cat_mood==CAT_PANIC) begin
                if((cat_x==4'd13 && (cat_y==4'd0 || cat_y==4'd1)) ||
                   ((cat_x==4'd12 || cat_x==4'd13) && cat_y==4'd2)) begin
                    cat_ink=1'b1; cat_pixel=anim[3] ? 16'h6EFF : 16'h05BF;
                end
            end else if(cat_mood==CAT_HAPPY || cat_mood==CAT_WINK) begin
                if((cat_x==4'd13 && (cat_y==4'd0 || cat_y==4'd2)) ||
                   (cat_x==4'd12 && cat_y==4'd1)) begin
                    cat_ink=1'b1; cat_pixel=anim[3] ? WHITE : GOLD;
                end
            end
        end
    end

    reg [7:0] glyph;
    reg [2:0] glyph_x, glyph_y;
    reg [4:0] glyph_index;
    reg [15:0] glyph_color;
    reg [14:0] glyph_bits;
    reg bumper_bonus;
    reg bumper_flash;
    reg bumper_mission;
    reg bumper_upper;
    reg [6:0] bumper_dx;
    reg [5:0] bumper_dy;
    reg [7:0] bumper_sum;
    integer trail_index;
    integer object_index;
    reg [6:0] object_x;

    always @* begin
        pixel = NIGHT;
        glyph=8'd32;
        glyph_x=3'd7;
        glyph_y=3'd7;
        glyph_index=5'd0;
        glyph_color=WHITE;
        glyph_bits=15'd0;
        bumper_bonus=1'b0;
        bumper_flash=1'b0;
        bumper_mission=1'b0;
        bumper_upper=1'b0;
        bumper_dx=7'd0;
        bumper_dy=6'd0;
        bumper_sum=8'd0;
        object_x=7'd0;

        if (state==MENU) begin
            // Sparse circuit dots and a violet cabinet chase stay outside text.
            if (x[3:0]==4'd0 && y[3:0]==4'd0) pixel=VIOLET;
            // Moving stars and cabinet lights leave the title and controls clear.
            if ((x==7'd9 && y==6'd15) || (x==7'd84 && y==6'd28) ||
                (x==7'd13 && y==6'd38) || (x==7'd86 && y==6'd47) ||
                (x==7'd77 && y==6'd5) || (x==7'd18 && y==6'd26))
                pixel=anim[5] ? RAIL : MUTED;
            if ((x==7'd10 && y==6'd10+{3'd0,anim[4:2]}) ||
                (x==7'd87 && y==6'd36+{3'd0,anim[5:3]})) pixel=CYAN;
            if (x>=7'd7 && x<=7'd17 && y==6'd53) pixel=ORANGE;
            if (x>=7'd78 && x<=7'd88 && y==6'd53) pixel=ORANGE;
            if ((x==7'd11 && y==6'd49) || (x==7'd84 && y==6'd49))
                pixel=anim[4] ? WHITE : GOLD;
            if (((x==7'd3 || x==7'd92) && y>=6'd3 && y<=6'd60) ||
                (y==6'd3 && x>=7'd3 && x<=7'd92))
                pixel=y[3:1]==anim[5:3] ? VIOLET_LIT : VIOLET;
            if ((y==6'd4 && x>=7'd4 && x<=7'd18) ||
                (y==6'd4 && x>=7'd77 && x<=7'd91))
                pixel=CYAN;
            // Distinct selection cards and an emphasized primary action.
            if (x>=7'd24 && x<=7'd72 && y>=6'd22 && y<=6'd29) begin
                pixel=mode_hover ? PANEL_LIT : PANEL;
                if (x==7'd24 || x==7'd72 || y==6'd22 || y==6'd29)
                    pixel=mode_hover ? CYAN : VIOLET_LIT;
            end
            if (y>=6'd30 && y<=6'd39 && x>=7'd22 && x<=7'd73) begin
                pixel=level_hover ? PANEL_LIT : PANEL;
                if (x==7'd22 || x==7'd73 || y==6'd30 || y==6'd39)
                    pixel=level_hover ? CYAN : VIOLET_LIT;
            end
            if (x>=7'd24 && x<=7'd72 && y>=6'd42 && y<=6'd48) begin
                pixel=action_hover ? PANEL_LIT : PANEL;
                if (x==7'd24 || x==7'd72 || y==6'd42 || y==6'd48)
                    pixel=action_hover ? WHITE : CYAN;
            end

            if (x>=7'd20 && x<7'd76 && y>=6'd9 && y<6'd19) begin
                glyph_index=(x-7'd20)>>3;
                glyph=message_char(4'd0,glyph_index);
                glyph_x=(x-7'd20)>>1;
                glyph_x=glyph_x & 3'd3;
                glyph_y=(y-6'd9)>>1;
                glyph_color=y<6'd13 ? WHITE : CYAN;
            end else if (x>=7'd30 && x<7'd66 && y>=6'd23 && y<6'd28) begin
                // U or a click on this row toggles the menu's ball selection.
                glyph_index=(x-7'd30)>>2;
                case(glyph_index)
                    0: glyph="U";
                    1: glyph=":";
                    3: glyph=two_ball_mode ? "2" : "1";
                    5: glyph="B";
                    6: glyph="A";
                    7,8: glyph="L";
                    default: glyph=" ";
                endcase
                glyph_x=(x-7'd30)&7'd3;
                glyph_y=y-6'd23;
                glyph_color=GOLD;
            end else if (y>=6'd33 && y<6'd38) begin
                if (difficulty==2'd0 && x>=7'd32 && x<7'd64) begin
                    glyph=message_char(4'd2,(x-7'd32)>>2);
                    glyph_x=(x-7'd32)&7'd3;
                    glyph_y=y-6'd33;
                    glyph_color=GOLD;
                end else if (difficulty==2'd1 && x>=7'd28 && x<7'd68) begin
                    glyph=message_char(4'd3,(x-7'd28)>>2);
                    glyph_x=(x-7'd28)&7'd3;
                    glyph_y=y-6'd33;
                    glyph_color=GOLD;
                end else if (difficulty==2'd2 && x>=7'd32 && x<7'd64) begin
                    glyph=message_char(4'd4,(x-7'd32)>>2);
                    glyph_x=(x-7'd32)&7'd3;
                    glyph_y=y-6'd33;
                    glyph_color=GOLD;
                end
            end else if (x>=7'd32 && x<7'd64 && y>=6'd43 && y<6'd48) begin
                glyph=message_char(4'd5,(x-7'd32)>>2);
                glyph_x=(x-7'd32)&7'd3;
                glyph_y=y-6'd43;
                glyph_color=action_hover ? WHITE : CYAN;
            end else if (x>=7'd30 && x<7'd66 && y>=6'd51 && y<6'd56) begin
                glyph=message_char(4'd6,(x-7'd30)>>2);
                glyph_x=(x-7'd30)&7'd3;
                glyph_y=y-6'd51;
                glyph_color=MUTED;
            end else if (x>=7'd30 && x<7'd66 && y>=6'd58 && y<6'd63) begin
                glyph_index=(x-7'd30)>>2;
                if (glyph_index<5'd5) glyph=message_char(4'd7,glyph_index);
                else glyph=bcd_char(high_bcd,glyph_index-5'd5);
                glyph_x=(x-7'd30)&7'd3;
                glyph_y=y-6'd58;
                glyph_color=GOLD;
            end
        end else begin
            // Main table. The open red drain between the flippers is intentional.
            if (y>=6'd9) begin
                pixel=FIELD;
                if (x[3:0]==4'd0 && y[3:0]==4'd0) pixel=FIELD_LIGHT;
            end
            if(cat_ink) pixel=cat_pixel;
            // Paint oldest first, so overlapping history cannot dim the fresh
            // trail head. All trail samples remain behind table objects.
            for (trail_index=7; trail_index>=0; trail_index=trail_index-1) begin
                if (state==PLAY && trail_valid[trail_index] && y>=6'd10 &&
                    x==oled_trail_x[trail_index*7 +: 7] &&
                    y==oled_trail_y[trail_index*6 +: 6])
                    pixel=save_protected ?
                          (trail_index<2 ? 16'h04DF : trail_index<5 ? 16'h0359 : 16'h0212) :
                          (trail_index<2 ? 16'h7BF0 : trail_index<5 ? 16'h34D1 : 16'h21CB);
            end
            if (y==6'd7) pixel=RAIL;
            if ((x==7'd2 || x==7'd94) && y>=6'd9)
                pixel=y[3:1]==anim[5:3] ? CYAN : RAIL;
            if (y==6'd9 && x>=7'd2 && x<=7'd94)
                pixel=x[3:1]==anim[5:3] ? WHITE : CYAN;
            if (x==7'd84 && y>=6'd18) pixel=RAIL;
            if (x>=7'd85 && x<=7'd93 && y>=6'd18) pixel=NIGHT;
            if ((x==7'd86 || x==7'd92) && y>=6'd23 && y<=6'd52)
                pixel=FIELD_LIGHT;
            if (y==6'd63 && ((x>=7'd2 && x<=7'd29) ||
                (x>=7'd57 && x<=7'd94))) pixel=RAIL;
            if (y==6'd62 && (x==7'd37 || x==7'd50)) pixel=RED;
            if (save_timer!=11'd0 && y==6'd62 && x>=7'd30 && x<=7'd56)
                pixel=anim[4] ? CYAN : RAIL;
            if ((x>=7'd5 && x<=7'd21 &&
                 (y==left_guide_y || y==left_guide_y+6'd1)) ||
                (x>=7'd65 && x<=7'd81 &&
                 (y==right_guide_y || y==right_guide_y+6'd1))) pixel=CYAN;
            // These sloping lower walls feed the central drain. Their drawn
            // surfaces are two pixels outside the ball-centre collision bounds.
            if (y>=6'd54 && ((y==x+7'd35 || y==x+7'd36) ||
                (x+y==7'd121 || x+y==7'd122))) pixel=RAIL;
            if (x>=7'd86 && x<=7'd92 && y>=6'd56 && y<=6'd61 &&
                (y[0]==1'b0)) pixel=ORANGE;

            // Faces and progress lamps follow the same captured Q8 centres
            // as collision detection. OLED intentionally floors to whole pixels.
            if (((x>=7'd5 && x<=7'd7) && y>=side_left_y-6'd3 && y<=side_left_y+6'd3) ||
                ((x>=7'd77 && x<=7'd79) && y>=side_right_y-6'd3 && y<=side_right_y+6'd3)) begin
                pixel=((x<=7'd7 && hit_flash[3]) || (x>=7'd77 && hit_flash[4])) ? WHITE : PINK;
                if ((x==7'd6 && y>=side_left_y-6'd2 && y<=side_left_y+6'd2) ||
                    (x==7'd78 && y>=side_right_y-6'd2 && y<=side_right_y+6'd2))
                    pixel=((x==7'd6 && hit_flash[3]) || (x==7'd78 && hit_flash[4])) ? GOLD : 16'h780F;
            end
            if ((x==7'd10 && y>=side_left_y-6'd4 && y<=side_left_y-6'd2) ||
                (x==7'd74 && y>=side_right_y-6'd4 && y<=side_right_y-6'd2))
                pixel=((x==7'd10 && target_progress[0]) || (x==7'd74 && target_progress[1])) ? GOLD : MUTED;

            // Pass-through rollover arches: gold lamps mark all three lanes.
            for (object_index=0; object_index<3; object_index=object_index+1) begin
                object_x=7'd25+object_index*7'd17;
                if (x>=object_x-7'd2 && x<=object_x+7'd2 && y>=6'd12 && y<=6'd16 &&
                    (x==object_x-7'd2 || x==object_x+7'd2 || y==6'd12 || y==6'd16))
                    pixel=table_progress[object_index] ? GOLD : RAIL;
                if (x==object_x && y==6'd14)
                    pixel=hit_flash[5+object_index] ? WHITE :
                          table_progress[object_index] ? GOLD : MUTED;
                // Three stand-up targets between the top bumper pair.
                object_x=7'd34+object_index*7'd8;
                if (x>=object_x-7'd1 && x<=object_x+7'd1 && y>=6'd19 && y<=6'd21) begin
                    pixel=table_progress[3+object_index] ? GOLD : PINK;
                    if (y==6'd19) pixel=WHITE;
                    if (x==object_x && y==6'd20)
                        pixel=hit_flash[11+object_index] ? WHITE :
                              table_progress[3+object_index] ? ORANGE : 16'h800D;
                end
            end
            // Compact diamond slings match Manhattan-radius-three collision faces.
            if (sling_dx<=7'd3 && sling_dy<=6'd3 && sling_sum<=8'd3) begin
                pixel=sling_flash ? WHITE : PINK;
                if (sling_sum<=8'd1) pixel=sling_flash ? GOLD : 16'h800D;
                if (sling_sum==8'd3 && y<6'd41) pixel=WHITE;
            end
            if (sling_flash && sling_sum==8'd5 && sling_dx<=7'd5 && sling_dy<=6'd5)
                pixel=anim[2] ? GOLD : WHITE;
            // Rotating spinner narrows face-on to edge-on; it remains pass-through.
            if (spinner_dx<=(spinner_phase[2:1]==2'd2 ? 7'd1 :
                            spinner_phase[1] ? 7'd3 : 7'd4) &&
                (y==6'd27 || (spinner_phase[1] && spinner_dy<=6'd1 &&
                 ((x<7'd42 && y==6'd26) || (x>7'd42 && y==6'd28)))))
                pixel=hit_flash[8] ? WHITE : (spinner_phase[0] ? GOLD : CYAN);
            if (x==7'd42 && y==6'd27) pixel=WHITE;

            // Dotted cyan paths are decoration only, beneath the bumper faces.
            if ((x==7'd26 && y>=6'd22 && y<=6'd28 && !y[0]) ||
                (y==6'd22 && x>=7'd58 && x<=7'd66 && !x[0]))
                pixel=16'h126B;

            // A clipped, expanding diamond is a cheap impact animation.
            if ((hit_flash[0] && b0dx<=ring_radius && b0dy<=ring_radius && b0sum==ring_edge) ||
                (hit_flash[1] && b1dx<=ring_radius && b1dy<=ring_radius && b1sum==ring_edge) ||
                (hit_flash[2] && b2dx<=ring_radius && b2dy<=ring_radius && b2sum==ring_edge))
                pixel=anim[2] ? GOLD : WHITE;

            // Compact mission lamps leave room for rollover lanes and the spinner.
            if (x>=7'd25 && x<=7'd27 && y==moving_bumper_y-6'd4)
                pixel=mission_progress[0] ? GOLD : MUTED;
            if (b1dx<=7'd1 && y==6'd18)
                pixel=mission_progress[1] ? GOLD : MUTED;
            if (x>=7'd41 && x<=7'd43 && y==6'd30)
                pixel=mission_progress[2] ? GOLD : MUTED;

            if (in_b0 || in_b1 || in_b2) begin
                if (in_b0) begin
                    bumper_dx=b0dx; bumper_dy=b0dy; bumper_sum=b0sum;
                    bumper_bonus=bonus_active && bonus_target==2'd0;
                    bumper_flash=hit_flash[0];
                    bumper_mission=mission_progress[0]; bumper_upper=y<moving_bumper_y;
                end else if (in_b1) begin
                    bumper_dx=b1dx; bumper_dy=b1dy; bumper_sum=b1sum;
                    bumper_bonus=bonus_active && bonus_target==2'd1;
                    bumper_flash=hit_flash[1];
                    bumper_mission=mission_progress[1]; bumper_upper=y<6'd22;
                end else begin
                    bumper_dx=b2dx; bumper_dy=b2dy; bumper_sum=b2sum;
                    bumper_bonus=bonus_active && bonus_target==2'd2;
                    bumper_flash=hit_flash[2];
                    bumper_mission=mission_progress[2]; bumper_upper=y<6'd35;
                end
                pixel=bumper_bonus || bumper_mission ? GOLD : CYAN;
                if (bumper_dx<=7'd2 && bumper_dy<=6'd2 && bumper_sum<=8'd3)
                    pixel=bumper_bonus ? 16'h8200 : 16'h0170;
                if (bumper_sum<=8'd2)
                    pixel=bumper_flash ? WHITE :
                        (bumper_bonus && anim[4] ? WHITE : PINK);
                if (bumper_dy==6'd2 && bumper_dx<=7'd1 && bumper_upper) pixel=WHITE;
                if (bumper_mission && bumper_sum<=8'd1) pixel=GOLD;
                if (bumper_bonus && bumper_upper && bumper_dx=={4'd0,anim[4:2]})
                    pixel=WHITE;
            end

            if (x>=7'd21 && x<=7'd39 &&
                left_distance>=-13'sd27 && left_distance<=13'sd27) begin
                pixel=left_distance< -13'sd9 ? WHITE :
                      left_distance<=13'sd9 ? GOLD : ORANGE;
            end
            if (x>=7'd47 && x<=7'd65 &&
                right_distance>=-13'sd27 && right_distance<=13'sd27) begin
                pixel=right_distance< -13'sd9 ? WHITE :
                      right_distance<=13'sd9 ? GOLD : ORANGE;
            end
            if ((x>=7'd20 && x<=7'd22 && y>=6'd52 && y<=6'd54) ||
                (x>=7'd64 && x<=7'd66 && y>=6'd52 && y<=6'd54))
                pixel=GOLD;
            if ((x==7'd21 || x==7'd65) && y==6'd53) pixel=WHITE;

            if (state!=PLAY && on_ball) pixel=ball_color;
            if (state!=PLAY && on_ball2) pixel=ball2_color;

            // Compact HUD: score, lives (three hearts), and difficulty initial.
            if (x>=7'd3 && x<7'd31 && y>=6'd1 && y<6'd6) begin
                glyph_index=(x-7'd3)>>2;
                if (glyph_index==5'd0) glyph="S";
                else if (glyph_index==5'd1) glyph="C";
                else if (glyph_index==5'd2) glyph=8'd32;
                else glyph=bcd_char(score_bcd,glyph_index-5'd3);
                glyph_x=(x-7'd3)&7'd3; glyph_y=y-6'd1;
            end else if (combo>3'd1 && x>=7'd33 && x<7'd41 && y>=6'd1 && y<6'd6) begin
                glyph=x<7'd37 ? "X" : 8'd48+{5'd0,combo};
                glyph_x=(x-7'd33)&7'd3; glyph_y=y-6'd1;
                glyph_color=combo>=3'd4 ? WHITE : GOLD;
            end else if (x>=7'd43 && x<7'd47 && y>=6'd1 && y<6'd6) begin
                glyph="L"; glyph_x=x-7'd43; glyph_y=y-6'd1;
                glyph_color=RED;
            end else if (save_timer!=11'd0 && x>=7'd74 && x<7'd82 && y>=6'd1 && y<6'd6) begin
                glyph=x<7'd78 ? "S" : 8'd48+{5'd0,save_seconds};
                glyph_x=(x-7'd74)&7'd3; glyph_y=y-6'd1;
                glyph_color=save_timer<11'd120 && anim[3] ? RED : CYAN;
            end else if (x>=7'd86 && x<7'd90 && y>=6'd1 && y<6'd6) begin
                glyph=difficulty==2'd0 ? "E" : difficulty==2'd1 ? "N" : "H";
                glyph_x=x-7'd86; glyph_y=y-6'd1;
                glyph_color=GOLD;
            end
            if (x>=7'd51 && x<=7'd55 && y>=6'd1 && y<=6'd5 &&
                heart(x-7'd51,y-6'd1)) pixel=lives>=2'd1 ? RED : MUTED;
            if (x>=7'd58 && x<=7'd62 && y>=6'd1 && y<=6'd5 &&
                heart(x-7'd58,y-6'd1)) pixel=lives>=2'd2 ? RED : MUTED;
            if (x>=7'd65 && x<=7'd69 && y>=6'd1 && y<=6'd5 &&
                heart(x-7'd65,y-6'd1)) pixel=lives>=2'd3 ? RED : MUTED;

            // Two miniature lamps identify which multiball sprites survive.
            if (two_ball_mode && x>=7'd92 && x<=7'd93) begin
                if (y>=6'd1 && y<=6'd2)
                    pixel=balls_visible[0] ? (save_protected ? 16'h05BF : WHITE) : MUTED;
                if (y>=6'd4 && y<=6'd5)
                    pixel=balls_visible[1] ? (save_protected ? 16'h05BF : GOLD) : MUTED;
            end

            if (state==PLAY && feature_timer!=10'd0 && feature_event!=3'd0 &&
                x>=7'd31 && x<7'd51 && y<=6'd6) begin
                pixel=PANEL;
                if (y==6'd6) pixel=PINK;
                if (y>=6'd1 && y<6'd6) begin
                    glyph_index=(x-7'd31)>>2;
                    if (feature_event==3'd4 || feature_event==3'd6)
                        glyph=glyph_index<5'd4 ? feature_char(feature_event,glyph_index[2:0]) : " ";
                    else if (glyph_index==5'd0) glyph="+";
                    else glyph=bcd_char(last_award_bcd,glyph_index-5'd1);
                    glyph_x=(x-7'd31)&7'd3; glyph_y=y-6'd1;
                    glyph_color=(feature_event==3'd7 || feature_event==3'd3) ? GOLD :
                                 feature_event==3'd4 ? CYAN : PINK;
                end
            end

            if (state==READY) begin
                // Charge meter's 63-pixel interior directly matches charge 0..63.
                if (x>=7'd10 && x<=7'd75 && y>=6'd12 && y<=6'd16) begin
                    pixel=CYAN;
                    if (x>=7'd11 && x<=7'd74 && y>=6'd13 && y<=6'd15)
                        pixel=NIGHT;
                    if (x>=7'd11 && {1'b0,x}<8'd11+{2'b0,charge} &&
                        y>=6'd13 && y<=6'd15 && x[2:0]!=3'd2)
                        pixel=x<7'd31 ? CYAN : x<7'd55 ? GOLD : PINK;
                end
                if (x>=7'd13 && x<=7'd80 && y>=6'd37 && y<=6'd52) begin
                    pixel=PANEL;
                    if (x==7'd13 || x==7'd80 || y==6'd37 || y==6'd52)
                        pixel=VIOLET_LIT;
                end
                if (x>=7'd20 && x<7'd76 && y>=6'd39 && y<6'd44) begin
                    glyph=message_char(4'd8,(x-7'd20)>>2);
                    glyph_x=(x-7'd20)&7'd3; glyph_y=y-6'd39;
                    glyph_color=GOLD;
                end else if (x>=7'd18 && x<7'd78 && y>=6'd46 && y<6'd51) begin
                    glyph=message_char(4'd9,(x-7'd18)>>2);
                    glyph_x=(x-7'd18)&7'd3; glyph_y=y-6'd46;
                    glyph_color=WHITE;
                end
            end

            if (state==PAUSE || state==OVER) begin
                if (y>=6'd9)
                    pixel={1'b0,pixel[15:12],1'b0,pixel[10:6],1'b0,pixel[4:1]};
                if (x>=7'd8 && x<=7'd83 && y>=6'd17 && y<=6'd55) begin
                    pixel=PANEL;
                    if (x==7'd8 || x==7'd83 || y==6'd17 || y==6'd55)
                        pixel=state==OVER ? GOLD : VIOLET_LIT;
                end
                if (x>=7'd24 && x<=7'd72 &&
                    ((state==PAUSE && y>=6'd38 && y<=6'd46) ||
                     (state==OVER && y>=6'd48 && y<=6'd54))) begin
                    pixel=action_hover ? PANEL_LIT : PANEL;
                    if (x==7'd24 || x==7'd72 ||
                        (state==PAUSE && (y==6'd38 || y==6'd46)) ||
                        (state==OVER && (y==6'd48 || y==6'd54)))
                        pixel=action_hover ? WHITE : CYAN;
                end
                if (state==PAUSE) begin
                    if (x>=7'd24 && x<7'd72 && y>=6'd25 && y<6'd35) begin
                        glyph=message_char(4'd10,(x-7'd24)>>3);
                        glyph_x=((x-7'd24)>>1)&7'd3;
                        glyph_y=(y-6'd25)>>1;
                        glyph_color=CYAN;
                    end else if (x>=7'd30 && x<7'd66 && y>=6'd41 && y<6'd46) begin
                        glyph=message_char(4'd11,(x-7'd30)>>2);
                        glyph_x=(x-7'd30)&7'd3; glyph_y=y-6'd41;
                        glyph_color=WHITE;
                    end else if (x>=7'd34 && x<7'd62 && y>=6'd49 && y<6'd54) begin
                        glyph=message_char(4'd12,(x-7'd34)>>2);
                        glyph_x=(x-7'd34)&7'd3; glyph_y=y-6'd49;
                        glyph_color=MUTED;
                    end
                end else begin
                    if (x>=7'd12 && x<7'd84 && y>=6'd21 && y<6'd31) begin
                        glyph=message_char(4'd13,(x-7'd12)>>3);
                        glyph_x=((x-7'd12)>>1)&7'd3;
                        glyph_y=(y-6'd21)>>1;
                        glyph_color=RED;
                    end else if (x>=7'd28 && x<7'd68 && y>=6'd34 && y<6'd39) begin
                        glyph_index=(x-7'd28)>>2;
                        if (glyph_index<5'd6) glyph=message_char(4'd14,glyph_index);
                        else glyph=bcd_char(score_bcd,glyph_index-5'd6);
                        glyph_x=(x-7'd28)&7'd3; glyph_y=y-6'd34;
                        glyph_color=WHITE;
                    end else if (x>=7'd30 && x<7'd66 && y>=6'd41 && y<6'd46) begin
                        glyph_index=(x-7'd30)>>2;
                        if (glyph_index<5'd5) glyph=message_char(4'd7,glyph_index);
                        else glyph=bcd_char(high_bcd,glyph_index-5'd5);
                        glyph_x=(x-7'd30)&7'd3; glyph_y=y-6'd41;
                        glyph_color=GOLD;
                    end else if (x>=7'd28 && x<7'd68 && y>=6'd49 && y<6'd54) begin
                        glyph=message_char(4'd15,(x-7'd28)>>2);
                        glyph_x=(x-7'd28)&7'd3; glyph_y=y-6'd49;
                        glyph_color=CYAN;
                    end
                end
            end
        end

        // Modal panels are opaque; redraw the mascot in their reserved margin.
        // Its footprint never intersects a heading, score or clickable prompt.
        if((state==MENU || state==PAUSE || state==OVER) && cat_ink) pixel=cat_pixel;
        glyph_bits=font_3x5(glyph);
        if (glyph_x<3'd3 && glyph_y<3'd5) begin
            if (glyph_bits[4'd14-(glyph_y*2'd3)-glyph_x]) pixel=glyph_color;
        end

        // Optional PS/2 pointer; a tiny outlined cross stays readable on OLED.
        if (cursor_visible) begin
            if (((x>=cursor_x && x<=cursor_x+7'd3) && y==cursor_y) ||
                (({1'b0,y}>={1'b0,cursor_y} &&
                  {1'b0,y}<={1'b0,cursor_y}+7'd3) && x==cursor_x))
                pixel=GOLD;
            if (cursor_y<6'd63 && x==cursor_x+7'd1 && y==cursor_y+6'd1)
                pixel=NIGHT;
        end
        // A pointer, impact effect or notification cannot hide a live ball.
        if (state==PLAY && on_ball) pixel=ball_color;
        if (state==PLAY && on_ball2) pixel=ball2_color;
    end
endmodule
`default_nettype wire
