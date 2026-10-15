`timescale 1ns/1ps
// The real rules engine and shared physics scheduler run together. Controlled
// positions make event/life races reproducible; ordinary contact tests use the
// real collision geometry. One explicit decoder fixture exercises hit+drain
// queuing, since the table's scoring objects are far above its drain opening.
module tb_two_ball_game;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1,tick=0,start_press=0,launch_down=0,pause_press=0,menu_press=0;
    reg level_left=0,level_right=0,two_ball_select=0,nudge_press=0;
    reg left_pressed=0,right_pressed=0,nudge=0;
    wire [2:0] state,combo,mission_progress,feature_event;
    wire [1:0] lives,difficulty,bonus_target,target_progress;
    wire [15:0] score_bcd,high_bcd,last_award_bcd;
    wire [5:0] charge,table_progress;
    wire [3:0] spinner_phase;
    wire prepare,launch,active,bonus_active,two_ball_mode;
    wire [13:0] hit_events,hit_flash,moving_bumper_y_fp;
    wire [14:0] moving_bumper_x_fp;
    wire [7:0] anim;
    wire [10:0] save_timer;
    wire [9:0] feature_timer;
    wire [6:0] ball_x,ball2_x;
    wire [5:0] ball_y,ball2_y;
    wire [14:0] ball_x_fp,ball2_x_fp;
    wire [13:0] ball_y_fp,ball2_y_fp;
    wire [13:0] side_left_y_fp,side_right_y_fp;
    wire [1:0] balls_visible;
    wire [2:0] left_angle,right_angle;
    wire drained,in_lane,hit_ball;
    wire [5:0] launch_power=charge;
    integer checks=0,hit_pulses=0,ball1_hits=0,ball2_hits=0,drain_pulses=0,launch_pulses=0;
    integer hits_before,drains_before,launches_before,k;
    reg signed [15:0] paused_x,paused_x2;
    pinball_game game(.*);
    pinball_physics physics(.*);

    always @(posedge clk) begin
        #1;
        if(!reset) begin
            if(|hit_events) begin
                hit_pulses=hit_pulses+1;
                if(hit_ball) ball2_hits=ball2_hits+1;
                else ball1_hits=ball1_hits+1;
            end
            if(drained) drain_pulses=drain_pulses+1;
            if(launch) launch_pulses=launch_pulses+1;
        end
    end

    task check;
        input condition;
        input [767:0] message;
        begin
            checks=checks+1;
            if(!condition) begin
                $display("FAIL two-ball game: %0s state=%0d lives=%0d score=%h half=%0d visible=%b combo=%0d",
                    message,state,lives,score_bcd,game.score_half,balls_visible,combo);
                $fatal(1);
            end
        end
    endtask
    task cycle; @(posedge clk); #2; endtask
    task pulse_tick;
        @(negedge clk);tick=1;cycle();
        @(negedge clk);tick=0;cycle();
    endtask
    task world_step;
        pulse_tick();repeat(50)cycle();
    endtask
    task start_game;
        input mode;
        begin
            @(negedge clk);menu_press=1;two_ball_select=mode;cycle();
            @(negedge clk);menu_press=0;cycle();
            @(negedge clk);start_press=1;cycle();
            check(state==1 && prepare && two_ball_mode==mode,"start latches the menu mode");
            @(negedge clk);start_press=0;repeat(3)cycle();
            check(balls_visible==(mode ? 2'b11 : 2'b01) && in_lane &&
                  !physics.launched && !physics.launched2,"prepare constructs the selected ball count");
            check(score_bcd==0 && !game.score_half,"new game clears whole and fractional scores");
        end
    endtask
    task shoot;
        begin
            launches_before=launch_pulses;
            @(negedge clk);launch_down=1;
            repeat(80)pulse_tick();
            @(negedge clk);launch_down=0;cycle();
            check(launch && state==2 && charge==20,"one C release generates the selected shot power");
            cycle();
            check(!launch && physics.launched && physics.launched2==two_ball_mode &&
                  physics.velocity_y==-308 && (!two_ball_mode || physics.velocity2_y==-308) &&
                  physics.shot_power==20,"one launch pulse captures equal power in all selected balls");
            repeat(3)cycle();
            check(launch_pulses==launches_before+1,"dual mode does not synthesize a second launch pulse");
        end
    endtask
    task seed_bumper_pair;
        begin
            @(negedge clk);
            physics.ball1_in_lane=0;physics.ball2_in_lane=0;
            physics.position_x=26*256;physics.position_y=moving_bumper_y_fp-1152;
            physics.position2_x=26*256;physics.position2_y=moving_bumper_y_fp-1152;
            physics.velocity_x=0;physics.velocity_y=300;
            physics.velocity2_x=0;physics.velocity2_y=300;
            physics.hit_armed=14'h3fff;physics.hit_armed2=14'h3fff;
            for(k=0;k<14;k=k+1) begin physics.cooldown[k]=0;physics.cooldown2[k]=0;end
        end
    endtask
    task seed_drain;
        input [1:0] which;
        begin
            @(negedge clk);
            physics.ball1_in_lane=0;physics.ball2_in_lane=0;
            physics.position_x=(which[0] ? 42 : 70)*256;
            physics.position_y=which[0] ? 64*256-32 : 45*256;
            physics.velocity_x=0;physics.velocity_y=which[0] ? 76 : 0;
            physics.position2_x=(which[1] ? 42 : 70)*256;
            physics.position2_y=which[1] ? 64*256-32 : 45*256;
            physics.velocity2_x=0;physics.velocity2_y=which[1] ? 76 : 0;
        end
    endtask
    task disable_save;
        @(negedge clk);game.save_timer=0;cycle();
    endtask
    task await_pair_commit;
        begin
            pulse_tick();
            check(physics.collision_busy,"dual collision batch started");
            while(physics.collision_busy)cycle();
            check(physics.pending_hit_wait==4,"second event is queued after the atomic pair commit");
        end
    endtask

    initial begin
        repeat(3)cycle();@(negedge clk);reset=0;cycle();
        check(state==0 && !two_ball_mode && balls_visible==1,"reset starts with single-ball defaults");

        start_game(0);shoot();
        @(negedge clk);two_ball_select=1;cycle();
        check(!two_ball_mode && balls_visible==1,"changing the menu choice during single-ball play does not spawn a ball");
        hits_before=hit_pulses;seed_bumper_pair();world_step();
        check(hit_pulses==hits_before+1 && score_bcd==0 && game.score_half && combo==1,
              "single-ball contact gives exactly one half-point award");
        disable_save();drains_before=drain_pulses;seed_drain(1);world_step();
        check(drain_pulses==drains_before+1 && state==1 && lives==2 && balls_visible==1 &&
              !two_ball_mode,"single-ball drain retains the existing one-life behavior");

        start_game(1);shoot();
        @(negedge clk);two_ball_select=0;cycle();
        check(two_ball_mode && balls_visible==3,"changing the menu choice during a pair does not remove a ball");
        hits_before=hit_pulses;seed_bumper_pair();world_step();
        check(hit_pulses==hits_before+2 && ball1_hits!=0 && ball2_hits!=0 &&
              score_bcd==16'h0001 && game.score_half && last_award_bcd==16'h0001 &&
              combo==2 && mission_progress==1 && !physics.hit_armed[0] && !physics.hit_armed2[0],
              "both real contacts at one bumper score individually with combo and half-point carry");
        disable_save();drains_before=drain_pulses;seed_drain(1);world_step();
        check(drain_pulses==drains_before && state==2 && lives==3 && balls_visible==2 &&
              !physics.launched && physics.launched2 && score_bcd==16'h0001 && game.score_half,
              "the first ball drain keeps its partner in PLAY without consuming a life");
        seed_drain(2);world_step();
        check(drain_pulses==drains_before+1 && state==1 && lives==2 && balls_visible==3 &&
              !physics.launched && !physics.launched2 && two_ball_mode && score_bcd==16'h0001 &&
              game.score_half,"the final partner drain consumes one pair life and rebuilds both balls");

        start_game(1);shoot();
        drains_before=drain_pulses;seed_drain(3);world_step();
        check(drain_pulses==drains_before+1 && state==1 && lives==3 && balls_visible==3 &&
              save_timer==0 && !game.launch_save_eligible && feature_event==4,
              "launch save restores the pair with no lost life and consumes its entitlement");
        shoot();check(save_timer==0,"a saved pair relaunch gets no second launch-save window");
        seed_drain(3);world_step();
        check(state==1 && lives==2 && balls_visible==3 && game.launch_save_eligible,
              "the saved pair's next final drain costs one life");

        // Decoder injection isolates the scheduler/rules race while the real
        // drain calculation and delayed drain signal remain active.
        start_game(1);shoot();disable_save();seed_drain(3);
        hits_before=hit_pulses;drains_before=drain_pulses;
        force physics.contact_events=14'h0100;
        await_pair_commit();release physics.contact_events;repeat(20)cycle();
        check(hit_pulses==hits_before+2 && drain_pulses==drains_before+1 && state==1 && lives==2 &&
              score_bcd==16'h0001 && game.score_half && last_award_bcd==16'h0001 && balls_visible==3,
              "both final-batch hit awards commit before the pair drain prepares the next life");

        start_game(1);shoot();disable_save();seed_drain(3);
        hits_before=hit_pulses;drains_before=drain_pulses;
        force physics.contact_events=14'h0100;
        await_pair_commit();release physics.contact_events;
        @(negedge clk);pause_press=1;cycle();
        @(negedge clk);pause_press=0;repeat(20)cycle();
        check(state==3 && game.resume_state==1 && lives==2 && score_bcd==16'h0001 && game.score_half &&
              hit_pulses==hits_before+2 && drain_pulses==drains_before+1 && balls_visible==3,
              "pause accepts both in-flight awards and preserves the final drain resume state");
        paused_x=physics.position_x;paused_x2=physics.position2_x;
        repeat(5)world_step();
        check(!physics.collision_busy && physics.position_x==paused_x && physics.position2_x==paused_x2,
              "paused pair cannot start another collision calculation");
        @(negedge clk);pause_press=1;cycle();
        @(negedge clk);pause_press=0;cycle();
        check(state==1 && two_ball_mode && charge==0,"paused final drain resumes into a prepared pair");

        start_game(1);shoot();disable_save();seed_drain(3);
        hits_before=hit_pulses;drains_before=drain_pulses;
        force physics.contact_events=14'h0100;
        await_pair_commit();release physics.contact_events;
        @(negedge clk);menu_press=1;cycle();
        @(negedge clk);menu_press=0;repeat(20)cycle();
        check(state==0 && lives==3 && hit_pulses==hits_before+1 && drain_pulses==drains_before &&
              !physics.collision_busy && physics.pending_hit_wait==0 && physics.pending_drain_wait==0 &&
              score_bcd==0 && game.score_half && two_ball_mode,
              "menu prepare cancels the pending second hit and drain without a stale life transition");
        start_game(0);
        check(score_bcd==0 && !game.score_half && !two_ball_mode && balls_visible==1,
              "a new single-ball game clears the cancelled pair's fractional award");

        start_game(1);shoot();disable_save();seed_drain(3);
        force physics.contact_events=14'h0100;
        await_pair_commit();release physics.contact_events;
        @(negedge clk);reset=1;repeat(3)cycle();
        hits_before=hit_pulses;drains_before=drain_pulses;
        @(negedge clk);reset=0;repeat(20)cycle();
        check(state==0 && lives==3 && !two_ball_mode && balls_visible==1 && score_bcd==0 && high_bcd==0 &&
              !game.score_half && !physics.collision_busy && physics.pending_hit_wait==0 &&
              physics.pending_drain_wait==0 && hit_pulses==hits_before && drain_pulses==drains_before,
              "reset clears the pair queues, fractional score and mode without stale outputs");
        $display("PASS tb_two_ball_game: %0d checks; selected pair launch, individual awards, fractional carry, pair lives/save, final-batch scoring, pause, menu/reset cancellation",checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"Two-ball game timeout");end
endmodule
