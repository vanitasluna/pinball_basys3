`timescale 1ns/1ps
module tb_game;
    reg clk=0; always #5 clk=~clk;
    reg reset=1,tick=0,start_press=0,launch_down=0,pause_press=0,menu_press=0;
    reg level_left=0,level_right=0,two_ball_select=0,drained=0,in_lane=0,nudge_press=0;
    reg [13:0] hit_events=0;
    wire [2:0] state,combo,mission_progress,feature_event;
    wire [1:0] lives,difficulty,bonus_target,target_progress;
    wire [15:0] score_bcd,high_bcd,last_award_bcd;
    wire [5:0] charge;
    wire [5:0] table_progress;
    wire [3:0] spinner_phase;
    wire prepare,launch,active,bonus_active,two_ball_mode;
    wire [13:0] hit_flash;
    wire [7:0] anim;
    wire [10:0] save_timer;
    wire [9:0] feature_timer;
    reg [9:0] bonus_before_pause,combo_before_pause,feature_before_pause;
    reg [10:0] save_before_pause;
    reg [1:0] late_bonus_target;
    reg [3:0] spinner_before_pause;
    reg [6:0] spinner_time_before_pause;
    integer charge_expected;
    pinball_game dut(.*);
    task cycle; @(posedge clk); #1; endtask
    task game_tick; @(negedge clk);tick=1;cycle();@(negedge clk);tick=0;cycle();endtask
    task start; @(negedge clk);start_press=1;cycle();
        if(!prepare || state!=1) $fatal(1,"Start did not prepare ball");
        @(negedge clk);start_press=0;cycle();endtask
    task shoot; @(negedge clk);launch_down=1;
        repeat(80) game_tick();
        @(negedge clk);launch_down=0;cycle();
        if(!launch || state!=2 || charge!=20) $fatal(1,"Charge or launch failed");
        cycle();if(launch) $fatal(1,"Launch pulse longer than one clock");endtask
    task hit; input [13:0] mask;
        @(negedge clk);hit_events=mask;cycle();
        @(negedge clk);hit_events=0;repeat(4)cycle();endtask
    task lose_ball; @(negedge clk);drained=1;cycle();
        @(negedge clk);drained=0;repeat(4)cycle();endtask
    task toggle_pause; @(negedge clk);pause_press=1;cycle();
        @(negedge clk);pause_press=0;cycle();endtask
    task check_ready_charge; input integer expected;
        if(state!=1 || launch || charge!=expected)
            $fatal(1,"Held launch: expected READY charge %0d, got state %0d charge %0d launch %0d",
                expected,state,charge,launch);
    endtask
    task hold_charge; input integer ticks;
        @(negedge clk);launch_down=1;repeat(ticks)game_tick();
    endtask
    task release_charge; input [5:0] expected;
        @(negedge clk);launch_down=0;cycle();
        if(state!=2 || !launch || charge!=expected)
            $fatal(1,"Released launch: expected power %0d, got state %0d charge %0d launch %0d",
                expected,state,charge,launch);
        repeat(3)begin cycle();if(launch) $fatal(1,"Released charge retriggered launch");end
    endtask
    task fresh_ready;
        @(negedge clk);menu_press=1;cycle();
        if(state!=0 || charge!=0 || launch) $fatal(1,"Menu retained launch power");
        @(negedge clk);menu_press=0;cycle();start();check_ready_charge(0);
    endtask
    initial begin
        repeat(3)cycle();@(negedge clk);reset=0;cycle();
        if(state!=0 || difficulty!=1 || lives!=3 || combo!=1 || two_ball_mode) $fatal(1,"Reset failed");
        @(negedge clk);level_left=1;cycle();@(negedge clk);level_left=0;cycle();
        if(difficulty!=0) $fatal(1,"Level selection failed");
        @(negedge clk);two_ball_select=1;cycle();
        if(two_ball_mode) $fatal(1,"Mode changed before new-game capture");
        start();
        if(!two_ball_mode) $fatal(1,"Two-ball mode was not captured on start");
        @(negedge clk);two_ball_select=0;cycle();
        if(!two_ball_mode) $fatal(1,"Mode switch altered a prepared game");
        // Releasing a partially charged ball while paused must not launch it.
        @(negedge clk);launch_down=1;repeat(24)game_tick();
        if(charge!=6) $fatal(1,"Ready charge setup failed");
        toggle_pause();@(negedge clk);launch_down=0;cycle();
        repeat(6)game_tick();
        if(state!=3 || launch || charge!=6 || !two_ball_mode) $fatal(1,"Ready pause did not freeze charge");
        toggle_pause();repeat(3)game_tick();
        if(state!=1 || launch || charge!=0) $fatal(1,"Resume launched a released ready ball");
        shoot();
        if(save_timer!=720) $fatal(1,"New life did not get launch grace");
        @(negedge clk);in_lane=1;repeat(20)game_tick();
        if(save_timer!=720) $fatal(1,"Launch grace ran down inside shooter lane");
        @(negedge clk);in_lane=0;game_tick();
        if(save_timer!=719) $fatal(1,"Launch grace did not start outside lane");

        // A scoring transaction advances the combo once, including multi-hit
        // masks. Three different bumpers pay a flat 5-point mission reward.
        hit(1);
        if(score_bcd!=16'h0000 || high_bcd!=16'h0000 || combo!=1 ||
           mission_progress!=1 || last_award_bcd!=16'h0000 || !hit_flash[0])
            $fatal(1,"First bumper score/progress failed");
        hit(8);
        if(score_bcd!=16'h0002 || combo!=2 || target_progress!=1 || feature_event!=2)
            $fatal(1,"x2 target score or combo failed");
        hit(2);
        if(score_bcd!=16'h0004 || combo!=3 || mission_progress!=3)
            $fatal(1,"x3 bumper score failed");
        hit(4);
        if(score_bcd!=16'h0011 || combo!=4 || mission_progress!=0 ||
           last_award_bcd!=16'h0007 || feature_event!=3)
            $fatal(1,"Bumper mission reward/reset failed");
        hit(16);
        if(score_bcd!=16'h0017 || target_progress!=0 || save_timer!=1440 ||
           last_award_bcd!=16'h0006 || feature_event!=5)
            $fatal(1,"Side-pair score or six-second ball save failed");
        hit(24);
        if(score_bcd!=16'h0028 || combo!=4 || target_progress!=0 ||
           last_award_bcd!=16'h0011)
            $fatal(1,"Simultaneous side targets or combo cap failed");
        hit(31);
        if(score_bcd!=16'h0049 || last_award_bcd!=16'h0021 ||
           mission_progress!=0 || target_progress!=0 || feature_event!=3)
            $fatal(1,"Combined mission/side reward or event priority failed");
        // The five-contact award is 24: 14 at x4 plus flat 2.5/5/2.5 bonuses.
        force dut.bonus_timer=10'd480;cycle();release dut.bonus_timer;
        hit(31);
        if(score_bcd!=16'h0073 || last_award_bcd!=16'h0024 ||
           dut.bonus_timer!=720 || feature_event!=3)
            $fatal(1,"Maximum combined award or jackpot priority failed");
        // Adjacent clock results must all survive the award pipeline.
        @(negedge clk);hit_events=1;cycle();
        @(negedge clk);hit_events=2;cycle();
        @(negedge clk);hit_events=4;cycle();
        @(negedge clk);hit_events=0;repeat(5)cycle();
        if(score_bcd!=16'h0084 || high_bcd!=16'h0084 || last_award_bcd!=16'h0007)
            $fatal(1,"Consecutive score transactions were lost");
        repeat(480)game_tick();
        if(combo!=1 || dut.combo_timer!=0 || feature_event!=0 || feature_timer!=0 ||
           save_timer!=960 || score_bcd!=16'h0084)
            $fatal(1,"Combo/effect expiry or full-width save countdown failed");
        // Saturating decimal scoring across all four digits.
        force dut.score_bcd=16'h9998;cycle();release dut.score_bcd;
        hit(24);
        if(score_bcd!=16'h9999 || high_bcd!=16'h9999) $fatal(1,"Score saturation failed");

        // Start again while an old award is still travelling through the
        // pipeline. It must not leak into the new game's zero score.
        @(negedge clk);hit_events=1;cycle();
        @(negedge clk);hit_events=0;menu_press=1;cycle();
        @(negedge clk);menu_press=0;start_press=1;cycle();
        @(negedge clk);start_press=0;repeat(5)cycle();
        if(state!=1 || score_bcd!=0 || high_bcd!=16'h9999 || lives!=3 ||
           combo!=1 || mission_progress!=0 || target_progress!=0 || last_award_bcd!=0 ||
           two_ball_mode || dut.score_half)
            $fatal(1,"New game did not flush old scores/features");
        shoot();repeat(241)game_tick();
        if(!bonus_active) $fatal(1,"Gold bonus window failed");
        late_bonus_target=bonus_target;
        hit(5'b00001<<late_bonus_target);
        if(score_bcd!=16'h0003 || bonus_active || last_award_bcd!=16'h0003)
            $fatal(1,"First gold bonus scoring/consume failed");
        hit(5'b00001<<late_bonus_target);
        hit(5'b00001<<late_bonus_target);
        hit(5'b00001<<late_bonus_target);
        if(score_bcd!=16'h0007 || combo!=4) $fatal(1,"Combo accumulation failed");
        repeat(241)game_tick();
        if(!bonus_active) $fatal(1,"Second gold bonus window failed");
        hit(5'b00001<<bonus_target);
        if(score_bcd!=16'h0012 || last_award_bcd!=16'h0005 || bonus_active)
            $fatal(1,"Gold bonus was incorrectly multiplied");
        hit(8);hit(16);
        if(score_bcd!=16'h0022 || save_timer!=1440) $fatal(1,"Second pair setup failed");
        repeat(241)game_tick();
        if(!bonus_active) $fatal(1,"Late gold bonus setup failed");
        bonus_before_pause=dut.bonus_timer;combo_before_pause=dut.combo_timer;
        save_before_pause=save_timer;feature_before_pause=feature_timer;
        late_bonus_target=bonus_target;
        toggle_pause();repeat(100)game_tick();
        if(state!=3 || active || score_bcd!=16'h0022 ||
           dut.bonus_timer!=bonus_before_pause || dut.combo_timer!=combo_before_pause ||
           save_timer!=save_before_pause || feature_timer!=feature_before_pause)
            $fatal(1,"Pause changed arcade timers/data");
        // A registered physics hit after the pause transition keeps its gold
        // entitlement and scores through the pipeline while timers stay frozen.
        hit(5'b00001<<late_bonus_target);
        if(state!=3 || score_bcd!=16'h0027 || last_award_bcd!=16'h0005 ||
           !hit_flash[late_bonus_target] || dut.bonus_timer!=720 || feature_event!=1)
            $fatal(1,"Paused in-flight gold hit was lost");
        repeat(5)game_tick();
        if(dut.bonus_timer!=720 || dut.combo_timer!=480 ||
           feature_timer!=240 || save_timer!=save_before_pause)
            $fatal(1,"Paused late-event timer advanced");
        @(negedge clk);drained=1;cycle();
        if(state!=3 || lives!=3 || !prepare || dut.resume_state!=1 || two_ball_mode ||
           save_timer!=0 || feature_event!=4 || combo!=1)
            $fatal(1,"Paused saved drain lost a life or resume state");
        @(negedge clk);drained=0;cycle();
        if(prepare) $fatal(1,"Saved prepare was not a one-clock pulse");
        toggle_pause();
        if(state!=1 || lives!=3 || active) $fatal(1,"Saved ball resumed into stalled play");
        // Holding launch through a READY pause must clear stale spring power.
        @(negedge clk);launch_down=1;repeat(24)game_tick();
        toggle_pause();toggle_pause();
        if(state!=1 || charge!=0 || launch) $fatal(1,"Held READY pause retained stale charge");
        shoot();
        if(save_timer!=0) $fatal(1,"Saved relaunch incorrectly granted unlimited saves");
        lose_ball();
        if(state!=1 || lives!=2 || combo!=1) $fatal(1,"Unprotected drain failed");
        shoot();
        if(save_timer!=720) $fatal(1,"Next physical life did not get launch grace");
        @(negedge clk);nudge_press=1;cycle();
        @(negedge clk);nudge_press=0;cycle();
        if(feature_event!=6 || feature_timer!=240 || score_bcd!=16'h0027)
            $fatal(1,"Nudge feedback altered scoring");
        repeat(720)game_tick();
        if(save_timer!=0) $fatal(1,"Three-second launch grace did not expire");
        lose_ball();if(state!=1 || lives!=1) $fatal(1,"Second unprotected drain failed");
        shoot();repeat(720)game_tick();
        toggle_pause();
        @(negedge clk);drained=1;hit_events=8;cycle();
        if(state!=4 || lives!=0 || prepare) $fatal(1,"Paused final drain did not reach game over");
        @(negedge clk);drained=0;hit_events=0;repeat(5)cycle();
        if(score_bcd!=16'h0028 || high_bcd!=16'h9999)
            $fatal(1,"Final drained ball score was lost");
        start();
        if(score_bcd!=0 || high_bcd!=16'h9999 || lives!=3 || mission_progress!=0 ||
           target_progress!=0 || feature_timer!=0)
            $fatal(1,"Restart/high score or feature reset failed");
        @(negedge clk);menu_press=1;cycle();@(negedge clk);menu_press=0;cycle();
        if(state!=0 || high_bcd!=16'h9999 || two_ball_mode) $fatal(1,"Return to menu failed");

        // Independent lane and target-bank collections persist until their
        // own completion; simultaneous contacts still advance the combo once.
        start();shoot();
        if(table_progress!=0 || spinner_phase!=0 || hit_flash!=0)
            $fatal(1,"New table features did not reset");
        hit(14'h0020);
        if(score_bcd!=16'h0000 || table_progress!=6'b000001 || !hit_flash[5])
            $fatal(1,"First top rollover score/progress failed");
        hit(14'h0800);
        if(score_bcd!=16'h0002 || table_progress!=6'b001001 || !hit_flash[11])
            $fatal(1,"Stand-up target score/progress failed");
        hit(14'h00c0);
        if(score_bcd!=16'h0008 || last_award_bcd!=16'h0006 || combo!=3 ||
           table_progress!=6'b001000 || feature_event!=7 || !hit_flash[6] || !hit_flash[7])
            $fatal(1,"Simultaneous rollover completion/reward failed");
        hit(14'h3000);
        if(score_bcd!=16'h0020 || last_award_bcd!=16'h0012 || combo!=4 ||
           table_progress!=0 || feature_event!=7 || !hit_flash[12] || !hit_flash[13])
            $fatal(1,"Simultaneous target-bank completion/reward failed");
        hit(14'h00e0);
        if(score_bcd!=16'h0029 || last_award_bcd!=16'h0009 || table_progress!=0)
            $fatal(1,"Rollover collection was not repeatable or bonus was multiplied");
        hit(14'h3800);
        if(score_bcd!=16'h0045 || last_award_bcd!=16'h0016 || table_progress!=0)
            $fatal(1,"Target bank was not repeatable or bonus was multiplied");

        // The spinner keeps turning briefly after contact and stops cleanly.
        hit(14'h0100);
        if(score_bcd!=16'h0047 || last_award_bcd!=16'h0002 || !hit_flash[8] ||
           spinner_phase!=3 || dut.spinner_timer!=120)
            $fatal(1,"Spinner score or spin impulse failed");
        repeat(4)game_tick();
        if(spinner_phase!=4 || dut.spinner_timer!=116)
            $fatal(1,"Spinner continuation did not animate");
        spinner_before_pause=spinner_phase;spinner_time_before_pause=dut.spinner_timer;
        toggle_pause();repeat(200)game_tick();
        if(spinner_phase!=spinner_before_pause || dut.spinner_timer!=spinner_time_before_pause)
            $fatal(1,"Paused spinner did not freeze");
        toggle_pause();repeat(116)game_tick();
        if(dut.spinner_timer!=0) $fatal(1,"Spinner did not settle");
        spinner_before_pause=spinner_phase;repeat(32)game_tick();
        if(spinner_phase!=spinner_before_pause) $fatal(1,"Settled spinner kept rotating");
        hit(14'h0600);
        if(score_bcd!=16'h0051 || last_award_bcd!=16'h0004 || !hit_flash[9] || !hit_flash[10])
            $fatal(1,"Slingshot scoring/flash failed");
        hit(14'h0820);
        if(score_bcd!=16'h0057 || table_progress!=6'b001001)
            $fatal(1,"Mixed new-contact mask overflowed base award");
        lose_ball();
        if(state!=1 || lives!=3 || table_progress!=6'b001001)
            $fatal(1,"Saved drain discarded collected table lamps");
        shoot();
        // Adjacent transactions can complete both new collections together.
        @(negedge clk);hit_events=14'h0040;cycle();
        @(negedge clk);hit_events=14'h1000;cycle();
        @(negedge clk);hit_events=14'h2080;cycle();
        @(negedge clk);hit_events=0;repeat(5)cycle();
        if(score_bcd!=16'h0071 || last_award_bcd!=16'h0011 || combo!=3 ||
           table_progress!=0 || feature_event!=7)
            $fatal(1,"Consecutive new-contact awards or combined collection rewards failed");
        // Every contact at x4: 9.5 x 4 + 2.5 + 5 + 2.5 + 3 + 4 = 55.
        // The accumulated total is 71.5 + 55 = 126.5, well below the display cap.
        force dut.bonus_timer=10'd480;cycle();release dut.bonus_timer;
        hit(14'h3fff);
        if(score_bcd!=16'h0126 || last_award_bcd!=16'h0055 || combo!=4 ||
           mission_progress!=0 || target_progress!=0 || table_progress!=0 ||
           feature_event!=3 || hit_flash!=14'h3fff || save_timer!=1440)
            $fatal(1,"Maximum fourteen-contact award overflowed or dropped a bonus");
        @(negedge clk);menu_press=1;cycle();@(negedge clk);menu_press=0;cycle();
        start();
        if(score_bcd!=0 || table_progress!=0 || spinner_phase!=0 || dut.spinner_timer!=0 ||
           hit_flash!=0 || high_bcd!=16'h9999)
            $fatal(1,"Restart failed to clear expanded table state");

        // Holding the spring makes a continuous 0..63..0 triangle. At 240 Hz,
        // each power step lasts four ticks, so each half-cycle is 1.05 seconds.
        // Check every step across both reversals, including the very next step
        // after each endpoint: neither maximum nor minimum may stick or wrap.
        @(negedge clk);launch_down=1;
        for(charge_expected=1;charge_expected<=63;charge_expected=charge_expected+1)begin
            repeat(4)game_tick();check_ready_charge(charge_expected);
        end
        for(charge_expected=62;charge_expected>=0;charge_expected=charge_expected-1)begin
            repeat(4)game_tick();check_ready_charge(charge_expected);
        end
        for(charge_expected=1;charge_expected<=17;charge_expected=charge_expected+1)begin
            repeat(4)game_tick();check_ready_charge(charge_expected);
        end
        release_charge(17);

        // Releasing uses the power currently shown, on either side of the
        // triangle. The existing 16-unit minimum keeps taps and zero usable.
        fresh_ready();hold_charge(252);check_ready_charge(63);release_charge(63);
        fresh_ready();hold_charge(408);check_ready_charge(24);release_charge(24);
        fresh_ready();hold_charge(504);check_ready_charge(0);release_charge(16);
        fresh_ready();hold_charge(0);cycle();check_ready_charge(0);release_charge(16);

        // Pause freezes descending power even with a partly elapsed step.
        // Resume clears the spring; its next full step must rise from zero.
        fresh_ready();hold_charge(414);check_ready_charge(23);
        toggle_pause();repeat(300)game_tick();
        if(state!=3 || launch || charge!=23) $fatal(1,"Descending charge changed during pause");
        @(negedge clk);launch_down=0;cycle();toggle_pause();check_ready_charge(0);
        hold_charge(4);check_ready_charge(1);

        // Returning to the menu while C stays held resets direction and the
        // partial step. Starting again cannot inherit a falling spring.
        hold_charge(334);check_ready_charge(42);
        @(negedge clk);menu_press=1;cycle();
        @(negedge clk);menu_press=0;repeat(9)game_tick();
        if(state!=0 || charge!=0 || launch) $fatal(1,"Held C charged or launched in menu");
        start();hold_charge(4);check_ready_charge(1);

        // A saved drain after a descending release also prepares a fresh,
        // rising spring, without granting a second launch-save window.
        fresh_ready();hold_charge(384);check_ready_charge(30);release_charge(30);
        lose_ball();check_ready_charge(0);
        hold_charge(4);check_ready_charge(1);release_charge(16);
        if(save_timer!=0) $fatal(1,"Bounced-power saved relaunch granted another save");
        // Half-point contacts are never discarded. Three consecutive small
        // awards leave 1.5 points, including across the commit pipeline.
        fresh_ready();shoot();
        force dut.combo_timer=10'd0;
        @(negedge clk);hit_events=14'h0100;cycle();
        cycle();cycle();
        @(negedge clk);hit_events=0;release dut.combo_timer;repeat(5)cycle();
        if(score_bcd!=16'h0001 || high_bcd!=16'h9999 || last_award_bcd!=0 || !dut.score_half)
            $fatal(1,"Consecutive half-point contacts lost fractional carry");
        repeat(720)game_tick();lose_ball();
        if(state!=1 || lives!=2 || score_bcd!=16'h0001 || !dut.score_half)
            $fatal(1,"Unprotected drain lost the half-point score");
        shoot();hit(14'h0100);
        if(score_bcd!=16'h0002 || last_award_bcd!=16'h0001 || dut.score_half)
            $fatal(1,"Half-point remainder did not carry into the next life");
        toggle_pause();
        force dut.combo_timer=10'd0;
        hit(14'h0100);release dut.combo_timer;
        if(state!=3 || score_bcd!=16'h0002 || !dut.score_half)
            $fatal(1,"Paused in-flight half-point award was lost");
        fresh_ready();
        if(score_bcd!=0 || dut.score_half) $fatal(1,"New game retained fractional score");
        shoot();hit(14'h0100);
        if(score_bcd!=0 || !dut.score_half || last_award_bcd!=0)
            $fatal(1,"New game inherited a previous half-point carry");

        // A mode selected in the menu remains fixed across ready/play/pause,
        // pair drains and return to the menu; the next start samples the menu choice.
        @(negedge clk);two_ball_select=1;cycle();
        if(two_ball_mode) $fatal(1,"Live mode switch altered single-ball play");
        fresh_ready();
        if(!two_ball_mode) $fatal(1,"Next game did not capture two-ball selection");
        shoot();toggle_pause();
        @(negedge clk);two_ball_select=0;cycle();
        lose_ball();
        if(state!=3 || !two_ball_mode || dut.resume_state!=1)
            $fatal(1,"Paused pair drain changed the selected mode");
        @(negedge clk);menu_press=1;cycle();
        @(negedge clk);menu_press=0;cycle();
        if(!two_ball_mode) $fatal(1,"Menu overwrote the last game's mode");
        start();if(two_ball_mode) $fatal(1,"Next game did not capture single-ball selection");
        // A completed physics drain must not swallow the same-cycle pause or
        // resume command. Both saved and ordinary next-life preparation retain
        // the player's requested paused/running state.
        shoot();
        @(negedge clk);pause_press=1;drained=1;cycle();
        if(state!=3 || dut.resume_state!=1 || lives!=3 || !prepare || save_timer!=0)
            $fatal(1,"Saved drain swallowed a simultaneous pause press");
        @(negedge clk);pause_press=0;drained=0;cycle();toggle_pause();
        if(state!=1) $fatal(1,"Saved same-cycle pause did not resume to READY");
        shoot();
        @(negedge clk);pause_press=1;drained=1;cycle();
        if(state!=3 || dut.resume_state!=1 || lives!=2 || !prepare)
            $fatal(1,"Ordinary drain swallowed a simultaneous pause press");
        @(negedge clk);pause_press=0;drained=0;cycle();toggle_pause();
        shoot();toggle_pause();
        @(negedge clk);pause_press=1;drained=1;cycle();
        if(state!=1 || lives!=2 || !prepare || save_timer!=0)
            $fatal(1,"Saved drain swallowed a simultaneous resume press");
        @(negedge clk);pause_press=0;drained=0;cycle();
        shoot();toggle_pause();
        @(negedge clk);start_press=1;drained=1;cycle();
        if(state!=1 || lives!=1 || !prepare)
            $fatal(1,"Ordinary drain swallowed a simultaneous C resume press");
        @(negedge clk);start_press=0;drained=0;cycle();
        shoot();
        @(negedge clk);dut.save_timer=0;pause_press=1;drained=1;cycle();
        if(state!=4 || lives!=0 || prepare)
            $fatal(1,"A simultaneous pause overrode the final game-over drain");
        @(negedge clk);pause_press=0;drained=0;cycle();start();shoot();
        @(negedge clk);menu_press=1;pause_press=1;drained=1;cycle();
        if(state!=0 || lives!=3 || !prepare || charge!=0)
            $fatal(1,"A simultaneous drain/pause overrode return to menu");
        @(negedge clk);menu_press=0;pause_press=0;drained=0;cycle();
        @(negedge clk);reset=1;cycle();
        if(two_ball_mode || score_bcd!=0 || high_bcd!=0 || dut.score_half)
            $fatal(1,"Full reset retained mode or fractional score");
        $display("PASS tb_game: latched one/two-ball mode, half-point scoring/carry, bouncing charge, fourteen contacts, collections, combos, save, queued scores, simultaneous pause/resume/drain priorities, saturation");
        $finish;
    end
endmodule
