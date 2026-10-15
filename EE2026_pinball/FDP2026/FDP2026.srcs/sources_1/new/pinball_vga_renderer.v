`timescale 1ns / 1ps
`default_nettype none

// Native 800 x 600 RGB565 raster. Q8 physics maps to eight native pixels
// per logical pixel: screen_x=16+8*x, screen_y=32+8*y.
// A single 5 x 7 character ROM serves all text. Bounded squared distances and
// cross products draw curves and moving flippers without division or trig.
module pinball_vga_renderer (
    input wire [9:0] x, y,
    input wire [2:0] state,
    input wire [14:0] ball_x_fp,
    input wire [13:0] ball_y_fp,
    input wire [14:0] ball2_x_fp,
    input wire [13:0] ball2_y_fp,
    input wire two_ball_mode,
    input wire [1:0] balls_visible,
    input wire [13:0] moving_bumper_y_fp,
    input wire [14:0] moving_bumper_x_fp,
    input wire [13:0] side_left_y_fp,
    input wire [13:0] side_right_y_fp,
    input wire [2:0] left_angle, right_angle,
    input wire [15:0] score_bcd, high_bcd,
    input wire [1:0] lives, difficulty,
    input wire [5:0] charge,
    input wire [13:0] hit_flash,
    input wire [1:0] bonus_target,
    input wire bonus_active,
    input wire [7:0] anim,
    input wire [6:0] cursor_x,
    input wire [5:0] cursor_y,
    input wire cursor_visible,
    input wire [2:0] combo, mission_progress,
    input wire [1:0] target_progress,
    input wire [5:0] table_progress,
    input wire [3:0] spinner_phase,
    input wire [10:0] save_timer,
    input wire [2:0] feature_event,
    input wire [9:0] feature_timer,
    input wire [15:0] last_award_bcd,
    input wire [79:0] particle_x, particle_y,
    input wire [31:0] particle_life,
    input wire [79:0] trail_x, trail_y,
    input wire [7:0] trail_valid,
    output reg [15:0] pixel
);
    localparam [2:0] MENU=3'd0, READY=3'd1, PLAY=3'd2,
                     PAUSE=3'd3, OVER=3'd4;
    localparam [15:0] NIGHT=16'h0843, FIELD=16'h1048, VIOLET=16'h2810,
                     VIOLET_LIGHT=16'h501B, PANEL=16'h0844,
                     CYAN=16'h07FF, CYAN_DARK=16'h0250,
                     GOLD=16'hFF20, ORANGE=16'hFC80, PINK=16'hF89D,
                     WHITE=16'hFFFF, MUTED=16'h6B6E, RED=16'hF989,
                     GREEN=16'h47EF;

    function [34:0] font_5x7;
        input [7:0] ch;
        begin
            case(ch)
                "A": font_5x7=35'b01110_10001_10001_11111_10001_10001_10001;
                "B": font_5x7=35'b11110_10001_10001_11110_10001_10001_11110;
                "C": font_5x7=35'b01111_10000_10000_10000_10000_10000_01111;
                "D": font_5x7=35'b11110_10001_10001_10001_10001_10001_11110;
                "E": font_5x7=35'b11111_10000_10000_11110_10000_10000_11111;
                "F": font_5x7=35'b11111_10000_10000_11110_10000_10000_10000;
                "G": font_5x7=35'b01111_10000_10000_10111_10001_10001_01111;
                "H": font_5x7=35'b10001_10001_10001_11111_10001_10001_10001;
                "I": font_5x7=35'b11111_00100_00100_00100_00100_00100_11111;
                "J": font_5x7=35'b00111_00010_00010_00010_00010_10010_01100;
                "K": font_5x7=35'b10001_10010_10100_11000_10100_10010_10001;
                "L": font_5x7=35'b10000_10000_10000_10000_10000_10000_11111;
                "M": font_5x7=35'b10001_11011_10101_10101_10001_10001_10001;
                "N": font_5x7=35'b10001_11001_11001_10101_10011_10011_10001;
                "O": font_5x7=35'b01110_10001_10001_10001_10001_10001_01110;
                "P": font_5x7=35'b11110_10001_10001_11110_10000_10000_10000;
                "Q": font_5x7=35'b01110_10001_10001_10001_10101_10010_01101;
                "R": font_5x7=35'b11110_10001_10001_11110_10100_10010_10001;
                "S": font_5x7=35'b01111_10000_10000_01110_00001_00001_11110;
                "T": font_5x7=35'b11111_00100_00100_00100_00100_00100_00100;
                "U": font_5x7=35'b10001_10001_10001_10001_10001_10001_01110;
                "V": font_5x7=35'b10001_10001_10001_10001_10001_01010_00100;
                "W": font_5x7=35'b10001_10001_10001_10101_10101_11011_10001;
                "X": font_5x7=35'b10001_10001_01010_00100_01010_10001_10001;
                "Y": font_5x7=35'b10001_10001_01010_00100_00100_00100_00100;
                "Z": font_5x7=35'b11111_00001_00010_00100_01000_10000_11111;
                "0": font_5x7=35'b01110_10001_10011_10101_11001_10001_01110;
                "1": font_5x7=35'b00100_01100_00100_00100_00100_00100_01110;
                "2": font_5x7=35'b01110_10001_00001_00010_00100_01000_11111;
                "3": font_5x7=35'b11110_00001_00001_01110_00001_00001_11110;
                "4": font_5x7=35'b00010_00110_01010_10010_11111_00010_00010;
                "5": font_5x7=35'b11111_10000_10000_11110_00001_00001_11110;
                "6": font_5x7=35'b01110_10000_10000_11110_10001_10001_01110;
                "7": font_5x7=35'b11111_00001_00010_00100_01000_01000_01000;
                "8": font_5x7=35'b01110_10001_10001_01110_10001_10001_01110;
                "9": font_5x7=35'b01110_10001_10001_01111_00001_00001_01110;
                "+": font_5x7=35'b00000_00100_00100_11111_00100_00100_00000;
                "-": font_5x7=35'b00000_00000_00000_11111_00000_00000_00000;
                "/": font_5x7=35'b00001_00001_00010_00100_01000_10000_10000;
                "<": font_5x7=35'b00010_00100_01000_10000_01000_00100_00010;
                ">": font_5x7=35'b01000_00100_00010_00001_00010_00100_01000;
                "!": font_5x7=35'b00100_00100_00100_00100_00100_00000_00100;
                ":": font_5x7=35'b00000_00100_00100_00000_00100_00100_00000;
                default: font_5x7=35'd0;
            endcase
        end
    endfunction

    // Message ROM: constant strings are synthesized as a character selector,
    // then decoded once by font_5x7. Digits share that same font path.
    function [7:0] message_char;
        input [5:0] msg;
        input [5:0] index;
        reg [351:0] line;
        begin
            case(msg)
                0: line={"NEON PINBALL",256'd0};
                1: line={"FPGA ARCADE",264'd0};
                2: line={"PRESS C TO START",224'd0};
                3: line={"L / R SELECT LEVEL",208'd0};
                4: line={"< EASY >",288'd0};
                5: line={"< NORMAL >",272'd0};
                6: line={"< HARD >",288'd0};
                7: line={"SCORE ",304'd0};
                8: line={"BEST ",312'd0};
                9: line={"HOLD C TO CHARGE",224'd0};
                10: line={"RELEASE TO LAUNCH",216'd0};
                11: line={"PAUSED",304'd0};
                12: line={"U RESUME  D MENU",224'd0};
                13: line={"GAME OVER",280'd0};
                14: line={"C RESTART  D MENU",216'd0};
                15: line={"BUMPER MISSION",240'd0};
                16: line={"HIT ALL THREE FOR 5",200'd0};
                17: line={"COMBO X",296'd0};
                18: line={"BALL SAVE",280'd0};
                19: line={"C LAUNCH  L / R FLIPPERS  U PAUSE  D MENU",24'd0};
                20: line={"MISSION CLEAR!",240'd0};
                21: line={"TARGET JACKPOT!",232'd0};
                22: line={"BALL SAVED!",264'd0};
                23: line={"COMBO BONUS!",256'd0};
                24: line={"+",344'd0};
                25: line={"LVL",328'd0};
                26: line={"TARGETS",296'd0};
                27: line={"POWER",312'd0};
                28: line={"BONUS AWARD!",256'd0};
                29: line={"C NUDGE  L / R FLIPPERS  U PAUSE  D MENU",32'd0};
                30: line={"NUDGE!",304'd0};
                31: line={"HIT THE GOLD BUMPER",200'd0};
                32: line={"TABLE BONUS!",256'd0};
                33: line={"LANES",312'd0};
                34: line={"TARGET BANK",264'd0};
                35: line={"LIGHT ALL SIX FOR TABLE BONUS",120'd0};
                36: line={"SPINNER",296'd0};
                37: line={"U: 1 BALL",280'd0};
                38: line={"U: 2 BALL",280'd0};
                39: line={"C START  L / R LEVEL  U BALLS",120'd0};
                40: line={"U RESUME",288'd0};
                41: line={"C RESTART",280'd0};
                42: line={"BALLS ",304'd0};
                43: line={"SAFE ",312'd0};
                44: line={"NO SAVE",296'd0};
                45: line={"LAST BALL",280'd0};
                46: line={"1 BALL",304'd0};
                47: line={"2 BALLS",296'd0};
                48: line={"YATTA!",304'd0};
                49: line={"NANI!",312'd0};
                50: line={"PHEW!",312'd0};
                default: line=352'd0;
            endcase
            message_char = index<6'd44 ? line[351-(index*8) -: 8] : 8'd32;
        end
    endfunction

    // Original circuit-cat silhouette: cyan outline, violet inset. A tiny
    // constant row selector draws the cameo without geometry multipliers.
    function [47:0] circuit_cat_row;
        input [4:0] row;
        begin
            case(row)
                0:circuit_cat_row={24'h100008,24'h000000};
                1:circuit_cat_row={24'h38001C,24'h000000};
                2:circuit_cat_row={24'h3C003C,24'h180018};
                3:circuit_cat_row={24'h7E007E,24'h3C003C};
                4:circuit_cat_row={24'h7F00FE,24'h3E007C};
                5:circuit_cat_row={24'h7F81FE,24'h3F00FC};
                6,7,8,9,10,11,12,13,14,15,16,17,18:
                    circuit_cat_row={24'h7FFFFE,24'h3FFFFC};
                19,20:circuit_cat_row={24'h3FFFFC,24'h1FFFF8};
                21:circuit_cat_row={24'h1FFFF8,24'h0FFFF0};
                22:circuit_cat_row={24'h0FFFF0,24'h03FFC0};
                23:circuit_cat_row={24'h03FFC0,24'h000000};
                default:circuit_cat_row=48'd0;
            endcase
        end
    endfunction

    function [7:0] bcd_char;
        input [15:0] digits;
        input [1:0] index;
        reg [3:0] digit;
        begin
            case(index)
                0: digit=digits[15:12];
                1: digit=digits[11:8];
                2: digit=digits[7:4];
                default: digit=digits[3:0];
            endcase
            bcd_char=8'd48+{4'd0,digit};
        end
    endfunction

    // Constant eight-pixel scaling preserves all three Q8 fractional bits.
    wire [9:0] ball_cx=10'd16+ball_x_fp[14:5];
    wire [9:0] ball_cy=10'd32+{1'b0,ball_y_fp[13:5]};
    wire [9:0] ball_dx=x>=ball_cx ? x-ball_cx : ball_cx-x;
    wire [9:0] ball_dy=y>=ball_cy ? y-ball_cy : ball_cy-y;
    wire [7:0] ball_x2=ball_dx[3:0]*ball_dx[3:0];
    wire [7:0] ball_y2=ball_dy[3:0]*ball_dy[3:0];
    wire [8:0] ball_r2={1'b0,ball_x2}+{1'b0,ball_y2};
    wire on_ball=balls_visible[0] && ball_dx<=10'd8 && ball_dy<=10'd8 && ball_r2<=9'd64;
    wire save_protected=save_timer!=11'd0;
    wire [15:0] ball_color =
        save_protected ? ((x<ball_cx && y<ball_cy) ? 16'h6EFF :
                         (ball_r2>9'd40 && x>ball_cx && y>ball_cy) ? 16'h0297 : 16'h05BF) :
        (x+10'd2>=ball_cx && x<ball_cx && y+10'd5>=ball_cy && y+10'd2<ball_cy) ? WHITE :
        (ball_r2>9'd40 && x>ball_cx && y>ball_cy) ? 16'h6B6E :
        (x<ball_cx && y<ball_cy) ? WHITE :
        (x<=ball_cx || y<=ball_cy) ? 16'hE71C : 16'hAF5F;

    // The second sprite uses a chamfered silhouette: no added DSP datapath.
    // Its centre keeps exactly the same fractional resolution and radius.
    wire [9:0] ball2_cx=10'd16+ball2_x_fp[14:5];
    wire [9:0] ball2_cy=10'd32+{1'b0,ball2_y_fp[13:5]};
    wire [9:0] ball2_dx=x>=ball2_cx ? x-ball2_cx : ball2_cx-x;
    wire [9:0] ball2_dy=y>=ball2_cy ? y-ball2_cy : ball2_cy-y;
    wire [10:0] ball2_sum={1'b0,ball2_dx}+{1'b0,ball2_dy};
    wire on_ball2=two_ball_mode && balls_visible[1] &&
                  ball2_dx<=10'd8 && ball2_dy<=10'd8 && ball2_sum<=11'd11;
    wire [15:0] ball2_color=save_protected ?
                           ((x<ball2_cx && y<ball2_cy) ? 16'h6EFF :
                            (x>ball2_cx && y>ball2_cy && ball2_sum>11'd8) ? 16'h0297 : 16'h05BF) :
                           (x<ball2_cx && y<ball2_cy) ? WHITE :
                           (x>ball2_cx && y>ball2_cy) ? ORANGE : GOLD;

    // Moving objects retain one-eighth logical-pixel resolution on VGA.
    wire [9:0] moving_bumper_cy=10'd32+{1'b0,moving_bumper_y_fp[13:5]};
    wire [9:0] moving_bumper_cx=10'd16+moving_bumper_x_fp[14:5];

    // Three bumpers share one bounded distance datapath. The disjoint column
    // bands cover each complete travel corridor and all expanding hit rings.
    // A fixed row split would clip the left bumper at its lowest position.
    reg [9:0] bumper_cx,bumper_cy;
    reg [1:0] bumper_id;
    always @* begin
        if(x<10'd288) begin
            bumper_cx=10'd224; bumper_cy=moving_bumper_cy; bumper_id=2'd0;
        end else if(x>=10'd432) begin
            bumper_cx=moving_bumper_cx; bumper_cy=10'd208; bumper_id=2'd1;
        end else begin bumper_cx=10'd352; bumper_cy=10'd312; bumper_id=2'd2; end
    end
    wire [9:0] bumper_dx=x>=bumper_cx ? x-bumper_cx : bumper_cx-x;
    wire [9:0] bumper_dy=y>=bumper_cy ? y-bumper_cy : bumper_cy-y;
    wire [11:0] bumper_x2=bumper_dx[5:0]*bumper_dx[5:0];
    wire [11:0] bumper_y2=bumper_dy[5:0]*bumper_dy[5:0];
    wire [12:0] bumper_r2={1'b0,bumper_x2}+{1'b0,bumper_y2};
    wire near_bumper=bumper_dx<=10'd40 && bumper_dy<=10'd40;
    wire lit_bumper=bonus_active && bonus_target==bumper_id;
    wire [5:0] ring_r=6'd27+{3'd0,anim[3:1]};
    wire [11:0] ring_outer=ring_r*ring_r;
    wire [11:0] ring_inner=(ring_r-6'd2)*(ring_r-6'd2);
    wire bumper_hit=hit_flash[bumper_id];
    wire [9:0] bumper_lamp_y=bumper_id==2'd2 ? 10'd272 : bumper_cy-10'd32;

    reg signed [4:0] left_slope,right_slope;
    always @* begin
        case(left_angle)
            0:left_slope=5'sd5; 1:left_slope=5'sd3; 2:left_slope=5'sd1;
            3:left_slope=-5'sd2; default:left_slope=-5'sd4;
        endcase
        case(right_angle)
            0:right_slope=5'sd5; 1:right_slope=5'sd3; 2:right_slope=5'sd1;
            3:right_slope=-5'sd2; default:right_slope=-5'sd4;
        endcase
    end
    wire signed [10:0] flip_y=$signed({1'b0,y})-11'sd456;
    wire signed [10:0] left_dx=$signed({1'b0,x})-11'sd184;
    wire signed [10:0] right_dx=11'sd536-$signed({1'b0,x});
    wire signed [15:0] left_distance=flip_y*6'sd18-left_dx*left_slope;
    wire signed [15:0] right_distance=flip_y*6'sd18-right_dx*right_slope;
    wire signed [10:0] guide_y=$signed({1'b0,y})-11'sd376;
    wire signed [10:0] guide_lx=$signed({1'b0,x})-11'sd56;
    wire signed [10:0] guide_rx=11'sd664-$signed({1'b0,x});
    wire signed [15:0] guide_l=guide_y*6'sd16-guide_lx*5'sd10;
    wire signed [15:0] guide_r=guide_y*6'sd16-guide_rx*5'sd10;
    wire [10:0] xy={1'b0,x}+{1'b0,y};
    wire [9:0] sling_cx=x<10'd352 ? 10'd152 : 10'd568;
    wire [9:0] sling_dx=x>=sling_cx ? x-sling_cx : sling_cx-x;
    wire [9:0] sling_dy=y>=10'd360 ? y-10'd360 : 10'd360-y;
    wire [10:0] sling_sum={1'b0,sling_dx}+{1'b0,sling_dy};
    wire sling_hit=x<10'd352 ? hit_flash[9] : hit_flash[10];
    wire signed [10:0] spinner_dx=$signed({1'b0,x})-11'sd352;
    wire signed [10:0] spinner_dy=$signed({1'b0,y})-11'sd248;
    reg signed [3:0] spinner_slope;
    reg [5:0] spinner_half;
    always @* begin
        case(spinner_phase[3:1])
            0,4:begin spinner_slope=4'sd0; spinner_half=6'd32; end
            1,5:begin spinner_slope=4'sd1; spinner_half=6'd24; end
            2,6:begin spinner_slope=4'sd0; spinner_half=6'd8; end
            default:begin spinner_slope=-4'sd1; spinner_half=6'd24; end
        endcase
    end
    wire signed [15:0] spinner_line=spinner_dy*4'sd4-spinner_dx*spinner_slope;
    wire [9:0] spinner_absx=x>=352 ? x-352 : 352-x;
    wire [9:0] spinner_absy=y>=248 ? y-248 : 248-y;
    wire [9:0] cursor_nx=10'd16+{cursor_x,3'b000};
    wire [9:0] cursor_ny=10'd32+{1'b0,cursor_y,3'b000};
    wire [10:0] charge_end=11'd272+({5'd0,charge}<<2);
    wire show_play_status=state==READY || state==PLAY || state==PAUSE;
    // Six small thresholds give ceil(seconds), including the final tick.
    wire [2:0] save_seconds=save_timer>1200 ? 3'd6 : save_timer>960 ? 3'd5 :
        save_timer>720 ? 3'd4 : save_timer>480 ? 3'd3 : save_timer>240 ? 3'd2 :
        save_timer!=0 ? 3'd1 : 3'd0;
    wire [1:0] live_balls={1'b0,balls_visible[0]}+{1'b0,balls_visible[1]};
    wire cursor_action=cursor_visible && cursor_x>=24 && cursor_x<=72;
    wire hover_mode=cursor_action && state==MENU && cursor_y>=22 && cursor_y<=29;
    wire hover_level=cursor_visible && state==MENU && cursor_x>=22 && cursor_x<=73 &&
        cursor_y>=30 && cursor_y<=39;
    wire hover_start=cursor_action && state==MENU && cursor_y>=43 && cursor_y<=47;
    wire hover_resume=cursor_action && state==PAUSE && cursor_y>=39 && cursor_y<=45;
    wire hover_restart=cursor_action && state==OVER && cursor_y>=49 && cursor_y<=53;
    wire button_mode=state==MENU && y>=208 && y<=271;
    wire button_level=state==MENU && y>=272 && y<=351;
    wire button_start=state==MENU && y>=376 && y<=415;
    wire button_resume=state==PAUSE && y>=344 && y<=399;
    wire button_restart=state==OVER && y>=424 && y<=463;
    wire button_active=button_mode || button_level || button_start || button_resume || button_restart;
    wire button_hover=button_mode ? hover_mode : button_level ? hover_level :
        button_start ? hover_start : button_resume ? hover_resume : hover_restart;
    wire [9:0] button_left=button_level ? 10'd192 : 10'd208;
    wire [9:0] button_right=button_level ? 10'd600 : 10'd592;
    wire [9:0] button_top=button_mode ? 10'd208 : button_level ? 10'd272 :
        button_start ? 10'd376 : button_resume ? 10'd344 : 10'd424;
    wire [9:0] button_bottom=button_mode ? 10'd271 : button_level ? 10'd351 :
        button_start ? 10'd415 : button_resume ? 10'd399 : 10'd463;
    wire signed [10:0] x_minus_y=$signed({1'b0,x})-$signed({1'b0,y});
    // One chamfer datapath serves every button; selected bounds are constants.
    wire [10:0] button_tl=button_mode ? 11'd424 : button_level ? 11'd472 :
        button_start ? 11'd592 : button_resume ? 11'd560 : 11'd640;
    wire [10:0] button_br=button_mode ? 11'd855 : button_level ? 11'd943 :
        button_start ? 11'd999 : button_resume ? 11'd983 : 11'd1047;
    wire signed [10:0] button_tr=button_mode ? 11'sd376 : button_level ? 11'sd320 :
        button_start ? 11'sd208 : button_resume ? 11'sd240 : 11'sd160;
    wire signed [10:0] button_bl=button_mode ? -11'sd55 : button_level ? -11'sd151 :
        button_start ? -11'sd199 : button_resume ? -11'sd183 : -11'sd247;
    wire in_button=button_active && x>=button_left && x<=button_right &&
        xy>=button_tl && xy<=button_br && x_minus_y<=button_tr && x_minus_y>=button_bl;
    wire [3:0] arrow_row=y[3] ? 4'd0-y[3:0] : y[3:0];
    // Persistent original mascot: all states have a clear left-hand margin.
    // Only fresh major events override its idle/blink/playful expression cycle.
    localparam [2:0] CAT_IDLE=3'd0, CAT_HAPPY=3'd1, CAT_WINK=3'd2,
                     CAT_PANIC=3'd3, CAT_SAD=3'd4, CAT_SLEEPY=3'd5;
    wire cat_fresh=feature_timer>10'd120;
    wire cat_relief=cat_fresh && feature_event==3'd4 && (state==PLAY || state==READY);
    wire cat_panic=cat_fresh && feature_event==3'd6 && state==PLAY;
    wire cat_reward=cat_fresh && state==PLAY &&
        (feature_event==3'd1 || feature_event==3'd3 || feature_event==3'd5 || feature_event==3'd7);
    wire cat_reaction=cat_relief || cat_panic || cat_reward;
    wire [2:0] cat_mood=state==OVER ? CAT_SAD : state==PAUSE ? CAT_SLEEPY :
        cat_panic ? CAT_PANIC : cat_relief ? CAT_WINK : cat_reward ? CAT_HAPPY :
        anim[7:5]==3'd3 ? CAT_WINK : anim[7:5]==3'd5 ? CAT_HAPPY : CAT_IDLE;
    wire cat_active=state<=OVER;
    wire [9:0] cat_top=(state==READY ? 10'd184 : 10'd128)+{8'd0,anim[5],1'b0};
    wire cat_box=x>=10'd64 && x<10'd112 && y>=cat_top && y<cat_top+10'd48;
    wire [9:0] cat_dy=y-cat_top;
    wire [4:0] cat_x=x[5:1],cat_y=cat_dy[5:1];
    wire [47:0] cat_masks=circuit_cat_row(cat_y);
    wire [23:0] cat_outline=cat_masks[47:24],cat_fill=cat_masks[23:0];
    wire cat_blink=anim[6:2]==5'd0;
    wire cat_left_eye=cat_x>=5 && cat_x<=9;
    wire cat_right_eye=cat_x>=14 && cat_x<=18;
    wire [9:0] cat_bubble_top=cat_top+10'd8;
    wire [9:0] cat_caption_y=cat_top+10'd13;
    wire comic_caption=cat_reaction && x>=124 && x<172 &&
                       y>=cat_caption_y && y<cat_caption_y+7;
    reg cat_ink;
    reg [15:0] cat_pixel;
    wire [9:0] side_left_y=10'd32+{1'b0,side_left_y_fp[13:5]};
    wire [9:0] side_right_y=10'd32+{1'b0,side_right_y_fp[13:5]};

    always @* begin
        cat_ink=1'b0;
        cat_pixel=CYAN;
        if(cat_active && cat_box && cat_outline[5'd23-cat_x]) begin
            cat_ink=1'b1;
            cat_pixel=cat_fill[5'd23-cat_x] ? VIOLET : CYAN;
            if(cat_y>=5'd3 && cat_y<=5'd6 &&
               ((cat_x>=5'd3 && cat_x<=5'd5) || (cat_x>=5'd18 && cat_x<=5'd20))) cat_pixel=PINK;
            if(cat_y==5'd15 && ((cat_x>=5'd3 && cat_x<=5'd6) ||
               (cat_x>=5'd17 && cat_x<=5'd20))) cat_pixel=PINK;
            if(cat_y>=5'd10 && cat_y<=5'd14 && (cat_left_eye || cat_right_eye)) begin
                if(cat_blink || cat_mood==CAT_SLEEPY || (cat_mood==CAT_WINK && cat_left_eye)) begin
                    if(cat_y==5'd12) cat_pixel=WHITE;
                end else if(cat_mood==CAT_HAPPY) begin
                    if(cat_y==5'd12 || cat_x==5'd7 || cat_x==5'd16) cat_pixel=GOLD;
                    if(cat_y==5'd12 && (cat_x==5'd7 || cat_x==5'd16)) cat_pixel=WHITE;
                end else if(cat_mood==CAT_SAD) begin
                    if(cat_y==5'd13 || ((cat_x==5'd7 || cat_x==5'd16) && cat_y==5'd14)) cat_pixel=16'h05BF;
                end else if(cat_y>=5'd11 && cat_y<=5'd13) cat_pixel=WHITE;
            end
            if(cat_mood==CAT_PANIC) begin
                if(cat_x>=5'd10 && cat_x<=5'd13 && cat_y>=5'd16 && cat_y<=5'd19)
                    cat_pixel=(cat_x==5'd10 || cat_x==5'd13 || cat_y==5'd16 || cat_y==5'd19) ? WHITE : PINK;
                if(cat_x>=5'd21 && cat_y>=5'd5 && cat_y<=5'd8) cat_pixel=CYAN;
            end else if(cat_mood==CAT_SAD) begin
                if((cat_y==5'd17 && cat_x>=5'd10 && cat_x<=5'd13) ||
                   (cat_y==5'd18 && (cat_x==5'd9 || cat_x==5'd14))) cat_pixel=WHITE;
            end else if(cat_mood==CAT_SLEEPY) begin
                if(cat_y==5'd18 && (cat_x==5'd11 || cat_x==5'd12)) cat_pixel=PINK;
            end else if((cat_y==5'd18 && cat_x>=5'd10 && cat_x<=5'd13) ||
                       (cat_y==5'd17 && (cat_x==5'd9 || cat_x==5'd14))) cat_pixel=WHITE;
        end
    end

    // A single font decoder serves HUD, instructions and transient feedback.
    reg text_enable;
    reg [9:0] text_x,text_y;
    reg [1:0] text_scale;
    reg [5:0] text_message;
    reg [15:0] text_color;
    reg trail_hit;
    reg [9:0] text_dx,text_dy;
    reg [5:0] text_index;
    reg [2:0] glyph_x,glyph_y;
    reg [7:0] glyph;
    reg [34:0] glyph_bits;
    integer i;
    reg [9:0] fx,fy,px,py,tx,ty,lamp_x,object_x;
    reg [3:0] pl;
    reg [2:0] object_id;
    reg [15:0] lamp_color;

    always @* begin
        pixel=NIGHT;
        text_enable=1'b0;
        text_x=0; text_y=0; text_scale=0; text_message=0; text_color=WHITE;
        trail_hit=1'b0;
        text_dx=0; text_dy=0; text_index=0;
        glyph_x=7; glyph_y=7; glyph=32; glyph_bits=0;
        fx=0; fy=0; px=0; py=0; tx=0; ty=0;
        pl=0; lamp_x=0; object_x=0; object_id=0; lamp_color=MUTED;

        // Subdued grid and sparse twinkling lights leave the ball easy to read.
        if(x>=16 && x<=783 && y>=32 && y<=543) begin
            pixel=y[7] ? NIGHT : FIELD;
            if(x[5:0]==0 || y[5:0]==0) pixel=16'h180B;
            if(x[6:0]==y[6:0]) pixel=16'h200C;
            if(y[5:0]==anim[7:2] && x[3:0]<2) pixel=VIOLET;
            if((x[7:0]==19 && y[6:0]==25) || (x[7:0]==183 && y[6:0]==81))
                pixel=anim[5] ? 16'h2A6E : 16'h194A;
        end
        if(((x>=16 && x<=19) || (x>=780 && x<=783)) && y>=32 && y<=543)
            pixel=y[5:3]==anim[6:4] ? CYAN_DARK : VIOLET;
        if((y==32 || y==543) && x>=16 && x<=783)
            pixel=x[7:4]==anim[7:4] ? CYAN_DARK : VIOLET;

        // Persistent face remains below the entire physical table and trails.
        if(cat_ink) pixel=cat_pixel;
        if(cat_reaction && x>=116 && x<=184 && y>=cat_bubble_top && y<=cat_bubble_top+16) begin
            pixel=PANEL;
            if(x==116 || x==184 || y==cat_bubble_top || y==cat_bubble_top+16)
                pixel=cat_panic ? CYAN : PINK;
        end

        // Oldest first: fresh samples stay bright where their squares overlap.
        // The entire trail remains behind obstacles and live balls.
        for(i=7;i>=0;i=i-1) begin
            tx=trail_x[i*10+:10]; ty=trail_y[i*10+:10];
            if(state==PLAY && trail_valid[i] && x+3>=tx && x<=tx+3 && y+3>=ty && y<=ty+3) begin
                trail_hit=1'b1;
                pixel=save_protected ? (i<2 ? 16'h04DF : i<5 ? 16'h0359 : 16'h0212) :
                      (i<2 ? 16'h4DF9 : i<5 ? 16'h2353 : 16'h194B);
            end
        end

        // Collision wall centre-lines exactly match x=2/94 and y=9.
        if(((x>=29 && x<=35) || (x>=765 && x<=771)) && y>=104 && y<=543) begin
            pixel=CYAN_DARK;
            if(x==32 || x==768) pixel=CYAN;
            if(x==31 || x==767) pixel=WHITE;
        end
        if(y>=101 && y<=107 && x>=29 && x<=771) begin
            pixel=CYAN_DARK;
            if(y==103) pixel=WHITE;
            if(y==104) pixel=CYAN;
        end
        if(x>=689 && x<=765 && y>=176 && y<=541) pixel=16'h0842;
        if(x>=685 && x<=690 && y>=176 && y<=541) begin
            pixel=CYAN_DARK;
            if(x==688) pixel=CYAN;
        end
        if((x==704 || x==752) && y>=216 && y<=448) pixel=16'h18E7;
        if(x>=704 && x<=752 && y>=480 && y<=520 && y[3:0]<3) pixel=ORANGE;
        if(x>=56 && x<=184 && guide_l>=-48 && guide_l<=144) begin
            pixel=CYAN_DARK;
            if(guide_l>=0 && guide_l<=32) pixel=CYAN;
            if(guide_l>=-16 && guide_l<0) pixel=WHITE;
        end
        if(x>=536 && x<=664 && guide_r>=-48 && guide_r<=144) begin
            pixel=CYAN_DARK;
            if(guide_r>=0 && guide_r<=32) pixel=CYAN;
            if(guide_r>=-16 && guide_r<0) pixel=WHITE;
        end
        // Lower funnel has the same 45-degree surfaces as the OLED geometry.
        if(y>=464 && y<=543 &&
            ((y>=x+296 && y<=x+304 && x<=248) ||
             (xy>=1016 && xy<=1024 && x>=472))) begin
            pixel=CYAN_DARK;
            if(y==x+300 || xy==1020) pixel=CYAN;
        end
        if(y>=535 && y<=541 && ((x>=32 && x<=248) || (x>=472 && x<=768))) pixel=CYAN_DARK;
        if(y>=536 && y<=540 && x>248 && x<472)
            pixel=save_timer!=0 ? (anim[3] ? 16'h05BF : 16'h0297) : RED;

        // Rollover lanes are pass-through illuminated arches, never solid walls.
        for(i=0;i<3;i=i+1) begin
            object_x=216+i*136;
            lamp_color=table_progress[i] ? GOLD : CYAN_DARK;
            if(x>=object_x-18 && x<=object_x+18 && y>=126 && y<=162 &&
                (x==object_x-18 || x==object_x+18 || y==126 || y==162))
                pixel=table_progress[i] ? 16'h6200 : VIOLET;
            if(x>=object_x-16 && x<=object_x+16 && y>=128 && y<=160 &&
                (x==object_x-16 || x==object_x+16 || y==128 || y==160)) pixel=lamp_color;
            if(x>=object_x-8 && x<=object_x+8 && y>=142 && y<=146)
                pixel=hit_flash[5+i] ? WHITE : (table_progress[i] ? GOLD : MUTED);
        end
        // Three small stand-up targets occupy a compact row between bumpers.
        for(i=0;i<3;i=i+1) begin
            object_x=288+i*64;
            if(x>=object_x-10 && x<=object_x+10 && y>=182 && y<=202)
                pixel=hit_flash[11+i] ? PINK : VIOLET;
            if(x>=object_x-8 && x<=object_x+8 && y>=184 && y<=200) begin
                pixel=table_progress[3+i] ? GOLD : PINK;
                if(x>=object_x-4 && x<=object_x+4 && y>=188 && y<=196)
                    pixel=hit_flash[11+i] ? WHITE : (table_progress[3+i] ? ORANGE : 16'h800D);
                if(y==184) pixel=WHITE;
            end
        end
        // Q8 motion resolves 1/8 of a logical pixel here. Face shading and
        // completion lamps translate with the same captured collision centre.
        if(((x>=56 && x<=72) && y>=side_left_y-10'd24 && y<=side_left_y+10'd24) ||
           ((x>=632 && x<=648) && y>=side_right_y-10'd24 && y<=side_right_y+10'd24)) begin
            pixel=PINK;
            if((x>=61 && x<=67 && y>=side_left_y-10'd16 && y<=side_left_y+10'd16) ||
               (x>=637 && x<=643 && y>=side_right_y-10'd16 && y<=side_right_y+10'd16))
                pixel=x<352 ? (hit_flash[3] ? WHITE : (target_progress[0] ? GOLD : 16'h700D)) :
                    (hit_flash[4] ? WHITE : (target_progress[1] ? GOLD : 16'h700D));
            if((x<352 && (y==side_left_y-10'd24 || x==56)) ||
               (x>=352 && (y==side_right_y-10'd24 || x==632))) pixel=WHITE;
        end

        // Energetic diamond slingshots: Manhattan radius three, matching physics.
        if(sling_dx<=24 && sling_dy<=24 && sling_sum<=24) begin
            pixel=sling_hit ? WHITE : PINK;
            if(sling_sum<=16) pixel=sling_hit ? GOLD : 16'h800D;
            if(sling_sum<=8) pixel=sling_hit ? WHITE : 16'hD019;
            if(y<360 && sling_sum>=18) pixel=WHITE;
        end
        if(sling_sum>=26 && sling_sum<=32 && sling_dx<=32 && sling_dy<=32)
            pixel=sling_hit ? PINK : VIOLET;
        if(sling_hit && sling_sum>=28+{8'd0,anim[3:2]} &&
            sling_sum<=30+{8'd0,anim[3:2]} && sling_dx<=40 && sling_dy<=40) pixel=GOLD;
        // Spinner silhouette cycles in width and tilt. Centre bolt stays fixed.
        if(spinner_absx<=spinner_half && spinner_absy<=8 && spinner_line>=-10 && spinner_line<=10)
            pixel=hit_flash[8] ? WHITE : (spinner_phase[0] ? GOLD : CYAN);
        if(spinner_absx<=3 && spinner_absy<=3) pixel=WHITE;

        // Dim dashed rails identify the two moving bumper routes without
        // resembling solid collision walls. Object bodies cover their paths.
        if((x>=223 && x<=225 && y>=208 && y<=256 && y[3:0]<3) ||
           (y>=207 && y<=209 && x>=480 && x<=544 && x[3:0]<3)) pixel=16'h126B;
        if(near_bumper) begin
            if(bumper_r2>=625 && bumper_r2<=1024)
                pixel=lit_bumper ? 16'h6200 : (anim[4] ? VIOLET_LIGHT : VIOLET);
            if(bumper_r2>=676 && bumper_r2<=784) pixel=16'h1129;
            if((lit_bumper || bumper_hit) && bumper_r2>=ring_inner && bumper_r2<=ring_outer)
                pixel=bumper_hit ? WHITE : GOLD;
            if(bumper_r2<=576) begin
                pixel=lit_bumper || mission_progress[bumper_id] ? GOLD : CYAN;
                if(bumper_r2<=400) pixel=lit_bumper ? 16'h9B00 : 16'h0210;
                if(bumper_r2<=256) pixel=bumper_hit ? WHITE : (lit_bumper ? ORANGE : PINK);
                if(bumper_r2<=100) pixel=bumper_hit ? GOLD : (lit_bumper ? 16'hFCE0 : 16'hA015);
                if(x<bumper_cx && y<bumper_cy && bumper_r2>=100 && bumper_r2<=256) pixel=WHITE;
                if(bumper_dx<=2 && bumper_dy<=2) pixel=WHITE;
            end
        end
        // Local progress lamps travel with their matching physical objects;
        // the separate HUD mission readout remains fixed above the table.
        if(bumper_dx<=10 && y+2>=bumper_lamp_y && y<=bumper_lamp_y+2)
            pixel=mission_progress[bumper_id] ? GOLD : MUTED;
        if(x>=184 && x<=328 && left_distance>=-144 && left_distance<=144) begin
            pixel=ORANGE;
            if(left_distance<=-96) pixel=GOLD;
            if(left_distance>=96) pixel=16'hB260;
        end
        if(x>=392 && x<=536 && right_distance>=-144 && right_distance<=144) begin
            pixel=ORANGE;
            if(right_distance<=-96) pixel=GOLD;
            if(right_distance>=96) pixel=16'hB260;
        end
        if(y>=448 && y<=464 && ((x>=176 && x<=192) || (x>=528 && x<=544))) begin
            pixel=GOLD;
            if(y>=453 && y<=459 && ((x>=181 && x<=187) || (x>=533 && x<=539))) pixel=WHITE;
        end
        if(state!=PLAY && on_ball) pixel=ball_color;
        if(state!=PLAY && on_ball2) pixel=ball2_color;
        for(i=0;i<8;i=i+1) begin
            px=particle_x[i*10+:10]; py=particle_y[i*10+:10]; pl=particle_life[i*4+:4];
            if(pl!=0 && ((x==px && y+2>=py && y<=py+2) || (y==py && x+2>=px && x<=px+2))) begin
                case(pl[3:2])
                    0:pixel=VIOLET; 1:pixel=VIOLET_LIGHT; 2:pixel=PINK; default:pixel=WHITE;
                endcase
            end
        end

        // Full-resolution HUD uses the margin above the physical playfield.
        if(y<32) begin
            pixel=16'h0842;
            if(y==30) pixel=CYAN;
            if(y==31) pixel=CYAN_DARK;
            if(y>=8 && y<22) begin
                if(x>=24 && x<184) begin text_enable=1; text_x=24; text_y=8; text_scale=1; text_message=7; end
                else if(x>=224 && x<368) begin text_enable=1; text_x=224; text_y=8; text_scale=1; text_message=8; text_color=GOLD; end
                else if(x>=650 && x<698) begin text_enable=1; text_x=650; text_y=8; text_scale=1; text_message=25; text_color=CYAN; end
                else if(x>=714 && x<730) begin text_enable=1; text_x=714; text_y=8; text_scale=1; text_message=4; text_color=GOLD; end
            end
            if(x>=384 && x<=468 && y>=4 && y<=26) begin
                pixel=VIOLET;
                if(x==384 || x==468 || y==4 || y==26) pixel=CYAN_DARK;
                if(x>=392 && x<464 && y>=12 && y<19) begin
                    text_enable=1; text_x=392; text_y=12;
                    text_scale=0; text_color=WHITE;
                    text_message=state==MENU || state==READY ? (two_ball_mode ? 47 : 46) :
                        live_balls==2 ? 47 : live_balls==1 ? (two_ball_mode ? 45 : 46) : 42;
                    if(two_ball_mode && live_balls==1 && state!=MENU && state!=READY) text_color=PINK;
                end
            end
            for(i=0;i<3;i=i+1) begin
                lamp_x=480+i*34;
                if(x>=lamp_x && x<=lamp_x+15 && y>=7 && y<=22) begin
                    pixel=lives>i ? RED : 16'h2986;
                    if((x==lamp_x || x==lamp_x+15) && (y<11 || y>18)) pixel=16'h0842;
                    if(x>=lamp_x+3 && x<=lamp_x+6 && y>=10 && y<=13) pixel=lives>i ? WHITE : MUTED;
                end
            end
        end
        // Small mission readouts occupy logical HUD rows zero through seven.
        if(y>=55 && y<62 && x>=48 && x<160) begin
            text_enable=1; text_x=48; text_y=55; text_message=15; text_color=MUTED;
        end else if(y>=55 && y<62 && x>=306 && x<346) begin
            text_enable=1; text_x=306; text_y=55; text_message=33; text_color=MUTED;
        end else if(y>=55 && y<62 && x>=480 && x<568) begin
            text_enable=1; text_x=480; text_y=55; text_message=34; text_color=MUTED;
        end
        for(i=0;i<3;i=i+1) begin
            lamp_x=176+i*22;
            if(x>=lamp_x && x<lamp_x+14 && y>=52 && y<=65)
                pixel=mission_progress[i] ? GOLD : 16'h2268;
            lamp_x=356+i*22;
            if(x>=lamp_x && x<lamp_x+14 && y>=52 && y<=65)
                pixel=table_progress[i] ? GOLD : 16'h2268;
            lamp_x=584+i*22;
            if(x>=lamp_x && x<lamp_x+14 && y>=52 && y<=65)
                pixel=table_progress[3+i] ? GOLD : 16'h2268;
        end
        if(y>=544) begin
            pixel=16'h0842;
            if(y==545) pixel=CYAN_DARK;
            if(show_play_status && x>=600 && x<=756 && y>=550 && y<=574) begin
                pixel=PANEL;
                if(x==600 || x==756 || y==550 || y==574)
                    pixel=save_protected ? 16'h05BF : VIOLET;
            end
            if(show_play_status && y>=554 && y<568 && x>=40 && x<168) begin
                text_enable=1; text_x=40; text_y=554; text_scale=1; text_message=17; text_color=GOLD;
            end else if(show_play_status && y>=554 && y<568 && x>=608 && x<752) begin
                text_enable=1; text_x=608; text_y=554; text_scale=1;
                text_message=save_protected ? 43 : 44; text_color=save_protected ? 16'h05BF : MUTED;
            end else if(y>=584 && y<591 && x>=236 && x<564) begin
                text_enable=1; text_x=236; text_y=584; text_message=state==PLAY ? 29 : 19; text_color=16'h8C31;
                if(state==MENU) begin
                    text_enable=x>=284 && x<516; text_x=284; text_message=39;
                end else if(state==PAUSE) begin
                    text_enable=x>=336 && x<464; text_x=336; text_message=12;
                end else if(state==OVER) begin
                    text_enable=x>=332 && x<468; text_x=332; text_message=14;
                end
            end
            if(state==PLAY && feature_timer!=0 && feature_event!=0 && x>=190 && x<=588 && y>=550 && y<=574) begin
                pixel=NIGHT;
                if(y==550 || y==574) pixel=anim[2] ? PINK : VIOLET;
                if(y>=554 && y<561 && x>=224 && x<448) begin
                    text_enable=1; text_x=224; text_y=554; text_message=28;
                    text_color=feature_event==4 ? 16'h05BF : feature_event==6 ? CYAN : PINK;
                    case(feature_event)
                        1:text_message=28; 2:text_message=23; 3:text_message=20;
                        4:text_message=22; 5:text_message=21; 6:text_message=30; default:text_message=32;
                    endcase
                end else if(feature_event!=4 && feature_event!=6 && last_award_bcd!=0 &&
                    y>=564 && y<571 && x>=376 && x<416) begin
                    text_enable=1; text_x=376; text_y=564; text_message=24;
                end
            end
        end
        if(state==READY) begin
            if(x>=232 && x<=570 && y>=353 && y<=417) begin
                pixel=NIGHT;
                if(y==353 || y==417) pixel=CYAN_DARK;
            end
            if(x>=268 && x<=531 && y>=378 && y<=392) begin
                pixel=CYAN_DARK;
                if(x>=272 && x<charge_end && y>=381 && y<=389)
                    pixel=x[3:0]<2 ? NIGHT : (charge>45 ? ORANGE : GOLD);
                if(x>=272 && x<charge_end && y==381) pixel=WHITE;
            end
            if(x>=280 && x<536 && y>=360 && y<374) begin
                text_enable=1; text_x=280; text_y=360; text_scale=1; text_message=9; text_color=GOLD;
            end else if(x>=272 && x<544 && y>=400 && y<414) begin
                text_enable=1; text_x=272; text_y=400; text_scale=1; text_message=10;
            end
        end
        if(state==MENU || state==PAUSE || state==OVER) begin
            if(y>=32 && y<544) pixel={1'b0,pixel[15:12],1'b0,pixel[10:6],1'b0,pixel[4:1]};
            if(state==MENU) begin
                // Shared mouse coordinates are logical OLED pixels. Keep the
                // level label on rows33..34 and start on43..44 so both displays
                // use the same level-selection and start-click regions.
                if(x>=160 && x<=640 && y>=152 && y<=490) begin
                    if(xy>=324 && xy<=1118 && x_minus_y<=476 && x_minus_y>=-318) begin
                        pixel=PANEL;
                        if(x<=163 || x>=637 || y<=154 || y>=488 ||
                           xy<=326 || xy>=1116 || x_minus_y>=474 || x_minus_y<=-316)
                            pixel=anim[5] ? VIOLET_LIGHT : VIOLET;
                    end
                end
                if(x>=208 && x<592 && y>=176 && y<204) begin
                    text_enable=1; text_x=208; text_y=176; text_scale=2; text_message=0; text_color=CYAN;
                end else if(x>=328 && x<472 && y>=232 && y<246) begin
                    text_enable=1; text_x=328; text_y=232; text_scale=1;
                    text_message=two_ball_mode ? 38 : 37; text_color=hover_mode ? CYAN : WHITE;
                end else if(y>=296 && y<310) begin
                    text_enable=1; text_y=296; text_scale=1; text_color=hover_level ? CYAN : WHITE;
                    if(difficulty==1) begin text_x=320; text_message=5; text_enable=x>=320 && x<480; end
                    else begin text_x=336; text_message=difficulty==0 ? 4 : 6; text_enable=x>=336 && x<464; end
                end else if(x>=328 && x<472 && y>=328 && y<335) begin
                    text_enable=1; text_x=328; text_y=328; text_message=3; text_color=MUTED;
                end else if(x>=272 && x<528 && y>=388 && y<402) begin
                    text_enable=1; text_x=272; text_y=388; text_scale=1; text_message=2; text_color=hover_start ? CYAN : WHITE;
                end else if(x>=320 && x<480 && y>=416 && y<423) begin
                    text_enable=1; text_x=320; text_y=416; text_message=16; text_color=MUTED;
                end else if(x>=288 && x<520 && y>=442 && y<449) begin
                    text_enable=1; text_x=288; text_y=442; text_message=35; text_color=GOLD;
                end else if(x>=328 && x<480 && y>=464 && y<471) begin
                    text_enable=1; text_x=328; text_y=464; text_message=31; text_color=CYAN;
                end
            end else begin
                if(x>=190 && x<=610 && y>=206 && y<=(state==OVER ? 464 : 408)) begin
                    pixel=16'h0844;
                    if(x<=192 || x>=608 || y<=208 || y>=(state==OVER ? 462 : 406))
                        pixel=state==OVER ? GOLD : CYAN;
                end
                if(state==PAUSE) begin
                    if(x>=304 && x<496 && y>=244 && y<272) begin
                        text_enable=1; text_x=304; text_y=244; text_scale=2; text_message=11; text_color=CYAN;
                    end else if(x>=336 && x<464 && y>=365 && y<379) begin
                        text_enable=1; text_x=336; text_y=365; text_scale=1; text_message=40;
                        text_color=hover_resume ? CYAN : WHITE;
                    end
                end else begin
                    if(x>=256 && x<544 && y>=240 && y<268) begin
                        text_enable=1; text_x=256; text_y=240; text_scale=2; text_message=13; text_color=RED;
                    end else if(x>=320 && x<480 && y>=306 && y<320) begin
                        text_enable=1; text_x=320; text_y=306; text_scale=1; text_message=7;
                    end else if(x>=328 && x<472 && y>=437 && y<451) begin
                        text_enable=1; text_x=328; text_y=437; text_scale=1; text_message=41; text_color=hover_restart ? CYAN : WHITE;
                    end
                end
            end
        end
        // Opaque modal panels cannot erase the mascot in the reserved margin.
        if((state==MENU || state==PAUSE || state==OVER) && cat_ink) pixel=cat_pixel;
        // All visible button backgrounds share one bounded/chamfered path.
        // Hover uses the actual logical control contracts, never a hidden cursor.
        if(in_button) begin
            pixel=button_hover ? 16'h114B : 16'h1008;
            if(x<=button_left+1 || x>=button_right-1 || y<=button_top+1 ||
               y>=button_bottom-1 || xy<=button_tl+1 || xy>=button_br-1 ||
               x_minus_y>=button_tr-1 || x_minus_y<=button_bl+1)
                pixel=button_hover ? CYAN : CYAN_DARK;
        end
        if(button_level && y>=297 && y<=311 &&
           ((x>=216 && x<=223 && x[2:0]==arrow_row[2:0]) ||
            (x>=576 && x<=583 && (~x[2:0])==arrow_row[2:0]))) pixel=CYAN;
        // Decode the caption independently of trail tests. Gate only the
        // final ink so a trail path never runs through the shared font ROM.
        if(comic_caption) begin
            text_enable=1; text_x=124; text_y=cat_caption_y; text_scale=0;
            text_message=feature_event==6 ? 49 : feature_event==4 ? 50 : 48;
            text_color=WHITE;
        end
        text_dx=x-text_x; text_dy=y-text_y;
        case(text_scale)
            0:begin text_index=text_dx[8:3]; glyph_x=text_dx[2:0]; glyph_y=text_dy[2:0]; end
            1:begin text_index=text_dx[9:4]; glyph_x=text_dx[3:1]; glyph_y=text_dy[3:1]; end
            default:begin text_index={1'b0,text_dx[9:5]}; glyph_x=text_dx[4:2]; glyph_y=text_dy[4:2]; end
        endcase
        glyph=message_char(text_message,text_index);
        if(text_message==7 && text_index>=6 && text_index<10) glyph=bcd_char(score_bcd,text_index-6);
        if(text_message==8 && text_index>=5 && text_index<9) glyph=bcd_char(high_bcd,text_index-5);
        if(text_message==17 && text_index==7) glyph=8'd48+{5'd0,combo};
        if(text_message==24 && text_index>=1 && text_index<5) glyph=bcd_char(last_award_bcd,text_index-1);
        if(text_message==42 && text_index==6) glyph=8'd48+{6'd0,live_balls};
        if(text_message==43 && text_index==5) glyph=8'd48+{5'd0,save_seconds};
        if(text_message==43 && text_index==6) glyph="S";
        if(text_message==4 && x>=714 && x<730 && y<32) glyph=difficulty==0 ? "E" : difficulty==1 ? "N" : "H";
        glyph_bits=font_5x7(glyph);
        if(text_enable && glyph_x<5 && glyph_y<7 && glyph_bits[34-(glyph_y*5)-glyph_x] &&
           (!comic_caption || !trail_hit)) pixel=text_color;
        if(cursor_visible && x>=cursor_nx && x<cursor_nx+13 && y>=cursor_ny && y<cursor_ny+17) begin
            fx=x-cursor_nx; fy=y-cursor_ny;
            if(fx<=fy && fx<10) begin
                if(fx==0 || fx==fy || fy==16) pixel=NIGHT;
                else if(fy<=12) pixel=GOLD;
            end
        end
        // Keep both live sprites above pointer outlines as well as effects.
        if(state==PLAY && on_ball) pixel=ball_color;
        if(state==PLAY && on_ball2) pixel=ball2_color;
    end
endmodule
`default_nettype wire
