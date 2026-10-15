`timescale 1ns / 1ps
`default_nettype none

// Both balls share one arithmetic/collision datapath. A 240 Hz world step
// captures one 16-clock collision calculation per live ball. Ball positions
// and moving bumpers commit together after 16 clocks (one ball) or 33 clocks
// (two balls); the latter includes one clock to load the second operands.
module pinball_physics (
    input wire clk, reset, tick, active, prepare, launch,
    input wire two_ball_mode,
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
    (* KEEP = "TRUE" *) reg collision_nudge;

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

    // The radius-three bumpers follow short, clear tracks: left x=26,
    // y=22..28; right y=22, x=58..66. Four Q8 units per accepted physics
    // step are 3.75 OLED pixels/second. Centre, direction and ball commit
    // together, so neither the renderer nor collision sees a partial move.
    wire signed [15:0] next_bumper_y = $signed({2'b0,moving_bumper_y_fp}) +
        (moving_bumper_y_positive ? 16'sd4 : -16'sd4);
    wire signed [15:0] next_bumper_x = $signed({1'b0,moving_bumper_x_fp}) +
        (moving_bumper_x_positive ? 16'sd4 : -16'sd4);
    wire next_bumper_y_positive = (next_bumper_y >= 16'sd7168) ? 1'b0 :
        ((next_bumper_y <= 16'sd5632) ? 1'b1 : moving_bumper_y_positive);
    wire next_bumper_x_positive = (next_bumper_x >= 16'sd16896) ? 1'b0 :
        ((next_bumper_x <= 16'sd14848) ? 1'b1 : moving_bumper_x_positive);

    // Side targets move on disjoint vertical tracks, away from the launch
    // lane and lower guides. They share the same atomic world transaction as
    // the bumpers and both balls; only one motion step is accepted per pair.
    wire signed [15:0] next_side_left_y = $signed({2'b0,side_left_y_fp}) +
        (side_left_y_positive ? 16'sd4 : -16'sd4);
    wire signed [15:0] next_side_right_y = $signed({2'b0,side_right_y_fp}) +
        (side_right_y_positive ? 16'sd4 : -16'sd4);
    wire next_side_left_y_positive = (next_side_left_y >= 16'sd9472) ? 1'b0 :
        ((next_side_left_y <= 16'sd7424) ? 1'b1 : side_left_y_positive);
    wire next_side_right_y_positive = (next_side_right_y >= 16'sd9472) ? 1'b0 :
        ((next_side_right_y <= 16'sd7424) ? 1'b1 : side_right_y_positive);

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
        (magnitude(operand_x - 16'sd6656) > 16'd1536) ||
        (magnitude(operand_y - $signed({2'b0,moving_bumper_y_fp})) > 16'd1536);
    assign far_from_object[1] =
        (magnitude(operand_x - $signed({1'b0,moving_bumper_x_fp})) > 16'd1536) ||
        (magnitude(operand_y - 16'sd5632) > 16'd1536);
    assign far_from_object[2] =
        (magnitude(operand_x - 16'sd10752) > 16'd1536) ||
        (magnitude(operand_y - 16'sd8960) > 16'd1536);
    assign far_from_object[3] =
        (magnitude(operand_x-16'sd1536) > 16'd1280) ||
        (magnitude(operand_y-$signed({2'b0,side_left_y_fp})) > 16'd1536);
    assign far_from_object[4] =
        (magnitude(operand_x-16'sd19968) > 16'd1280) ||
        (magnitude(operand_y-$signed({2'b0,side_right_y_fp})) > 16'd1536);

    // Hysteresis and independent cooldowns ensure traversing a lit lane or
    // spinner scores once until the ball really leaves its sensor region.
    assign far_from_object[5] = magnitude(operand_x-16'sd6400)>16'd1024 ||
        operand_y<16'sd2816 || operand_y>16'sd4352;
    assign far_from_object[6] = magnitude(operand_x-16'sd10752)>16'd1024 ||
        operand_y<16'sd2816 || operand_y>16'sd4352;
    assign far_from_object[7] = magnitude(operand_x-16'sd15104)>16'd1024 ||
        operand_y<16'sd2816 || operand_y>16'sd4352;
    assign far_from_object[8] = magnitude(operand_x-16'sd10752)>16'd1280 ||
        operand_y<16'sd6400 || operand_y>16'sd7424;
    assign far_from_object[9] = ({1'b0,magnitude(operand_x-16'sd4352)}+
        {1'b0,magnitude(operand_y-16'sd10496)})>17'd1536;
    assign far_from_object[10] = ({1'b0,magnitude(operand_x-16'sd17664)}+
        {1'b0,magnitude(operand_y-16'sd10496)})>17'd1536;
    assign far_from_object[11] = magnitude(operand_x-16'sd8704)>16'd1024 ||
        magnitude(operand_y-16'sd5120)>16'd1024;
    assign far_from_object[12] = magnitude(operand_x-16'sd10752)>16'd1024 ||
        magnitude(operand_y-16'sd5120)>16'd1024;
    assign far_from_object[13] = magnitude(operand_x-16'sd12800)>16'd1024 ||
        magnitude(operand_y-16'sd5120)>16'd1024;

    pinball_collision collisions (
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
        if (reset || prepare) begin
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
            moving_bumper_y_fp<=14'd5632; moving_bumper_x_fp<=15'd14848;
            moving_bumper_y_positive<=1; moving_bumper_x_positive<=1;
            side_left_y_fp<=14'd8448; side_right_y_fp<=14'd8448;
            side_left_y_positive<=1; side_right_y_positive<=0;
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
                        stage_position_x<=corrected_x; stage_position_y<=corrected_y;
                        stage_velocity_x<=result_vx; stage_velocity_y<=result_vy;
                        stage_in_lane<=result_lane; stage_alive<=!result_drains;
                        stage_hits<=result_hits;
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
                            position2_x<=corrected_x; position2_y<=corrected_y;
                            velocity2_x<=result_vx; velocity2_y<=result_vy;
                            ball2_in_lane<=result_lane; ball2_alive<=!result_drains;
                            launched2<=!result_drains;
                        end else begin
                            position_x<=corrected_x; position_y<=corrected_y;
                            velocity_x<=result_vx; velocity_y<=result_vy;
                            ball1_in_lane<=result_lane; ball1_alive<=!result_drains;
                            launched<=!result_drains;
                        end
                        if(batch_both) begin
                            position_x<=stage_position_x; position_y<=stage_position_y;
                            velocity_x<=stage_velocity_x; velocity_y<=stage_velocity_y;
                            ball1_in_lane<=stage_in_lane; ball1_alive<=stage_alive;
                            launched<=stage_alive;
                            hit_events<=stage_hits; hit_ball<=0;
                            pending_hits<=result_hits; pending_hit_wait<=4;
                            if(!stage_alive && result_drains) pending_drain_wait<=6;
                        end else begin
                            hit_events<=result_hits; hit_ball<=work_ball;
                            if(result_drains && (work_ball ? !ball1_alive : !ball2_alive)) drained<=1;
                        end
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
