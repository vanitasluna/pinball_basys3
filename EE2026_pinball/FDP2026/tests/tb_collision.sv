`timescale 1ns/1ps
module tb_collision;
    reg signed [15:0] proposed_x, proposed_y, velocity_x, velocity_y;
    reg signed [15:0] previous_x, previous_y;
    reg in_lane, left_pressed, right_pressed, left_moving, right_moving;
    reg [2:0] left_angle, right_angle;
    reg signed [15:0] moving_bumper_previous_y, moving_bumper_next_y, moving_bumper_velocity_y;
    reg signed [15:0] moving_bumper_previous_x, moving_bumper_next_x, moving_bumper_velocity_x;
    reg signed [15:0] side_left_previous_y, side_left_next_y, side_left_velocity_y;
    reg signed [15:0] side_right_previous_y, side_right_next_y, side_right_velocity_y;
    wire signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy;
    wire [13:0] hit_events;
    integer checks = 0, extreme, direction, target, mirror, sling;

    pinball_collision dut (.*);

    task setup;
        input integer x, y, vx, vy;
        begin
            proposed_x = x; proposed_y = y;
            previous_x = x - vx; previous_y = y - vy;
            velocity_x = vx; velocity_y = vy;
            in_lane = 0; left_angle = 0; right_angle = 0;
            left_pressed = 0; right_pressed = 0;
            left_moving = 0; right_moving = 0;
            moving_bumper_previous_y=22*256; moving_bumper_next_y=22*256;
            moving_bumper_velocity_y=0;
            moving_bumper_previous_x=58*256; moving_bumper_next_x=58*256;
            moving_bumper_velocity_x=0;
            side_left_previous_y=33*256; side_left_next_y=33*256; side_left_velocity_y=0;
            side_right_previous_y=33*256; side_right_next_y=33*256; side_right_velocity_y=0;
        end
    endtask

    task check;
        input condition;
        input [511:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL collision: %0s x=%0d y=%0d vx=%0d vy=%0d hits=%b",
                    message, corrected_x, corrected_y, corrected_vx, corrected_vy, hit_events);
                $fatal(1);
                $finish;
            end
        end
    endtask

    initial begin
        // Both guides end at their flipper pivots. A ball already beneath a
        // flipper must fall through the visible gap, without an invisible
        // extension of the right guide reflecting it back into play.
        for(extreme=0;extreme<5;extreme=extreme+1) begin
            for(mirror=0;mirror<2;mirror=mirror+1) begin
                setup((mirror ? 62 : 24)*256,55*256,0,64);
                left_angle=extreme;right_angle=extreme;#1;
                check(corrected_x==proposed_x && corrected_y==proposed_y &&
                      corrected_vx==0 && corrected_vy==64 && hit_events==0,
                      "no invisible guide beneath either flipper at any angle");
            end
        end
        setup(76*256,46*256,0,200);#1;
        check(corrected_vx<0 && corrected_vy<0,"visible right guide still directs inward");
        setup(2*256, 15*256, -200, 0); #1;
        check(corrected_x == 3*256 && corrected_vx == 175, "left wall restitution");
        setup(2*256, 15*256, 200, 0); #1;
        check(corrected_x == 3*256 && corrected_vx == 200, "outgoing wall velocity retained");
        setup(20*256, 9*256, 0, -200); #1;
        check(corrected_y == 10*256 && corrected_vy == 175, "top wall correction");
        setup(86*256, 20*256, 200, 0); #1;
        check(corrected_x == 83*256 && corrected_vx == -175, "divider prevents lane reentry");
        setup(89*256, 20*256, 0, -200); in_lane = 1; #1;
        check(corrected_x == 89*256 && corrected_y == 20*256, "shooter lane permitted");

        setup(26*256, 18*256, 0, 256); #1;
        check(hit_events == 5'b00001 && corrected_vy < 0 && corrected_y < 18*256,
            "left bumper bit and outward correction");
        setup(58*256, 18*256, 0, 256); #1;
        check(hit_events == 5'b00010 && corrected_vy < 0, "right bumper bit");
        setup(42*256, 31*256, 0, 256); #1;
        check(hit_events == 5'b00100 && corrected_vy < 0, "centre bumper bit");
        setup(26*256, 18*256, 0, -256); #1;
        check(hit_events == 0 && corrected_vy == -256, "outgoing bumper does not retrigger");
        setup(29*256, 24*256, -160, -160); #1;
        check(hit_events == 5'b00001 && corrected_vx > 0 && corrected_vy > 0,
            "diagonal bumper reflection");
        setup(8*256, 33*256, -200, 0); #1;
        check(hit_events == 5'b01000 && corrected_vx > 0 && corrected_x > 8*256,
            "left target bit");
        setup(76*256, 33*256, 200, 0); #1;
        check(hit_events == 5'b10000 && corrected_vx < 0 && corrected_x < 76*256,
            "right target bit");

        setup(30*256, 54*256, 0, 256); previous_y = 52*256; #1;
        check(corrected_vy < 0 && corrected_vx > 0 && corrected_y < proposed_y,
            "resting left flipper returns falling ball towards gap");
        setup(56*256, 54*256, 0, 256); previous_y = 52*256; #1;
        check(corrected_vy < 0 && corrected_vx < 0, "right flipper mirrored return");
        setup(36*256, 48*256+128, 0, 50);
        previous_y = 48*256; left_angle = 4; left_pressed = 1; left_moving = 1; #1;
        check(corrected_vy <= -300 && corrected_vx > 0, "moving flipper strong impulse");
        setup(30*256, 49*256+128, 0, 100);
        previous_y = 47*256; left_angle = 4; left_pressed = 1; #1;
        check(corrected_vy < -128 && corrected_vy > -200, "held flipper weaker impulse");
        setup(30*256, 54*256, 0, 100);
        previous_y = 54*256; left_angle = 4; #1;
        check(corrected_y == proposed_y && corrected_vy == 100,
            "ball below raised flipper is not teleported");
        setup(10*256, 46*256, 0, 200); #1;
        check(corrected_vx > 0 && corrected_vy < 0, "left guide directs inward");
        setup(26*256,17*256+128,0,160); #1;
        check(!hit_events[0] && corrected_y==proposed_y,
            "smaller bumpers leave a real gap outside radius-four envelope");
        setup(25*256,14*256,0,100); #1;
        check(hit_events==14'h0020 && corrected_x==proposed_x && corrected_y==proposed_y &&
            corrected_vy==100,"left rollover scores without reflecting motion");
        setup(42*256,14*256,0,-100); #1;
        check(hit_events==14'h0040 && corrected_vy==-100,"middle rollover both travel directions");
        setup(59*256,14*256,120,0); #1;
        check(hit_events==14'h0080 && corrected_vx==120,"right rollover independent event");
        setup(21*256,14*256,0,100); #1;
        check(hit_events==0,"outside rollover horizontal boundary is silent");
        setup(25*256,17*256,0,100); #1;
        check(hit_events==0,"outside rollover vertical boundary is silent");
        setup(42*256,27*256,100,20); #1;
        check(hit_events==14'h0100 && corrected_vx==100 && corrected_vy==20 &&
            corrected_y==proposed_y,"spinner sensor leaves trajectory continuous");
        setup(47*256,27*256,100,0); #1;
        check(hit_events==0,"spinner horizontal boundary");
        setup(17*256,37*256,0,76); #1;
        check(hit_events==14'h0200 && corrected_vy==-224 && corrected_vx>0,
            "left sling returns a falling ball up and inward");
        setup(69*256,37*256,0,76); #1;
        check(hit_events==14'h0400 && corrected_vy==-224 && corrected_vx<0,
            "right sling mirrors energized return");
        setup(20*256,44*256,0,50); #1;
        check(hit_events==0 && corrected_y==proposed_y,
            "diamond bounding-box corner is empty");
        setup(34*256,18*256,0,100); #1;
        check(hit_events==14'h0800 && corrected_vy<0 && corrected_y==17*256+128,
            "stand-up bank target one reflects top-face contact");
        setup(42*256,18*256,0,100); #1;
        check(hit_events==14'h1000 && corrected_vy<0,"stand-up bank target two");
        setup(50*256,18*256,0,100); #1;
        check(hit_events==14'h2000 && corrected_vy<0,"stand-up bank target three");
        setup(32*256,20*256,100,0); #1;
        check(hit_events==14'h0800 && corrected_vx<0 && corrected_x==31*256+128,
            "target side-face contact has radius-one clearance");
        setup(34*256,18*256,0,-100); #1;
        check(hit_events==0 && corrected_vy==-100,"departing stand-up target does not rescore");
        setup(25*256,14*256,0,100); in_lane=1; #1;
        check(hit_events==0,"all table sensors are disabled in shooter lane");

        // Moving bumpers carry their OLD and NEXT centres into collision.
        // A stationary ball just beyond the old envelope is contacted by the
        // advancing surface, with rebound in the bumper's velocity frame.
        setup(26*256,26*256+2,0,0);
        moving_bumper_next_y=22*256+4; moving_bumper_velocity_y=4; #1;
        check(hit_events==14'h0001 && corrected_y==moving_bumper_next_y+1152 &&
            corrected_vy==164,"downward bumper sweeps into stationary ball");
        setup(26*256,24*256-2,0,0);
        moving_bumper_previous_y=28*256; moving_bumper_next_y=28*256-4;
        moving_bumper_velocity_y=-4; #1;
        check(hit_events==14'h0001 && corrected_y==moving_bumper_next_y-1152 &&
            corrected_vy==-164,"upward bumper sweeps into stationary ball");
        setup(62*256+2,22*256,0,0);
        moving_bumper_next_x=58*256+4; moving_bumper_velocity_x=4; #1;
        check(hit_events==14'h0002 && corrected_x==moving_bumper_next_x+1152 &&
            corrected_vx==164,"rightward bumper sweeps into stationary ball");
        setup(62*256-2,22*256,0,0);
        moving_bumper_previous_x=66*256; moving_bumper_next_x=66*256-4;
        moving_bumper_velocity_x=-4; #1;
        check(hit_events==14'h0002 && corrected_x==moving_bumper_next_x-1152 &&
            corrected_vx==-164,"leftward bumper sweeps into stationary ball");

        setup(62*256+1,22*256,2,0);
        moving_bumper_next_x=58*256+4; moving_bumper_velocity_x=4; #1;
        check(hit_events[1] && corrected_vx==164,
            "bumper overtaking slower ball uses relative approach");
        setup(62*256,22*256,20,0);
        moving_bumper_next_x=58*256+4; moving_bumper_velocity_x=4; #1;
        check(hit_events==0 && corrected_vx==20,
            "faster departing ball cannot retrigger moving bumper");
        setup(62*256,22*256,-200,0);
        moving_bumper_next_x=58*256+4; moving_bumper_velocity_x=4; #1;
        check(hit_events[1] && corrected_vx==206,
            "opposite velocity reflects relative speed plus moving surface");
        setup(62*256,22*256,-200,0);
        moving_bumper_previous_x=58*256+4; moving_bumper_next_x=58*256;
        moving_bumper_velocity_x=-4; #1;
        check(hit_events[1] && corrected_vx==191,
            "receding surface transfers less energy than approaching surface");

        // Grazing movement can cross the finite octagon between two outside
        // endpoints; neither a point sample nor old fixed centre can catch it.
        setup(26*256+1000,22*256+480,-40,70); #1;
        check(hit_events[0] && corrected_vx>0 && corrected_x==26*256+1152,
            "relative sweep catches corner transit with both endpoints outside");
        setup(26*256+1000,22*256+492,-40,70); #1;
        check(hit_events==0 && corrected_x==proposed_x && corrected_y==proposed_y,
            "swept finite-face bounds reject a genuine corner near miss");

        setup(26*256,18*256,0,256);
        moving_bumper_previous_y=28*256; moving_bumper_next_y=28*256; #1;
        check(!hit_events[0] && corrected_y==proposed_y && corrected_vy==256,
            "left bumper old static position is empty after movement");
        setup(54*256,22*256,256,0);
        moving_bumper_previous_x=66*256; moving_bumper_next_x=66*256; #1;
        check(!hit_events[1] && corrected_x==proposed_x && corrected_vx==256,
            "right bumper old static position is empty after movement");

        for(extreme=0;extreme<2;extreme=extreme+1) begin
            for(direction=0;direction<2;direction=direction+1) begin
                setup(26*256,(extreme ? 28 : 22)*256-1000,0,160);
                moving_bumper_previous_y=(extreme ? 28 : 22)*256;
                moving_bumper_velocity_y=direction ? 4 : -4;
                moving_bumper_next_y=moving_bumper_previous_y+moving_bumper_velocity_y; #1;
                check(hit_events[0] && corrected_vy<0 && corrected_y<proposed_y,
                    "left bumper collision follows both extrema and directions");
                setup((extreme ? 66 : 58)*256+1000,22*256,-160,0);
                moving_bumper_previous_x=(extreme ? 66 : 58)*256;
                moving_bumper_velocity_x=direction ? 4 : -4;
                moving_bumper_next_x=moving_bumper_previous_x+moving_bumper_velocity_x; #1;
                check(hit_events[1] && corrected_vx>0 && corrected_x>proposed_x,
                    "right bumper collision follows both extrema and directions");
            end
        end
        // A bounded legal diagonal tick can enter and exit adjacent target
        // faces while neither endpoint lies inside the solid rectangle.
        for(target=0;target<3;target=target+1) for(mirror=0;mirror<2;mirror=mirror+1) begin
            setup((34+8*target)*256+(mirror ? 344 : -344),20*256-670,
                mirror ? -256 : 256,-320); #1;
            check(hit_events==(14'h0800<<target) &&
                corrected_x==(34+8*target)*256+(mirror ? 640 : -640) &&
                (mirror ? corrected_vx>0 : corrected_vx<0),
                "stand-up sweep catches a legal corner transit between outside endpoints");
            setup((34+8*target)*256+(mirror ? 344 : -344),20*256-730,
                mirror ? -256 : 256,-320); #1;
            check(hit_events==0 && corrected_x==proposed_x && corrected_y==proposed_y,
                "stand-up finite face sweep rejects the adjacent genuine near miss");
        end
        for(sling=0;sling<2;sling=sling+1) for(mirror=0;mirror<2;mirror=mirror+1) begin
            setup((sling ? 69 : 17)*256+(mirror ? -136 : 136),41*256-980,
                mirror ? -256 : 256,0); #1;
            check(hit_events==(14'h0200<<sling) && corrected_vy<0 &&
                (mirror ? corrected_vx>0 : corrected_vx<0),
                "diamond sling sweep catches a horizontal top-tip corner transit");
            setup((sling ? 69 : 17)*256+(mirror ? -136 : 136),41*256-1040,
                mirror ? -256 : 256,0); #1;
            check(hit_events==0 && corrected_x==proposed_x && corrected_y==proposed_y,
                "diamond sling sweep rejects a path above its finite top tip");
        end
        // Moving rectangles collide with every real face, not their old
        // fixed y band. Reflection uses surface-relative vertical velocity.
        for (target=0;target<2;target=target+1) begin
            setup((target ? 78 : 6)*256,37*256+2,0,0);
            if (target) begin side_right_next_y=33*256+4;side_right_velocity_y=4;end
            else begin side_left_next_y=33*256+4;side_left_velocity_y=4;end
            #1;
            check(hit_events==(14'h0008<<target) && corrected_vy==39 &&
                corrected_y==33*256+4+1152,
                "moving rectangle bottom sweeps a stationary ball in its velocity frame");
            setup((target ? 78 : 6)*256,29*256-2,0,0);
            if (target) begin side_right_next_y=33*256-4;side_right_velocity_y=-4;end
            else begin side_left_next_y=33*256-4;side_left_velocity_y=-4;end
            #1;
            check(hit_events==(14'h0008<<target) && corrected_vy==-39 &&
                corrected_y==33*256-4-1152,
                "moving rectangle top sweeps a stationary ball upward");
            setup((target ? 78 : 6)*256,37*256,0,20);
            if (target) begin side_right_next_y=33*256+4;side_right_velocity_y=4;end
            else begin side_left_next_y=33*256+4;side_left_velocity_y=4;end
            #1;
            check(hit_events==0 && corrected_vy==20,
                "a departing ball faster than the target does not rescore");
            setup((target ? 78 : 6)*256,29*256,0,112);
            if (target) begin side_right_previous_y=37*256;side_right_next_y=37*256;end
            else begin side_left_previous_y=37*256;side_left_next_y=37*256;end
            #1;
            check(hit_events==0 && corrected_y==proposed_y,
                "old side-target anchor is empty when the rectangle has moved");
            for (mirror=0;mirror<2;mirror=mirror+1) begin
                setup((target ? 78 : 6)*256+(mirror ? 344 : -344),33*256-1182,
                    mirror ? -256 : 256,-320);#1;
                check(hit_events==(14'h0008<<target) &&
                    corrected_x==(target ? 78 : 6)*256+(mirror ? 640 : -640) &&
                    (mirror ? corrected_vx>0 : corrected_vx<0),
                    "tall moving-target sweep catches adjacent-face corner transit");
                setup((target ? 78 : 6)*256+(mirror ? 344 : -344),33*256-1250,
                    mirror ? -256 : 256,-320);#1;
                check(hit_events==0 && corrected_x==proposed_x && corrected_y==proposed_y,
                    "tall moving-target finite sweep rejects a real corner near miss");
            end
            for (extreme=0;extreme<2;extreme=extreme+1) begin
                setup((target ? 76 : 8)*256,(extreme ? 37 : 29)*256,target ? 200 : -200,0);
                if (target) begin side_right_previous_y=(extreme ? 37 : 29)*256;
                    side_right_next_y=side_right_previous_y;end
                else begin side_left_previous_y=(extreme ? 37 : 29)*256;
                    side_left_next_y=side_left_previous_y;end
                #1;
                check(hit_events==(14'h0008<<target) &&
                    (target ? corrected_vx<0 : corrected_vx>0),
                    "side faces follow both moving track extrema");
            end
        end
        $display("PASS tb_collision (%0d checks)", checks);
        $finish;
    end
endmodule
