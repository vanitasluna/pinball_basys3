`timescale 1ns/1ps
module tb_top;
    reg clk=0;
    reg btnC=0,btnU=0,btnL=0,btnR=0,btnD=0;
    reg [15:0] sw=0;
    wire [7:0] JC;
    tri1 PS2Clk,PS2Data; // Model the board's mandatory PS/2 pull-ups.
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an,vgaRed,vgaGreen,vgaBlue;
    wire dp,Hsync,Vsync;
    integer config_x=0,config_y=0,center_x=0,center_y=0;
    integer command_count=0,spi_bits=0,data_bits=0,sampled_pixels=0;
    reg [39:0] spi_packet=0,expected_command[0:24];
    integer expected_bits[0:24];
    reg [15:0] expected_pixel=0,first_pixel=0,first_serial_pixel=0;
    reg first_pixel_loaded=0;
    reg packet_left=0,packet_middle=0,packet_right=0,packet_event=0;
    reg [11:0] packet_x=192,packet_y=128;
    integer accepted_clicks=0;
    reg [13:0] scene_probe_y=14'd6432;
    reg [14:0] scene_probe_x=15'd15904;
    reg [13:0] scene_side_left_y=14'd7552,scene_side_right_y=14'd9344;
    reg [14:0] scene_ball2_x=15'd14112;
    reg [13:0] scene_ball2_y=14'd10048;
    reg tick_probe=0;
    always #5 clk=~clk;
    My_Top_Module dut(.clk(clk),.btnC(btnC),.btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(btnD),
        .sw(sw),.JC(JC),.PS2Clk(PS2Clk),.PS2Data(PS2Data),.led(led),.seg(seg),.an(an),.dp(dp),
        .vgaRed(vgaRed),.vgaGreen(vgaGreen),.vgaBlue(vgaBlue),.Hsync(Hsync),.Vsync(Vsync));
    // Accelerate board debounce only in simulation; tb_input checks its filter.
    defparam dut.inputs.STABLE_CYCLES=4;
    task board_press(input [4:0] keys);
        @(negedge clk);{btnD,btnR,btnL,btnU,btnC}=keys;
        repeat(16) @(posedge clk);#2;
        @(negedge clk);{btnD,btnR,btnL,btnU,btnC}=0;
        repeat(16) @(posedge clk);#2;
    endtask

    task mouse_tap(input [11:0] px,py);
        @(negedge clk);packet_left=0;complete_packet(0);
        // Menu fixtures use logical pixels; MouseCtl positions are four times
        // larger so subpixel motion is retained by its protected accumulator.
        @(negedge clk);packet_x=px<<2;packet_y=py<<2;packet_left=1;complete_packet(1);
        @(negedge clk);packet_left=0;complete_packet(0);
    endtask

    task cursor_packet(input [11:0] raw_x,raw_y,input [6:0] logical_x,input [5:0] logical_y);
        reg [6:0] old_x;
        reg [5:0] old_y;
        begin
            old_x=dut.cursor_x;old_y=dut.cursor_y;
            @(negedge clk);packet_x=raw_x;packet_y=raw_y;
            repeat(3) @(posedge clk);#2;
            if(dut.cursor_x!==old_x || dut.cursor_y!==old_y)
                $fatal(1,"Raw subpixel movement escaped the complete-packet boundary");
            complete_packet(0);
            if(dut.cursor_x!==logical_x || dut.cursor_y!==logical_y ||
               dut.mouse_cursor_x!==logical_x || dut.mouse_cursor_y!==logical_y)
                $fatal(1,"Quarter-speed cursor wrong for raw position %0d,%0d",raw_x,raw_y);
        end
    endtask

    // Observe configuration requests at the exact edge sampled by MouseCtl.
    always @(posedge clk) if(!dut.reset) begin
        if(dut.mouse_click) accepted_clicks=accepted_clicks+1;
        case(dut.mouse_config)
            0: begin if(dut.mouse_value!==12'd383) $fatal(1,"Mouse X bound wrong"); config_x=config_x+1; end
            1: begin if(dut.mouse_value!==12'd255) $fatal(1,"Mouse Y bound wrong"); config_y=config_y+1; end
            2: begin if(dut.mouse_value!==12'd192) $fatal(1,"Mouse X centering wrong"); center_x=center_x+1; end
            3: begin if(dut.mouse_value!==12'd128) $fatal(1,"Mouse Y centering wrong"); center_y=center_y+1; end
        endcase
    end

    // Abstract a completed PS/2 packet at the protected controller's outputs.
    // Button bytes may precede new_event; game clicks must use whole packets.
    task complete_packet(input expected_click);
        @(negedge clk); packet_event=1;
        @(posedge clk); #2;
        if(dut.mouse_click!==expected_click) $fatal(1,"Completed mouse packet produced the wrong click edge");
        @(negedge clk); packet_event=0;
        @(posedge clk); #2;
        if(dut.mouse_click!==0) $fatal(1,"Mouse packet click lasted more than one cycle");
        if(dut.mouse_prev!=={packet_right,packet_middle,packet_left})
            $fatal(1,"Previous mouse buttons did not commit on delayed packet completion");
    endtask

    // Keep real SPI clocks and all initialization words. Skip only long waits.
    // This tests sequencing/sampling; physical power-up delays are a hardware check.
    initial begin
        wait(!dut.reset);
        forever begin
            @(negedge dut.oled_clk); #1;
            if(dut.oled.delay>100) begin
                force dut.oled.delay=0;
                #1; release dut.oled.delay;
            end
        end
    end

    always @(posedge JC[3]) if(JC[0]===1'b0) begin
        if(JC[4]===1'b0) begin
            spi_packet={spi_packet[38:0],JC[1]}; spi_bits=spi_bits+1;
        end else if(JC[4]===1'b1 && data_bits<16) begin
            first_serial_pixel={first_serial_pixel[14:0],JC[1]}; data_bits=data_bits+1;
            if(data_bits==16 && first_serial_pixel!==first_pixel)
                $fatal(1,"First serialized RGB565 pixel disagrees with renderer");
        end
    end
    always @(posedge JC[0]) if(spi_bits!=0) begin
        if(command_count>24) $fatal(1,"Unexpected OLED command before first pixel");
        if(spi_bits!=expected_bits[command_count] || spi_packet!==expected_command[command_count])
            $fatal(1,"OLED command %0d wrong: %0d bits %h",command_count,spi_bits,spi_packet);
        command_count=command_count+1; spi_bits=0; spi_packet=0;
    end
    always @(posedge dut.oled_clk) begin
        #1;
        if(dut.sample_pixel) expected_pixel=dut.oled_pixel;
    end
    always @(negedge dut.oled_clk) begin
        #2;
        if(dut.sending_pixels && dut.oled.spi_word_bit_count==16) begin
            if(dut.oled.spi_word[39:24]!==expected_pixel) $fatal(1,"OLED sampled stale/wrong pixel");
            if(!first_pixel_loaded) begin first_pixel=expected_pixel; first_pixel_loaded=1; end
            sampled_pixels=sampled_pixels+1;
        end
    end

    initial begin
        expected_command[0]=40'hFD12; expected_bits[0]=16;
        expected_command[1]=40'hAE; expected_bits[1]=8;
        expected_command[2]=40'hA072; expected_bits[2]=16;
        expected_command[3]=40'hA100; expected_bits[3]=16;
        expected_command[4]=40'hA200; expected_bits[4]=16;
        expected_command[5]=40'hA4; expected_bits[5]=8;
        expected_command[6]=40'hA83F; expected_bits[6]=16;
        expected_command[7]=40'hAD8E; expected_bits[7]=16;
        expected_command[8]=40'hB00B; expected_bits[8]=16;
        expected_command[9]=40'hB131; expected_bits[9]=16;
        expected_command[10]=40'hB3F0; expected_bits[10]=16;
        expected_command[11]=40'h8A64; expected_bits[11]=16;
        expected_command[12]=40'h8B78; expected_bits[12]=16;
        expected_command[13]=40'h8C64; expected_bits[13]=16;
        expected_command[14]=40'hBB3A; expected_bits[14]=16;
        expected_command[15]=40'hBE3E; expected_bits[15]=16;
        expected_command[16]=40'h8706; expected_bits[16]=16;
        expected_command[17]=40'h8191; expected_bits[17]=16;
        expected_command[18]=40'h8250; expected_bits[18]=16;
        expected_command[19]=40'h837D; expected_bits[19]=16;
        expected_command[20]=40'h25; expected_bits[20]=8;
        expected_command[21]=40'h2500005F3F; expected_bits[21]=40;
        expected_command[22]=40'hAF; expected_bits[22]=8;
        expected_command[23]=40'h15005F; expected_bits[23]=24;
        expected_command[24]=40'h75003F; expected_bits[24]=24;
        repeat(24) @(posedge clk); #2;
        if(!dut.reset || JC[7]!==1'b0) $fatal(1,"Power-on reset did not hold OLED power off");
        repeat(56) @(posedge clk); #2;
        if(dut.reset || dut.mouse_config!=4) $fatal(1,"Power-on reset/configuration failed to complete");
        if(config_x!=1 || config_y!=1 || center_x!=1 || center_y!=1) $fatal(1,"Mouse configuration requests must each occur once");
        if(dut.mouse_x!==12'd192 || dut.mouse_y!==12'd128) $fatal(1,"Protected MouseCtl did not apply initial raw position");
        if(dut.cursor_x!==48 || dut.cursor_y!==32) $fatal(1,"Mouse logical position did not stay centered");
        if(dut.mouse_seen || dut.mouse_click || dut.left_pressed || dut.right_pressed || dut.launch_down)
            $fatal(1,"Missing mouse injected a game action");
        if($isunknown({JC,led,seg,an,dp,Hsync,Vsync,vgaRed,vgaGreen,vgaBlue,dut.buttons,dut.state}))
            $fatal(1,"Unknown top-level display/control output after startup");
        if(JC[2]!==1'b0 || JC[7]!==1'b1) $fatal(1,"OLED connector mapping/power enable incorrect");

        wait(dut.oled.state==5'b10001);
        if(command_count!=25 || JC[4]!==0 || JC[5]!==1 || JC[6]!==1 || JC[7]!==1)
            $fatal(1,"OLED initialization/power/data-command sequencing failed");
        // Advance the idle frame boundary without changing the driver's source.
        @(negedge dut.oled_clk); #3;
        force dut.oled.frame_counter=0; #1; release dut.oled.frame_counter;
        wait(sampled_pixels>=8 && data_bits==16);
        if(command_count!=25 || JC[4]!==1) $fatal(1,"OLED did not enter RGB pixel streaming");
        if(dut.pixel_index<7 || dut.pixel_index>9) $fatal(1,"OLED raster indexing incorrect");
        // Verify that both complete frame payloads carry the SAME nondefault
        // fractional moving centres, then remain frozen between frame starts.
        force dut.moving_bumper_y_fp=scene_probe_y;
        force dut.moving_bumper_x_fp=scene_probe_x;
        force dut.side_left_y_fp=scene_side_left_y;
        force dut.side_right_y_fp=scene_side_right_y;
        force dut.ball2_x=7'd55;force dut.ball2_y=6'd39;
        force dut.ball2_x_fp=scene_ball2_x;force dut.ball2_y_fp=scene_ball2_y;
        force dut.balls_visible=2'b11;force dut.display_two_ball_mode=1'b1;
        repeat(4) @(posedge clk);
        @(negedge dut.oled_clk); force dut.oled_frame=1'b1;
        @(posedge dut.oled_clk); #2; release dut.oled_frame;
        @(negedge dut.vga_clk); force dut.vga_frame=1'b1;
        @(posedge dut.vga_clk); #2; release dut.vga_frame;
        if(dut.oled_graphics.moving_bumper_y_fp!==scene_probe_y ||
           dut.oled_graphics.moving_bumper_x_fp!==scene_probe_x ||
           dut.vga_graphics.moving_bumper_y_fp!==scene_probe_y ||
           dut.vga_graphics.moving_bumper_x_fp!==scene_probe_x)
            $fatal(1,"Moving centres were truncated, reordered or omitted in a display frame");
        if(dut.oled_graphics.side_left_y_fp!==scene_side_left_y ||
           dut.oled_graphics.side_right_y_fp!==scene_side_right_y ||
           dut.vga_graphics.side_left_y_fp!==scene_side_left_y ||
           dut.vga_graphics.side_right_y_fp!==scene_side_right_y)
            $fatal(1,"Moving side targets were truncated, reordered or omitted in a display frame");
        if(dut.oled_graphics.ball2_x!==55 || dut.oled_graphics.ball2_y!==39 ||
           dut.vga_graphics.ball2_x_fp!==scene_ball2_x || dut.vga_graphics.ball2_y_fp!==scene_ball2_y ||
           dut.oled_graphics.balls_visible!==3 || dut.vga_graphics.balls_visible!==3 ||
           !dut.oled_graphics.two_ball_mode || !dut.vga_graphics.two_ball_mode)
            $fatal(1,"Two-ball coordinates, visibility or mode omitted from frame snapshot");
        scene_probe_y=14'd7168;scene_probe_x=15'd16896;
        scene_side_left_y=14'd9472;scene_side_right_y=14'd7424;
        scene_ball2_x=15'd16640;scene_ball2_y=14'd12800;
        repeat(4) @(posedge clk); #2;
        if(dut.oled_graphics.moving_bumper_y_fp!==14'd6432 ||
           dut.vga_graphics.moving_bumper_x_fp!==15'd15904)
            $fatal(1,"Moving objects changed before the next display frame");
        if(dut.oled_graphics.side_left_y_fp!==14'd7552 ||
           dut.oled_graphics.side_right_y_fp!==14'd9344 ||
           dut.vga_graphics.side_left_y_fp!==14'd7552 ||
           dut.vga_graphics.side_right_y_fp!==14'd9344)
            $fatal(1,"Moving side targets changed before the next display frame");
        if(dut.vga_graphics.ball2_x_fp!==15'd14112 || dut.vga_graphics.ball2_y_fp!==14'd10048)
            $fatal(1,"Second ball changed before the next display frame");
        release dut.moving_bumper_y_fp;release dut.moving_bumper_x_fp;
        release dut.side_left_y_fp;release dut.side_right_y_fp;
        release dut.ball2_x;release dut.ball2_y;release dut.ball2_x_fp;release dut.ball2_y_fp;
        release dut.balls_visible;release dut.display_two_ball_mode;

        // SW1 is ignored in the menu. U toggles once per debounced press.
        sw[1]=1;repeat(8) @(posedge clk);#2;
        if(dut.menu_two_ball_mode || dut.display_two_ball_mode || dut.state!==0)
            $fatal(1,"SW1 still selects the ball mode");
        @(negedge clk);btnU=1;repeat(40) @(posedge clk);#2;
        if(!dut.menu_two_ball_mode || dut.state!==0 || dut.difficulty!==1)
            $fatal(1,"Held U did not toggle mode once without starting or changing level");
        @(negedge clk);btnU=0;repeat(16) @(posedge clk);#2;
        board_press(5'b00010);
        if(dut.menu_two_ball_mode || dut.state!==0) $fatal(1,"Second U press did not select one ball");
        board_press(5'b00010);
        if(!dut.menu_two_ball_mode) $fatal(1,"Third U press did not select two balls");
        // Simultaneous U+C must start the new choice, rather than the old one.
        board_press(5'b00011);
        if(dut.state!==2 || dut.two_ball_mode || dut.balls_visible!==1 || dut.menu_two_ball_mode)
            $fatal(1,"Simultaneous U/C started a stale mode or failed to launch");
        board_press(5'b10000);
        if(dut.state!==0 || dut.menu_two_ball_mode) $fatal(1,"Menu return discarded the selected mode");
        sw[0]=1;sw[1]=0; repeat(8) @(posedge clk); #2;
        if(dut.mouse_click || dut.left_pressed || dut.right_pressed || dut.launch_down)
            $fatal(1,"Enabling an absent mouse injected actions");

        // A first click must work without an earlier movement packet. Model the
        // old Y output until the event edge, then supply the new Y in the cycle
        // before the game consumes its delayed packet. Old Y is the difficulty
        // row; new Y is the mode row, exposing dispatch based on stale position.
        force dut.mouse_left=packet_left;
        force dut.mouse_middle=packet_middle;
        force dut.mouse_right=packet_right;
        force dut.mouse_event=packet_event;
        force dut.mouse_x=packet_x;
        force dut.mouse_y=packet_y;
        @(negedge clk); packet_left=1; packet_x=240; packet_y=140;
        repeat(4) @(posedge clk); #2;
        if(dut.mouse_click || dut.mouse_seen || dut.mouse_prev!==0 || dut.state!==0 || dut.difficulty!==1)
            $fatal(1,"Mouse byte 1 triggered a click before packet completion");
        if(dut.cursor_x!==48 || dut.cursor_y!==32 || dut.left_pressed)
            $fatal(1,"Partial mouse packet moved the cursor or flipper");
        @(negedge clk); packet_event=1;
        @(posedge clk); #2;
        if(!dut.mouse_click || !dut.mouse_seen || dut.mouse_prev!==0 || dut.state!==0)
            $fatal(1,"First complete mouse click was lost or consumed too early");
        packet_y=100; #1;
        if(dut.cursor_y!==25 || dut.mouse_level!==0 || !dut.mouse_mode)
            $fatal(1,"New mouse Y was not available for delayed packet dispatch");
        @(negedge clk); packet_event=0;
        @(posedge clk); #2;
        if(dut.state!==0 || dut.difficulty!==1 || accepted_clicks!=1 || dut.mouse_click ||
           !dut.menu_two_ball_mode || !dut.display_two_ball_mode)
            $fatal(1,"First mode click used stale Y, repeated, or accidentally started");
        complete_packet(0);complete_packet(0);
        if(!dut.menu_two_ball_mode || accepted_clicks!=1 || dut.state!==0)
            $fatal(1,"Holding a mode-row click repeated the toggle");
        @(negedge clk);packet_left=0;complete_packet(0);
        @(negedge clk);packet_left=1;packet_y=176;complete_packet(1);
        repeat(3) @(posedge clk);#2;
        if(dut.state!==1 || !dut.two_ball_mode || dut.balls_visible!==2'b11 || dut.ball2_y!==60)
            $fatal(1,"Menu choice did not prepare two balls on mouse start");
        sw[1]=1;repeat(8) @(posedge clk);#2;
        if(!dut.two_ball_mode || !dut.display_two_ball_mode)
            $fatal(1,"Changing SW1 during a game changed the selected mode");

        // Repeated movement packets while held must never create another click.
        complete_packet(0); complete_packet(0);
        if(accepted_clicks!=2) $fatal(1,"Held mouse button repeated a click");
        @(negedge clk); packet_left=0;
        repeat(3) @(posedge clk); #2;
        if(dut.mouse_prev!==1 || !dut.left_pressed)
            $fatal(1,"Raw release byte changed prior complete-packet state");
        complete_packet(0);
        if(dut.mouse_prev!==0 || accepted_clicks!=2) $fatal(1,"Release packet created a click");
        @(negedge clk); packet_left=1;
        repeat(3) @(posedge clk); #2;
        if(dut.mouse_click || dut.left_pressed || accepted_clicks!=2)
            $fatal(1,"Raw press byte triggered a new click or flipper");
        complete_packet(1);
        if(accepted_clicks!=3) $fatal(1,"Release followed by press did not re-arm mouse click");
        // One middle-button release must launch both prepared balls using
        // the same selected charge. Accelerate only the shared tick enable.
        @(negedge clk);packet_left=0;complete_packet(0);
        force dut.tick=tick_probe;
        @(negedge clk);packet_middle=1;complete_packet(0);
        repeat(80) begin
            @(negedge clk);tick_probe=1;
            @(negedge clk);tick_probe=0;
        end
        #2;if(dut.charge!==20 || dut.state!==1) $fatal(1,"Mouse middle did not charge shared spring");
        @(negedge clk);packet_middle=0;complete_packet(0);
        repeat(3) @(posedge clk);#2;
        if(dut.state!==2 || dut.charge!==20 || dut.balls_visible!==3)
            $fatal(1,"Single mouse release failed to launch two balls");
        @(negedge clk);tick_probe=1;
        @(negedge clk);tick_probe=0;
        repeat(15) @(posedge clk);#2;
        if(dut.ball_y_fp!==56*256 || dut.ball2_y_fp!==60*256)
            $fatal(1,"Two-ball physics exported a partial batch");
        repeat(24) @(posedge clk);#2;
        if(dut.ball_y_fp>=56*256 || dut.ball2_y_fp>=60*256 ||
           dut.moving_bumper_y_fp!==22*256+4)
            $fatal(1,"Both balls did not move together or world advanced twice");
        release dut.tick;
        // Survivor trail selection must clear the drained ball's history.
        @(negedge clk);force dut.effects.trail_valid=8'hff;
        @(posedge clk);#2;release dut.effects.trail_valid;
        force dut.balls_visible=2'b10;
        @(posedge clk);#2;
        if(dut.oled_transfer[7:0]!==0 || dut.vga_transfer[7:0]!==0)
            $fatal(1,"First survivor scene captured the old white-ball trail");
        repeat(2) @(posedge clk);#2;
        if(dut.effects.trail_valid!==0 || !dut.gold_trail)
            $fatal(1,"Gold survivor inherited a ghost white-ball trail");
        release dut.balls_visible;
        board_press(5'b00010);
        if(dut.state!==3 || !dut.menu_two_ball_mode || !dut.two_ball_mode)
            $fatal(1,"U during play changed the mode instead of pausing");
        mouse_tap(48,20);
        if(dut.state!==3) $fatal(1,"A blank pause-screen click resumed the game");
        mouse_tap(48,41);
        if(dut.state!==2 || !dut.two_ball_mode) $fatal(1,"Resume prompt click failed");
        board_press(5'b00010);
        board_press(5'b00010);
        if(dut.state!==2 || !dut.menu_two_ball_mode || !dut.two_ball_mode)
            $fatal(1,"U during pause changed the mode instead of resuming");
        board_press(5'b10000);
        if(dut.state!==0 || !dut.menu_two_ball_mode || !dut.display_two_ball_mode)
            $fatal(1,"Chosen two-ball mode was not retained on menu return");
        // Menu mouse toggles work in both directions; SW1 cannot force either.
        @(negedge clk);packet_left=1;packet_y=100;complete_packet(1);
        if(dut.menu_two_ball_mode || dut.state!==0) $fatal(1,"Mode click did not select one ball");
        @(negedge clk);packet_left=0;complete_packet(0);
        sw[1]=0;repeat(8) @(posedge clk);#2;
        @(negedge clk);packet_left=1;complete_packet(1);
        if(!dut.menu_two_ball_mode || dut.state!==0) $fatal(1,"Mode click did not select two balls");
        mouse_tap(48,12);
        if(dut.state!==0 || !dut.menu_two_ball_mode) $fatal(1,"Title click accidentally started the game");
        mouse_tap(5,25);
        if(dut.state!==0 || !dut.menu_two_ball_mode) $fatal(1,"Margin click toggled ball mode");
        mouse_tap(5,44);
        if(dut.state!==0) $fatal(1,"Margin click started the game");
        mouse_tap(5,35);
        if(dut.state!==0 || dut.difficulty!==1) $fatal(1,"Margin click changed difficulty");
        // Button and coordinate bytes remain isolated until packet completion.
        @(negedge clk);packet_middle=1;packet_right=1;packet_x=320;packet_y=240;
        repeat(4) @(posedge clk);#2;
        if(dut.right_pressed || dut.launch_down || dut.cursor_x!==5 || dut.cursor_y!==35)
            $fatal(1,"Partial mouse packet activated controls or tore coordinates");
        complete_packet(0);
        if(!dut.right_pressed || !dut.launch_down || dut.cursor_x!==80 || dut.cursor_y!==60)
            $fatal(1,"Completed mouse packet did not publish its controls and position");
        @(negedge clk);packet_middle=0;packet_right=0;packet_x=4;packet_y=4;
        repeat(4) @(posedge clk);#2;
        if(!dut.right_pressed || !dut.launch_down || dut.cursor_x!==80 || dut.cursor_y!==60)
            $fatal(1,"Partial release byte cleared committed controls");
        complete_packet(0);
        if(dut.right_pressed || dut.launch_down) $fatal(1,"Complete release packet did not release controls");
        // Fine motion retains two fractional bits in the raw controller. A
        // four-count change moves one logical pixel in either direction.
        cursor_packet(192,128,48,32);
        cursor_packet(195,131,48,32);
        cursor_packet(196,132,49,33);
        cursor_packet(193,129,48,32);
        cursor_packet(0,0,0,0);
        cursor_packet(3,3,0,0);
        cursor_packet(4,4,1,1);
        cursor_packet(380,252,95,63);
        cursor_packet(383,255,95,63);
        // Defensive publication clamp also handles an invalid/raw stale value
        // outside the configured controller range without wrapping the cursor.
        cursor_packet(4095,4095,95,63);
        cursor_packet(0,255,0,63);
        cursor_packet(383,0,95,0);
        // Hit testing uses the same divided coordinate as both renderers.
        // Logical X=21 misses the difficulty row; X=22 is its first valid pixel.
        @(negedge clk);packet_x=87;packet_y=143;packet_left=1;complete_packet(1);
        if(dut.cursor_x!==21 || dut.cursor_y!==35 || dut.mouse_level || dut.difficulty!==1)
            $fatal(1,"A fractional raw click outside the displayed widget changed difficulty");
        @(negedge clk);packet_left=0;complete_packet(0);
        @(negedge clk);packet_x=88;packet_left=1;complete_packet(1);
        if(dut.cursor_x!==22 || dut.cursor_y!==35 || !dut.mouse_level || dut.difficulty!==0)
            $fatal(1,"Click dispatch did not align with the quarter-speed displayed cursor");
        @(negedge clk);packet_left=0;complete_packet(0);
        mouse_tap(48,35);
        if(dut.difficulty!==1) $fatal(1,"Mouse difficulty fixture did not restore normal mode");
        // Exercise the restart widget with a valid terminal-state fixture.
        @(negedge clk);dut.game.state=3'd4;dut.game.lives=0;
        dut.physics.ball1_alive=0;dut.physics.ball2_alive=0;
        dut.physics.launched=0;dut.physics.launched2=0;
        mouse_tap(48,43);
        if(dut.state!==4 || dut.lives!==0) $fatal(1,"Best-score click accidentally restarted");
        mouse_tap(48,51);
        if(dut.state!==1 || dut.lives!==3 || !dut.two_ball_mode || dut.balls_visible!==3)
            $fatal(1,"Restart prompt did not prepare the selected pair");
        board_press(5'b10000);
        mouse_tap(48,44);
        if(dut.state!==1 || !dut.two_ball_mode) $fatal(1,"Start widget failed after menu return");
        release dut.mouse_left;
        release dut.mouse_middle;
        release dut.mouse_right;
        release dut.mouse_event;
        release dut.mouse_x;
        release dut.mouse_y;

        sw[15]=1; repeat(16) @(posedge clk); #2;
        if(!dut.reset || JC[7]!==0 || dut.state!==0 || dut.two_ball_mode || dut.menu_two_ball_mode)
            $fatal(1,"SW15 system reset failed");
        sw[15]=0; repeat(20) @(posedge clk); #2;
        if(dut.reset || dut.mouse_x!==192 || dut.mouse_y!==128) $fatal(1,"Reset release failed to reconfigure raw mouse position");
        if(dut.cursor_x!==48 || dut.cursor_y!==32) $fatal(1,"Reset release failed to recenter logical cursor");
        $display("PASS tb_top: quarter-speed complete mouse packets, subpixel motion, endpoint clamps, aligned clicks, bounded start/resume/restart widgets, menu mode choice, ignored SW1, held-input rejection, simultaneous U/C capture, pause, survivor trail, paired launch, atomic frames, reset, protected drivers and JC SPI");
        $finish;
    end
    initial begin #2000000; $fatal(1,"tb_top timeout"); end
endmodule
