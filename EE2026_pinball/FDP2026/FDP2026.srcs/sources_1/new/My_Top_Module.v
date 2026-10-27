`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: Truong Phi Hung
//  STUDENT B NAME: Suraj
//  STUDENT C NAME: Duong Nghiep Hoang
//  STUDENT D NAME: Nguyen Duc Khoa
//////////////////////////////////////////////////////////////////////////////////

// OLED: plug Pmod OLEDrgb into JC. Mouse: Basys 3 USB HID host port.
// C hold/release: start/launch; L/R: flippers or menu level; D: menu.
// U: choose one/two balls in the menu, pause/resume during a game.
// SW0 enables mouse controls; SW15 resets.
module My_Top_Module (
    input wire clk, input wire btnC,btnU,btnL,btnR,btnD, input wire [15:0] sw,
    output wire [7:0] JC, inout wire PS2Clk,PS2Data,
    output wire [15:0] led, output wire [6:0] seg, output wire [3:0] an, output wire dp,
    output wire [3:0] vgaRed,vgaGreen,vgaBlue, output wire Hsync,Vsync
);
    localparam [2:0] MENU=3'd0, READY=3'd1, PLAY=3'd2, PAUSE=3'd3, OVER=3'd4;
    localparam [18:0] PHYSICS_TICK_LAST = 19'd416665;
    localparam [8:0] NUDGE_COOLDOWN_TICKS = 9'd480;
    reg [31:0] power_on = 32'hFFFFFFFF;
    reg [3:0] divider = 0;
    reg system_reset = 1;
    (* ASYNC_REG = "TRUE" *) reg [15:0] sw_meta=0, sw_sync=0;
    always @(posedge clk) begin
        power_on <= {power_on[30:0],1'b0};
        divider <= divider+1'b1;
        sw_meta<=sw; sw_sync<=sw_meta;
        system_reset <= (|power_on) || sw_sync[15];
    end
    wire reset = system_reset;
    wire oled_clk, vga_clk;
    BUFG oled_clock_buffer(.I(divider[3]),.O(oled_clk));
    wire vga_locked;
    pinball_vga_clock vga_clock(.clk(clk),.reset(reset),.pixel_clk(vga_clk),.locked(vga_locked));
    // Assert reset whenever the MMCM loses lock; release synchronously.
    (* ASYNC_REG = "TRUE" *) reg [2:0] vga_reset_pipe = 3'b111;
    always @(posedge vga_clk or negedge vga_locked)
        if(!vga_locked) vga_reset_pipe<=3'b111;
        else vga_reset_pipe<={vga_reset_pipe[1:0],reset};
    wire vga_reset=vga_reset_pipe[2];
    reg [18:0] tick_count;
    wire tick=tick_count==PHYSICS_TICK_LAST;
    always @(posedge clk)
        if(reset || tick) tick_count<=0; else tick_count<=tick_count+1'b1;

    wire [4:0] buttons,button_press;
    pinball_input #(.STABLE_CYCLES(500000)) inputs(.clk(clk),.reset(reset),.raw({btnD,btnR,btnL,btnU,btnC}),
        .down(buttons),.pressed(button_press));
    wire [11:0] mouse_x,mouse_y;
    wire [3:0] mouse_z;
    wire mouse_left,mouse_middle,mouse_right,mouse_event;
    reg [2:0] mouse_config;
    always @(posedge clk) if(reset) mouse_config<=0;
        else if(mouse_config<4) mouse_config<=mouse_config+1'b1;
    // Keep four raw mouse counts per logical pixel. The supplied controller
    // retains the fractional movement, so slow gestures accumulate naturally
    // rather than losing small deltas or accelerating at a screen boundary.
    wire [11:0] mouse_value = mouse_config==0 ? 12'd383 :
        mouse_config==1 ? 12'd255 : mouse_config==2 ? 12'd192 : 12'd128;
    MouseCtl mouse(.clk(clk),.rst(reset),.xpos(mouse_x),.ypos(mouse_y),.zpos(mouse_z),
        .left(mouse_left),.middle(mouse_middle),.right(mouse_right),.new_event(mouse_event),
        .value(mouse_value),.setmax_x(!reset && mouse_config==0),
        .setmax_y(!reset && mouse_config==1),.setx(!reset && mouse_config==2),
        .sety(!reset && mouse_config==3),.ps2_clk(PS2Clk),.ps2_data(PS2Data));
    reg [2:0] mouse_prev;
    reg mouse_seen;
    reg mouse_event_d;
    reg [4:0] mouse_release_wait;
    reg [6:0] mouse_cursor_x=7'd48;
    reg [5:0] mouse_cursor_y=6'd32;
    wire [6:0] packet_cursor_x=mouse_x>12'd383 ? 7'd95 : mouse_x[8:2];
    wire [5:0] packet_cursor_y=mouse_y>12'd255 ? 6'd63 : mouse_y[7:2];
    always @(posedge clk) begin
        if(reset) begin
            mouse_prev<=0; mouse_seen<=0; mouse_event_d<=0;
            mouse_release_wait<=0;
            mouse_cursor_x<=48; mouse_cursor_y<=32;
        end
        else begin
            mouse_event_d<=mouse_event;
            // Track complete packets after the supplied controller has also
            // registered the new cursor Y position (including non-wheel mice).
            if(mouse_event_d) begin
                mouse_prev<={mouse_right,mouse_middle,mouse_left};
                mouse_cursor_x<=packet_cursor_x; mouse_cursor_y<=packet_cursor_y;
                mouse_release_wait<=0;
            end else if(!(mouse_right || mouse_middle || mouse_left) && |mouse_prev) begin
                // MouseCtl clears its buttons during an internal reconnect,
                // without publishing a completed release packet. Retire that
                // stale hold after 32 ticks (~133 ms). A stationary held mouse
                // stays raw-high, so normal holds never expire. Complete
                // packets always win, including a normal button release.
                if(tick) begin
                    if(&mouse_release_wait) begin
                        mouse_prev<=0; mouse_seen<=0; mouse_release_wait<=0;
                    end else mouse_release_wait<=mouse_release_wait+1'b1;
                end
            end else begin
                mouse_release_wait<=0;
            end
            if(mouse_event) mouse_seen<=1;
        end
    end
    wire mouse_click=sw_sync[0] && mouse_event_d && mouse_left && !mouse_prev[0];
    // The packet currently being dispatched already has its final Y. Other
    // clocks use the last complete position, avoiding half-packet cursor jumps.
    wire [6:0] cursor_x=mouse_event_d ? packet_cursor_x : mouse_cursor_x;
    wire [5:0] cursor_y=mouse_event_d ? packet_cursor_y : mouse_cursor_y;
    wire [2:0] state;
    wire [1:0] lives,difficulty,bonus_target;
    wire [15:0] score_bcd,high_bcd;
    wire [5:0] charge;
    wire two_ball_mode;
    reg menu_two_ball_mode=0;
    wire display_two_ball_mode=state==MENU ? menu_two_ball_mode : two_ball_mode;
    wire [13:0] hit_events,hit_flash;
    wire [7:0] anim;
    wire [2:0] combo,mission_progress,feature_event;
    wire [1:0] target_progress;
    wire [10:0] save_timer;
    wire [9:0] feature_timer;
    wire [15:0] last_award_bcd;
    wire [5:0] table_progress;
    wire [3:0] spinner_phase;
    wire prepare,launch,active,drained,in_lane,bonus_active;
    // Held controls also use complete packets; raw first button bytes must
    // not move flippers or release a charged ball before the packet finishes.
    wire left_pressed=buttons[2] || (sw_sync[0] && mouse_seen && mouse_prev[0]);
    wire right_pressed=buttons[3] || (sw_sync[0] && mouse_seen && mouse_prev[2]);
    wire launch_down=buttons[0] || (sw_sync[0] && mouse_seen && mouse_prev[1]);
    // Menu clicks select balls, change difficulty, or start. Mode clicks and
    // U presses toggle once; they cannot accidentally start the game.
    wire mouse_action_column=cursor_x>=24 && cursor_x<=72;
    wire mouse_mode=state==MENU && mouse_action_column && cursor_y>=22 && cursor_y<=29;
    wire mouse_level=state==MENU && cursor_x>=22 && cursor_x<=73 && cursor_y>=30 && cursor_y<=39;
    wire mouse_start=mouse_click && mouse_action_column &&
        ((state==MENU && cursor_y>=43 && cursor_y<=47) ||
         (state==PAUSE && cursor_y>=39 && cursor_y<=45) ||
         (state==OVER && cursor_y>=49 && cursor_y<=53));
    wire mode_change=state==MENU && (button_press[1] || (mouse_click && mouse_mode));
    always @(posedge clk)
        if(reset) menu_two_ball_mode<=0;
        else if(mode_change) menu_two_ball_mode<=~menu_two_ball_mode;
    reg [8:0] nudge_cooldown;
    wire nudge_request=state==PLAY && !in_lane && nudge_cooldown==0 &&
        (button_press[0] || (sw_sync[0] && mouse_event_d && mouse_middle && !mouse_prev[1]));
    always @(posedge clk) begin
        if(reset || prepare || state==MENU || state==OVER) nudge_cooldown<=0;
        else if(nudge_request) nudge_cooldown<=NUDGE_COOLDOWN_TICKS;
        else if(tick && active && nudge_cooldown!=0) nudge_cooldown<=nudge_cooldown-1'b1;
    end
    pinball_game game(.clk(clk),.reset(reset),.tick(tick),
        // A simultaneous U/C press starts the newly selected mode.
        .two_ball_select(menu_two_ball_mode ^ mode_change),.two_ball_mode(two_ball_mode),
        .start_press(button_press[0] || mouse_start),
        .launch_down(launch_down),.pause_press(button_press[1]),.menu_press(button_press[4]),
        .level_left(button_press[2] || (mouse_click && mouse_level && cursor_x<48)),
        .level_right(button_press[3] || (mouse_click && mouse_level && cursor_x>=48)),
        .drained(drained),.in_lane(in_lane),.nudge_press(nudge_request),
        .hit_events(hit_events),.state(state),.lives(lives),
        .difficulty(difficulty),.score_bcd(score_bcd),.high_bcd(high_bcd),.charge(charge),
        .prepare(prepare),.launch(launch),.active(active),.hit_flash(hit_flash),
        .bonus_target(bonus_target),.bonus_active(bonus_active),.anim(anim),
        .combo(combo),.mission_progress(mission_progress),.target_progress(target_progress),
        .save_timer(save_timer),.feature_event(feature_event),.feature_timer(feature_timer),
        .last_award_bcd(last_award_bcd),.table_progress(table_progress),.spinner_phase(spinner_phase));
    wire [5:0] selected_layout,layout_id;
    // D/menu has priority over start, matching the rule controller. A map
    // changes only for a new game, never for a paid life or a saved relaunch.
    pinball_map_select maps(.clk(clk),.reset(reset),
        .new_game((state==MENU || state==OVER) &&
            (button_press[0] || mouse_start) && !button_press[4]),
        .selected_layout(selected_layout));
    wire [6:0] ball_x,ball2_x;
    wire [5:0] ball_y,ball2_y;
    wire [1:0] balls_visible;
    wire hit_ball;
    wire [2:0] left_angle,right_angle;
    wire [14:0] ball_x_fp,ball2_x_fp;
    wire [13:0] ball_y_fp,ball2_y_fp;
    wire [13:0] moving_bumper_y_fp;
    wire [14:0] moving_bumper_x_fp;
    wire [13:0] side_left_y_fp,side_right_y_fp;
    wire [1:0] black_slot,white_slot,teleported;
    wire [4:0] portal_flash;
    wire [7:0] portal_anim;
    wire portals_visible=state==READY || state==PLAY || state==PAUSE;
    pinball_physics physics(.clk(clk),.reset(reset),.tick(tick),.active(active),
        .selected_layout(selected_layout),.layout_id(layout_id),
        .two_ball_mode(two_ball_mode),.balls_visible(balls_visible),.hit_ball(hit_ball),
        .prepare(prepare),.launch(launch),.launch_power(charge),.difficulty(difficulty),
        .left_pressed(left_pressed),.right_pressed(right_pressed),.nudge(nudge_request),
        .ball_x(ball_x),.ball_y(ball_y),.left_angle(left_angle),.right_angle(right_angle),
        .ball_x_fp(ball_x_fp),.ball_y_fp(ball_y_fp),
        .ball2_x(ball2_x),.ball2_y(ball2_y),.ball2_x_fp(ball2_x_fp),.ball2_y_fp(ball2_y_fp),
        .moving_bumper_y_fp(moving_bumper_y_fp),.moving_bumper_x_fp(moving_bumper_x_fp),
        .side_left_y_fp(side_left_y_fp),.side_right_y_fp(side_right_y_fp),
        .black_slot(black_slot),.white_slot(white_slot),.portal_flash(portal_flash),
        .portal_anim(portal_anim),.teleported(teleported),
        .drained(drained),.hit_events(hit_events),.in_lane(in_lane));
    wire [79:0] particle_x,particle_y,trail_x,trail_y;
    wire [31:0] particle_life;
    wire [7:0] trail_valid;
    wire [55:0] oled_trail_x;
    wire [47:0] oled_trail_y;
    wire gold_trail=!balls_visible[0] && balls_visible[1];
    reg previous_gold_trail=0;
    // The producer and effects run on the same edge. Mask old history during
    // handoff so even that first bundle cannot pair a survivor with stale trails.
    wire followed_teleported=balls_visible[0] ? teleported[0] : teleported[1];
    wire trail_handoff=gold_trail!=previous_gold_trail || followed_teleported;
    wire [7:0] scene_trail_valid=(trail_handoff || balls_visible==0) ? 8'd0 : trail_valid;
    always @(posedge clk)
        if(reset || prepare) previous_gold_trail<=0;
        else previous_gold_trail<=gold_trail;
    pinball_effects effects(.clk(clk),.reset(reset),.tick(tick),.active(active),.prepare(prepare),
        .hit_enable(state==PLAY || state==PAUSE),.trail_reset(trail_handoff),
        .hit_events(hit_events),
        .ball_x_fp(balls_visible[0] ? ball_x_fp : ball2_x_fp),
        .ball_y_fp(balls_visible[0] ? ball_y_fp : ball2_y_fp),
        .hit_x_fp(hit_ball ? ball2_x_fp : ball_x_fp),
        .hit_y_fp(hit_ball ? ball2_y_fp : ball_y_fp),
        .particle_x(particle_x),.particle_y(particle_y),.particle_life(particle_life),
        .trail_x(trail_x),.trail_y(trail_y),.trail_valid(trail_valid),
        .oled_trail_x(oled_trail_x),.oled_trail_y(oled_trail_y));
    pinball_sevenseg score_display(.clk(clk),.reset(reset),.bcd(score_bcd),
        .seg(seg),.an(an),.dp(dp));
    assign led={state==OVER,state==PAUSE,active,in_lane,bonus_active,difficulty,
        charge[5:1],sw_sync[0] && mouse_seen,lives>=3,lives>=2,lives>=1};

    wire [102:0] live_scene={state,ball_x,ball_y,left_angle,right_angle,score_bcd,
        high_bcd,lives,difficulty,charge,hit_flash,bonus_target,bonus_active,anim,
        cursor_x,cursor_y,sw_sync[0] && mouse_seen};
    wire [57:0] live_features={combo,mission_progress,target_progress,save_timer,
        feature_event,feature_timer,last_award_bcd,table_progress,spinner_phase};
    wire [17:0] live_portals={black_slot,white_slot,portal_flash,portal_anim,portals_visible};
    reg [369:0] oled_scene,oled_transfer;
    reg [662:0] vga_scene,vga_transfer;
    // Register derived graphics fields in the 100 MHz producer domain.
    // The 100-to-40 MHz crossing then has only register/wiring delay,
    // rather than position scaling or hit-flash decoding in its 5 ns window.
    always @(posedge clk) begin
        if(reset) begin oled_transfer<=0;vga_transfer<=0;end
        else begin
            oled_transfer<={live_portals,layout_id,live_scene,live_features,display_two_ball_mode,balls_visible,ball2_x,ball2_y,
                moving_bumper_y_fp,moving_bumper_x_fp,side_left_y_fp,side_right_y_fp,
                oled_trail_x,oled_trail_y,scene_trail_valid};
            vga_transfer<={live_portals,layout_id,live_scene,live_features,display_two_ball_mode,balls_visible,ball2_x_fp,ball2_y_fp,
                moving_bumper_y_fp,moving_bumper_x_fp,side_left_y_fp,side_right_y_fp,ball_x_fp,ball_y_fp,
                particle_x,particle_y,particle_life,trail_x,trail_y,scene_trail_valid};
        end
    end
    wire oled_frame,vga_frame;
    // Related BUFG clocks are timed by generated-clock constraints. Latch the
    // complete scene once per display frame so moving objects never tear.
    always @(posedge oled_clk)
        if(reset) oled_scene<=0; else if(oled_frame)
            oled_scene<=oled_transfer;
    always @(posedge vga_clk)
        if(vga_reset) vga_scene<=0; else if(vga_frame)
            vga_scene<=vga_transfer;
    wire [12:0] pixel_index;
    wire [6:0] oled_x=pixel_index%96;
    wire [5:0] oled_y=pixel_index/96;
    wire [15:0] oled_pixel,vga_pixel;
    wire sending_pixels,sample_pixel;
    pinball_scene oled_graphics(.scene(oled_scene),.x(oled_x),.y(oled_y),.pixel(oled_pixel));
    Oled_Display oled(.clk(oled_clk),.reset(reset),.frame_begin(oled_frame),
        .sending_pixels(sending_pixels),.sample_pixel(sample_pixel),
        .pixel_index(pixel_index),.pixel_data(oled_pixel),
        .cs(JC[0]),.sdin(JC[1]),.sclk(JC[3]),.d_cn(JC[4]),.resn(JC[5]),
        .vccen(JC[6]),.pmoden(JC[7]));
    assign JC[2]=1'b0; // OLEDrgb pin 3 is not connected.
    wire [9:0] vga_x,vga_y;
    pinball_vga_scene vga_graphics(.scene(vga_scene),.x(vga_x),.y(vga_y),.pixel(vga_pixel));
    pinball_vga video(.clk(vga_clk),.reset(vga_reset),.pixel(vga_pixel),.x(),.y(),
        .pixel_x(vga_x),.pixel_y(vga_y),
        .frame_begin(vga_frame),.red(vgaRed),.green(vgaGreen),.blue(vgaBlue),
        .hsync(Hsync),.vsync(Vsync));
endmodule

module pinball_scene(input wire [369:0] scene,input wire [6:0] x,input wire [5:0] y,output wire [15:0] pixel);
    wire [5:0] layout_id;
    wire [1:0] black_slot,white_slot;
    wire [4:0] portal_flash;
    wire [7:0] portal_anim;
    wire portals_visible;
    wire [6:0] black_hole_x,white_hole_x;
    wire [5:0] black_hole_y,white_hole_y;
    pinball_portal_position black_position(.layout_id(layout_id),.slot(black_slot),.x(black_hole_x),.y(black_hole_y));
    pinball_portal_position white_position(.layout_id(layout_id),.slot(white_slot),.x(white_hole_x),.y(white_hole_y));
    wire [13:0] moving_bumper_y_fp;
    wire [14:0] moving_bumper_x_fp;
    wire [13:0] side_left_y_fp,side_right_y_fp;
    wire [2:0] state,left_angle,right_angle;
    wire [6:0] ball_x,cursor_x;
    wire [5:0] ball_y,charge,cursor_y;
    wire [6:0] ball2_x;
    wire [5:0] ball2_y;
    wire two_ball_mode;
    wire [1:0] balls_visible;
    wire [15:0] score_bcd,high_bcd;
    wire [1:0] lives,difficulty,bonus_target;
    wire [13:0] hit_flash;
    wire [7:0] anim;
    wire bonus_active,cursor_visible;
    wire [2:0] combo,mission_progress,feature_event;
    wire [1:0] target_progress;
    wire [10:0] save_timer;
    wire [9:0] feature_timer;
    wire [15:0] last_award_bcd;
    wire [5:0] table_progress;
    wire [3:0] spinner_phase;
    wire [55:0] oled_trail_x;
    wire [47:0] oled_trail_y;
    wire [7:0] trail_valid;
    assign {black_slot,white_slot,portal_flash,portal_anim,portals_visible,layout_id,state,ball_x,ball_y,left_angle,right_angle,score_bcd,high_bcd,lives,
        difficulty,charge,hit_flash,bonus_target,bonus_active,anim,cursor_x,cursor_y,
        cursor_visible,combo,mission_progress,target_progress,save_timer,
        feature_event,feature_timer,last_award_bcd,table_progress,spinner_phase,
        two_ball_mode,balls_visible,ball2_x,ball2_y,
        moving_bumper_y_fp,moving_bumper_x_fp,side_left_y_fp,side_right_y_fp,
        oled_trail_x,oled_trail_y,trail_valid}=scene;
    pinball_renderer graphics(.x(x),.y(y),.layout_id(layout_id),.state(state),.ball_x(ball_x),.ball_y(ball_y),
        .black_hole_x(black_hole_x),.black_hole_y(black_hole_y),.white_hole_x(white_hole_x),.white_hole_y(white_hole_y),
        .portal_flash(portal_flash),.portal_anim(portal_anim),.portals_visible(portals_visible),
        .two_ball_mode(two_ball_mode),.balls_visible(balls_visible),.ball2_x(ball2_x),.ball2_y(ball2_y),
        .left_angle(left_angle),.right_angle(right_angle),.score_bcd(score_bcd),
        .high_bcd(high_bcd),.lives(lives),.difficulty(difficulty),.charge(charge),
        .hit_flash(hit_flash),.bonus_target(bonus_target),.bonus_active(bonus_active),
        .anim(anim),.cursor_x(cursor_x),.cursor_y(cursor_y),
        .cursor_visible(cursor_visible),.combo(combo),.mission_progress(mission_progress),
        .target_progress(target_progress),.save_timer(save_timer),.feature_event(feature_event),
        .feature_timer(feature_timer),.last_award_bcd(last_award_bcd),.table_progress(table_progress),.spinner_phase(spinner_phase),
        .moving_bumper_y_fp(moving_bumper_y_fp),.moving_bumper_x_fp(moving_bumper_x_fp),
        .side_left_y_fp(side_left_y_fp),.side_right_y_fp(side_right_y_fp),
        .oled_trail_x(oled_trail_x),.oled_trail_y(oled_trail_y),.trail_valid(trail_valid),.pixel(pixel));
endmodule

module pinball_vga_scene(input wire [662:0] scene,input wire [9:0] x,y,output wire [15:0] pixel);
    wire [5:0] layout_id;
    wire [1:0] black_slot,white_slot;
    wire [4:0] portal_flash;
    wire [7:0] portal_anim;
    wire portals_visible;
    wire [6:0] black_hole_x,white_hole_x;
    wire [5:0] black_hole_y,white_hole_y;
    pinball_portal_position black_position(.layout_id(layout_id),.slot(black_slot),.x(black_hole_x),.y(black_hole_y));
    pinball_portal_position white_position(.layout_id(layout_id),.slot(white_slot),.x(white_hole_x),.y(white_hole_y));
    wire [2:0] state,left_angle,right_angle,combo,mission_progress,feature_event;
    wire [6:0] ball_x,cursor_x;
    wire [5:0] ball_y,charge,cursor_y;
    wire [15:0] score_bcd,high_bcd,last_award_bcd;
    wire [5:0] table_progress;
    wire [3:0] spinner_phase;
    wire [1:0] lives,difficulty,bonus_target,target_progress;
    wire [13:0] hit_flash;
    wire [7:0] anim,trail_valid;
    wire bonus_active,cursor_visible;
    wire [10:0] save_timer;
    wire [9:0] feature_timer;
    wire [14:0] ball_x_fp;
    wire [13:0] ball_y_fp;
    wire [14:0] ball2_x_fp;
    wire [13:0] ball2_y_fp;
    wire two_ball_mode;
    wire [1:0] balls_visible;
    wire [13:0] moving_bumper_y_fp;
    wire [14:0] moving_bumper_x_fp;
    wire [13:0] side_left_y_fp,side_right_y_fp;
    wire [79:0] particle_x,particle_y,trail_x,trail_y;
    wire [31:0] particle_life;
    assign {black_slot,white_slot,portal_flash,portal_anim,portals_visible,layout_id,state,ball_x,ball_y,left_angle,right_angle,score_bcd,high_bcd,lives,
        difficulty,charge,hit_flash,bonus_target,bonus_active,anim,cursor_x,cursor_y,
        cursor_visible,combo,mission_progress,target_progress,save_timer,feature_event,
        feature_timer,last_award_bcd,table_progress,spinner_phase,
        two_ball_mode,balls_visible,ball2_x_fp,ball2_y_fp,
        moving_bumper_y_fp,moving_bumper_x_fp,side_left_y_fp,side_right_y_fp,
        ball_x_fp,ball_y_fp,particle_x,particle_y,
        particle_life,trail_x,trail_y,trail_valid}=scene;
    pinball_vga_renderer graphics(.x(x),.y(y),.layout_id(layout_id),.state(state),.ball_x_fp(ball_x_fp),
        .black_hole_x(black_hole_x),.black_hole_y(black_hole_y),.white_hole_x(white_hole_x),.white_hole_y(white_hole_y),
        .portal_flash(portal_flash),.portal_anim(portal_anim),.portals_visible(portals_visible),
        .two_ball_mode(two_ball_mode),.balls_visible(balls_visible),.ball2_x_fp(ball2_x_fp),.ball2_y_fp(ball2_y_fp),
        .ball_y_fp(ball_y_fp),.left_angle(left_angle),.right_angle(right_angle),
        .score_bcd(score_bcd),.high_bcd(high_bcd),.lives(lives),.difficulty(difficulty),
        .charge(charge),.hit_flash(hit_flash),.bonus_target(bonus_target),
        .bonus_active(bonus_active),.anim(anim),.cursor_x(cursor_x),.cursor_y(cursor_y),
        .cursor_visible(cursor_visible),.combo(combo),.mission_progress(mission_progress),
        .target_progress(target_progress),.save_timer(save_timer),.feature_event(feature_event),
        .feature_timer(feature_timer),.last_award_bcd(last_award_bcd),.table_progress(table_progress),.spinner_phase(spinner_phase),
        .moving_bumper_y_fp(moving_bumper_y_fp),.moving_bumper_x_fp(moving_bumper_x_fp),
        .side_left_y_fp(side_left_y_fp),.side_right_y_fp(side_right_y_fp),
        .particle_x(particle_x),.particle_y(particle_y),.particle_life(particle_life),
        .trail_x(trail_x),.trail_y(trail_y),.trail_valid(trail_valid),.pixel(pixel));
endmodule
`default_nettype wire
