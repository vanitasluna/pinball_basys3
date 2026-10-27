`timescale 1ns / 1ps
`default_nettype none

// Both balls share one arithmetic/collision datapath. A 240 Hz world step
// captures one 16-clock collision calculation per live ball. Ball positions
// and moving bumpers commit together after 16 clocks (one ball) or 33 clocks
// (two balls); the latter includes one clock to load the second operands.
module pinball_physics (
    input wire clk, reset, tick, active, prepare, launch,
    input wire two_ball_mode,
    input wire [5:0] selected_layout,
    output reg [5:0] layout_id,
    input wire [5:0] launch_power,
    input wire [1:0] difficulty,
    input wire left_pressed, right_pressed, nudge,
    output wire [6:0] ball_x, ball2_x,
    output wire [5:0] ball_y, ball2_y,
    output wire [14:0] ball_x_fp, ball2_x_fp,
    output wire [13:0] ball_y_fp, ball2_y_fp,
    output wire [1:0] balls_visible,
    output reg [13:0] moving_bumper_y_fp,
    output reg [14:0] moving_bumper_x_fp,
    output reg [13:0] side_left_y_fp, side_right_y_fp,
    output reg [1:0] black_slot, white_slot,
    output reg [4:0] portal_flash,
    output reg [7:0] portal_anim,
    output reg [1:0] teleported,
    output reg [2:0] left_angle, right_angle,
    output reg drained,
    output reg [13:0] hit_events,
    output reg hit_ball,
    output wire in_lane
);
    // First-ball names remain stable for diagnostics and existing benches.
    reg signed [15:0] position_x, position_y, velocity_x, velocity_y;
    reg signed [15:0] position2_x, position2_y, velocity2_x, velocity2_y;
    reg launched, launched2, ball1_alive, ball2_alive;
    reg ball1_in_lane, ball2_in_lane;
    reg [5:0] shot_power;
    reg [13:0] hit_armed, hit_armed2;
    reg [4:0] cooldown [0:13];
    reg [4:0] cooldown2 [0:13];
    reg collision_busy;
    reg [4:0] collision_wait;
    reg work_ball, batch_both, load_second;
    reg batch_nudge, nudge_pending;
    reg moving_bumper_y_positive, moving_bumper_x_positive;
    reg side_left_y_positive, side_right_y_positive;
    reg gravity_phase;
    reg signed [15:0] batch_gravity;
    reg [1:0] batch_difficulty;
    reg signed [15:0] stage_position_x, stage_position_y;
    reg signed [15:0] stage_velocity_x, stage_velocity_y;
    reg stage_in_lane, stage_alive;
    reg [13:0] stage_hits, pending_hits;
    reg [2:0] pending_hit_wait, pending_drain_wait;
    reg [7:0] portal_rng;
    reg [10:0] portal_age;
    reg portal_pending;
    reg portal_armed,portal_armed2;
    reg [4:0] portal_cooldown,portal_cooldown2;
    reg stage_teleport;
    (* KEEP = "TRUE" *) reg collision_nudge;
    (* KEEP = "TRUE" *) reg [5:0] collision_layout_id;
    (* KEEP = "TRUE" *) reg [6:0] collision_black_x,collision_white_x;
    (* KEEP = "TRUE" *) reg [5:0] collision_black_y,collision_white_y;
    (* KEEP = "TRUE" *) reg collision_portal_armed;

    wire [6:0] black_hole_x,white_hole_x;
    wire [5:0] black_hole_y,white_hole_y;
    wire [5:0] prepare_layout=reset ? 6'd0 : selected_layout;
    pinball_portal_position black_position(.layout_id(layout_id),.slot(black_slot),
        .x(black_hole_x),.y(black_hole_y));
    pinball_portal_position white_position(.layout_id(layout_id),.slot(white_slot),
        .x(white_hole_x),.y(white_hole_y));
    wire [1:0] initial_black=portal_rng[1:0]^prepare_layout[1:0];
    wire [1:0] initial_white=initial_black+
        (portal_rng[3:2]==0 ? 2'd1 : portal_rng[3:2]);
    wire [1:0] relocated_black=portal_rng[1:0]==black_slot ?
        black_slot+2'd1 : portal_rng[1:0];
    wire [1:0] relocated_white=choose_white(portal_rng[5:4],relocated_black,
        white_slot,black_slot,relocated_black==white_slot);

    // Two distinct slots must both move; swapping their colors alone does
    // not count as relocation. Four validated sites always leave a choice.
    function [1:0] choose_white;
        input [1:0] candidate,black,old_white,old_black;
        input forbid_swap;
        integer choice;
        begin
            choose_white=candidate;
            for(choice=0;choice<3;choice=choice+1)
                if(choose_white==black || choose_white==old_white ||
                    (forbid_swap && choose_white==old_black))
                    choose_white=choose_white+2'd1;
        end
    endfunction
    always @(posedge clk)
        if(reset) portal_rng<=8'hA7;
        else portal_rng<={portal_rng[6:0],portal_rng[7]^portal_rng[5]^portal_rng[4]^portal_rng[3]};

    wire [6:0] map_left_x,map_center_x,map_bank_x0,map_bank_x1,map_bank_x2,map_spinner_x;
    wire [5:0] map_right_y,map_center_y,map_bank_y,map_bank_y1,map_bank_y2,map_spinner_y,map_rollover_y;
    wire [5:0] map_bumper_y_min,map_bumper_y_max;
    wire [6:0] map_bumper_x_min,map_bumper_x_max;
    wire [6:0] map_sling_left_x,map_sling_right_x,map_side_left_x,map_side_right_x;
    wire [5:0] map_sling_left_y,map_sling_right_y;
    wire [5:0] map_side_left_min,map_side_left_max,map_side_right_min,map_side_right_max;
    pinball_layout geometry(.layout_id(layout_id),
        .bumper_left_x(map_left_x),.bumper_right_y(map_right_y),
        .bumper_center_x(map_center_x),.bumper_center_y(map_center_y),
        .bank_x0(map_bank_x0),.bank_y(map_bank_y),
        .bank_x1(map_bank_x1),.bank_x2(map_bank_x2),.bank_y1(map_bank_y1),.bank_y2(map_bank_y2),
        .bumper_y_min(map_bumper_y_min),.bumper_y_max(map_bumper_y_max),
        .bumper_x_min(map_bumper_x_min),.bumper_x_max(map_bumper_x_max),
        .sling_left_x(map_sling_left_x),.sling_left_y(map_sling_left_y),
        .sling_right_x(map_sling_right_x),.sling_right_y(map_sling_right_y),
        .side_left_x(map_side_left_x),.side_right_x(map_side_right_x),
        .side_left_y_min(map_side_left_min),.side_left_y_max(map_side_left_max),
        .side_right_y_min(map_side_right_min),.side_right_y_max(map_side_right_max),
        .spinner_x(map_spinner_x),.spinner_y(map_spinner_y),.rollover_y(map_rollover_y));
    wire signed [15:0] map_bumper_y_min_q8={2'b0,map_bumper_y_min,8'b0};
    wire signed [15:0] map_bumper_y_max_q8={2'b0,map_bumper_y_max,8'b0};
    wire signed [15:0] map_bumper_x_min_q8={1'b0,map_bumper_x_min,8'b0};
    wire signed [15:0] map_bumper_x_max_q8={1'b0,map_bumper_x_max,8'b0};
    wire signed [15:0] map_side_left_min_q8={2'b0,map_side_left_min,8'b0};
    wire signed [15:0] map_side_left_max_q8={2'b0,map_side_left_max,8'b0};
    wire signed [15:0] map_side_right_min_q8={2'b0,map_side_right_min,8'b0};
    wire signed [15:0] map_side_right_max_q8={2'b0,map_side_right_max,8'b0};
    wire signed [15:0] map_sling_left_x_q8={1'b0,map_sling_left_x,8'b0};
    wire signed [15:0] map_sling_left_y_q8={2'b0,map_sling_left_y,8'b0};
    wire signed [15:0] map_sling_right_x_q8={1'b0,map_sling_right_x,8'b0};
    wire signed [15:0] map_sling_right_y_q8={2'b0,map_sling_right_y,8'b0};

    // Preparation consumes the newly selected map, while the live decoder
    // above remains tied to the atomically committed world until this edge.
    wire [5:0] prepare_bumper_y_min,prepare_bumper_y_max;
    wire [6:0] prepare_bumper_x_min,prepare_bumper_x_max;
    wire [5:0] prepare_side_left_min,prepare_side_left_max,prepare_side_right_min,prepare_side_right_max;
    pinball_layout prepared_geometry(.layout_id(prepare_layout),
        .bumper_y_min(prepare_bumper_y_min),.bumper_y_max(prepare_bumper_y_max),
        .bumper_x_min(prepare_bumper_x_min),.bumper_x_max(prepare_bumper_x_max),
        .side_left_y_min(prepare_side_left_min),.side_left_y_max(prepare_side_left_max),
        .side_right_y_min(prepare_side_right_min),.side_right_y_max(prepare_side_right_max));
    wire [13:0] prepare_bumper_y_mid={1'b0,prepare_bumper_y_min,7'b0}+{1'b0,prepare_bumper_y_max,7'b0};
    wire [14:0] prepare_bumper_x_mid={1'b0,prepare_bumper_x_min,7'b0}+{1'b0,prepare_bumper_x_max,7'b0};

    // Collision is a deliberately multi-cycle combinational calculation.
    // Every operand is isolated here and remains stable for 16 system
    // clocks before the corrected result is committed. The matching XDC
    // exceptions apply only from these snapshot registers to result state.
    (* KEEP = "TRUE" *) reg signed [15:0] collision_proposed_x, collision_proposed_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_velocity_x, collision_velocity_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_previous_x, collision_previous_y;
    (* KEEP = "TRUE" *) reg collision_in_lane;
    (* KEEP = "TRUE" *) reg [2:0] collision_left_angle, collision_right_angle;
    (* KEEP = "TRUE" *) reg collision_left_pressed, collision_right_pressed;
    (* KEEP = "TRUE" *) reg collision_left_moving, collision_right_moving;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_moving_bumper_previous_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_moving_bumper_next_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_moving_bumper_velocity_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_moving_bumper_previous_x;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_moving_bumper_next_x;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_moving_bumper_velocity_x;
    (* KEEP = "TRUE" *) reg collision_moving_bumper_y_positive;
    (* KEEP = "TRUE" *) reg collision_moving_bumper_x_positive;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_side_left_previous_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_side_left_next_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_side_left_velocity_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_side_right_previous_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_side_right_next_y;
    (* KEEP = "TRUE" *) reg signed [15:0] collision_side_right_velocity_y;
    (* KEEP = "TRUE" *) reg collision_side_left_y_positive;
    (* KEEP = "TRUE" *) reg collision_side_right_y_positive;
    integer k;

    assign balls_visible = {ball2_alive,ball1_alive};
    // Nudge/save controls treat the launch as in-lane only while every live
    // ball remains in its own lane. A drained ball cannot hold this high.
    assign in_lane = (ball1_alive || ball2_alive) &&
                     (!ball1_alive || ball1_in_lane) &&
                     (!ball2_alive || ball2_in_lane);

    wire accept_batch = tick && active && !launch && !collision_busy &&
                        (launched || launched2);
    // A one-clock handover makes the shared gravity/clamp/hysteresis mux
    // settle before the second isolated collision snapshot is captured.
    wire operand_ball = load_second ? 1'b1 :
                        (collision_busy ? work_ball : !launched);
    wire signed [15:0] operand_x = operand_ball ? position2_x : position_x;
    wire signed [15:0] operand_y = operand_ball ? position2_y : position_y;
    wire signed [15:0] operand_vx = operand_ball ? velocity2_x : velocity_x;
    wire signed [15:0] operand_vy = operand_ball ? velocity2_y : velocity_y;
    wire operand_lane = operand_ball ? ball2_in_lane : ball1_in_lane;

    // Tracks preserve clearance for a whole ball at walls, guides and other
    // objects in every map. Reverse on the proposed endpoint, before the
    // next step could enter a wall. Four Q8 units = 3.75 pixels/second.
    wire signed [15:0] bumper_y_step=layout_id[4] ? 16'sd8 : 16'sd4;
    wire signed [15:0] bumper_x_step=layout_id[5] ? 16'sd8 : 16'sd4;
    wire signed [15:0] side_left_step=(layout_id[0]^layout_id[5]) ? 16'sd8 : 16'sd4;
    wire signed [15:0] side_right_step=(layout_id[1]^layout_id[4]) ? 16'sd8 : 16'sd4;
    wire signed [15:0] next_bumper_y = $signed({2'b0,moving_bumper_y_fp}) +
        (moving_bumper_y_positive ? bumper_y_step : -bumper_y_step);
    wire signed [15:0] next_bumper_x = $signed({1'b0,moving_bumper_x_fp}) +
        (moving_bumper_x_positive ? bumper_x_step : -bumper_x_step);
    wire next_bumper_y_positive = (next_bumper_y >= map_bumper_y_max_q8) ? 1'b0 :
        ((next_bumper_y <= map_bumper_y_min_q8) ? 1'b1 : moving_bumper_y_positive);
    wire next_bumper_x_positive = (next_bumper_x >= map_bumper_x_max_q8) ? 1'b0 :
        ((next_bumper_x <= map_bumper_x_min_q8) ? 1'b1 : moving_bumper_x_positive);

    // Side targets move on disjoint vertical tracks, away from the launch
    // lane and lower guides. They share the same atomic world transaction as
    // the bumpers and both balls; only one motion step is accepted per pair.
    wire signed [15:0] next_side_left_y = $signed({2'b0,side_left_y_fp}) +
        (side_left_y_positive ? side_left_step : -side_left_step);
    wire signed [15:0] next_side_right_y = $signed({2'b0,side_right_y_fp}) +
        (side_right_y_positive ? side_right_step : -side_right_step);
    wire next_side_left_y_positive = (next_side_left_y >= map_side_left_max_q8) ? 1'b0 :
        ((next_side_left_y <= map_side_left_min_q8) ? 1'b1 : side_left_y_positive);
    wire next_side_right_y_positive = (next_side_right_y >= map_side_right_max_q8) ? 1'b0 :
        ((next_side_right_y <= map_side_right_min_q8) ? 1'b1 : side_right_y_positive);

    wire [2:0] next_left_angle = left_pressed ?
        ((left_angle < 4) ? left_angle + 1'b1 : left_angle) :
        ((left_angle != 0) ? left_angle - 1'b1 : left_angle);
    wire [2:0] next_right_angle = right_pressed ?
        ((right_angle < 4) ? right_angle + 1'b1 : right_angle) :
        ((right_angle != 0) ? right_angle - 1'b1 : right_angle);
    wire left_moving = left_pressed && (left_angle < 4);
    wire right_moving = right_pressed && (right_angle < 4);

    // Easy averages half a Q8 unit of gravity without widening every ball
    // register: alternate 0/1 ONCE per world step. The second ball consumes
    // the captured gravity, so neither pair ordering nor a survivor changes
    // the profile. Normal/Hard use one/two Q8 units per world step.
    wire signed [15:0] selected_gravity = (difficulty == 2'd0) ?
        (gravity_phase ? 16'sd1 : 16'sd0) :
        ((difficulty == 2'd1) ? 16'sd1 : 16'sd2);
    wire signed [15:0] gravity = load_second ? batch_gravity : selected_gravity;
    wire [1:0] operand_difficulty = load_second ? batch_difficulty : difficulty;
    wire signed [15:0] accelerated_vy = clamp_vertical(operand_vy + gravity,
        operand_y, operand_lane, operand_difficulty);
    wire signed [15:0] proposed_x = operand_x + clamp_horizontal(operand_vx);
    wire signed [15:0] proposed_y = operand_y + accelerated_vy;
    wire signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy;
    wire [13:0] contact_events, far_from_object;
    wire portal_far=far_static(operand_x,black_hole_x,4'd4) ||
        far_static(operand_y,{1'b0,black_hole_y},4'd4);
    wire white_portal_far=far_static(operand_x,white_hole_x,4'd4) ||
        far_static(operand_y,{1'b0,white_hole_y},4'd4);

    function signed [15:0] clamp_horizontal;
        input signed [15:0] value;
        begin
            if (value > 16'sd256) clamp_horizontal = 16'sd256;
            else if (value < -16'sd256) clamp_horizontal = -16'sd256;
            else clamp_horizontal = value;
        end
    endfunction

    function signed [15:0] clamp_vertical;
        input signed [15:0] value;
        input signed [15:0] height;
        input lane;
        input [1:0] level;
        reg signed [15:0] descent_limit;
        begin
            if (!lane && height >= 16'sd9728)
                descent_limit = (level==2'd0) ? 16'sd48 :
                    ((level==2'd1) ? 16'sd60 : 16'sd72);
            else
                descent_limit = (level==2'd0) ? 16'sd112 :
                    ((level==2'd1) ? 16'sd136 : 16'sd160);
            if (value > descent_limit) clamp_vertical = descent_limit;
            else if (value < -16'sd320) clamp_vertical = -16'sd320;
            else clamp_vertical = value;
        end
    endfunction

    function [15:0] magnitude;
        input signed [15:0] value;
        begin
            magnitude = (value < 0) ? -value : value;
        end
    endfunction

    // Exact Q8 distance-to-integer-center test without a 16-bit subtract/abs.
    // The fractional upper edge matters: center+radius+1/256 is already far.
    // Moving fractional centers still use the full-precision test below.
    function far_static;
        input signed [15:0] value;
        input [6:0] center;
        input [3:0] radius;
        reg signed [8:0] low,high;
        reg signed [7:0] whole;
        begin
            low=$signed({2'b0,center})-$signed({5'b0,radius});
            high=$signed({2'b0,center})+$signed({5'b0,radius});
            whole=$signed(value[15:8]);
            far_static=whole<low || whole>high ||
                (whole==high && |value[7:0]);
        end
    endfunction

    function [6:0] display_x;
        input signed [15:0] value;
        begin
            display_x = (value < 0) ? 7'd0 :
                        ((value >= 16'sd24320) ? 7'd95 : value[14:8]);
        end
    endfunction
    function [5:0] display_y;
        input signed [15:0] value;
        begin
            display_y = (value < 0) ? 6'd0 :
                        ((value >= 16'sd16128) ? 6'd63 : value[13:8]);
        end
    endfunction
    function [14:0] display_x_fp;
        input signed [15:0] value;
        begin
            display_x_fp = (value < 0) ? 15'd0 :
                        ((value >= 16'sd24320) ? 15'd24320 : value[14:0]);
        end
    endfunction
    function [13:0] display_y_fp;
        input signed [15:0] value;
        begin
            display_y_fp = (value < 0) ? 14'd0 :
                        ((value >= 16'sd16128) ? 14'd16128 : value[13:0]);
        end
    endfunction
    assign ball_x=display_x(position_x);
    assign ball_y=display_y(position_y);
    assign ball_x_fp=display_x_fp(position_x);
    assign ball_y_fp=display_y_fp(position_y);
    assign ball2_x=display_x(position2_x);
    assign ball2_y=display_y(position2_y);
    assign ball2_x_fp=display_x_fp(position2_x);
    assign ball2_y_fp=display_y_fp(position2_y);

    assign far_from_object[0] =
        far_static(operand_x,map_left_x,4'd6) ||
        (magnitude(operand_y - $signed({2'b0,moving_bumper_y_fp})) > 16'd1536);
    assign far_from_object[1] =
        (magnitude(operand_x - $signed({1'b0,moving_bumper_x_fp})) > 16'd1536) ||
        far_static(operand_y,{1'b0,map_right_y},4'd6);
    assign far_from_object[2] =
        far_static(operand_x,map_center_x,4'd6) ||
        far_static(operand_y,{1'b0,map_center_y},4'd6);
    assign far_from_object[3] =
        far_static(operand_x,map_side_left_x,4'd5) ||
        (magnitude(operand_y-$signed({2'b0,side_left_y_fp})) > 16'd1536);
    assign far_from_object[4] =
        far_static(operand_x,map_side_right_x,4'd5) ||
        (magnitude(operand_y-$signed({2'b0,side_right_y_fp})) > 16'd1536);

    // Hysteresis and independent cooldowns ensure traversing a lit lane or
    // spinner scores once until the ball really leaves its sensor region.
    assign far_from_object[5] = far_static(operand_x,7'd25,4'd4) ||
        far_static(operand_y,{1'b0,map_rollover_y},4'd3);
    assign far_from_object[6] = far_static(operand_x,7'd42,4'd4) ||
        far_static(operand_y,{1'b0,map_rollover_y},4'd3);
    assign far_from_object[7] = far_static(operand_x,7'd59,4'd4) ||
        far_static(operand_y,{1'b0,map_rollover_y},4'd3);
    assign far_from_object[8] = far_static(operand_x,map_spinner_x,4'd5) ||
        far_static(operand_y,{1'b0,map_spinner_y},4'd2);
    assign far_from_object[9] = ({1'b0,magnitude(operand_x-map_sling_left_x_q8)}+
        {1'b0,magnitude(operand_y-map_sling_left_y_q8)})>17'd1536;
    assign far_from_object[10] = ({1'b0,magnitude(operand_x-map_sling_right_x_q8)}+
        {1'b0,magnitude(operand_y-map_sling_right_y_q8)})>17'd1536;
    assign far_from_object[11] = far_static(operand_x,map_bank_x0,4'd4) ||
        far_static(operand_y,{1'b0,map_bank_y},4'd4);
    assign far_from_object[12] = far_static(operand_x,map_bank_x1,4'd4) ||
        far_static(operand_y,{1'b0,map_bank_y1},4'd4);
    assign far_from_object[13] = far_static(operand_x,map_bank_x2,4'd4) ||
        far_static(operand_y,{1'b0,map_bank_y2},4'd4);

    pinball_collision collisions (
        .layout_id(collision_layout_id),
        .proposed_x(collision_proposed_x), .proposed_y(collision_proposed_y),
        .velocity_x(collision_velocity_x), .velocity_y(collision_velocity_y),
        .previous_x(collision_previous_x), .previous_y(collision_previous_y),
        .in_lane(collision_in_lane),
        .left_angle(collision_left_angle), .right_angle(collision_right_angle),
        .left_pressed(collision_left_pressed), .right_pressed(collision_right_pressed),
        .left_moving(collision_left_moving), .right_moving(collision_right_moving),
        .moving_bumper_previous_y(collision_moving_bumper_previous_y),
        .moving_bumper_next_y(collision_moving_bumper_next_y),
        .moving_bumper_velocity_y(collision_moving_bumper_velocity_y),
        .moving_bumper_previous_x(collision_moving_bumper_previous_x),
        .moving_bumper_next_x(collision_moving_bumper_next_x),
        .moving_bumper_velocity_x(collision_moving_bumper_velocity_x),
        .side_left_previous_y(collision_side_left_previous_y),
        .side_left_next_y(collision_side_left_next_y),
        .side_left_velocity_y(collision_side_left_velocity_y),
        .side_right_previous_y(collision_side_right_previous_y),
        .side_right_next_y(collision_side_right_next_y),
        .side_right_velocity_y(collision_side_right_velocity_y),
        .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy),
        .hit_events(contact_events)
    );

    wire [15:0] black_dx=magnitude(corrected_x-$signed({1'b0,collision_black_x,8'b0}));
    wire [15:0] black_dy=magnitude(corrected_y-$signed({2'b0,collision_black_y,8'b0}));
    wire [15:0] white_dx=magnitude(corrected_x-$signed({1'b0,collision_white_x,8'b0}));
    wire [15:0] white_dy=magnitude(corrected_y-$signed({2'b0,collision_white_y,8'b0}));
    wire enter_black=black_dx<=16'd512 && black_dy<=16'd512 &&
        {1'b0,black_dx}+{1'b0,black_dy}<=17'd768;
    wire enter_white=white_dx<=16'd512 && white_dy<=16'd512 &&
        {1'b0,white_dx}+{1'b0,white_dy}<=17'd768;
    wire result_teleports=collision_portal_armed && !collision_in_lane &&
        (enter_black || enter_white);
    wire signed [15:0] result_x=result_teleports ?
        $signed({1'b0,(enter_black ? collision_white_x : collision_black_x),8'b0}) : corrected_x;
    wire signed [15:0] result_y=result_teleports ?
        $signed({2'b0,(enter_black ? collision_white_y : collision_black_y),8'b0}) : corrected_y;
    wire lane_exit = collision_in_lane && collision_proposed_y <= 16'sd3840;
    wire result_drains = !collision_in_lane && corrected_y >= 16'sd16384 &&
        corrected_x >= 16'sd7680 && corrected_x <= 16'sd14336;
    wire result_lane = collision_in_lane && !lane_exit;
    wire signed [15:0] result_vx = result_drains ? 16'sd0 :
        (lane_exit ? ((work_ball ? -16'sd128 : -16'sd160) -
            $signed({10'b0,shot_power})) :
        clamp_horizontal(corrected_vx + (collision_nudge ?
            (collision_previous_x<16'sd11008 ? 16'sd48 : -16'sd48) : 16'sd0)));
    wire signed [15:0] result_vy = result_drains ? 16'sd0 :
        (lane_exit ? -16'sd56 : clamp_vertical(corrected_vy -
            (collision_nudge ? 16'sd80 : 16'sd0),corrected_y,collision_in_lane,batch_difficulty));
    wire [13:0] result_hits = collision_in_lane ? 14'd0 :
        (contact_events & (work_ball ? hit_armed2 : hit_armed));

    always @(posedge clk) begin
        drained <= 1'b0;
        hit_events <= 14'b0;
        teleported<=2'b0;
        if (reset || prepare) begin
            black_slot<=reset ? 2'd0 : initial_black;
            white_slot<=reset ? 2'd2 : initial_white;
            portal_age<=0;portal_pending<=0;portal_anim<=0;portal_flash<=5'd24;
            portal_armed<=1;portal_armed2<=1;
            portal_cooldown<=0;portal_cooldown2<=0;stage_teleport<=0;
            collision_black_x<=0;collision_black_y<=0;
            collision_white_x<=0;collision_white_y<=0;collision_portal_armed<=0;
            layout_id<=prepare_layout;
            collision_layout_id<=prepare_layout;
            position_x<=16'sd22784; position_y<=16'sd14336;
            position2_x<=16'sd22784; position2_y<=16'sd15360;
            velocity_x<=0; velocity_y<=0; velocity2_x<=0; velocity2_y<=0;
            launched<=0; launched2<=0; ball1_alive<=1; ball2_alive<=two_ball_mode;
            ball1_in_lane<=1; ball2_in_lane<=1; shot_power<=0;
            left_angle<=0; right_angle<=0;
            hit_armed<=14'h3fff; hit_armed2<=14'h3fff;
            collision_busy<=0; collision_wait<=0;
            work_ball<=0; batch_both<=0; load_second<=0; batch_nudge<=0;
            nudge_pending<=0; collision_nudge<=0;
            stage_position_x<=16'sd22784; stage_position_y<=16'sd14336;
            stage_velocity_x<=0; stage_velocity_y<=0;
            stage_in_lane<=1; stage_alive<=1; stage_hits<=0;
            pending_hits<=0; pending_hit_wait<=0; pending_drain_wait<=0; hit_ball<=0;
            moving_bumper_y_fp<=prepare_layout[4] ? prepare_bumper_y_mid :
                {prepare_layout[1] ? prepare_bumper_y_max : prepare_bumper_y_min,8'b0};
            moving_bumper_x_fp<=prepare_layout[5] ? prepare_bumper_x_mid :
                {prepare_layout[0] ? prepare_bumper_x_max : prepare_bumper_x_min,8'b0};
            moving_bumper_y_positive<=!prepare_layout[1];
            moving_bumper_x_positive<=!prepare_layout[0];
            side_left_y_fp<={prepare_layout[1] ? prepare_side_left_max : prepare_side_left_min,8'b0};
            side_right_y_fp<={prepare_layout[0] ? prepare_side_right_max : prepare_side_right_min,8'b0};
            side_left_y_positive<=!prepare_layout[1];
            side_right_y_positive<=!prepare_layout[0];
            gravity_phase<=0; batch_gravity<=0; batch_difficulty<=difficulty;
            collision_side_left_previous_y<=16'sd8448;
            collision_side_left_next_y<=16'sd8448;
            collision_side_left_velocity_y<=0;
            collision_side_right_previous_y<=16'sd8448;
            collision_side_right_next_y<=16'sd8448;
            collision_side_right_velocity_y<=0;
            collision_side_left_y_positive<=1;
            collision_side_right_y_positive<=0;
            collision_moving_bumper_previous_y<=16'sd5632;
            collision_moving_bumper_next_y<=16'sd5632;
            collision_moving_bumper_velocity_y<=0;
            collision_moving_bumper_previous_x<=16'sd14848;
            collision_moving_bumper_next_x<=16'sd14848;
            collision_moving_bumper_velocity_x<=0;
            collision_moving_bumper_y_positive<=1;
            collision_moving_bumper_x_positive<=1;
            collision_proposed_x<=16'sd22784; collision_proposed_y<=16'sd14336;
            collision_previous_x<=16'sd22784; collision_previous_y<=16'sd14336;
            collision_velocity_x<=0; collision_velocity_y<=0; collision_in_lane<=1;
            collision_left_angle<=0; collision_right_angle<=0;
            collision_left_pressed<=0; collision_right_pressed<=0;
            collision_left_moving<=0; collision_right_moving<=0;
            for(k=0;k<14;k=k+1) begin cooldown[k]<=0; cooldown2[k]<=0; end
        end else begin
            // Count real PLAY ticks, independently of the arithmetic engine.
            // A due relocation waits for an idle edge between world batches.
            if(tick && active) begin
                portal_anim<=portal_anim+1'b1;
                if(portal_flash!=0) portal_flash<=portal_flash-1'b1;
                if(portal_age==11'd1199) begin portal_age<=0;portal_pending<=1;end
                else portal_age<=portal_age+1'b1;
            end
            if(portal_pending && active && !collision_busy && !accept_batch) begin
                black_slot<=relocated_black;white_slot<=relocated_white;
                portal_pending<=0;portal_flash<=5'd24;
                // A new portal appearing under a ball must not capture it
                // until the ball has left the mouth and entered again.
                portal_armed<=0;portal_armed2<=0;
                portal_cooldown<=0;portal_cooldown2<=0;
            end
            // Separate pulses preserve two awards even when both balls hit
            // the same object in one world step. Final drain follows the
            // second pulse's acceptance, so rules see both while in PLAY.
            if(pending_hit_wait!=0) begin
                pending_hit_wait<=pending_hit_wait-1'b1;
                if(pending_hit_wait==1) begin hit_events<=pending_hits; hit_ball<=1; end
            end
            if(pending_drain_wait!=0) begin
                pending_drain_wait<=pending_drain_wait-1'b1;
                if(pending_drain_wait==1) drained<=1;
            end
            if(nudge && active && !in_lane) nudge_pending<=1;
            if(launch && !collision_busy) begin
                shot_power<=launch_power;
                if(ball1_alive && ball1_in_lane && !launched) begin
                    launched<=1; velocity_y<=-16'sd288-$signed({10'b0,launch_power});
                    velocity_x<=0;
                end
                if(ball2_alive && ball2_in_lane && !launched2) begin
                    launched2<=1; velocity2_y<=-16'sd288-$signed({10'b0,launch_power});
                    velocity2_x<=0;
                end
            end
            if(tick && active && !collision_busy) begin
                left_angle<=next_left_angle; right_angle<=next_right_angle;
            end
            if(accept_batch) begin
                collision_black_x<=black_hole_x;collision_black_y<=black_hole_y;
                collision_white_x<=white_hole_x;collision_white_y<=white_hole_y;
                collision_layout_id<=layout_id;
                work_ball<=!launched;
                batch_both<=launched && launched2;
                batch_gravity<=selected_gravity; batch_difficulty<=difficulty;
                gravity_phase<=!gravity_phase;
                batch_nudge<=nudge_pending || nudge;
                nudge_pending<=0;
                collision_busy<=1; collision_wait<=5'd16;
                collision_left_angle<=next_left_angle;
                collision_right_angle<=next_right_angle;
                collision_left_pressed<=left_pressed; collision_right_pressed<=right_pressed;
                collision_left_moving<=left_moving; collision_right_moving<=right_moving;
                collision_moving_bumper_previous_y<=$signed({2'b0,moving_bumper_y_fp});
                collision_moving_bumper_next_y<=next_bumper_y;
                collision_moving_bumper_velocity_y<=next_bumper_y-$signed({2'b0,moving_bumper_y_fp});
                collision_moving_bumper_previous_x<=$signed({1'b0,moving_bumper_x_fp});
                collision_moving_bumper_next_x<=next_bumper_x;
                collision_moving_bumper_velocity_x<=next_bumper_x-$signed({1'b0,moving_bumper_x_fp});
                collision_moving_bumper_y_positive<=next_bumper_y_positive;
                collision_moving_bumper_x_positive<=next_bumper_x_positive;
                collision_side_left_previous_y<=$signed({2'b0,side_left_y_fp});
                collision_side_left_next_y<=next_side_left_y;
                collision_side_left_velocity_y<=next_side_left_y-$signed({2'b0,side_left_y_fp});
                collision_side_right_previous_y<=$signed({2'b0,side_right_y_fp});
                collision_side_right_next_y<=next_side_right_y;
                collision_side_right_velocity_y<=next_side_right_y-$signed({2'b0,side_right_y_fp});
                collision_side_left_y_positive<=next_side_left_y_positive;
                collision_side_right_y_positive<=next_side_right_y_positive;
            end
            if(accept_batch || load_second) begin
                collision_portal_armed<=operand_ball ?
                    (portal_armed2 && portal_cooldown2==0) :
                    (portal_armed && portal_cooldown==0);
                if(operand_ball) begin
                    if(portal_cooldown2!=0) portal_cooldown2<=portal_cooldown2-1'b1;
                    else if(portal_far && white_portal_far) portal_armed2<=1;
                end else begin
                    if(portal_cooldown!=0) portal_cooldown<=portal_cooldown-1'b1;
                    else if(portal_far && white_portal_far) portal_armed<=1;
                end
                collision_proposed_x<=proposed_x; collision_proposed_y<=proposed_y;
                collision_velocity_x<=operand_vx; collision_velocity_y<=accelerated_vy;
                collision_previous_x<=operand_x; collision_previous_y<=operand_y;
                collision_in_lane<=operand_lane;
                collision_nudge<=!operand_lane &&
                    (load_second ? batch_nudge : (nudge_pending || nudge));
                // Rearming and decrement use the same shared envelopes but
                // separate per-ball state, exactly once per accepted step.
                for(k=0;k<14;k=k+1) begin
                    if(operand_ball) begin
                        if(cooldown2[k]!=0) cooldown2[k]<=cooldown2[k]-1'b1;
                        else if(far_from_object[k]) hit_armed2[k]<=1;
                    end else begin
                        if(cooldown[k]!=0) cooldown[k]<=cooldown[k]-1'b1;
                        else if(far_from_object[k]) hit_armed[k]<=1;
                    end
                end
            end
            if(collision_busy) begin
                if(load_second) begin
                    load_second<=0; collision_wait<=5'd16;
                end else if(collision_wait>1) begin
                    collision_wait<=collision_wait-1'b1;
                end else begin
                    // Disarm only the ball that made this contact.
                    for(k=0;k<14;k=k+1) if(result_hits[k]) begin
                        if(work_ball) begin hit_armed2[k]<=0; cooldown2[k]<=5'd16; end
                        else begin hit_armed[k]<=0; cooldown[k]<=5'd16; end
                    end
                    if(batch_both && !work_ball) begin
                        stage_position_x<=result_x; stage_position_y<=result_y;
                        stage_velocity_x<=result_vx; stage_velocity_y<=result_vy;
                        stage_in_lane<=result_lane; stage_alive<=!result_drains;
                        stage_hits<=result_hits;stage_teleport<=result_teleports;
                        work_ball<=1; load_second<=1; collision_wait<=0;
                    end else begin
                        collision_busy<=0; collision_wait<=0;
                        moving_bumper_y_fp<=collision_moving_bumper_next_y[13:0];
                        moving_bumper_x_fp<=collision_moving_bumper_next_x[14:0];
                        moving_bumper_y_positive<=collision_moving_bumper_y_positive;
                        moving_bumper_x_positive<=collision_moving_bumper_x_positive;
                        side_left_y_fp<=collision_side_left_next_y[13:0];
                        side_right_y_fp<=collision_side_right_next_y[13:0];
                        side_left_y_positive<=collision_side_left_y_positive;
                        side_right_y_positive<=collision_side_right_y_positive;
                        if(work_ball) begin
                            position2_x<=result_x; position2_y<=result_y;
                            velocity2_x<=result_vx; velocity2_y<=result_vy;
                            ball2_in_lane<=result_lane; ball2_alive<=!result_drains;
                            launched2<=!result_drains;
                        end else begin
                            position_x<=result_x; position_y<=result_y;
                            velocity_x<=result_vx; velocity_y<=result_vy;
                            ball1_in_lane<=result_lane; ball1_alive<=!result_drains;
                            launched<=!result_drains;
                        end
                        if(batch_both) begin
                            teleported<={result_teleports,stage_teleport};
                            if(stage_teleport) begin portal_armed<=0;portal_cooldown<=5'd24;end
                            position_x<=stage_position_x; position_y<=stage_position_y;
                            velocity_x<=stage_velocity_x; velocity_y<=stage_velocity_y;
                            ball1_in_lane<=stage_in_lane; ball1_alive<=stage_alive;
                            launched<=stage_alive;
                            hit_events<=stage_hits; hit_ball<=0;
                            pending_hits<=result_hits; pending_hit_wait<=4;
                            if(!stage_alive && result_drains) pending_drain_wait<=6;
                        end else begin
                            teleported<=work_ball ? {result_teleports,1'b0} : {1'b0,result_teleports};
                            hit_events<=result_hits; hit_ball<=work_ball;
                            if(result_drains && (work_ball ? !ball1_alive : !ball2_alive)) drained<=1;
                        end
                        if(result_teleports || (batch_both && stage_teleport)) portal_flash<=5'd24;
                        if(result_teleports) begin
                            if(work_ball) begin portal_armed2<=0;portal_cooldown2<=5'd24;end
                            else begin portal_armed<=0;portal_cooldown<=5'd24;end
                        end
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
