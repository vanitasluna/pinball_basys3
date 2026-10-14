`timescale 1ns/1ps
module tb_renderer;
    reg [6:0] x=0,ball_x=39,cursor_x=70;
    reg [5:0] y=0,ball_y=43,charge=47,cursor_y=40;
    reg [6:0] ball2_x=55;
    reg [5:0] ball2_y=38;
    reg two_ball_mode=0;
    reg [1:0] balls_visible=2'b01;
    reg [13:0] moving_bumper_y_fp=14'd5632;
    reg [14:0] moving_bumper_x_fp=15'd14848;
    reg [2:0] state=2,left_angle=4,right_angle=1;
    reg [15:0] score_bcd=16'h0018,high_bcd=16'h0092;
    reg [1:0] lives=3,difficulty=1,bonus_target=1;
    reg [13:0] hit_flash=0;
    reg bonus_active=1,cursor_visible=0;
    reg [7:0] anim=39;
    reg [2:0] combo=4,mission_progress=3'b101,feature_event=0;
    reg [1:0] target_progress=2'b01;
    reg [5:0] table_progress=6'b101011;
    reg [3:0] spinner_phase=0;
    reg [10:0] save_timer=0;
    reg [9:0] feature_timer=0;
    reg [15:0] last_award_bcd=16'h0005;
    reg [55:0] oled_trail_x=0;
    reg [47:0] oled_trail_y=0;
    reg [7:0] trail_valid=8'hFF;
    wire [15:0] pixel;
    pinball_renderer dut(.*);
    integer s,xx,yy,f,i;
    reg [8*80-1:0] path;
    reg [15:0] hidden_ball1_pixel,hidden_ball2_pixel;
    reg [15:0] cursor_top_pixel;
    reg [15:0] hidden_cat_pixel;
    task expect_pixel;
        input [6:0] px;
        input [5:0] py;
        input [15:0] expected;
        begin
            x=px;y=py;#1;
            if(pixel!==expected)$fatal(1,"OLED pixel x%0d,y%0d got%04h expected%04h",px,py,pixel,expected);
        end
    endtask
    initial begin
        for(i=0;i<8;i=i+1) begin
            oled_trail_x[i*7+:7]=39-i;
            oled_trail_y[i*6+:6]=43+(i/2);
        end
        expect_pixel(33,1,16'hFFFF); // Actual x4 combo.
        save_timer=300;expect_pixel(75,1,16'h07FF);save_timer=0; // Save S.
        expect_pixel(26,18,16'hFEA0);
        expect_pixel(58,18,16'h4A8A);
        expect_pixel(25,14,16'hFEA0); // Completed rollover lamp.
        expect_pixel(59,14,16'h4A8A); // Unlit third rollover.
        expect_pixel(34,20,16'hFD20); // First stand-up target is complete.
        expect_pixel(42,20,16'h800D); // Middle stand-up target is incomplete.
        expect_pixel(17,41,16'h800D); // Radius3 diamond sling.
        expect_pixel(20,41,16'hF89D);
        hit_flash[9]=1;expect_pixel(17,41,16'hFEA0);hit_flash[9]=0;
        // Every new object responds only to its own registered hit event.
        table_progress=0;
        for(i=0;i<3;i=i+1) begin
            hit_flash=14'd1<<(5+i);expect_pixel(25+i*17,14,16'hFFFF);
            hit_flash=14'd1<<(5+((i+1)%3));expect_pixel(25+i*17,14,16'h4A8A);
            hit_flash=14'd1<<(11+i);expect_pixel(34+i*8,20,16'hFFFF);
            hit_flash=14'd1<<(11+((i+1)%3));expect_pixel(34+i*8,20,16'h800D);
        end
        hit_flash=14'd1<<8;expect_pixel(46,27,16'hFFFF);
        hit_flash=14'd1<<9;expect_pixel(46,27,16'h07FF);
        hit_flash=14'd1<<9;expect_pixel(17,41,16'hFEA0);
        hit_flash=14'd1<<10;expect_pixel(17,41,16'h800D);
        hit_flash=14'd1<<10;expect_pixel(69,41,16'hFEA0);
        hit_flash=14'd1<<9;expect_pixel(69,41,16'h800D);
        hit_flash=0;table_progress=6'b101011;
        expect_pixel(46,27,16'h07FF); // Spinner halfwidth4.
        spinner_phase=4;x=46;y=27;#1;
        if(pixel===16'h07FF)$fatal(1,"OLED spinner did not turn edge-on");
        spinner_phase=0;
        expect_pixel(39,43,16'hEF7D); // Radius1 readable ball.
        expect_pixel(40,43,16'hD69A);
        x=41;y=43;#1;if(pixel===16'hD69A)$fatal(1,"OLED ball extends beyond radius1");
        expect_pixel(26,19,16'hFEA0); // Radius3 bumper rim.
        x=26;y=18;#1;if(dut.in_b0)$fatal(1,"OLED bumper extends beyond radius3");
        // Both moving bumper corridors remain matched to their Q8 snapshots.
        // Mission lamps, highlights and hit rings follow the physical centre.
        moving_bumper_y_fp=14'd7168;moving_bumper_x_fp=15'd16896; //28 and66.
        expect_pixel(26,24,16'hFEA0);
        expect_pixel(66,18,16'h4A8A);
        expect_pixel(26,22,16'h126B); // Vacated origin is the dim route.
        expect_pixel(58,22,16'h126B);
        bonus_active=0;mission_progress=0;
        expect_pixel(26,28,16'hF89D);
        expect_pixel(66,22,16'hF89D);
        expect_pixel(26,26,16'hFFFF); // Gloss translates with the body.
        x=26;y=19;#1;
        if(dut.in_b0 || pixel===16'hFEA0)$fatal(1,"Old left bumper rim left a ghost");
        x=58;y=19;#1;
        if(dut.in_b1 || pixel===16'h07FF)$fatal(1,"Old right bumper rim left a ghost");
        hit_flash=1;expect_pixel(26,28,16'hFFFF);
        expect_pixel(29,31,16'hFEA0); // Expanding diamond at the moved centre.
        hit_flash=2;expect_pixel(66,22,16'hFFFF);
        expect_pixel(69,25,16'hFEA0);
        hit_flash=0;
        moving_bumper_y_fp=14'd6432;moving_bumper_x_fp=15'd15904; //25.125 and62.125.
        expect_pixel(26,25,16'hF89D);
        expect_pixel(62,22,16'hF89D);
        if(dut.moving_bumper_y!==25 || dut.moving_bumper_x!==62)
            $fatal(1,"OLED must floor the same Q8 bumper positions used by VGA");
        moving_bumper_y_fp=14'd5632;moving_bumper_x_fp=15'd14848;
        bonus_active=1;mission_progress=3'b101;
        // Award badges occupy only the former combo/L slot: every score digit
        // and life remains readable even during sustained award activity.
        feature_timer=100;feature_event=7;
        expect_pixel(25,14,16'hFEA0);
        expect_pixel(4,1,16'hFFFF); // Score S stays white.
        expect_pixel(52,1,16'hF9A8); // First heart stays red.
        expect_pixel(59,1,16'hF9A8); // Second heart stays red.
        expect_pixel(66,1,16'hF9A8); // Third heart stays red.
        x=27;y=1;#1;if(dut.glyph!=="8")$fatal(1,"Award badge overwrites last score digit");
        // Scoreless nudge/save messages cannot show a stale prior award.
        feature_event=6;expect_pixel(31,1,16'hF89D);
        x=47;y=1;#1;if(dut.glyph!==" ")$fatal(1,"Nudge badge shows a stale award");
        feature_event=4;expect_pixel(47,1,16'h0844);
        feature_event=7;expect_pixel(32,3,16'hFEA0); // Plus-sign award is drawn.
        ball_x=32;ball_y=3; // HUD positions cannot be physical ball positions.
        ball_x=39;ball_y=43;
        expect_pixel(39,43,16'hEF7D);
        // Each live ball has its own visibility mask, including the case in
        // which the white ball drains first and the gold ball keeps playing.
        balls_visible=0;expect_pixel(55,38,16'h1048);
        hidden_ball2_pixel=pixel;
        x=39;y=43;#1;hidden_ball1_pixel=pixel;
        two_ball_mode=1;balls_visible=2'b11;
        expect_pixel(39,43,16'hEF7D);
        expect_pixel(55,38,16'hFEA0);
        expect_pixel(56,38,16'hB260);
        expect_pixel(55,39,16'hFD20);
        x=56;y=39;#1;
        if(dut.on_ball2)$fatal(1,"OLED second ball extends outside its radius1 cross");
        balls_visible=2'b10;
        expect_pixel(39,43,hidden_ball1_pixel);
        expect_pixel(55,38,16'hFEA0);
        balls_visible=2'b01;expect_pixel(55,38,hidden_ball2_pixel);
        // Disabling two-ball mode must suppress a stale visibility bit.
        two_ball_mode=0;balls_visible=2'b11;expect_pixel(55,38,hidden_ball2_pixel);
        two_ball_mode=1;balls_visible=2'b11;
        // Protection tints both live balls and the existing shared trail.
        // Expiry restores their individual palettes without changing masks.
        save_timer=300;
        expect_pixel(78,1,16'h07FF); // S2: ceil(300/240), not truncated1.
        if(dut.glyph!=="2")$fatal(1,"OLED save countdown is not ceiling seconds");
        expect_pixel(39,43,16'h05BF);expect_pixel(55,38,16'h05BF);
        expect_pixel(55,37,16'h6EFF);expect_pixel(56,38,16'h0297);
        expect_pixel(36,44,16'h0359);expect_pixel(33,46,16'h0212);
        balls_visible=2'b10;
        expect_pixel(39,43,16'h04DF); // Trail remains; the drained sprite does not.
        expect_pixel(55,38,16'h05BF);
        balls_visible=2'b01;expect_pixel(55,38,hidden_ball2_pixel);
        balls_visible=2'b11;save_timer=1;
        cursor_visible=1;cursor_x=38;cursor_y=42;
        expect_pixel(39,43,16'h05BF);
        cursor_x=54;cursor_y=37;expect_pixel(55,38,16'h05BF);
        cursor_visible=0;cursor_x=70;cursor_y=40;
        save_timer=0;
        expect_pixel(39,43,16'hEF7D);expect_pixel(55,38,16'hFEA0);
        expect_pixel(36,44,16'h34D1);expect_pixel(33,46,16'h21CB);
        feature_event=7;feature_timer=100;
        expect_pixel(55,38,16'hFEA0); // Effects remain underneath ball 2.
        cursor_visible=1;cursor_x=38;cursor_y=42;
        expect_pixel(39,43,16'hEF7D); // Pointer's black interior cannot hide white.
        cursor_x=54;cursor_y=37;
        expect_pixel(55,38,16'hFEA0); // Or the remaining gold ball.
        cursor_visible=0;cursor_x=70;cursor_y=40;
        ball2_x=56;expect_pixel(56,38,16'hFEA0);ball2_x=55;
        state=1;ball_x=89;ball_y=56;ball2_x=89;ball2_y=60;
        expect_pixel(89,56,16'hEF7D);expect_pixel(89,60,16'hFEA0);
        save_timer=1;expect_pixel(89,56,16'h05BF);expect_pixel(89,60,16'h05BF);
        state=3;expect_pixel(89,56,16'h02CF);expect_pixel(89,60,16'h02CF);
        save_timer=0;
        state=3;expect_pixel(89,56,16'h73AE);expect_pixel(89,60,16'h7B40);
        balls_visible=2'b01;x=89;y=60;#1;
        if(dut.on_ball2)$fatal(1,"Paused OLED draws a drained second ball");
        state=2;ball_x=39;ball_y=43;ball2_x=55;ball2_y=38;
        two_ball_mode=0;balls_visible=2'b01;
        // The three-pixel pointer arm clips at row63 instead of wrapping its
        // six-bit coordinate arithmetic and disappearing near the lower edge.
        feature_timer=0;cursor_visible=1;cursor_x=70;cursor_y=61;
        expect_pixel(70,62,16'hFEA0);expect_pixel(70,63,16'hFEA0);
        cursor_x=95;
        expect_pixel(95,61,16'hFEA0);expect_pixel(95,63,16'hFEA0);
        cursor_visible=0;x=71;y=0;#1;cursor_top_pixel=pixel;
        cursor_visible=1;cursor_x=70;cursor_y=63;
        expect_pixel(70,63,16'hFEA0);expect_pixel(71,0,cursor_top_pixel);
        cursor_visible=0;cursor_x=70;cursor_y=40;
        // Physical OLED text confirms the shared logical menu click rows.
        feature_timer=0;feature_event=0;state=0;cursor_visible=0;
        x=30;y=23;#1;
        if(dut.glyph!=="U")$fatal(1,"OLED menu does not identify U as the ball-mode key");
        x=35;y=24;#1;
        if(dut.glyph!==":" || pixel!==16'hFEA0)
            $fatal(1,"OLED ball-mode label separator is missing");
        x=42;y=23;#1;
        if(dut.glyph!=="1")$fatal(1,"OLED menu does not label one-ball mode");
        two_ball_mode=1;x=42;y=23;#1;
        if(dut.glyph!=="2")$fatal(1,"OLED menu does not label two-ball mode");
        two_ball_mode=0;
        x=36;y=33;#1;
        if(dut.glyph!=="N" || pixel!==16'hFEA0)
            $fatal(1,"OLED difficulty label is absent from shared mouse row33");
        x=32;y=43;#1;
        if(dut.glyph!=="C" || pixel!==16'h0844)
            $fatal(1,"OLED start prompt moved away from shared mouse row43");
        state=3;x=30;y=41;#1;
        if(dut.glyph!=="U")$fatal(1,"OLED pause resume prompt moved outside shared39..45 rows");
        state=4;balls_visible=0;x=28;y=49;#1;
        if(dut.glyph!=="C")$fatal(1,"OLED restart prompt moved outside shared49..53 rows");
        x=64;y=34;#1;
        if(dut.glyph!=="8")$fatal(1,"OLED game-over score lost its fourth BCD digit");
        x=62;y=41;#1;
        if(dut.glyph!=="2")$fatal(1,"OLED game-over best score lost its fourth BCD digit");
        // Hover must be visible and stay inside the shared logical click bands.
        state=0;cursor_visible=0;cursor_x=48;cursor_y=32;
        expect_pixel(73,35,16'h501B);
        cursor_visible=1;expect_pixel(73,35,16'h07FF);
        cursor_x=74;expect_pixel(73,35,16'h501B);
        cursor_x=24;cursor_y=22;expect_pixel(72,25,16'h07FF);
        cursor_x=23;expect_pixel(72,25,16'h501B);
        cursor_x=24;cursor_y=43;expect_pixel(72,45,16'hFFFF);
        cursor_y=42;expect_pixel(72,45,16'h07FF);
        state=3;cursor_y=39;expect_pixel(72,42,16'hFFFF);
        cursor_y=38;expect_pixel(72,42,16'h07FF);
        state=4;cursor_y=49;expect_pixel(72,51,16'hFFFF);
        cursor_y=48;expect_pixel(72,51,16'h07FF);
        cursor_visible=0;cursor_x=70;cursor_y=40;
        // The save digit covers each boundary without a divider, and survives
        // a pause because it reads the same frozen scene timer as the blue ball.
        state=2;
        for(i=1;i<=6;i=i+1) begin
            save_timer=(i-1)*240+1;x=78;y=1;#1;
            if(dut.glyph!==8'd48+i)$fatal(1,"Wrong OLED save seconds at first tick %0d",save_timer);
            save_timer=i*240;#1;
            if(dut.glyph!==8'd48+i)$fatal(1,"Wrong OLED save seconds at last tick %0d",save_timer);
        end
        save_timer=0;#1;if(dut.save_seconds!==0)$fatal(1,"Expired save count remains nonzero");
        two_ball_mode=1;balls_visible=2'b11;
        expect_pixel(92,1,16'hFFFF);expect_pixel(92,4,16'hFEA0);
        balls_visible=2'b10;expect_pixel(92,1,16'h4A8A);expect_pixel(92,4,16'hFEA0);
        save_timer=1;expect_pixel(92,4,16'h05BF);
        // A segmented charge gauge encodes useful/strong power in color.
        state=1;save_timer=0;charge=63;
        expect_pixel(20,14,16'h07FF);expect_pixel(36,14,16'hFEA0);
        expect_pixel(60,14,16'hF89D);expect_pixel(18,14,16'h0843);
        charge=0;expect_pixel(20,14,16'h0843);
        charge=47;two_ball_mode=0;balls_visible=1;
        // Original circuit-cat reactions activate only for the first half of
        // major award/nudge/save notifications. Ordinary combos never sustain
        // the cameo, and modal screens cannot display a stale expression.
        state=2;save_timer=0;feature_timer=240;anim=0;
        for(i=1;i<=7;i=i+1) begin
            feature_event=i;
            expect_pixel(6,12,i==2 ? 16'h1048 : 16'h07FF);
        end
        feature_event=2;combo=1;expect_pixel(6,12,16'h1048);
        combo=4;expect_pixel(6,12,16'h1048);
        feature_event=0;expect_pixel(6,12,16'h1048);
        feature_event=3;feature_timer=120;expect_pixel(6,12,16'h1048);
        feature_timer=121;expect_pixel(6,12,16'h07FF);
        feature_timer=0;expect_pixel(6,12,16'h1048);
        feature_timer=240;
        expect_pixel(8,15,16'hFEA0); // Open joy eye.
        expect_pixel(7,16,16'h2810);
        anim=16;expect_pixel(7,16,16'hFFFF); // Happy blinking eye.
        anim=0;feature_event=6;
        expect_pixel(10,18,16'hFFFF); // Panic opens a rectangular mouth.
        expect_pixel(18,12,16'h05BF); // Cyan comic sweat drop.
        feature_event=4;expect_pixel(7,16,16'hFFFF); // Relieved closed eyes.
        expect_pixel(10,18,16'h2810); // Smile keeps the middle mouth row dark.
        feature_event=3;expect_pixel(19,12,16'h1048); // Clipped safe-gap footprint.
        expect_pixel(4,1,16'hFFFF);expect_pixel(52,1,16'hF9A8);
        for(s=0;s<5;s=s+1) begin
            if(s!=2) begin
                state=s;feature_event=0;x=6;y=12;#1;hidden_cat_pixel=pixel;
                feature_event=3;expect_pixel(6,12,hidden_cat_pixel);
            end
        end
        state=1;feature_event=4;
        expect_pixel(6,20,16'h07FF); // Saved READY pose shifts below charge bar.
        expect_pixel(6,12,16'h1048);
        expect_pixel(20,14,16'h07FF); // Charge UI remains fully readable.
        feature_timer=120;expect_pixel(6,20,16'h1048);
        state=2;feature_event=3;feature_timer=240;trail_valid=1;
        oled_trail_x[6:0]=6;oled_trail_y[5:0]=12;
        expect_pixel(6,12,16'h7BF0); // Trail paints above the cameo.
        save_timer=300;expect_pixel(6,12,16'h04DF);
        trail_valid=0;ball_x=6;ball_y=12;save_timer=0;
        expect_pixel(6,12,16'hEF7D); // Live white sprite has final priority.
        save_timer=300;expect_pixel(6,12,16'h05BF);
        two_ball_mode=1;balls_visible=2'b10;ball2_x=6;ball2_y=12;
        save_timer=0;expect_pixel(6,12,16'hFEA0);
        save_timer=300;expect_pixel(6,12,16'h05BF);
        two_ball_mode=0;balls_visible=1;ball_x=39;ball_y=43;
        ball2_x=55;ball2_y=38;feature_timer=0;feature_event=0;anim=39;
        for(i=0;i<8;i=i+1) begin
            oled_trail_x[i*7+:7]=39-i;
            oled_trail_y[i*6+:6]=43+(i/2);
        end
        for(s=0;s<6;s=s+1) begin
            state=s==5 ? 2 : s;
            lives=state==4 ? 0 : 3;balls_visible=state==4 ? 0 : 1;
            save_timer=(state==0 || state==1 || state==4) ? 0 : 300;combo=state==4 ? 1 : 4;
            feature_event=s==5 ? 7 : 0;
            feature_timer=s==5 ? 100 : 0;
            ball_x=s==1 ? 89 : 39;ball_y=s==1 ? 56 : 43;
            trail_valid=s==1 ? 0 : 8'hFF;
            cursor_visible=s==0;
            spinner_phase=s==2 ? 3 : 0;
            $sformat(path,"../render_%0d.hex",s);
            f=$fopen(path,"w");if(!f)$fatal(1,"Cannot open OLED render output");
            for(yy=0;yy<64;yy=yy+1) for(xx=0;xx<96;xx=xx+1) begin
                x=xx;y=yy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown OLED pixel state%0d x%0d y%0d",s,xx,yy);
                $fdisplay(f,"%04x",pixel);
            end
            $fclose(f);
        end
        // Three PLAY snapshots expose endpoints and a fractional midpoint for
        // visual QA. These supplementary files use the same RGB565 hex format.
        state=2;cursor_visible=0;feature_event=0;feature_timer=0;
        lives=3;balls_visible=1;
        save_timer=300;combo=4;
        for(s=0;s<3;s=s+1) begin
            moving_bumper_y_fp=s==0 ? 14'd5632 : s==1 ? 14'd6432 : 14'd7168;
            moving_bumper_x_fp=s==0 ? 15'd14848 : s==1 ? 15'd15904 : 15'd16896;
            hit_flash=s==2 ? 14'd3 : 0;
            $sformat(path,"../render_motion_%0d.hex",s);
            f=$fopen(path,"w");if(!f)$fatal(1,"Cannot open OLED motion output");
            for(yy=0;yy<64;yy=yy+1) for(xx=0;xx<96;xx=xx+1) begin
                x=xx;y=yy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown moving OLED pixel frame%0d",s);
                $fdisplay(f,"%04x",pixel);
            end
            $fclose(f);
        end
        // New full-frame samples cover the menu selection, both queued balls,
        // simultaneous play and continued play after ball 1 drains.
        two_ball_mode=1;feature_timer=0;hit_flash=0;save_timer=0;
        for(s=0;s<4;s=s+1) begin
            state=s<2 ? s : 2;
            balls_visible=s==3 ? 2'b10 : 2'b11;
            ball_x=s==1 ? 89 : 39;ball_y=s==1 ? 56 : 43;
            ball2_x=s==1 ? 89 : 55;ball2_y=s==1 ? 60 : 38;
            trail_valid=s<2 ? 0 : 8'hFF;
            $sformat(path,"../render_multiball_%0d.hex",s);
            f=$fopen(path,"w");if(!f)$fatal(1,"Cannot open OLED two-ball output");
            for(yy=0;yy<64;yy=yy+1) for(xx=0;xx<96;xx=xx+1) begin
                x=xx;y=yy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown two-ball OLED pixel frame%0d",s);
                $fdisplay(f,"%04x",pixel);
            end
            $fclose(f);
        end
        // Three matching reaction captures: jackpot joy, nudge panic, and a
        // saved READY relief pose. These retain both normal ball palettes and
        // the existing bright-blue protection display contract.
        moving_bumper_y_fp=14'd5632;moving_bumper_x_fp=15'd14848;
        two_ball_mode=1;balls_visible=2'b11;hit_flash=0;feature_timer=180;
        for(s=0;s<3;s=s+1) begin
            state=s==2 ? 1 : 2;
            feature_event=s==0 ? 3 : s==1 ? 6 : 4;
            anim=s==0 ? 0 : s==1 ? 8 : 16;
            // A saved turn has consumed its protection. Match the native
            // examples: protected PLAY, then an unprotected READY relaunch.
            save_timer=s==2 ? 0 : 300;charge=s==2 ? 0 : 47;
            ball_x=s==2 ? 89 : 39;ball_y=s==2 ? 56 : 43;
            ball2_x=s==2 ? 89 : 55;ball2_y=s==2 ? 60 : 38;
            trail_valid=s==2 ? 0 : 8'hFF;
            $sformat(path,"../render_funny_%0d.hex",s);
            f=$fopen(path,"w");if(!f)$fatal(1,"Cannot open OLED reaction output");
            for(yy=0;yy<64;yy=yy+1) for(xx=0;xx<96;xx=xx+1) begin
                x=xx;y=yy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown OLED reaction pixel frame%0d",s);
                $fdisplay(f,"%04x",pixel);
            end
            $fclose(f);
        end
        $display("PASS tb_renderer: bounded original reactions, persistent HUD, independent two-ball visibility/menu/queued sprites, moving bumpers and sixteen complete frames (98304 pixels)");
        $finish;
    end
endmodule
