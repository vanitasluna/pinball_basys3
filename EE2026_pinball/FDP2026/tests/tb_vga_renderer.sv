`timescale 1ns / 1ps
module tb_vga_renderer;
    reg [9:0] x=0,y=0;
    reg [2:0] state=2;
    reg [14:0] ball_x_fp=15'd10112; //39.5 Q8 -> native x=332
    reg [13:0] ball_y_fp=14'd11136; //43.5 Q8 -> native y=380
    reg [14:0] ball2_x_fp=15'd14208; //55.5 -> native x460.
    reg [13:0] ball2_y_fp=14'd9856; //38.5 -> native y340.
    reg two_ball_mode=0;
    reg [1:0] balls_visible=2'b01;
    reg [13:0] moving_bumper_y_fp=14'd5632;
    reg [14:0] moving_bumper_x_fp=15'd14848;
    reg [13:0] side_left_y_fp=14'd8448,side_right_y_fp=14'd8448;
    reg [2:0] left_angle=4,right_angle=1;
    reg [15:0] score_bcd=16'h0018,high_bcd=16'h0092;
    reg [1:0] lives=3,difficulty=1;
    reg [5:0] charge=47;
    reg [13:0] hit_flash=0;
    reg [1:0] bonus_target=1;
    reg bonus_active=1;
    reg [7:0] anim=8'd39;
    reg [6:0] cursor_x=70;
    reg [5:0] cursor_y=40;
    reg cursor_visible=0;
    reg [2:0] combo=4,mission_progress=3'b101;
    reg [1:0] target_progress=2'b01;
    reg [5:0] table_progress=6'b101011;
    reg [3:0] spinner_phase=0;
    reg [10:0] save_timer=0;
    reg [2:0] feature_event=0;
    reg [9:0] feature_timer=0;
    reg [15:0] last_award_bcd=16'h0005;
    reg [79:0] particle_x=0,particle_y=0,trail_x=0,trail_y=0;
    reg [31:0] particle_life=0;
    reg [7:0] trail_valid=8'hFF;
    wire [15:0] pixel;
    pinball_vga_renderer dut(.*);
    integer fd,frame,ix,iy,i;
    reg [15:0] edge_pixel;
    reg [15:0] hidden_ball1_pixel,hidden_ball2_pixel;
    reg [15:0] cat_background;
    reg [255:0] filename;
    task expect_pixel;
        input [9:0] px,py;
        input [15:0] expected;
        begin
            x=px;y=py;#1;
            if(pixel!==expected)$fatal(1,"Native pixel %0d,%0d got %04h expected %04h",px,py,pixel,expected);
        end
    endtask
    task expect_countdown;
        input integer ticks,seconds;
        begin
            save_timer=ticks;x=688;y=554;#1;
            if(seconds!=0) begin
                if(!dut.text_enable || dut.text_message!==43 || dut.glyph!==8'd48+seconds)
                    $fatal(1,"Protection countdown ticks%0d got glyph%0d expected%0d",ticks,dut.glyph,seconds);
            end else begin
                x=608;#1;
                if(!dut.text_enable || dut.text_message!==44 || dut.glyph!=="N")
                    $fatal(1,"Expired protection must show NO SAVE");
            end
        end
    endtask
    initial begin
        // Overlapping seven-pixel trail squares must retain their newest
        // sample's brightness, rather than being darkened by older history.
        for(i=0;i<8;i=i+1) begin
            trail_x[i*10+:10]=136;trail_y[i*10+:10]=224;
        end
        save_timer=300;trail_valid=8'h81;expect_pixel(136,224,16'h04DF);
        save_timer=0;expect_pixel(136,224,16'h4DF9);
        trail_valid=8'h80;expect_pixel(136,224,16'h194B);
        save_timer=300;expect_pixel(136,224,16'h0212);
        trail_valid=8'h08;expect_pixel(136,224,16'h0359);
        save_timer=0;expect_pixel(136,224,16'h2353);
        trail_valid=8'hFF;
        for(i=0;i<8;i=i+1) begin
            trail_x[i*10+:10]=332-i*8;
            trail_y[i*10+:10]=380+i*5;
            particle_x[i*10+:10]=480+((i%4)*16)-24;
            particle_y[i*10+:10]=208+((i/4)*48)-24;
            particle_life[i*4+:4]=15-i;
        end
        #1;
        if(dut.ball_cx!==10'd332 || dut.ball_cy!==10'd380)
            $fatal(1,"Q8 position did not map correctly into 800x600 raster");
        expect_pixel(332,380,16'hE71C);
        expect_pixel(340,380,16'hE71C); // Smaller circle has physical radius8.
        edge_pixel=pixel;
        x=341;y=380;#1;
        if(pixel===edge_pixel)$fatal(1,"Native ball extends beyond radius8");
        expect_pixel(224,184,16'hFF20); // Radius3 logical =>24 native.
        expect_pixel(224,208,16'hFFFF);
        // Endpoint travel moves all layers and retains the entire lower rim.
        moving_bumper_y_fp=14'd7168;moving_bumper_x_fp=15'd16896;
        expect_pixel(224,256,16'hFFFF);
        expect_pixel(224,280,16'hFF20); // Previously clipped by fixed row split.
        expect_pixel(544,208,16'hFFFF);
        expect_pixel(568,208,16'hFF20);
        expect_pixel(224,224,16'hFF20); // Moving local mission lamp.
        expect_pixel(544,176,16'h6B6E);
        expect_pixel(224,208,16'h126B); // No face at the vacated start position.
        expect_pixel(480,208,16'h126B);
        bonus_active=0;mission_progress=0;
        expect_pixel(224,280,16'h07FF);
        expect_pixel(568,208,16'h07FF);
        expect_pixel(216,248,16'hFFFF); // Gloss follows the moved circle.
        x=224;y=184;#1;
        if(dut.near_bumper)$fatal(1,"Old left bumper rim left a native ghost");
        x=480;y=184;#1;
        if(dut.near_bumper)$fatal(1,"Old right bumper rim left a native ghost");
        hit_flash=1;expect_pixel(224,266,16'hFF20);
        expect_pixel(254,256,16'hFFFF); // Impact ring about the new centre.
        hit_flash=2;expect_pixel(554,208,16'hFF20);
        expect_pixel(574,208,16'hFFFF);
        hit_flash=0;
        // Fractional Q8 movement resolves every 1/8 logical pixel on VGA.
        moving_bumper_y_fp=14'd6432;moving_bumper_x_fp=15'd15904;
        x=224;y=233;#1;
        if(dut.bumper_cy!==233 || pixel!==16'hFFFF)
            $fatal(1,"Vertical native bumper fractional position was lost");
        x=513;y=208;#1;
        if(dut.bumper_cx!==513 || pixel!==16'hFFFF)
            $fatal(1,"Horizontal native bumper fractional position was lost");
        moving_bumper_y_fp=14'd5632;moving_bumper_x_fp=15'd14848;
        bonus_active=1;mission_progress=3'b101;
        // Side-bank native faces preserve fractional Q8 vertical movement.
        side_left_y_fp=14'd7552;side_right_y_fp=14'd9344; //29.5 and36.5.
        expect_pixel(64,244,16'hFFFF);expect_pixel(64,268,16'hFF20);
        expect_pixel(640,324,16'h700D);expect_pixel(648,348,16'hF89D);
        expect_pixel(73,268,16'h1048);expect_pixel(649,324,16'h1048);
        side_left_y_fp=14'd7584;expect_pixel(68,245,16'hFFFF); // +1 native pixel.
        x=68;y=244;#1;if(pixel===16'hFFFF)$fatal(1,"Native side target lost fractional movement");
        side_left_y_fp=14'd9472;side_right_y_fp=14'd7424; //37 and29.
        expect_pixel(64,352,16'hF89D);expect_pixel(648,240,16'hFFFF);
        hit_flash=14'd8;expect_pixel(64,328,16'hFFFF);expect_pixel(640,264,16'h700D);
        hit_flash=14'd16;expect_pixel(64,328,16'hFF20);expect_pixel(640,264,16'hFFFF);
        hit_flash=0;side_left_y_fp=14'd8448;side_right_y_fp=14'd8448;
        expect_pixel(216,144,16'hFF20); // Completed rollover lane lamp.
        expect_pixel(488,144,16'h6B6E); // Incomplete third lane lamp.
        expect_pixel(288,192,16'hFC80); // Completed first stand-up target.
        expect_pixel(352,192,16'h800D); // Incomplete central stand-up.
        expect_pixel(152,360,16'hD019); // Diamond centre.
        expect_pixel(176,360,16'hF89D); // Diamond radius24.
        hit_flash[9]=1;expect_pixel(152,360,16'hFFFF);hit_flash[9]=0;
        // Exercise all nine new events independently and reject neighboring hits.
        table_progress=0;
        for(i=0;i<3;i=i+1) begin
            hit_flash=14'd1<<(5+i);expect_pixel(216+i*136,144,16'hFFFF);
            hit_flash=14'd1<<(5+((i+1)%3));expect_pixel(216+i*136,144,16'h6B6E);
            hit_flash=14'd1<<(11+i);expect_pixel(288+i*64,192,16'hFFFF);
            hit_flash=14'd1<<(11+((i+1)%3));expect_pixel(288+i*64,192,16'h800D);
        end
        hit_flash=14'd1<<8;expect_pixel(384,248,16'hFFFF);
        hit_flash=14'd1<<9;expect_pixel(384,248,16'h07FF);
        hit_flash=14'd1<<9;expect_pixel(152,360,16'hFFFF);
        hit_flash=14'd1<<10;expect_pixel(152,360,16'hD019);
        hit_flash=14'd1<<10;expect_pixel(568,360,16'hFFFF);
        hit_flash=14'd1<<9;expect_pixel(568,360,16'hD019);
        hit_flash=0;table_progress=6'b101011;
        expect_pixel(384,248,16'h07FF); // Face-on spinner halfwidth32.
        spinner_phase=4;x=384;y=248;#1;
        if(pixel===16'h07FF)$fatal(1,"Spinner did not turn edge-on");
        expect_pixel(352,248,16'hFFFF);spinner_phase=0;
        x=153;y=554;#1;
        if(dut.glyph!==8'd52)$fatal(1,"Combo HUD must show actual x4 multiplier");
        // Native fractional motion resolves one-eighth of an OLED pixel.
        ball_x_fp=10144;x=333;y=380;#1;
        if(dut.ball_cx!==333 || pixel!==16'hE71C)$fatal(1,"Subpixel ball motion lost");
        ball_x_fp=10112;
        feature_event=7;feature_timer=100;
        expect_pixel(332,380,16'hE71C); // Table bonus never covers live ball.
        // Even a corrupt particle directly over the live ball remains underneath.
        particle_x[9:0]=332;particle_y[9:0]=380;particle_life[3:0]=15;
        expect_pixel(332,380,16'hE71C);
        particle_x[9:0]=400;particle_y[9:0]=350;
        expect_pixel(400,350,16'hFFFF);
        // Footer award digits are absent for non-scoring feedback.
        feature_event=6;expect_pixel(386,564,16'h0843);
        feature_event=4;expect_pixel(386,564,16'h0843);
        feature_event=7;expect_pixel(386,564,16'hFFFF);
        // Visibility is independent: either ball may drain while the other
        // remains live. Ball 2 uses no squared-distance hardware.
        balls_visible=0;x=332;y=380;#1;hidden_ball1_pixel=pixel;
        x=460;y=340;#1;hidden_ball2_pixel=pixel;
        two_ball_mode=1;balls_visible=2'b11;
        x=392;y=12;#1;
        if(dut.glyph!=="2" || dut.text_message!==47)$fatal(1,"Header omits the live pair");
        expect_pixel(332,380,16'hE71C);expect_pixel(460,340,16'hFF20);
        expect_pixel(468,340,16'hFF20);
        x=469;y=340;#1;if(dut.on_ball2)$fatal(1,"Native second ball extends beyond radius8");
        x=468;y=348;#1;if(dut.on_ball2)$fatal(1,"Native second-ball chamfer is missing");
        balls_visible=2'b10;
        x=392;y=12;#1;
        if(dut.glyph!=="L" || dut.text_message!==45 || pixel!==16'hF89D)
            $fatal(1,"Header does not identify a surviving gold ball");
        expect_pixel(332,380,hidden_ball1_pixel);expect_pixel(460,340,16'hFF20);
        balls_visible=2'b01;expect_pixel(460,340,hidden_ball2_pixel);
        x=392;y=12;#1;
        if(dut.glyph!=="L" || dut.text_message!==45)$fatal(1,"White survivor is not reported");
        balls_visible=0;x=440;y=12;#1;
        if(dut.glyph!=="0" || dut.text_message!==42)$fatal(1,"Zero live balls are not reported");
        balls_visible=2'b01;
        two_ball_mode=0;balls_visible=2'b11;expect_pixel(460,340,hidden_ball2_pixel);
        two_ball_mode=1;balls_visible=2'b11;
        ball2_x_fp=14240;ball2_y_fp=9888;x=461;y=341;#1;
        if(dut.ball2_cx!==461 || dut.ball2_cy!==341 || pixel!==16'hFF20)
            $fatal(1,"Second ball fractional Q8 motion was lost");
        ball2_x_fp=14208;ball2_y_fp=9856;
        particle_x[9:0]=460;particle_y[9:0]=340;particle_life[3:0]=15;
        expect_pixel(460,340,16'hFF20); // Both balls stay above particles/text.
        cursor_visible=1;cursor_x=39;cursor_y=43;
        expect_pixel(332,380,16'hE71C); // Pointer diagonal must not conceal white.
        cursor_x=55;cursor_y=38;
        expect_pixel(460,340,16'hFF20); // Nor a surviving gold ball.
        cursor_visible=0;cursor_x=70;cursor_y=40;
        particle_x[9:0]=400;particle_y[9:0]=350;
        save_timer=300;
        expect_pixel(332,380,16'h05BF);expect_pixel(460,340,16'h05BF);
        expect_pixel(328,376,16'h6EFF);expect_pixel(337,385,16'h0297);
        expect_pixel(456,336,16'h6EFF);expect_pixel(465,344,16'h0297);
        expect_pixel(308,395,16'h0359);expect_pixel(284,410,16'h0212);
        balls_visible=2'b10;
        expect_pixel(332,380,16'h04DF); // No drained ball over the protected trail.
        expect_pixel(460,340,16'h05BF);
        balls_visible=2'b01;expect_pixel(460,340,hidden_ball2_pixel);
        balls_visible=2'b11;save_timer=1;
        cursor_visible=1;cursor_x=39;cursor_y=43;
        expect_pixel(332,380,16'h05BF);
        cursor_x=55;cursor_y=38;expect_pixel(460,340,16'h05BF);
        cursor_visible=0;cursor_x=70;cursor_y=40;
        save_timer=0;
        expect_pixel(332,380,16'hE71C);expect_pixel(460,340,16'hFF20);
        expect_pixel(308,395,16'h2353);expect_pixel(284,410,16'h194B);
        state=1;ball_x_fp=22784;ball_y_fp=14336;ball2_x_fp=22784;ball2_y_fp=15360;
        expect_pixel(728,480,16'hE71C);expect_pixel(728,512,16'hFF20);
        save_timer=1;expect_pixel(728,480,16'h05BF);expect_pixel(728,512,16'h05BF);
        state=3;expect_pixel(728,480,16'h02CF);expect_pixel(728,512,16'h02CF);
        save_timer=0;
        state=3;
        // Pause dims both queued sprites consistently, away from the panel.
        expect_pixel(728,480,16'h738E);expect_pixel(728,512,16'h7B80);
        state=2;ball_x_fp=10112;ball_y_fp=11136;ball2_x_fp=14208;ball2_y_fp=9856;
        two_ball_mode=0;balls_visible=2'b01;
        // Message ROMs retain their leading character and correct score units.
        if(dut.message_char(35,0)!=="L" || dut.message_char(35,28)!=="S")
            $fatal(1,"Table bonus instruction was clipped or shifted in message ROM");
        if(dut.message_char(16,18)!=="5" || dut.message_char(16,19)!==0)
            $fatal(1,"Bumper mission instruction does not reflect five-point scoring");
        // Click the visible menu text through the actual shared cursor mapping.
        // These points represent menu actions, not renderer-local coordinates.
        feature_timer=0;feature_event=0;state=0;cursor_visible=0;
        // D-to-menu and game over may retain old gameplay fields. They must
        // not advertise an active combo or a ball-save opportunity there.
        combo=4;save_timer=300;
        expect_pixel(42,554,16'h0842);
        if(dut.text_enable)$fatal(1,"MENU advertises a stale combo");
        expect_pixel(608,554,16'h0842);
        if(dut.text_enable)$fatal(1,"MENU advertises a stale ball save");
        x=328;y=232;#1;
        if(dut.glyph!=="U")$fatal(1,"Native menu does not identify U as the ball-mode key");
        x=344;y=232;#1;
        if(dut.glyph!==":")$fatal(1,"Native ball-mode label separator is missing");
        x=376;y=232;#1;
        if(dut.glyph!=="1")$fatal(1,"Native menu does not label one-ball mode");
        two_ball_mode=1;x=376;y=232;#1;
        if(dut.glyph!=="2")$fatal(1,"Native menu does not label two-ball mode");
        two_ball_mode=0;
        x=460;y=584;#1;
        if(dut.glyph!=="U" || dut.text_message!==39)
            $fatal(1,"Native MENU footer must identify U as ball selection");
        x=312;y=211;#1;
        if(dut.text_enable || pixel!==16'h1008)
            $fatal(1,"Decorative subtitle remains inside the clickable ball-mode band");
        // Button hover follows the real logical input bounds and only an
        // enabled cursor. Hidden/reset cursors cannot light any button.
        expect_pixel(208,240,16'h0250);
        cursor_x=48;cursor_y=25;cursor_visible=1;
        expect_pixel(208,240,16'h07FF);
        cursor_visible=0;expect_pixel(208,240,16'h0250);
        cursor_visible=1;cursor_y=33;
        expect_pixel(192,300,16'h07FF);
        cursor_x=21;expect_pixel(192,300,16'h0250);
        cursor_x=48;cursor_y=45;expect_pixel(208,396,16'h07FF);
        cursor_y=48;expect_pixel(208,396,16'h0250);
        cursor_visible=0;cursor_x=70;cursor_y=40;
        expect_pixel(216,304,16'h07FF);expect_pixel(583,304,16'h07FF);
        x=16+8*42;y=32+8*33;#1; // NORMAL's left half, logical row33.
        if(pixel!==16'hFFFF || dut.glyph!=="N")
            $fatal(1,"Visible native difficulty label does not align with OLED mouse level row");
        x=16+8*52;y=32+8*33;#1; // NORMAL's right half.
        if(pixel!==16'hFFFF || dut.glyph!=="L")
            $fatal(1,"Native difficulty's right half is outside the shared clickable row");
        x=16+8*32;y=32+8*45;#1; // PRESS start prompt, inside shared43..47 band.
        if(pixel!==16'hFFFF || dut.glyph!=="P")
            $fatal(1,"Native start prompt is not on the shared OLED start row");
        state=1;
        expect_pixel(42,554,16'hFF20);expect_pixel(610,554,16'h05BF);
        for(i=1;i<=6;i=i+1) begin
            expect_countdown(i*240,i);
            expect_countdown((i-1)*240+1,i);
        end
        expect_countdown(0,0);save_timer=300;
        state=3;
        expect_pixel(42,554,16'hFF20);expect_pixel(610,554,16'h05BF);
        cursor_visible=1;cursor_x=48;cursor_y=42;
        expect_pixel(208,372,16'h07FF);
        cursor_y=46;expect_pixel(208,372,16'h0250);cursor_visible=0;
        x=336;y=365;#1;
        if(dut.glyph!=="U" || dut.text_message!==40)
            $fatal(1,"Native pause click row must identify only resume");
        expect_pixel(456,365,16'hFFFF); // Last E in RESUME is completely visible.
        x=456;y=584;#1;
        if(dut.glyph!=="U" || dut.text_message!==12)
            $fatal(1,"Native paused footer clips MENU or advertises live controls");
        state=4;balls_visible=0;x=328;y=437;#1;
        if(dut.glyph!=="C" || dut.text_message!==41)
            $fatal(1,"Native restart prompt must occupy shared logical49..53 rows");
        expect_pixel(42,554,16'h0842);
        if(dut.text_enable)$fatal(1,"OVER advertises a stale combo");
        expect_pixel(608,554,16'h0842);
        if(dut.text_enable)$fatal(1,"OVER advertises a stale ball save");
        expect_pixel(464,437,16'hFFFF); // Final T in RESTART, uncut.
        cursor_visible=1;cursor_x=48;cursor_y=51;
        expect_pixel(208,444,16'h07FF);
        cursor_y=48;expect_pixel(208,444,16'h0250);cursor_visible=0;
        expect_pixel(600,450,16'h0844); // Extended OVER panel contains the prompt.
        x=460;y=584;#1;
        if(dut.glyph!=="U" || dut.text_message!==14)
            $fatal(1,"Native OVER footer clips MENU or advertises live controls");
        x=464;y=306;#1;
        if(dut.glyph!=="8")$fatal(1,"Native game-over score lost its fourth BCD digit");
        // Persistent mascot is visible without events in every state, even
        // after opaque menu/modal panels paint. All coordinates remain clear
        // of the existing headings, controls, score and footer.
        state=2;feature_timer=0;feature_event=0;save_timer=0;
        cursor_visible=0;anim=8;balls_visible=1;trail_valid=0;
        for(frame=0;frame<5;frame=frame+1) begin
            state=frame;
            case(frame)
                0:expect_pixel(70,128,16'h07FF);
                1:expect_pixel(70,184,16'h07FF);
                2:expect_pixel(70,128,16'h07FF);
                3:expect_pixel(70,128,16'h07FF);
                4:expect_pixel(70,128,16'h07FF);
            endcase
        end
        state=2;expect_pixel(76,150,16'hFFFF); // Idle open eye.
        anim=0;expect_pixel(76,150,16'h2810); // Brief automatic blink.
        anim=96;expect_pixel(76,154,16'hFFFF); // Playful closed-eye wink + bob.
        anim=168;expect_pixel(76,154,16'hFF20); // Idle cycle reaches gold joy eyes.
        anim=40;expect_pixel(70,130,16'h07FF);
        x=70;y=128;#1;if(pixel===16'h07FF)$fatal(1,"Native breathing pose left old cat outline");
        anim=8;feature_event=3;feature_timer=240;
        expect_pixel(76,152,16'hFF20); // Fresh major reward star-eye spoke.
        x=124;y=141;#1;
        if(dut.glyph!=="Y" || dut.text_message!==48)$fatal(1,"Major reward lacks YATTA caption");
        feature_timer=121;expect_pixel(76,152,16'hFF20);
        feature_timer=120;expect_pixel(76,152,16'hFFFF);
        x=124;y=141;#1;if(dut.comic_caption)$fatal(1,"Expired reward retained speech ink");
        feature_timer=0;expect_pixel(70,128,16'h07FF);
        feature_timer=240;feature_event=2;combo=1;
        expect_pixel(76,152,16'hFFFF);combo=4;expect_pixel(76,152,16'hFFFF);
        feature_event=6;expect_pixel(86,162,16'hF89D); // Panic open mouth.
        x=124;y=141;#1;
        if(dut.glyph!=="N" || dut.text_message!==49)$fatal(1,"Nudge lacks NANI caption");
        state=1;feature_event=4;expect_pixel(70,184,16'h07FF);
        expect_pixel(76,208,16'hFFFF); // Saved-turn wink safely above side target.
        x=124;y=197;#1;
        if(dut.glyph!=="P" || dut.text_message!==50)$fatal(1,"Saved READY turn lacks PHEW caption");
        feature_event=3;x=124;y=197;#1;
        if(dut.comic_caption)$fatal(1,"READY stale reward generated a speech bubble");
        state=3;expect_pixel(76,152,16'hFFFF); // Sleepy closed eye.
        state=4;expect_pixel(76,154,16'h05BF); // Sad eye.
        feature_event=6;expect_pixel(76,154,16'h05BF); // Modal mood beats stale event.
        trail_valid=8'hFF;
        // The cameo cannot cover score/SAFE or either live ball, even when
        // a ball is deliberately placed directly over its face.
        state=2;feature_event=3;feature_timer=240;two_ball_mode=1;balls_visible=3;
        ball_x_fp=2304;ball_y_fp=3776;ball2_x_fp=2816;ball2_y_fp=3968;
        save_timer=0;expect_pixel(88,150,16'hE71C);expect_pixel(104,156,16'hFF20);
        save_timer=1;expect_pixel(88,150,16'h05BF);expect_pixel(104,156,16'h05BF);
        balls_visible=0;expect_pixel(88,150,16'h2810);
        // The same trail predicate keeps motion above face, speech-box border
        // and actual caption ink in both protection palettes.
        trail_x[9:0]=88;trail_y[9:0]=150;
        save_timer=1;expect_pixel(88,150,16'h04DF);
        save_timer=0;expect_pixel(88,150,16'h4DF9);
        trail_x[9:0]=116;trail_y[9:0]=136;
        save_timer=1;expect_pixel(116,136,16'h04DF);
        save_timer=0;expect_pixel(116,136,16'h4DF9);
        trail_x[9:0]=124;trail_y[9:0]=141;
        save_timer=1;expect_pixel(124,141,16'h04DF);
        save_timer=0;expect_pixel(124,141,16'h4DF9);
        if(!dut.comic_caption || !dut.trail_hit)
            $fatal(1,"Comic-caption trail overlap fixture missed its ink gate");
        trail_x[9:0]=332;trail_y[9:0]=380;
        x=120;y=8;#1;
        if(dut.glyph!=="0" || dut.text_message!==7)$fatal(1,"Cameo conceals permanent score");
        expect_countdown(300,2);
        ball_x_fp=10112;ball_y_fp=11136;ball2_x_fp=14208;ball2_y_fp=9856;
        two_ball_mode=0;balls_visible=1;feature_timer=0;feature_event=0;
        // Every visible RTL pixel is checked and retained for visual QA.
        for(frame=0;frame<6;frame=frame+1) begin
            state=frame<5 ? frame : 2;
            lives=state==4 ? 0 : 3;balls_visible=state==4 ? 0 : 1;
            save_timer=(state==0 || state==1 || state==4) ? 0 : 300;combo=state==4 ? 1 : 4;
            ball_x_fp=frame==1 ? 15'd22784 : 15'd10112;
            ball_y_fp=frame==1 ? 14'd14336 : 14'd11136;
            trail_valid=frame==1 ? 0 : 8'hFF;
            feature_event=frame==5 ? 3'd7 : 3'd0;
            feature_timer=frame==5 ? 100 : 0;
            cursor_visible=frame==0;
            spinner_phase=frame==2 ? 3 : 0;
            $sformat(filename,"../vga_render_%0d.hex",frame);
            fd=$fopen(filename,"w");
            if(fd==0)$fatal(1,"Cannot create native VGA render dump");
            for(iy=0;iy<600;iy=iy+1) for(ix=0;ix<800;ix=ix+1) begin
                x=ix;y=iy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown native pixel (%0d,%0d), state%0d",ix,iy,state);
                $fwrite(fd,"%04h\n",pixel);
            end
            $fclose(fd);
            $display("800x600 native RTL frame %0d captured",frame);
        end
        state=2;cursor_visible=0;feature_event=0;feature_timer=0;
        lives=3;balls_visible=1;
        save_timer=300;combo=4;
        for(frame=0;frame<3;frame=frame+1) begin
            moving_bumper_y_fp=frame==0 ? 14'd5632 : frame==1 ? 14'd6432 : 14'd7168;
            moving_bumper_x_fp=frame==0 ? 15'd14848 : frame==1 ? 15'd15904 : 15'd16896;
            side_left_y_fp=frame==0 ? 14'd8448 : frame==1 ? 14'd7552 : 14'd7424;
            side_right_y_fp=frame==0 ? 14'd8448 : frame==1 ? 14'd9344 : 14'd9472;
            hit_flash=frame==2 ? 14'd3 : 0;
            $sformat(filename,"../vga_render_motion_%0d.hex",frame);
            fd=$fopen(filename,"w");if(fd==0)$fatal(1,"Cannot create moving native dump");
            for(iy=0;iy<600;iy=iy+1) for(ix=0;ix<800;ix=ix+1) begin
                x=ix;y=iy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown moving native pixel frame%0d",frame);
                $fwrite(fd,"%04h\n",pixel);
            end
            $fclose(fd);
        end
        two_ball_mode=1;feature_timer=0;hit_flash=0;save_timer=0;
        for(frame=0;frame<4;frame=frame+1) begin
            state=frame<2 ? frame : 2;
            balls_visible=frame==3 ? 2'b10 : 2'b11;
            ball_x_fp=frame==1 ? 15'd22784 : 15'd10112;
            ball_y_fp=frame==1 ? 14'd14336 : 14'd11136;
            ball2_x_fp=frame==1 ? 15'd22784 : 15'd14208;
            ball2_y_fp=frame==1 ? 14'd15360 : 14'd9856;
            trail_valid=frame<2 ? 0 : 8'hFF;
            $sformat(filename,"../vga_render_multiball_%0d.hex",frame);
            fd=$fopen(filename,"w");if(fd==0)$fatal(1,"Cannot create native two-ball dump");
            for(iy=0;iy<600;iy=iy+1) for(ix=0;ix<800;ix=ix+1) begin
                x=ix;y=iy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown native two-ball pixel frame%0d",frame);
                $fwrite(fd,"%04h\n",pixel);
            end
            $fclose(fd);
        end
        // Three supplementary exact RTL frames keep the ordinary scene
        // fixtures stable while exposing reward, panic and saved reactions.
        two_ball_mode=1;balls_visible=3;cursor_visible=0;anim=39;
        feature_timer=240;last_award_bcd=16'h0005;
        for(frame=0;frame<3;frame=frame+1) begin
            state=frame==2 ? 1 : 2;
            feature_event=frame==0 ? 3 : frame==1 ? 6 : 4;
            save_timer=frame==2 ? 0 : 300;
            charge=frame==2 ? 0 : 47;
            ball_x_fp=frame==2 ? 22784 : 10112;
            ball_y_fp=frame==2 ? 14336 : 11136;
            ball2_x_fp=frame==2 ? 22784 : 14208;
            ball2_y_fp=frame==2 ? 15360 : 9856;
            moving_bumper_y_fp=5632;moving_bumper_x_fp=14848;
            trail_valid=frame==2 ? 0 : 8'hFF;
            $sformat(filename,"../vga_render_funny_%0d.hex",frame);
            fd=$fopen(filename,"w");if(fd==0)$fatal(1,"Cannot create native cameo dump");
            for(iy=0;iy<600;iy=iy+1) for(ix=0;ix<800;ix=ix+1) begin
                x=ix;y=iy;#1;
                if(^pixel===1'bx)$fatal(1,"Unknown native cameo pixel frame%0d",frame);
                $fwrite(fd,"%04h\n",pixel);
            end
            $fclose(fd);
        end
        $display("PASS tb_vga_renderer: persistent six-mood cat, moving side banks, trail/HUD/ball priority, hover/countdown and sixteen complete frames (7680000 pixels)");
        $finish;
    end
endmodule

