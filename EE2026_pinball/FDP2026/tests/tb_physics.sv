`timescale 1ns/1ps
module tb_physics;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1, tick = 0, active = 1, prepare = 0, launch = 0;
    reg [5:0] launch_power = 16;
    reg [1:0] difficulty = 1;
    reg two_ball_mode = 0;
    reg left_pressed = 0, right_pressed = 0, nudge = 0;
    wire [6:0] ball_x, ball2_x;
    wire [5:0] ball_y, ball2_y;
    wire [14:0] ball_x_fp, ball2_x_fp;
    wire [13:0] ball_y_fp, ball2_y_fp;
    wire [1:0] balls_visible;
    wire hit_ball;
    wire [13:0] moving_bumper_y_fp;
    wire [14:0] moving_bumper_x_fp;
    wire [13:0] side_left_y_fp, side_right_y_fp;
    wire [2:0] left_angle, right_angle;
    wire drained, in_lane;
    wire [13:0] hit_events;
    integer checks = 0, d, p, n, e, repeat_contact, descent_ticks, response_ticks;
    integer seed_x, seed_y, seed_vx, seed_vy;
    reg saw_drain;
    reg signed [15:0] saved_x, saved_y, saved_vx, saved_vy;
    reg [2:0] saved_angle;
    integer phase_y, phase_x, expected_y, expected_x, phase_side, expected_side;
    reg [13:0] saved_bumper_y, saved_side_left, saved_side_right;
    reg [14:0] saved_bumper_x;
    reg saved_bumper_y_direction, saved_bumper_x_direction;
    pinball_physics dut (.*);

    task check;
        input condition;
        input [511:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL physics: %0s d=%0d p=%0d n=%0d x=%0d y=%0d vx=%0d vy=%0d",
                    message, difficulty, launch_power, n,
                    dut.position_x, dut.position_y, dut.velocity_x, dut.velocity_y);
                $fatal(1);
                $finish;
            end
        end
    endtask

    task step;
        begin
            @(negedge clk); tick = 1;
            @(negedge clk); tick = 0;
            repeat (16) @(negedge clk);
            check(dut.velocity_x <= 256 && dut.velocity_x >= -256 &&
                  dut.velocity_y <= 160 && dut.velocity_y >= -320, "velocity cap");
            if (!in_lane && dut.position_y>=38*256)
                check(dut.velocity_y<=((difficulty==0)?48:((difficulty==1)?60:72)),"lower playfield profile descent cap");
            check(ball_x <= 95 && ball_y <= 63, "OLED coordinates bounded");
            check(moving_bumper_y_fp>=22*256 && moving_bumper_y_fp<=28*256 &&
                  moving_bumper_x_fp>=58*256 && moving_bumper_x_fp<=66*256,
                  "moving bumpers stay on their separated tracks");
            check(side_left_y_fp>=29*256 && side_left_y_fp<=37*256 &&
                side_right_y_fp>=29*256 && side_right_y_fp<=37*256,
                "side rectangles stay on disjoint vertical tracks");
        end
    endtask

    task prepare_ball;
        begin
            @(negedge clk); prepare = 1; launch = 0;
            @(negedge clk); prepare = 0;
            check(ball_x == 89 && ball_y == 56 && in_lane && !dut.launched,
                  "prepare restores stationary shooter ball");
            check(!dut.nudge_pending && !dut.collision_nudge,
                  "prepare clears queued and captured nudges");
            check(moving_bumper_y_fp==22*256 && moving_bumper_x_fp==58*256 &&
                dut.moving_bumper_y_positive && dut.moving_bumper_x_positive,
                "prepare resets both moving centres and directions");
            check(side_left_y_fp==33*256 && side_right_y_fp==33*256 &&
                dut.side_left_y_positive && !dut.side_right_y_positive && !dut.gravity_phase,
                "prepare resets side tracks and half-gravity phase");
        end
    endtask

    task pulse_nudge;
        begin
            @(negedge clk); nudge = 1;
            @(negedge clk); nudge = 0;
        end
    endtask

    task free_table_ball;
        input integer horizontal;
        input integer horizontal_speed;
        input integer vertical_speed;
        begin
            prepare_ball; shoot;
            @(negedge clk);
            dut.ball1_in_lane = 0;
            dut.position_x = horizontal*256; dut.position_y = 40*256;
            dut.velocity_x = horizontal_speed; dut.velocity_y = vertical_speed;
        end
    endtask

    task shoot;
        begin
            // Tick remains low for the entire launch pulse.
            @(negedge clk); launch = 1;
            @(negedge clk); launch = 0;
            check(dut.launched && dut.velocity_y < 0, "launch captured independently of tick");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        for (d = 0; d < 3; d = d + 1) begin
            difficulty = d;
            for (p = 0; p < 3; p = p + 1) begin
                launch_power = (p==0) ? 0 : ((p==1) ? 16 : 63);
                prepare_ball;
                shoot;
                n = 0;
                while (in_lane && n < 200) begin step; n = n + 1; end
                check(!in_lane, "minimum/light/full shots leave lane on all difficulties");
                saw_drain = 0;
                n = 0;
                while (!saw_drain && n < 7200) begin
                    step; n = n + 1;
                    if (drained) saw_drain = 1;
                    check(!in_lane, "launched ball never reenters shooter lane");
                end
                check(saw_drain, "uncontrolled shot eventually drains");
                step;
                check(!drained && !dut.launched, "drain is a one-cycle pulse and freezes ball");
            end
        end

        difficulty = 1; launch_power = 16;
        prepare_ball; shoot;
        repeat (10) step;
        saved_x = dut.position_x; saved_y = dut.position_y;
        saved_vx = dut.velocity_x; saved_vy = dut.velocity_y; saved_angle = left_angle;
        active = 0; left_pressed = 1;
        repeat (20) step;
        check(dut.position_x == saved_x && dut.position_y == saved_y &&
              dut.velocity_x == saved_vx && dut.velocity_y == saved_vy &&
              left_angle == saved_angle, "pause freezes ball and flipper state");
        active = 1;
        repeat (4) step;
        check(left_angle == 4, "flipper reaches raised angle in four ticks");
        left_pressed = 0;
        repeat (4) step;
        check(left_angle == 0, "flipper returns in four ticks");

        // Minimum-to-maximum charge reaches the lane exit on all three
        // profiles. A minimum shot must remain viable after reducing gravity.
        for(d=0;d<3;d=d+1) for(p=0;p<64;p=p+1) begin
            difficulty=d;launch_power=p;prepare_ball;shoot;n=0;
            while(in_lane && n<200) begin step;n=n+1;end
            check(!in_lane,"every launch power reaches table on each difficulty");
        end

        // Measure genuine accumulation in empty space: Easy 0/1 alternation,
        // Normal +1, Hard +2. A pause may not consume the half-gravity phase.
        for(d=0;d<3;d=d+1) begin
            difficulty=d;free_table_ball(70,0,0);
            @(negedge clk);dut.position_y=12*256;
            for(p=1;p<=20;p=p+1) begin
                step;
                check(dut.velocity_y==((d==0)?p/2:((d==1)?p:2*p)),
                    "gravity accumulates 0.5/1/2 Q8 per accepted world step");
            end
            active=0;saved_vy=dut.velocity_y;
            repeat(3)step;
            check(dut.velocity_y==saved_vy && !dut.gravity_phase,
                "pause freezes gravity accumulation and its phase");
            active=1;step;
            check(dut.velocity_y==saved_vy+((d==0)?0:((d==1)?1:2)),
                "resumed half-gravity phase continues without consuming paused ticks");
            @(negedge clk);dut.position_x=70*256;dut.position_y=12*256;
            dut.velocity_x=0;dut.velocity_y=300;step;
            check(dut.velocity_y==((d==0)?112:((d==1)?136:160)),
                "upper-playfield descent cap follows the selected difficulty");
        end
        // The result cap is part of the same transaction as its proposal.
        // A menu-level input changing mid-window cannot alter this batch.
        difficulty=1;free_table_ball(70,0,300);
        @(negedge clk);dut.position_y=12*256;tick=1;
        @(negedge clk);tick=0;difficulty=2;
        repeat(16)@(negedge clk);
        check(dut.velocity_y==136 && dut.batch_difficulty==1,
            "outstanding batch preserves the accepted difficulty's result cap");
        difficulty=1;launch_power=16;

        // Controlled geometric contact verifies score rearm, independently
        // of the repeatable launcher trajectory used above.
        prepare_ball; shoot;
        @(negedge clk);
        dut.ball1_in_lane = 0;
        dut.position_x = 26*256; dut.position_y = moving_bumper_y_fp-1152;
        dut.velocity_x = 0; dut.velocity_y = 300;
        step;
        check(hit_events == 5'b00001 && !dut.hit_armed[0], "bumper event disarms score");
        @(negedge clk);
        dut.position_x = 26*256; dut.position_y = moving_bumper_y_fp-1152;
        dut.velocity_x = 0; dut.velocity_y = 300;
        step;
        check(hit_events == 0, "same bumper contact cannot score during cooldown");
        @(negedge clk);
        dut.position_x = 70*256; dut.position_y = 12*256;
        dut.velocity_x = 0; dut.velocity_y = 0;
        repeat (20) step;
        check(dut.hit_armed[0], "score rearms after cooldown and leaving bumper");
        @(negedge clk);
        dut.position_x = 26*256; dut.position_y = moving_bumper_y_fp-1152;
        dut.velocity_x = 0; dut.velocity_y = 300;
        step;
        check(hit_events == 5'b00001, "new approach to rearmed bumper scores");

        difficulty = 1; left_pressed = 0;
        prepare_ball; shoot;
        saved_x = dut.position_x; saved_y = dut.position_y;
        @(negedge clk); tick = 1;
        @(negedge clk); tick = 0;
        check(dut.collision_busy && dut.collision_velocity_y == -303,
              "tick snapshots proposed motion before calculation window");
        difficulty = 2; left_pressed = 1;
        repeat (15) begin
            @(negedge clk);
            check(dut.position_x == saved_x && dut.position_y == saved_y &&
                  dut.collision_busy, "result does not commit before16 system clocks");
            check(dut.collision_velocity_y == -303 && !dut.collision_left_pressed,
                  "difficulty and buttons cannot change outstanding snapshot");
        end
        @(negedge clk);
        check(!dut.collision_busy && dut.position_y == saved_y - 303,
              "snapshot result commits on the16th clock");

        prepare_ball; shoot;
        @(negedge clk); tick = 1;
        @(negedge clk); tick = 0;
        check(dut.collision_busy, "calculation begins before cancellation");
        @(negedge clk); prepare = 1;
        @(negedge clk); prepare = 0;
        repeat (20) @(negedge clk);
        check(!dut.collision_busy && !dut.launched && ball_x == 89 && ball_y == 56,
              "prepare cancels outstanding calculation without stale commit");

        // The large-screen ball gets the genuine fraction, not a repeated
        // coarse OLED position. Display coordinates also saturate at both ends.
        @(negedge clk);
        dut.position_x = 39*256+128; dut.position_y = 43*256+128;
        #1;
        check(ball_x==39 && ball_y==43 && ball_x_fp==10112 && ball_y_fp==11136,
              "native outputs retain half-pixel motion");
        @(negedge clk); dut.position_x=-1; dut.position_y=-1; #1;
        check(ball_x==0 && ball_y==0 && ball_x_fp==0 && ball_y_fp==0,
              "negative native and OLED outputs saturate at zero");
        @(negedge clk); dut.position_x=95*256+128; dut.position_y=63*256+128; #1;
        check(ball_x==95 && ball_y==63 && ball_x_fp==24320 && ball_y_fp==16128,
              "native and OLED coordinates saturate without wrapping");

        difficulty=1; launch_power=16; left_pressed=0; right_pressed=0;
        prepare_ball; shoot;
        pulse_nudge;
        check(!dut.nudge_pending, "nudge cannot queue in shooter lane");
        step;
        check(!dut.collision_nudge && dut.velocity_x==0 && dut.velocity_y==-303,
              "lane launch trajectory ignores nudge");

        free_table_ball(20,0,0);
        active=0;
        pulse_nudge;
        check(!dut.nudge_pending, "inactive nudge cannot queue");
        step;
        check(dut.position_x==5120 && dut.position_y==10240 &&
              dut.velocity_x==0 && dut.velocity_y==0 && !dut.collision_busy,
              "inactive tick and nudge leave table motion frozen");
        active=1; step;
        check(dut.velocity_x==0 && dut.velocity_y==1,
              "resume has no deferred inactive nudge");

        free_table_ball(20,0,0);
        pulse_nudge;
        check(dut.nudge_pending, "off-tick nudge queues until next physics tick");
        step;
        check(dut.velocity_x==48 && dut.velocity_y==-79 && !dut.nudge_pending,
              "left-table nudge gives upward and inward impulse once");
        step;
        check(dut.velocity_x==48 && dut.velocity_y==-78,
              "one pulse cannot produce an additional impulse next tick");
        free_table_ball(60,0,0);
        pulse_nudge; step;
        check(dut.velocity_x==-48 && dut.velocity_y==-79,
              "right-table nudge points inward toward table center");
        free_table_ball(20,256,-320);
        pulse_nudge; step;
        check(dut.velocity_x==256 && dut.velocity_y==-320,
              "nudge respects maximum upward and rightward speed");
        free_table_ball(60,-256,-320);
        pulse_nudge; step;
        check(dut.velocity_x==-256 && dut.velocity_y==-320,
              "nudge respects maximum leftward speed");

        // A nudge received after a calculation begins is held for the next
        // calculation. It must not disturb any multi-cycle collision operand.
        free_table_ball(20,0,0);
        @(negedge clk); tick=1;
        @(negedge clk); tick=0;
        check(dut.collision_busy && !dut.collision_nudge,
              "ordinary transaction starts with isolated nudge inactive");
        nudge=1;
        @(negedge clk); nudge=0;
        check(dut.nudge_pending, "busy transaction queues a later nudge");
        repeat(14) begin
            @(negedge clk);
            check(dut.collision_busy && !dut.collision_nudge &&
                  dut.collision_velocity_x==0 && dut.collision_velocity_y==1 &&
                  dut.collision_proposed_x==5120 && dut.collision_proposed_y==10241,
                  "queued nudge cannot change isolated collision inputs");
        end
        @(negedge clk);
        check(!dut.collision_busy && dut.velocity_x==0 && dut.velocity_y==1,
              "outstanding ordinary transaction commits without late nudge");
        step;
        check(dut.velocity_x==48 && dut.velocity_y==-78 && !dut.nudge_pending,
              "queued late nudge applies to following calculation");

        // Preparing or resetting while a nudge is pending cancels it entirely.
        free_table_ball(20,0,0);
        pulse_nudge;
        prepare_ball;
        shoot;
        @(negedge clk); dut.ball1_in_lane=0;
        dut.position_x=5120; dut.position_y=10240;
        dut.velocity_x=0; dut.velocity_y=0;
        step;
        check(dut.velocity_x==0 && dut.velocity_y==1 && !dut.collision_nudge,
              "prepare cancellation cannot leak nudge into next ball");
        pulse_nudge;
        @(negedge clk); tick=1;
        @(negedge clk); tick=0;
        check(dut.collision_busy && dut.collision_nudge,
              "nudge is captured before reset cancellation");
        @(negedge clk); reset=1;
        @(negedge clk); reset=0;
        repeat(20) @(negedge clk);
        check(!dut.nudge_pending && !dut.collision_nudge && !dut.collision_busy &&
              ball_x_fp==22784 && ball_y_fp==14336 && !dut.launched,
              "reset cancels queued and outstanding nudge with no stale commit");

        // Every newly added object has its own one-shot gate. Staying in a
        // sensor longer than its cooldown cannot repeatedly award points;
        // leaving, waiting, and approaching again restores exactly one hit.
        difficulty=1; left_pressed=0; right_pressed=0;
        for(e=5;e<14;e=e+1) begin
            case(e)
                5: begin seed_x=25*256; seed_y=14*256; seed_vx=0; seed_vy=0; end
                6: begin seed_x=42*256; seed_y=14*256; seed_vx=0; seed_vy=0; end
                7: begin seed_x=59*256; seed_y=14*256; seed_vx=0; seed_vy=0; end
                8: begin seed_x=42*256; seed_y=27*256; seed_vx=0; seed_vy=0; end
                9: begin seed_x=17*256; seed_y=37*256; seed_vx=0; seed_vy=76; end
                10: begin seed_x=69*256; seed_y=37*256; seed_vx=0; seed_vy=76; end
                11: begin seed_x=34*256; seed_y=18*256-64; seed_vx=0; seed_vy=76; end
                12: begin seed_x=42*256; seed_y=18*256-64; seed_vx=0; seed_vy=76; end
                default: begin seed_x=50*256; seed_y=18*256-64; seed_vx=0; seed_vy=76; end
            endcase
            prepare_ball; shoot;
            @(negedge clk);
            dut.ball1_in_lane=0; dut.position_x=seed_x; dut.position_y=seed_y;
            dut.velocity_x=seed_vx; dut.velocity_y=seed_vy;
            step;
            check(hit_events==(14'b1<<e) && !dut.hit_armed[e],
                "new object awards exactly its event bit and disarms");
            for(repeat_contact=0;repeat_contact<22;repeat_contact=repeat_contact+1) begin
                @(negedge clk);
                dut.position_x=seed_x; dut.position_y=seed_y;
                dut.velocity_x=seed_vx; dut.velocity_y=seed_vy;
                step;
                check(hit_events==0 && !dut.hit_armed[e],
                    "contact does not reaward even after cooldown expires");
            end
            @(negedge clk);
            dut.position_x=70*256; dut.position_y=12*256;
            dut.velocity_x=0; dut.velocity_y=0;
            repeat(20) step;
            check(dut.hit_armed[e],"new object rearms after leaving its envelope");
            @(negedge clk);
            dut.position_x=seed_x; dut.position_y=seed_y;
            dut.velocity_x=seed_vx; dut.velocity_y=seed_vy;
            step;
            check(hit_events==(14'b1<<e),"reentered new object awards one fresh event");
        end

        // On the open central approach, a ball entering y=38 at any speed
        // needs 80/64/54 physics ticks (333/267/225 ms) to reach y=53. This checks
        // the actual integrated path rather than only the clamp constant.
        for(d=0;d<3;d=d+1) begin
            difficulty=d;
            free_table_ball(45,0,320);
            @(negedge clk); dut.position_y=38*256;
            descent_ticks=0;
            while(dut.position_y<53*256 && descent_ticks<100) begin
                step; descent_ticks=descent_ticks+1;
            end
            check(dut.position_y>=53*256 && descent_ticks==((d==0)?80:((d==1)?64:54)),
                "difficulty profiles grant 333/267/225 ms reaction approaches");
        end

        // Pressing a flipper underneath a descending ball reaches it within
        // the same four-tick stroke. Holding an already raised flipper has a
        // distinctly weaker return, so deliberate timing remains rewarding.
        difficulty=1;
        free_table_ball(34,0,76);
        @(negedge clk); dut.position_y=52*256+205; left_pressed=1;
        response_ticks=0;
        while(dut.velocity_y>=0 && response_ticks<4) begin
            step; response_ticks=response_ticks+1;
        end
        check(dut.velocity_y<=-288 && response_ticks<=4,
            "press stroke returns falling ball strongly within 16.7 ms");
        left_pressed=0;
        free_table_ball(34,0,76);
        @(negedge clk); dut.position_y=48*256+128; dut.left_angle=4; left_pressed=1;
        step;
        check(dut.velocity_y<-128 && dut.velocity_y>-220,
            "held flipper return is weaker than well timed moving stroke");
        left_pressed=0;
        free_table_ball(52,0,76);
        @(negedge clk); dut.position_y=52*256+205; right_pressed=1;
        response_ticks=0;
        while(dut.velocity_y>=0 && response_ticks<4) begin
            step; response_ticks=response_ticks+1;
        end
        check(dut.velocity_y<=-288 && dut.velocity_x<0 && response_ticks<=4,
            "right flipper mirrors quick press edge return");
        right_pressed=0;

        // Exercise the complete common period: four vertical cycles and
        // three horizontal cycles at exactly four Q8 units per accepted tick.
        // Keep a test ball in a clear area so motion checks do not depend on
        // contacts or a drain interrupting a cycle.
        difficulty=1; active=1; prepare_ball; shoot;
        for(n=1;n<=3072;n=n+1) begin
            @(negedge clk);
            dut.ball1_in_lane=0; dut.position_x=70*256; dut.position_y=12*256;
            dut.velocity_x=0; dut.velocity_y=0;
            saved_bumper_y=moving_bumper_y_fp; saved_bumper_x=moving_bumper_x_fp;
            step;
            phase_y=n%768; phase_x=n%1024;
            phase_side=(n+256)%1024;
            expected_side=(phase_side<=512) ? 29*256+4*phase_side :
                37*256-4*(phase_side-512);
            check(side_left_y_fp==expected_side && side_right_y_fp==66*256-expected_side,
                "side targets traverse opposed full triangle cycles once per world step");
            check(dut.side_left_y_positive==(phase_side<512) &&
                dut.side_right_y_positive==(phase_side>=512),
                "side directions reverse only at each inclusive endpoint");
            expected_y=(phase_y<=384) ? 22*256+4*phase_y : 28*256-4*(phase_y-384);
            expected_x=(phase_x<=512) ? 58*256+4*phase_x : 66*256-4*(phase_x-512);
            check(moving_bumper_y_fp==expected_y && moving_bumper_x_fp==expected_x,
                "both tracks follow full repeatable triangle cycles");
            check($signed({1'b0,moving_bumper_y_fp})-$signed({1'b0,saved_bumper_y})==4 ||
                $signed({1'b0,moving_bumper_y_fp})-$signed({1'b0,saved_bumper_y})==-4,
                "vertical centre moves exactly 1/64 pixel per accepted tick");
            check($signed({1'b0,moving_bumper_x_fp})-$signed({1'b0,saved_bumper_x})==4 ||
                $signed({1'b0,moving_bumper_x_fp})-$signed({1'b0,saved_bumper_x})==-4,
                "horizontal centre moves exactly 1/64 pixel per accepted tick");
            check(dut.moving_bumper_y_positive==(phase_y<384) &&
                dut.moving_bumper_x_positive==(phase_x<512),
                "directions reverse only at the inclusive extrema");
        end

        prepare_ball;
        repeat(20) step;
        check(moving_bumper_y_fp==22*256 && moving_bumper_x_fp==58*256,
            "READY ticks cannot move unlaunched bumpers");
        check(side_left_y_fp==33*256 && side_right_y_fp==33*256,
            "READY ticks cannot move the side rectangles");
        shoot; step;
        saved_bumper_y=moving_bumper_y_fp; saved_bumper_x=moving_bumper_x_fp;
        saved_bumper_y_direction=dut.moving_bumper_y_positive;
        saved_bumper_x_direction=dut.moving_bumper_x_positive;
        saved_side_left=side_left_y_fp;saved_side_right=side_right_y_fp;
        active=0;
        repeat(20) step;
        check(side_left_y_fp==saved_side_left && side_right_y_fp==saved_side_right,
            "pause freezes both side rectangles");
        check(moving_bumper_y_fp==saved_bumper_y && moving_bumper_x_fp==saved_bumper_x &&
            dut.moving_bumper_y_positive==saved_bumper_y_direction &&
            dut.moving_bumper_x_positive==saved_bumper_x_direction,
            "pause freezes moving bumper centres and directions");
        active=1; step;
        check(moving_bumper_y_fp==saved_bumper_y+4 && moving_bumper_x_fp==saved_bumper_x+4,
            "resuming advances each track by one ordinary step");

        // Positions and directions are genuine multi-cycle operands. A
        // pause after acceptance may complete that transaction, then freezes.
        prepare_ball; shoot;
        saved_x=dut.position_x; saved_y=dut.position_y;
        @(negedge clk); tick=1;
        @(negedge clk); tick=0; active=0;
        check(dut.collision_moving_bumper_previous_y==22*256 &&
            dut.collision_moving_bumper_next_y==22*256+4 &&
            dut.collision_moving_bumper_velocity_y==4 &&
            dut.collision_moving_bumper_previous_x==58*256 &&
            dut.collision_moving_bumper_next_x==58*256+4 &&
            dut.collision_moving_bumper_velocity_x==4,
            "transaction captures old/new centres and their actual displacement");
        check(dut.collision_side_left_previous_y==33*256 &&
            dut.collision_side_left_next_y==33*256+4 && dut.collision_side_left_velocity_y==4 &&
            dut.collision_side_right_previous_y==33*256 &&
            dut.collision_side_right_next_y==33*256-4 && dut.collision_side_right_velocity_y==-4,
            "side snapshots isolate both old/new centres and opposite velocities");
        repeat(15) begin
            @(negedge clk);
            check(dut.collision_busy && dut.position_x==saved_x && dut.position_y==saved_y &&
                moving_bumper_y_fp==22*256 && moving_bumper_x_fp==58*256,
                "ball and moving centres cannot commit before the 16th clock");
            check(dut.collision_moving_bumper_next_y==22*256+4 &&
                dut.collision_moving_bumper_next_x==58*256+4 &&
                dut.collision_moving_bumper_y_positive &&
                dut.collision_moving_bumper_x_positive,
                "pause cannot alter isolated next centres or directions");
        end
        @(negedge clk);
        check(!dut.collision_busy && dut.position_y==saved_y-303 &&
            moving_bumper_y_fp==22*256+4 && moving_bumper_x_fp==58*256+4,
            "accepted ball and moving centres commit atomically while paused");
        check(side_left_y_fp==33*256+4 && side_right_y_fp==33*256-4,
            "side targets commit with accepted ball even when pause arrives mid-window");
        repeat(8) step;
        check(moving_bumper_y_fp==22*256+4 && moving_bumper_x_fp==58*256+4,
            "paused ticks cannot queue another moving transaction");

        active=1; prepare_ball; shoot;
        @(negedge clk); tick=1;
        @(negedge clk); tick=0;
        @(negedge clk); prepare=1;
        @(negedge clk); prepare=0;
        repeat(20) @(negedge clk);
        check(!dut.collision_busy && !dut.launched && moving_bumper_y_fp==22*256 &&
            moving_bumper_x_fp==58*256 && dut.moving_bumper_y_positive &&
            dut.moving_bumper_x_positive,
            "prepare cancels moving transaction without a stale centre update");
        check(side_left_y_fp==33*256 && side_right_y_fp==33*256 && !dut.gravity_phase,
            "prepare cancels side updates and resets gravity phase");
        shoot; step;
        @(negedge clk); tick=1;
        @(negedge clk); tick=0;
        @(negedge clk); reset=1;
        @(negedge clk); reset=0;
        repeat(20) @(negedge clk);
        check(!dut.collision_busy && !dut.launched && moving_bumper_y_fp==22*256 &&
            moving_bumper_x_fp==58*256 && dut.moving_bumper_y_positive &&
            dut.moving_bumper_x_positive,
            "reset cancels motion and restores initial centres and directions");
        check(side_left_y_fp==33*256 && side_right_y_fp==33*256 && !dut.gravity_phase,
            "reset cancels side updates and resets gravity phase");

        // Slow moving surfaces must interact with a resting ball using
        // relative velocity, and score no more than once while touching.
        prepare_ball; shoot;
        @(negedge clk);
        dut.ball1_in_lane=0; dut.position_x=26*256; dut.position_y=26*256+2;
        dut.velocity_x=0; dut.velocity_y=0;
        step;
        check(hit_events==14'h0001 && dut.velocity_y==136 &&
            dut.position_y==moving_bumper_y_fp+1152 && !dut.hit_armed[0],
            "downward surface pushes resting ball, bounds speed and scores once");
        for(repeat_contact=0;repeat_contact<22;repeat_contact=repeat_contact+1) begin
            @(negedge clk);
            dut.position_x=26*256; dut.position_y=moving_bumper_y_fp+1026;
            dut.velocity_x=0; dut.velocity_y=0;
            step;
            check(!hit_events[0] && !dut.hit_armed[0],
                "moving contact cannot repeatedly score after cooldown expiry");
        end
        prepare_ball; shoot;
        @(negedge clk);
        dut.ball1_in_lane=0; dut.position_x=62*256+2; dut.position_y=22*256;
        dut.velocity_x=0; dut.velocity_y=0;
        step;
        check(hit_events==14'h0002 && dut.velocity_x==164 &&
            dut.position_x==moving_bumper_x_fp+1152,
            "horizontal surface gives resting ball an outward bounded return");

        // Rearming is measured from the current centre, not its old static
        // anchor. These balls are near the old anchor but leave the live one.
        prepare_ball; shoot;
        @(negedge clk);
        dut.ball1_in_lane=0; dut.position_x=26*256; dut.position_y=21*256;
        dut.velocity_x=0; dut.velocity_y=0;
        dut.moving_bumper_y_fp=28*256; dut.moving_bumper_y_positive=0;
        dut.hit_armed[0]=0; dut.cooldown[0]=0;
        step;
        check(dut.hit_armed[0] && !hit_events[0],
            "vertical score hysteresis follows the live centre");
        @(negedge clk);
        dut.position_x=59*256; dut.position_y=22*256;
        dut.velocity_x=0; dut.velocity_y=0;
        dut.moving_bumper_x_fp=66*256; dut.moving_bumper_x_positive=0;
        dut.hit_armed[1]=0; dut.cooldown[1]=0;
        step;
        check(dut.hit_armed[1] && !hit_events[1],
            "horizontal score hysteresis follows the live centre");

        prepare_ball; shoot;
        @(negedge clk);
        dut.ball1_in_lane=0; dut.position_x=43*256; dut.position_y=64*256;
        dut.velocity_x=0; dut.velocity_y=76;
        step;
        check(drained && !dut.launched,"controlled drain completes moving transaction");
        saved_bumper_y=moving_bumper_y_fp; saved_bumper_x=moving_bumper_x_fp;
        repeat(8) step;
        check(moving_bumper_y_fp==saved_bumper_y && moving_bumper_x_fp==saved_bumper_x,
            "game-over/drained ball cannot continue moving tracks");

        // Each moving side rectangle keeps independent contact hysteresis.
        // Holding contact past the cooldown cannot repeat; exit then reentry
        // creates exactly one new award at the CURRENT moving y coordinate.
        difficulty=1;
        for(e=3;e<=4;e=e+1) begin
            prepare_ball;shoot;
            for(repeat_contact=0;repeat_contact<23;repeat_contact=repeat_contact+1) begin
                @(negedge clk);dut.ball1_in_lane=0;
                dut.position_x=((e==3)?8:76)*256;
                dut.position_y=(e==3)?side_left_y_fp:side_right_y_fp;
                dut.velocity_x=(e==3)?-200:200;dut.velocity_y=0;step;
                check(hit_events==((repeat_contact==0)?(14'b1<<e):14'd0) && !dut.hit_armed[e],
                    "moving side contact awards once despite long contact and expired cooldown");
            end
            @(negedge clk);dut.position_x=43*256;dut.position_y=44*256;
            dut.velocity_x=0;dut.velocity_y=0;repeat(20)step;
            check(dut.hit_armed[e],"moving side target rearms after ball leaves its live envelope");
            @(negedge clk);dut.position_x=((e==3)?8:76)*256;
            dut.position_y=(e==3)?side_left_y_fp:side_right_y_fp;
            dut.velocity_x=(e==3)?-200:200;dut.velocity_y=0;step;
            check(hit_events==(14'b1<<e),"new side approach scores exactly its original event bit");
            @(negedge clk);dut.hit_armed[e]=0;dut.cooldown[e]=0;
            if(e==3)begin dut.side_left_y_fp=37*256;dut.side_left_y_positive=0;end
            else begin dut.side_right_y_fp=37*256;dut.side_right_y_positive=0;end
            dut.position_x=((e==3)?6:78)*256;dut.position_y=30*256;
            dut.velocity_x=0;dut.velocity_y=0;step;
            check(dut.hit_armed[e] && !hit_events[e],
                "side hysteresis follows moved centre rather than obsolete fixed anchor");
        end

        $display("PASS tb_physics (%0d checks)", checks);
        $finish;
    end
endmodule
