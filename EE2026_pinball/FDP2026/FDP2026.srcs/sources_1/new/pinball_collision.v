`timescale 1ns / 1ps
`default_nettype none

// All positions and velocities are signed Q8 (256 units per OLED pixel).
// The ball has radius one. Eight-direction bumper normals avoid dividers,
// square roots and trigonometric hardware while giving repeatable rebounds.
module pinball_collision (
    input wire [5:0] layout_id,
    input wire signed [15:0] proposed_x,
    input wire signed [15:0] proposed_y,
    input wire signed [15:0] velocity_x,
    input wire signed [15:0] velocity_y,
    input wire signed [15:0] previous_x,
    input wire signed [15:0] previous_y,
    input wire in_lane,
    input wire [2:0] left_angle,
    input wire [2:0] right_angle,
    input wire left_pressed,
    input wire right_pressed,
    input wire left_moving,
    input wire right_moving,
    input wire signed [15:0] moving_bumper_previous_y,
    input wire signed [15:0] moving_bumper_next_y,
    input wire signed [15:0] moving_bumper_velocity_y,
    input wire signed [15:0] moving_bumper_previous_x,
    input wire signed [15:0] moving_bumper_next_x,
    input wire signed [15:0] moving_bumper_velocity_x,
    input wire signed [15:0] side_left_previous_y,
    input wire signed [15:0] side_left_next_y,
    input wire signed [15:0] side_left_velocity_y,
    input wire signed [15:0] side_right_previous_y,
    input wire signed [15:0] side_right_next_y,
    input wire signed [15:0] side_right_velocity_y,
    output reg signed [15:0] corrected_x,
    output reg signed [15:0] corrected_y,
    output reg signed [15:0] corrected_vx,
    output reg signed [15:0] corrected_vy,
    output reg [13:0] hit_events
);

    wire [6:0] map_left_x,map_center_x,map_bank_x0,map_bank_x1,map_bank_x2,map_spinner_x;
    wire [5:0] map_right_y,map_center_y,map_bank_y,map_bank_y1,map_bank_y2,map_spinner_y,map_rollover_y;
    wire [6:0] map_sling_left_x,map_sling_right_x,map_side_left_x,map_side_right_x;
    wire [5:0] map_sling_left_y,map_sling_right_y;
    pinball_layout geometry(.layout_id(layout_id),
        .bumper_left_x(map_left_x),.bumper_right_y(map_right_y),
        .bumper_center_x(map_center_x),.bumper_center_y(map_center_y),
        .bank_x0(map_bank_x0),.bank_y(map_bank_y),
        .bank_x1(map_bank_x1),.bank_x2(map_bank_x2),.bank_y1(map_bank_y1),.bank_y2(map_bank_y2),
        .sling_left_x(map_sling_left_x),.sling_left_y(map_sling_left_y),
        .sling_right_x(map_sling_right_x),.sling_right_y(map_sling_right_y),
        .side_left_x(map_side_left_x),.side_right_x(map_side_right_x),
        .spinner_x(map_spinner_x),.spinner_y(map_spinner_y),.rollover_y(map_rollover_y));
    wire signed [15:0] map_left_x_q8={1'b0,map_left_x,8'b0};
    wire signed [15:0] map_right_y_q8={2'b0,map_right_y,8'b0};
    wire signed [15:0] map_center_x_q8={1'b0,map_center_x,8'b0};
    wire signed [15:0] map_center_y_q8={2'b0,map_center_y,8'b0};
    wire signed [15:0] map_bank_x_q8={1'b0,map_bank_x0,8'b0};
    wire signed [15:0] map_bank_y_q8={2'b0,map_bank_y,8'b0};
    wire signed [15:0] map_bank_x1_q8={1'b0,map_bank_x1,8'b0};
    wire signed [15:0] map_bank_x2_q8={1'b0,map_bank_x2,8'b0};
    wire signed [15:0] map_bank_y1_q8={2'b0,map_bank_y1,8'b0};
    wire signed [15:0] map_bank_y2_q8={2'b0,map_bank_y2,8'b0};
    wire signed [15:0] map_spinner_x_q8={1'b0,map_spinner_x,8'b0};
    wire signed [15:0] map_spinner_y_q8={2'b0,map_spinner_y,8'b0};
    wire signed [15:0] map_rollover_y_q8={2'b0,map_rollover_y,8'b0};
    wire signed [15:0] map_side_left_x_q8={1'b0,map_side_left_x,8'b0};
    wire signed [15:0] map_side_right_x_q8={1'b0,map_side_right_x,8'b0};
    wire signed [15:0] map_sling_left_x_q8={1'b0,map_sling_left_x,8'b0};
    wire signed [15:0] map_sling_right_x_q8={1'b0,map_sling_right_x,8'b0};
    wire signed [15:0] map_sling_left_y_q8={2'b0,map_sling_left_y,8'b0};
    wire signed [15:0] map_sling_right_y_q8={2'b0,map_sling_right_y,8'b0};

    reg signed [15:0] centre_x, centre_y;
    reg signed [15:0] previous_centre_x, previous_centre_y;
    reg signed [15:0] centre_vx, centre_vy;
    reg signed [15:0] dx, dy;
    reg signed [15:0] previous_dx, previous_dy;
    reg [15:0] ax, ay;
    reg signed [15:0] old_vx, old_vy;
    reg signed [16:0] approach;
    reg signed [31:0] line_y, previous_line_y;
    reg signed [31:0] local_x;
    reg signed [31:0] previous_local_x;
    reg signed [31:0] slope;
    reg signed [31:0] lower_bound;
    reg solid_contact;
    reg sx, sy;
    reg [4:0] sweep;
    reg [2:0] target_sweep;
    reg [1:0] normal_axis;
    reg rectangle_found;
    reg [2:0] rectangle_index;
    reg signed [15:0] rectangle_half_y, rectangle_impulse;
    reg signed [16:0] rectangle_old_x, rectangle_new_x;
    integer i;

    function [15:0] magnitude;
        input signed [15:0] value;
        begin
            magnitude = (value < 0) ? -value : value;
        end
    endfunction

    // Sweep the relative ball/bumper segment across all four pairs of
    // octagon faces. Cross-multiplication checks each finite face without
    // division. This catches a grazing step that enters and exits a corner
    // even when neither endpoint is inside; OLD and NEXT centres must both
    // belong to the same isolated transaction.
    // Result: hit, outward positive sign, face (x / y / x+y / x-y).
    function [4:0] swept_octagon;
        input signed [15:0] old_x, old_y, new_x, new_y;
        reg signed [16:0] old_projection, new_projection;
        reg signed [16:0] old_tangent, new_tangent;
        reg signed [16:0] boundary, tangent_limit;
        reg signed [17:0] denominator, numerator;
        reg signed [35:0] intercept, tangent_bound;
        reg positive;
        integer face;
        begin
            swept_octagon = 0;
            old_projection=0; new_projection=0;
            old_tangent=0; new_tangent=0;
            boundary=0; tangent_limit=0;
            denominator=0; numerator=0; intercept=0; tangent_bound=0;
            positive=0;
            for (face=0; face<4; face=face+1) begin
                case (face)
                    0: begin
                        old_projection=old_x; new_projection=new_x;
                        old_tangent=old_y; new_tangent=new_y;
                        boundary=17'sd1024; tangent_limit=17'sd448;
                    end
                    1: begin
                        old_projection=old_y; new_projection=new_y;
                        old_tangent=old_x; new_tangent=new_x;
                        boundary=17'sd1024; tangent_limit=17'sd448;
                    end
                    2: begin
                        old_projection=$signed(old_x)+$signed(old_y);
                        new_projection=$signed(new_x)+$signed(new_y);
                        old_tangent=$signed(old_x)-$signed(old_y);
                        new_tangent=$signed(new_x)-$signed(new_y);
                        boundary=17'sd1472; tangent_limit=17'sd576;
                    end
                    default: begin
                        old_projection=$signed(old_x)-$signed(old_y);
                        new_projection=$signed(new_x)-$signed(new_y);
                        old_tangent=$signed(old_x)+$signed(old_y);
                        new_tangent=$signed(new_x)+$signed(new_y);
                        boundary=17'sd1472; tangent_limit=17'sd576;
                    end
                endcase
                positive=(old_projection>=0);
                if (!positive) begin
                    old_projection=-old_projection;
                    new_projection=-new_projection;
                end
                denominator=old_projection-new_projection;
                numerator=old_projection-boundary;
                intercept=old_tangent*denominator+(new_tangent-old_tangent)*numerator;
                tangent_bound=tangent_limit*denominator;
                if (!swept_octagon[4] && old_projection>boundary &&
                    new_projection<=boundary && denominator>0 &&
                    intercept>=-tangent_bound && intercept<=tangent_bound)
                    swept_octagon={1'b1,positive,face[2:0]};
            end
        end
    endfunction

    // Adjacent-face corner transit for a rectangle clearance region. With
    // the bounded physics step (<=256 horizontally, <=320 vertically), a
    // segment cannot enter and leave opposite faces in one tick. Selecting
    // the old outside face shares one intercept calculation instead of
    // instantiating a multiplier for every face. The finite tangent bound
    // rejects genuine near misses. Slings use x+y/x-y coordinates to turn
    // their diamond into the same rectangle, with clearance 1024.
    // Result: hit, outward positive sign, y-face (otherwise x-face).
    function [2:0] swept_clearance;
        input signed [16:0] old_x, old_y, new_x, new_y;
        input signed [16:0] clearance;
        reg signed [16:0] old_projection, new_projection;
        reg signed [16:0] old_tangent, new_tangent;
        reg signed [17:0] denominator, numerator;
        reg signed [35:0] intercept, tangent_bound;
        reg positive, y_face;
        begin
            swept_clearance=0;
            y_face=!((old_x>clearance) || (old_x<-clearance));
            old_projection=y_face ? old_y : old_x;
            new_projection=y_face ? new_y : new_x;
            old_tangent=y_face ? old_x : old_y;
            new_tangent=y_face ? new_x : new_y;
            positive=(old_projection>=0);
            if(!positive) begin old_projection=-old_projection;new_projection=-new_projection;end
            denominator=old_projection-new_projection;
            numerator=old_projection-clearance;
            intercept=old_tangent*denominator+(new_tangent-old_tangent)*numerator;
            tangent_bound=clearance*denominator;
            if(old_projection>clearance && new_projection<=clearance && denominator>0 &&
                intercept>=-tangent_bound && intercept<=tangent_bound)
                swept_clearance={1'b1,positive,y_face};
        end
    endfunction

    // Inner tip heights, relative to the pivot at y = 53.
    function signed [31:0] tip_offset;
        input [2:0] angle;
        begin
            case (angle)
                3'd0: tip_offset = 5;
                3'd1: tip_offset = 3;
                3'd2: tip_offset = 1;
                3'd3: tip_offset = -2;
                default: tip_offset = -4;
            endcase
        end
    endfunction

    always @* begin
        corrected_x = proposed_x;
        corrected_y = proposed_y;
        corrected_vx = velocity_x;
        corrected_vy = velocity_y;
        hit_events = 14'b0;
        centre_x = 0;
        centre_y = 0;
        previous_centre_x=0; previous_centre_y=0;
        centre_vx=0; centre_vy=0;
        dx = 0;
        dy = 0;
        previous_dx=0; previous_dy=0;
        ax = 0;
        ay = 0;
        old_vx = 0;
        old_vy = 0;
        approach = 0;
        line_y = 0;
        previous_line_y = 0;
        local_x = 0;
        previous_local_x = 0;
        slope = 0;
        lower_bound = 0;
        solid_contact = 1'b0;
        sx = 1'b0;
        sy = 1'b0;
        sweep=0; target_sweep=0; normal_axis=0;
        rectangle_found=0; rectangle_index=0;
        rectangle_half_y=16'sd512; rectangle_impulse=16'sd16;
        rectangle_old_x=0; rectangle_new_x=0;

        if (!in_lane) begin
            // Rollovers and spinner are sensors: the ball passes through.
            // Physics separately rearms each sensor only after exit.
            if (proposed_y >= map_rollover_y_q8-16'sd512 &&
                proposed_y <= map_rollover_y_q8+16'sd512) begin
                if (proposed_x >= 16'sd5632 && proposed_x <= 16'sd7168) hit_events[5] = 1'b1;
                if (proposed_x >= 16'sd9984 && proposed_x <= 16'sd11520) hit_events[6] = 1'b1;
                if (proposed_x >= 16'sd14336 && proposed_x <= 16'sd15872) hit_events[7] = 1'b1;
            end
            if (proposed_x >= map_spinner_x_q8-16'sd1024 &&
                proposed_x <= map_spinner_x_q8+16'sd1024 &&
                proposed_y >= map_spinner_y_q8-16'sd256 &&
                proposed_y <= map_spinner_y_q8+16'sd256)
                hit_events[8] = 1'b1;

            // Radius-four collision octagons enclose the drawn radius-three
            // bumpers and radius-one ball. Solid-object priority is stable.
            for (i = 0; i < 3; i = i + 1) begin
                case (i)
                    0: begin
                        centre_x=map_left_x_q8; centre_y=moving_bumper_next_y;
                        previous_centre_x=map_left_x_q8; previous_centre_y=moving_bumper_previous_y;
                        centre_vx=0; centre_vy=moving_bumper_velocity_y;
                    end
                    1: begin
                        centre_x=moving_bumper_next_x; centre_y=map_right_y_q8;
                        previous_centre_x=moving_bumper_previous_x; previous_centre_y=map_right_y_q8;
                        centre_vx=moving_bumper_velocity_x; centre_vy=0;
                    end
                    default: begin
                        centre_x=map_center_x_q8; centre_y=map_center_y_q8;
                        previous_centre_x=map_center_x_q8; previous_centre_y=map_center_y_q8;
                        centre_vx=0; centre_vy=0;
                    end
                endcase
                dx = proposed_x - centre_x;
                dy = proposed_y - centre_y;
                ax = magnitude(dx);
                ay = magnitude(dy);
                previous_dx=previous_x-previous_centre_x;
                previous_dy=previous_y-previous_centre_y;
                sweep=swept_octagon(previous_dx,previous_dy,dx,dy);
                if (!solid_contact && ((ax <= 16'd1024 && ay <= 16'd1024 &&
                    ({1'b0, ax} + {1'b0, ay}) <= 17'd1472) || sweep[4])) begin
                    solid_contact = 1'b1;
                    sx = (dx >= 0);
                    sy = (dy >= 0);
                    old_vx = velocity_x-centre_vx;
                    old_vy = velocity_y-centre_vy;
                    normal_axis=(ax>(ay<<1)) ? 0 : ((ay>(ax<<1)) ? 1 : 2);
                    if (sweep[4]) begin
                        case (sweep[2:0])
                            0: begin normal_axis=0; sx=sweep[3]; end
                            1: begin normal_axis=1; sy=sweep[3]; end
                            2: begin normal_axis=2; sx=sweep[3]; sy=sweep[3]; end
                            default: begin normal_axis=2; sx=sweep[3]; sy=!sweep[3]; end
                        endcase
                    end
                    if (normal_axis==0) begin
                        corrected_x = centre_x + (sx ? 16'sd1152 : -16'sd1152);
                        approach = sx ? old_vx : -old_vx;
                        if (approach < 0) begin
                            corrected_vx = sx ?
                                $signed((magnitude(old_vx) * 7) >> 3) + 16'sd24 :
                                -$signed((magnitude(old_vx) * 7) >> 3) - 16'sd24;
                            if (magnitude(corrected_vx) < 16'd160)
                                corrected_vx = sx ? 16'sd160 : -16'sd160;
                            corrected_vx=corrected_vx+centre_vx;
                            hit_events[i] = 1'b1;
                        end
                    end else if (normal_axis==1) begin
                        corrected_y = centre_y + (sy ? 16'sd1152 : -16'sd1152);
                        approach = sy ? old_vy : -old_vy;
                        if (approach < 0) begin
                            corrected_vy = sy ?
                                $signed((magnitude(old_vy) * 7) >> 3) + 16'sd24 :
                                -$signed((magnitude(old_vy) * 7) >> 3) - 16'sd24;
                            if (magnitude(corrected_vy) < 16'd160)
                                corrected_vy = sy ? 16'sd160 : -16'sd160;
                            corrected_vy=corrected_vy+centre_vy;
                            hit_events[i] = 1'b1;
                        end
                    end else begin
                        corrected_x = centre_x + (sx ? 16'sd832 : -16'sd832);
                        corrected_y = centre_y + (sy ? 16'sd832 : -16'sd832);
                        approach = (sx ? old_vx : -old_vx) +
                                   (sy ? old_vy : -old_vy);
                        if (approach < 0) begin
                            // Reflection about a 45-degree normal swaps the
                            // components. A small radial impulse livens play.
                            corrected_vx = (sx == sy) ? -old_vy : old_vy;
                            corrected_vy = (sx == sy) ? -old_vx : old_vx;
                            corrected_vx = corrected_vx + (sx ? 16'sd32 : -16'sd32)+centre_vx;
                            corrected_vy = corrected_vy + (sy ? 16'sd32 : -16'sd32)+centre_vy;
                            hit_events[i] = 1'b1;
                        end
                    end
                end
            end

            // The three stand-up rectangles and two moving side rectangles
            // are far enough apart that one bounded tick cannot reach two.
            // A cheap segment bounding box chooses one candidate before a
            // SHARED finite-face sweep. This avoids five multiplier-heavy
            // sweeps and preserves the bank's original contact priority.
            for (i = 0; i < 5; i = i + 1) begin
                case (i)
                    0: begin centre_x=map_bank_x_q8; centre_y=map_bank_y_q8;
                        previous_centre_y=map_bank_y_q8; rectangle_half_y=16'sd512; end
                    1: begin centre_x=map_bank_x1_q8; centre_y=map_bank_y1_q8;
                        previous_centre_y=map_bank_y1_q8; rectangle_half_y=16'sd512; end
                    2: begin centre_x=map_bank_x2_q8; centre_y=map_bank_y2_q8;
                        previous_centre_y=map_bank_y2_q8; rectangle_half_y=16'sd512; end
                    3: begin centre_x=map_side_left_x_q8; centre_y=side_left_next_y;
                        previous_centre_y=side_left_previous_y; rectangle_half_y=16'sd1024; end
                    default: begin centre_x=map_side_right_x_q8; centre_y=side_right_next_y;
                        previous_centre_y=side_right_previous_y; rectangle_half_y=16'sd1024; end
                endcase
                dx=proposed_x-centre_x; dy=proposed_y-centre_y;
                previous_dx=previous_x-centre_x; previous_dy=previous_y-previous_centre_y;
                if (!rectangle_found &&
                    (previous_dx<=16'sd512 || dx<=16'sd512) &&
                    (previous_dx>=-16'sd512 || dx>=-16'sd512) &&
                    (previous_dy<=rectangle_half_y || dy<=rectangle_half_y) &&
                    (previous_dy>=-rectangle_half_y || dy>=-rectangle_half_y)) begin
                    rectangle_found=1;
                    rectangle_index=i[2:0];
                end
            end
            case (rectangle_index)
                0: begin centre_x=map_bank_x_q8; centre_y=map_bank_y_q8;
                    previous_centre_y=map_bank_y_q8; centre_vy=0; end
                1: begin centre_x=map_bank_x1_q8; centre_y=map_bank_y1_q8;
                    previous_centre_y=map_bank_y1_q8; centre_vy=0; end
                2: begin centre_x=map_bank_x2_q8; centre_y=map_bank_y2_q8;
                    previous_centre_y=map_bank_y2_q8; centre_vy=0; end
                3: begin centre_x=map_side_left_x_q8; centre_y=side_left_next_y;
                    previous_centre_y=side_left_previous_y; centre_vy=side_left_velocity_y; end
                default: begin centre_x=map_side_right_x_q8; centre_y=side_right_next_y;
                    previous_centre_y=side_right_previous_y; centre_vy=side_right_velocity_y; end
            endcase
            rectangle_half_y=(rectangle_index>=3) ? 16'sd1024 : 16'sd512;
            rectangle_impulse=(rectangle_index>=3) ? 16'sd32 : 16'sd16;
            dx=proposed_x-centre_x; dy=proposed_y-centre_y;
            previous_dx=previous_x-centre_x; previous_dy=previous_y-previous_centre_y;
            ax=magnitude(dx); ay=magnitude(dy);
            // Stretch a tall side rectangle horizontally by two so the
            // existing square sweep applies exactly, with no new multiplier.
            rectangle_old_x=$signed({previous_dx[15],previous_dx});
            rectangle_new_x=$signed({dx[15],dx});
            if (rectangle_index>=3) begin
                rectangle_old_x=rectangle_old_x<<<1;
                rectangle_new_x=rectangle_new_x<<<1;
            end
            target_sweep=(ax<=16'd512 && ay<=rectangle_half_y) ? 3'b0 :
                swept_clearance(rectangle_old_x,previous_dy,rectangle_new_x,dy,
                    $signed({rectangle_half_y[15],rectangle_half_y}));
            if (!solid_contact && rectangle_found &&
                ((ax<=16'd512 && ay<=rectangle_half_y) || target_sweep[2])) begin
                solid_contact=1;
                sx=(dx>=0); sy=(dy>=0);
                // Pick the nearest expanded face using penetration depths.
                normal_axis=({1'b0,ax}+{1'b0,rectangle_half_y}>
                    {1'b0,ay}+17'd512) ? 0 : 1;
                if (target_sweep[2]) begin
                    normal_axis=target_sweep[0] ? 1 : 0;
                    if (target_sweep[0]) sy=target_sweep[1]; else sx=target_sweep[1];
                end
                if (normal_axis==0) begin
                    corrected_x=centre_x+(sx ? 16'sd640 : -16'sd640);
                    approach=sx ? velocity_x : -velocity_x;
                    if (approach<0) begin
                        corrected_vx=sx ?
                            $signed((magnitude(velocity_x)*7)>>3)+rectangle_impulse :
                            -$signed((magnitude(velocity_x)*7)>>3)-rectangle_impulse;
                        if (rectangle_index<3) hit_events[11+rectangle_index]=1;
                        else hit_events[rectangle_index]=1;
                    end
                end else begin
                    corrected_y=centre_y+(sy ? (rectangle_half_y+16'sd128) :
                        -(rectangle_half_y+16'sd128));
                    old_vy=velocity_y-centre_vy;
                    approach=sy ? old_vy : -old_vy;
                    if (approach<0) begin
                        corrected_vy=(sy ?
                            $signed((magnitude(old_vy)*7)>>3)+rectangle_impulse :
                            -$signed((magnitude(old_vy)*7)>>3)-rectangle_impulse)+centre_vy;
                        if (rectangle_index<3) hit_events[11+rectangle_index]=1;
                        else hit_events[rectangle_index]=1;
                    end
                end
            end

            // Energized diamonds use the captured layout's validated slots.
            // Their Manhattan
            // radius three plus ball clearance gives a radius-four envelope.
            // An inward approach receives a stronger radial return; top-face
            // hits also send the ball inward towards the playable middle.
            for (i = 0; i < 2; i = i + 1) begin
                centre_x = (i == 0) ? map_sling_left_x_q8 : map_sling_right_x_q8;
                centre_y = (i == 0) ? map_sling_left_y_q8 : map_sling_right_y_q8;
                dx = proposed_x-centre_x; dy = proposed_y-centre_y;
                ax = magnitude(dx); ay = magnitude(dy);
                previous_dx=previous_x-centre_x;previous_dy=previous_y-centre_y;
                target_sweep=(({1'b0,ax}+{1'b0,ay})<=17'd1024) ? 3'b0 :
                    swept_clearance(
                        $signed({previous_dx[15],previous_dx})+$signed({previous_dy[15],previous_dy}),
                        $signed({previous_dx[15],previous_dx})-$signed({previous_dy[15],previous_dy}),
                        $signed({dx[15],dx})+$signed({dy[15],dy}),
                        $signed({dx[15],dx})-$signed({dy[15],dy}),17'sd1024);
                if (!solid_contact && (({1'b0,ax}+{1'b0,ay}) <= 17'd1024 || target_sweep[2])) begin
                    solid_contact = 1'b1;
                    sx = (dx >= 0); sy = (dy >= 0);
                    normal_axis=(ax>(ay<<1)) ? 0 : ((ay>(ax<<1)) ? 1 : 2);
                    if(target_sweep[2]) begin
                        normal_axis=2;
                        sx=target_sweep[1];
                        sy=target_sweep[0] ? !target_sweep[1] : target_sweep[1];
                    end
                    if (normal_axis==0) begin
                        corrected_x = centre_x+(sx ? 16'sd1152 : -16'sd1152);
                        approach = sx ? velocity_x : -velocity_x;
                        if (approach < 0) begin
                            corrected_vx = sx ? 16'sd224 : -16'sd224;
                            corrected_vy = velocity_y-16'sd64;
                            hit_events[9+i] = 1'b1;
                        end
                    end else if (normal_axis==1) begin
                        corrected_y = centre_y+(sy ? 16'sd1152 : -16'sd1152);
                        approach = sy ? velocity_y : -velocity_y;
                        if (approach < 0) begin
                            corrected_vy = sy ? 16'sd224 : -16'sd224;
                            corrected_vx = velocity_x+((i==0) ? 16'sd96 : -16'sd96);
                            hit_events[9+i] = 1'b1;
                        end
                    end else begin
                        corrected_x = centre_x+(sx ? 16'sd640 : -16'sd640);
                        corrected_y = centre_y+(sy ? 16'sd640 : -16'sd640);
                        approach = (sx ? velocity_x : -velocity_x)+(sy ? velocity_y : -velocity_y);
                        if (approach < 0) begin
                            corrected_vx = sx ? 16'sd192 : -16'sd192;
                            corrected_vy = sy ? 16'sd192 : -16'sd192;
                            hit_events[9+i] = 1'b1;
                        end
                    end
                end
            end

            // Flippers: compare the old ball height with the surface, so a
            // ball travelling below a flipper is not teleported through it.
            // A rising flipper can sweep into a ball within its reduced clearance
            // band. Constant division by 18 is synthesizable.
            if (!solid_contact && proposed_x >= 16'sd5120 && proposed_x <= 16'sd10240) begin
                local_x = $signed(proposed_x) - 32'sd5376;
                if (local_x < 0) local_x = 0;
                if (local_x > 32'sd4608) local_x = 32'sd4608;
                slope = tip_offset(left_angle);
                line_y = 32'sd13568 + (local_x * slope) / 18;
                previous_local_x = $signed(previous_x) - 32'sd5376;
                if (previous_local_x < 0) previous_local_x = 0;
                if (previous_local_x > 32'sd4608) previous_local_x = 32'sd4608;
                previous_line_y = 32'sd13568 + (previous_local_x * slope) / 18;
                if (proposed_y >= line_y - 32'sd448 && proposed_y <= line_y + 32'sd512 &&
                    ((velocity_y >= 0 && previous_y <= previous_line_y - 32'sd256) ||
                     (left_moving && previous_y <= previous_line_y + 32'sd512))) begin
                    corrected_y = line_y - 32'sd448;
                    corrected_x = proposed_x;
                    if (left_moving) begin
                        corrected_vy = -16'sd288 - (local_x >> 6);
                        corrected_vx = 16'sd48 + (local_x >> 5);
                    end else if (left_pressed && left_angle >= 3) begin
                        corrected_vy = -16'sd128 - (local_x >> 7);
                        corrected_vx = 16'sd40 + (local_x >> 6);
                    end else begin
                        if (velocity_y > 16'sd80) begin
                            corrected_vy = -$signed(magnitude(velocity_y) >> 1);
                            corrected_vx = velocity_x + 16'sd24;
                        end else begin
                            // At low energy the ball rolls down the released
                            // flipper towards its tip, rather than receiving
                            // an artificial upward impulse indefinitely.
                            corrected_vx = 16'sd48;
                            corrected_vy = (48 * slope) / 18;
                        end
                    end
                    solid_contact = 1'b1;
                end
            end
            if (!solid_contact && proposed_x >= 16'sd11776 && proposed_x <= 16'sd16896) begin
                local_x = 32'sd16640 - $signed(proposed_x);
                if (local_x < 0) local_x = 0;
                if (local_x > 32'sd4608) local_x = 32'sd4608;
                slope = tip_offset(right_angle);
                line_y = 32'sd13568 + (local_x * slope) / 18;
                previous_local_x = 32'sd16640 - $signed(previous_x);
                if (previous_local_x < 0) previous_local_x = 0;
                if (previous_local_x > 32'sd4608) previous_local_x = 32'sd4608;
                previous_line_y = 32'sd13568 + (previous_local_x * slope) / 18;
                if (proposed_y >= line_y - 32'sd448 && proposed_y <= line_y + 32'sd512 &&
                    ((velocity_y >= 0 && previous_y <= previous_line_y - 32'sd256) ||
                     (right_moving && previous_y <= previous_line_y + 32'sd512))) begin
                    corrected_y = line_y - 32'sd448;
                    corrected_x = proposed_x;
                    if (right_moving) begin
                        corrected_vy = -16'sd288 - (local_x >> 6);
                        corrected_vx = -16'sd48 - (local_x >> 5);
                    end else if (right_pressed && right_angle >= 3) begin
                        corrected_vy = -16'sd128 - (local_x >> 7);
                        corrected_vx = -16'sd40 - (local_x >> 6);
                    end else begin
                        if (velocity_y > 16'sd80) begin
                            corrected_vy = -$signed(magnitude(velocity_y) >> 1);
                            corrected_vx = velocity_x - 16'sd24;
                        end else begin
                            corrected_vx = -16'sd48;
                            corrected_vy = (48 * slope) / 18;
                        end
                    end
                    solid_contact = 1'b1;
                end
            end

            // Guides from (5,43) to (21,53), mirrored on the right, direct
            // descending side balls towards the flippers with no flat ledge.
            if (!solid_contact && velocity_y >= 0 && proposed_x < 16'sd5376 &&
                proposed_y >= 16'sd10240 && proposed_y < 16'sd14336) begin
                line_y = 32'sd11008 + (($signed(proposed_x) - 32'sd1280) * 10) / 16;
                if (proposed_y >= line_y - 32'sd256 && proposed_y <= line_y + 32'sd512) begin
                    corrected_y = line_y - 32'sd256;
                    corrected_vx = $signed((magnitude(velocity_y) * 3) >> 2) + 16'sd48;
                    corrected_vy = -$signed(magnitude(velocity_x) >> 1) - 16'sd48;
                    solid_contact = 1'b1;
                end
            end
            // Stop at the right pivot (65), mirroring the left pivot (21).
            // Extending this line beneath the flipper creates an invisible rail.
            if (!solid_contact && velocity_y >= 0 && proposed_x > 16'sd16640 &&
                proposed_y >= 16'sd10240 && proposed_y < 16'sd14336) begin
                line_y = 32'sd11008 + ((32'sd20736 - $signed(proposed_x)) * 10) / 16;
                if (proposed_y >= line_y - 32'sd256 && proposed_y <= line_y + 32'sd512) begin
                    corrected_y = line_y - 32'sd256;
                    corrected_vx = -$signed((magnitude(velocity_y) * 3) >> 2) - 16'sd48;
                    corrected_vy = -$signed(magnitude(velocity_x) >> 1) - 16'sd48;
                    solid_contact = 1'b1;
                end
            end

            // Lower sloping walls narrow the ball centre corridor from
            // x=20..66 at y=54 to x=30..56 at y=64, into the drain.
            if (!solid_contact && corrected_y >= 16'sd13824) begin
                lower_bound = 32'sd5120 + ($signed(corrected_y) - 32'sd13824);
                if (lower_bound > 32'sd7680) lower_bound = 32'sd7680;
                if (corrected_x < lower_bound) begin
                    corrected_x = lower_bound;
                    corrected_vx = $signed((magnitude(velocity_y) * 3) >> 2) + 16'sd64;
                    corrected_vy = -$signed(magnitude(velocity_x) >> 1) - 16'sd24;
                end else if (corrected_x > 32'sd22016 - lower_bound) begin
                    corrected_x = 32'sd22016 - lower_bound;
                    corrected_vx = -$signed((magnitude(velocity_y) * 3) >> 2) - 16'sd64;
                    corrected_vy = -$signed(magnitude(velocity_x) >> 1) - 16'sd24;
                end
            end
        end

        // Position correction plus inward-only reflection prevents sticking
        // and tunnelling at the outer wall or shooter-lane divider.
        if (corrected_y < 16'sd2560) begin
            corrected_y = 16'sd2560;
            if (corrected_vy < 0)
                corrected_vy = $signed((magnitude(corrected_vy) * 7) >> 3);
        end
        if (in_lane) begin
            if (corrected_x < 16'sd21760) begin
                corrected_x = 16'sd21760;
                if (corrected_vx < 0) corrected_vx = -corrected_vx;
            end
            if (corrected_x > 16'sd23808) begin
                corrected_x = 16'sd23808;
                if (corrected_vx > 0) corrected_vx = -corrected_vx;
            end
        end else begin
            if (corrected_x < 16'sd768) begin
                corrected_x = 16'sd768;
                if (corrected_vx < 0)
                    corrected_vx = $signed((magnitude(corrected_vx) * 7) >> 3);
            end
            if (corrected_y >= 16'sd4608 && corrected_x > 16'sd21248) begin
                corrected_x = 16'sd21248;
                if (corrected_vx > 0)
                    corrected_vx = -$signed((magnitude(corrected_vx) * 7) >> 3);
            end else if (corrected_x > 16'sd23808) begin
                corrected_x = 16'sd23808;
                if (corrected_vx > 0)
                    corrected_vx = -$signed((magnitude(corrected_vx) * 7) >> 3);
            end
        end
    end
endmodule
`default_nettype wire
