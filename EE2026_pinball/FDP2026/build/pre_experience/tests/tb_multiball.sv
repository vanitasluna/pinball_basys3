`timescale 1ns/1ps
module tb_multiball;
    reg clk=0; always #5 clk=!clk;
    reg reset=1, tick=0, active=1, prepare=0, launch=0, two_ball_mode=1;
    reg [5:0] launch_power=16;
    reg [1:0] difficulty=0;
    reg left_pressed=0, right_pressed=0, nudge=0;
    wire [6:0] ball_x,ball2_x;
    wire [5:0] ball_y,ball2_y;
    wire [14:0] ball_x_fp,ball2_x_fp,moving_bumper_x_fp;
    wire [13:0] ball_y_fp,ball2_y_fp,moving_bumper_y_fp,hit_events;
    wire [1:0] balls_visible;
    wire [2:0] left_angle,right_angle;
    wire drained,in_lane,hit_ball;
    integer checks=0,clock_count=0,event0=0,event1=0,drains=0;
    integer last_event0=-100,last_event1=-100,d,p,n,before0,before1,before_drain;
    reg [13:0] event_mask0,event_mask1;
    reg signed [15:0] saved_x,saved_y,saved2_x,saved2_y;
    reg [13:0] saved_world_y;
    reg [14:0] saved_world_x;
    pinball_physics dut(.*);
    always @(posedge clk) begin
        clock_count=clock_count+1;
        if(!reset) begin
            if(hit_events!=0) begin
                if(hit_ball) begin event1=event1+1;last_event1=clock_count;event_mask1=hit_events;end
                else begin event0=event0+1;last_event0=clock_count;event_mask0=hit_events;end
            end
            if(drained) drains=drains+1;
        end
    end
    task check(input condition,input [639:0] message);
        begin
            checks=checks+1;
            if(!condition) begin
                $display("FAIL multiball: %0s t=%0t first=(%0d,%0d) second=(%0d,%0d) visible=%b",message,$time,
                    dut.position_x,dut.position_y,dut.position2_x,dut.position2_y,balls_visible);
                $fatal(1);$finish;
            end
        end
    endtask
    task cycle; begin @(posedge clk); #1;end endtask
    task prepare_pair;
        begin
            @(negedge clk);prepare=1;cycle;
            @(negedge clk);prepare=0;cycle;
            check(balls_visible==(two_ball_mode?2'b11:2'b01) &&
                ball_x==89 && ball_y==56 && ball2_x==89 && ball2_y==60 && in_lane,
                "prepare shows the selected pair at separated shooter positions");
            check(!dut.collision_busy && !dut.launched && !dut.launched2 &&
                dut.pending_hit_wait==0 && dut.pending_drain_wait==0,
                "prepare clears both shots, calculation and pending event flush");
        end
    endtask
    task shoot;
        begin
            @(negedge clk);launch=1;cycle;
            check(dut.launched && (dut.launched2==two_ball_mode) &&
                $signed(dut.velocity_y)==-288-$signed({1'b0,launch_power}) &&
                (!two_ball_mode || dut.velocity2_y==dut.velocity_y),
                "one off-tick launch pulse shoots both with the captured strength");
            @(negedge clk);launch=0;cycle;
        end
    endtask
    task step;
        begin
            @(negedge clk);tick=1;cycle;
            @(negedge clk);tick=0;
            repeat(41) cycle;
            check(ball_x<=95 && ball_y<=63 && ball2_x<=95 && ball2_y<=63,
                "both exported coordinate pairs stay bounded");
            check(dut.velocity_x>=-256 && dut.velocity_x<=256 &&
                dut.velocity2_x>=-256 && dut.velocity2_x<=256 &&
                dut.velocity_y>=-320 && dut.velocity_y<=160 &&
                dut.velocity2_y>=-320 && dut.velocity2_y<=160,
                "shared clamps independently bound both velocities");
        end
    endtask
    task place_both_on_bumper;
        begin
            @(negedge clk);
            dut.ball1_in_lane=0;dut.ball2_in_lane=0;
            dut.position_x=26*256;dut.position_y=26*256+2;
            dut.position2_x=26*256;dut.position2_y=26*256+2;
            dut.velocity_x=0;dut.velocity_y=0;dut.velocity2_x=0;dut.velocity2_y=0;
        end
    endtask
    initial begin
        repeat(3) cycle; @(negedge clk);reset=0;
        prepare_pair;shoot;
        saved_x=dut.position_x;saved_y=dut.position_y;
        saved2_x=dut.position2_x;saved2_y=dut.position2_y;
        left_pressed=1;
        @(negedge clk);tick=1;cycle;
        @(negedge clk);tick=0;active=0;
        for(n=1;n<33;n=n+1) begin
            cycle;
            check(dut.collision_busy && dut.position_x==saved_x && dut.position_y==saved_y &&
                dut.position2_x==saved2_x && dut.position2_y==saved2_y &&
                moving_bumper_y_fp==22*256 && moving_bumper_x_fp==58*256,
                "neither ball nor moving centre commits before the complete two-ball batch");
            check(dut.collision_moving_bumper_next_y==22*256+4 &&
                dut.collision_moving_bumper_next_x==58*256+4,
                "both calculations retain the same next world geometry during pause");
        end
        cycle;
        check(!dut.collision_busy && dut.position_y==saved_y-303 &&
            dut.position2_y==saved2_y-303 && moving_bumper_y_fp==22*256+4 &&
            moving_bumper_x_fp==58*256+4 && left_angle==1,
            "accepted pair commits atomically after 33 clocks and advances world/flipper once");
        saved_y=dut.position_y;saved2_y=dut.position2_y;
        repeat(4) step;
        check(dut.position_y==saved_y && dut.position2_y==saved2_y &&
            moving_bumper_y_fp==22*256+4 && left_angle==1,
            "paused ticks cannot queue either ball or world movement");
        active=1;left_pressed=0;

        // All existing launch strengths and difficulties must clear both
        // lanes; the second starts four pixels lower, without a second shot.
        for(d=0;d<3;d=d+1) for(p=0;p<3;p=p+1) begin
            difficulty=d;launch_power=(p==0)?0:((p==1)?16:63);
            prepare_pair;shoot;
            for(n=0;n<180 && (dut.ball1_in_lane || dut.ball2_in_lane);n=n+1) step;
            step;
            check(!dut.ball1_in_lane && !dut.ball2_in_lane && !in_lane &&
                balls_visible==2'b11 && ball_x<89 && ball2_x<89,
                "minimum/light/full shared shots both clear the lane on every difficulty");
            check(dut.position_x!=dut.position2_x || dut.position_y!=dut.position2_y,
                "different start heights and leftward exit spread separate trajectories");
            before_drain=drains;
            for(n=0;n<7200 && balls_visible!=0;n=n+1) begin
                step;
                check((!dut.launched || !dut.ball1_in_lane) &&
                    (!dut.launched2 || !dut.ball2_in_lane),
                    "free-running launched balls cannot return to a shooter lane");
            end
            check(balls_visible==0 && drains==before_drain+1,
                "every difficulty/strength pair naturally drains both uncontrolled balls once");
            step;check(drains==before_drain+1 && !dut.launched && !dut.launched2,
                "uncontrolled completed round remains frozen without a repeated drain");
        end
        difficulty=0;launch_power=16;
        prepare_pair;shoot;place_both_on_bumper;
        before0=event0;before1=event1;step;
        check(event0==before0+1 && event1==before1+1 && event_mask0==14'h1 &&
            event_mask1==14'h1 && last_event1-last_event0==4,
            "both balls independently award the same bumper as separate spaced pulses");
        check(!dut.hit_armed[0] && !dut.hit_armed2[0] && dut.cooldown[0]==16 &&
            dut.cooldown2[0]==16,"each ball owns its contact arming and cooldown");
        for(n=0;n<22;n=n+1) begin
            @(negedge clk);
            dut.position_x=26*256;dut.position_y=moving_bumper_y_fp+1026;
            dut.position2_x=26*256;dut.position2_y=moving_bumper_y_fp+1026;
            dut.velocity_x=0;dut.velocity_y=0;dut.velocity2_x=0;dut.velocity2_y=0;
            step;
        end
        check(event0==before0+1 && event1==before1+1 && !dut.hit_armed[0] &&
            !dut.hit_armed2[0],"long simultaneous contact cannot repeatedly score either ball");
        @(negedge clk);dut.position_x=20*256;dut.position_y=40*256;
        dut.velocity_x=0;dut.velocity_y=0;step;
        check(dut.hit_armed[0] && !dut.hit_armed2[0],"one ball leaving rearms only that ball");
        @(negedge clk);dut.position_x=26*256;dut.position_y=moving_bumper_y_fp+1026;
        dut.velocity_x=0;dut.velocity_y=0;step;
        check(event0==before0+2 && event1==before1+1,
            "reentry scores the rearmed ball without re-awarding its touching partner");

        // First-ball and second-ball drains are symmetric and a surviving
        // ball continues with the same shared 16-clock engine.
        for(p=0;p<2;p=p+1) begin
            prepare_pair;shoot;
            @(negedge clk);dut.ball1_in_lane=0;dut.ball2_in_lane=0;
            dut.position_x=(p==0)?43*256:20*256;dut.position_y=(p==0)?64*256:40*256;
            dut.position2_x=(p==1)?43*256:20*256;dut.position2_y=(p==1)?64*256:40*256;
            dut.velocity_x=0;dut.velocity_y=76;dut.velocity2_x=0;dut.velocity2_y=76;
            before_drain=drains;step;
            check(balls_visible==((p==0)?2'b10:2'b01) && drains==before_drain && !in_lane,
                "draining either ball hides it without ending the remaining ball's play");
            saved_y=(p==0)?dut.position2_y:dut.position_y;step;
            check(((p==0)?dut.position2_y:dut.position_y)>saved_y && drains==before_drain,
                "one remaining ball keeps moving with no spurious whole-round drain");
            @(negedge clk);
            if(p==0) begin dut.position2_x=43*256;dut.position2_y=64*256;dut.velocity2_y=76;end
            else begin dut.position_x=43*256;dut.position_y=64*256;dut.velocity_y=76;end
            step;
            check(balls_visible==0 && drains==before_drain+1 && !dut.launched && !dut.launched2,
                "the last live ball emits one round drain and freezes both");
            saved_world_y=moving_bumper_y_fp;saved_world_x=moving_bumper_x_fp;
            repeat(3) step;
            check(drains==before_drain+1 && moving_bumper_y_fp==saved_world_y &&
                moving_bumper_x_fp==saved_world_x,"finished round cannot emit repeated drains or advance world");
        end
        prepare_pair;shoot;
        @(negedge clk);dut.ball1_in_lane=0;dut.ball2_in_lane=0;
        dut.position_x=43*256;dut.position_y=64*256;dut.position2_x=43*256;dut.position2_y=64*256;
        dut.velocity_x=0;dut.velocity_y=76;dut.velocity2_x=0;dut.velocity2_y=76;
        force dut.contact_events=14'h1;
        before0=event0;before1=event1;before_drain=drains;
        @(negedge clk);tick=1;cycle;@(negedge clk);tick=0;
        repeat(33) cycle;
        check(balls_visible==0 && !drained && drains==before_drain,
            "simultaneous final drain waits for the deferred second contact pulse");
        repeat(5) cycle;
        check(event0==before0+1 && event1==before1+1 && drains==before_drain,
            "both last-step event pulses are observable before final drain");
        repeat(2) cycle;release dut.contact_events;
        check(drains==before_drain+1,"last-step event flush precedes exactly one drain");

        // A queued nudge is captured once per world step and affects both
        // balls symmetrically according to their own side of the table.
        prepare_pair;shoot;
        @(negedge clk);dut.ball1_in_lane=0;dut.ball2_in_lane=0;
        dut.position_x=20*256;dut.position_y=40*256;dut.position2_x=66*256;dut.position2_y=40*256;
        dut.velocity_x=0;dut.velocity_y=0;dut.velocity2_x=0;dut.velocity2_y=0;
        nudge=1;cycle;@(negedge clk);nudge=0;step;
        check(dut.velocity_x==48 && dut.velocity2_x==-48 && dut.velocity_y==-79 &&
            dut.velocity2_y==-79 && !dut.nudge_pending,
            "one queued nudge reaches both outside-lane balls exactly once");
        step;check(dut.velocity_y==-78 && dut.velocity2_y==-78,
            "next world step cannot repeat an already consumed nudge");
        // A late nudge must not affect only the second half of an already
        // accepted pair; both consume it together on the next world step.
        prepare_pair;shoot;
        @(negedge clk);dut.ball1_in_lane=0;dut.ball2_in_lane=0;
        dut.position_x=20*256;dut.position_y=40*256;dut.position2_x=66*256;dut.position2_y=40*256;
        dut.velocity_x=0;dut.velocity_y=0;dut.velocity2_x=0;dut.velocity2_y=0;
        @(negedge clk);tick=1;cycle;@(negedge clk);tick=0;repeat(5) cycle;
        @(negedge clk);nudge=1;cycle;@(negedge clk);nudge=0;repeat(35) cycle;
        check(dut.velocity_x==0 && dut.velocity2_x==0 && dut.velocity_y==1 &&
            dut.velocity2_y==1 && dut.nudge_pending,
            "a nudge arriving between pair snapshots stays queued for both balls");
        step;check(dut.velocity_x==48 && dut.velocity2_x==-48 &&
            dut.velocity_y==-78 && dut.velocity2_y==-78 && !dut.nudge_pending,
            "the next accepted pair applies the late nudge symmetrically once");
        for(p=0;p<2;p=p+1) begin
            prepare_pair;shoot;
            @(negedge clk);tick=1;cycle;@(negedge clk);tick=0;
            repeat(20) cycle;
            check(dut.collision_busy && dut.work_ball && !dut.load_second,
                "cancellation is exercised during the second isolated calculation");
            @(negedge clk);if(p==0) prepare=1;else reset=1;cycle;
            @(negedge clk);prepare=0;reset=0;repeat(45) cycle;
            check(balls_visible==3 && ball_y==56 && ball2_y==60 && !dut.collision_busy &&
                !dut.launched && !dut.launched2 && hit_events==0 && !drained &&
                dut.pending_hit_wait==0 && moving_bumper_y_fp==22*256,
                "prepare/reset cancels both staged positions and deferred event/drain state");
        end
        // Selecting one ball restores the original presentation and exact
        // 16-clock update latency; the unused ball cannot launch or move.
        two_ball_mode=0;prepare_pair;shoot;
        saved_y=dut.position_y;saved2_y=dut.position2_y;
        @(negedge clk);tick=1;cycle;@(negedge clk);tick=0;
        repeat(15) cycle;
        check(dut.position_y==saved_y && dut.collision_busy,"one-ball path still isolates for 16 clocks");
        cycle;
        check(!dut.collision_busy && dut.position_y==saved_y-303 &&
            dut.position2_y==saved2_y && balls_visible==1,"one-ball mode retains existing launch/motion timing");
        $display("PASS tb_multiball (%0d checks)",checks);$finish;
    end
    initial begin #100000000;$fatal(1,"multiball timeout");end
endmodule
