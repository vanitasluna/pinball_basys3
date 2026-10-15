`timescale 1ns / 1ps
`default_nettype none
// Arcade rules. All real-time counters use the 240 Hz physics enable; score
// awards use a three-clock pipeline so added features keep the 100 MHz path short.
module pinball_game (
    input wire clk, reset, tick,
    input wire start_press, launch_down, pause_press, menu_press,
    input wire level_left, level_right, two_ball_select,
    input wire drained, input wire [13:0] hit_events,
    input wire in_lane, nudge_press,
    output reg [2:0] state,
    output reg [1:0] lives, difficulty,
    output reg two_ball_mode,
    output reg [15:0] score_bcd, high_bcd,
    output reg [5:0] charge,
    output reg prepare, launch,
    output wire active,
    output wire [13:0] hit_flash,
    output reg [1:0] bonus_target,
    output wire bonus_active,
    output reg [7:0] anim,
    output reg [2:0] combo,
    output reg [2:0] mission_progress,
    output reg [1:0] target_progress,
    output reg [5:0] table_progress,
    output reg [3:0] spinner_phase,
    output reg [10:0] save_timer,
    output reg [2:0] feature_event,
    output reg [15:0] last_award_bcd,
    output reg [9:0] feature_timer
);
    localparam MENU=3'd0, READY=3'd1, PLAY=3'd2, PAUSE=3'd3, OVER=3'd4;
    // feature_event: 0 none, 1 gold bonus, 2 combo, 3 bumper jackpot,
    // 4 saved ball, 5 side-target reward, 6 nudge, 7 table bonus.
    reg [2:0] resume_state;
    reg charging, charge_falling, launch_save_eligible;
    reg [1:0] charge_div;
    reg [9:0] bonus_timer, combo_timer;
    reg [15:0] rng;
    reg [4:0] flash_timer [0:13];
    reg [6:0] spinner_timer;
    reg [1:0] spinner_div;
    reg award_valid_1, award_valid_2;
    reg [6:0] award_units_1;
    reg [15:0] award_bcd_2;
    reg [6:0] multiplied_units;
    reg score_half;
    integer i;
    assign active = state == PLAY;
    assign bonus_active = state == PLAY && bonus_timer != 0 && bonus_timer <= 480;

    // A registered physics result may complete after the user pauses. Accept
    // that final result, retaining its bonus and save entitlement, then freeze.
    wire accepts_play_event = state == PLAY || (state == PAUSE && resume_state == PLAY);
    wire accepts_hit = accepts_play_event && |hit_events;
    wire bonus_available = accepts_play_event && bonus_timer != 0 && bonus_timer <= 480;
    wire bonus_hit = bonus_available && hit_events[bonus_target];
    wire [2:0] mission_next = mission_progress | hit_events[2:0];
    wire [1:0] target_next = target_progress | hit_events[4:3];
    wire [2:0] rollover_next = table_progress[2:0] | hit_events[7:5];
    wire [2:0] bank_next = table_progress[5:3] | hit_events[13:11];
    wire mission_complete = accepts_hit && &mission_next;
    wire target_complete = accepts_hit && &target_next;
    wire rollover_complete = accepts_hit && &rollover_next;
    wire bank_complete = accepts_hit && &bank_next;
    wire [2:0] scoring_combo = combo_timer == 0 ? 3'd1 :
        (combo < 4 ? combo + 1'b1 : 3'd4);
    wire [4:0] base_units = {4'd0,hit_events[0]} + {4'd0,hit_events[1]} +
        {4'd0,hit_events[2]} + {3'd0,hit_events[3],1'b0} + {3'd0,hit_events[4],1'b0} +
        {4'd0,hit_events[5]} + {4'd0,hit_events[6]} + {4'd0,hit_events[7]} +
        {4'd0,hit_events[8]} + {4'd0,hit_events[9]} + {4'd0,hit_events[10]} +
        {3'd0,hit_events[11],1'b0} + {3'd0,hit_events[12],1'b0} +
        {3'd0,hit_events[13],1'b0};
    wire [2:0] hit_feature = mission_complete ? 3'd3 : target_complete ? 3'd5 :
        rollover_complete || bank_complete ? 3'd7 :
        bonus_hit ? 3'd1 : scoring_combo > 1 ? 3'd2 : 3'd0;
    wire new_game = start_press && (state == MENU || state == OVER);
    // A completed drain and a pause/resume command can share one clock.
    // Apply that command to the prepared next life instead of discarding it.
    wire next_life_paused = state == PAUSE ? !(pause_press || start_press) : pause_press;
    // Award units are half-points. Carry the fractional remainder between
    // transactions so two small contacts still contribute a whole point.
    wire [7:0] credit_half_units = {1'b0,award_units_1} + {7'd0,score_half};

    genvar g;
    generate for(g=0;g<14;g=g+1) begin: flashes
        assign hit_flash[g] = flash_timer[g] != 0;
    end endgenerate

    // One internal award unit is half a point. The largest transaction is 110
    // units (55 points): all fourteen contacts at x4 plus every flat bonus.
    // The integer credit after carrying a previous half-point is at most 55.
    // Constant comparisons provide decimal conversion without a multiplier.
    function [15:0] points_to_bcd;
        input [6:0] points;
        reg [6:0] ones;
        reg [3:0] tens;
        begin
            ones=points; tens=0;
            if(ones>=60) begin ones=ones-60; tens=6; end
            else if(ones>=50) begin ones=ones-50; tens=5; end
            else if(ones>=40) begin ones=ones-40; tens=4; end
            else if(ones>=30) begin ones=ones-30; tens=3; end
            else if(ones>=20) begin ones=ones-20; tens=2; end
            else if(ones>=10) begin ones=ones-10; tens=1; end
            points_to_bcd={8'd0,tens,ones[3:0]};
        end
    endfunction

    // Decimal carry in each nibble; score saturates at 9999.
    function [15:0] add_bcd;
        input [15:0] a,b;
        reg [4:0] d;
        reg carry;
        reg [15:0] result;
        integer k;
        begin
            carry=0; result=0;
            for(k=0;k<4;k=k+1) begin
                d={1'b0,a[k*4+:4]}+{1'b0,b[k*4+:4]}+carry;
                carry=d>=10;
                result[k*4+:4]=carry ? d-10 : d;
            end
            add_bcd=carry ? 16'h9999 : result;
        end
    endfunction

    always @* begin
        case(scoring_combo)
            3'd2: multiplied_units={2'd0,base_units} << 1;
            3'd3: multiplied_units={2'd0,base_units}+({2'd0,base_units} << 1);
            3'd4: multiplied_units={2'd0,base_units} << 2;
            default: multiplied_units={2'd0,base_units};
        endcase
    end

    always @(posedge clk) begin
        if(reset) begin
            state<=MENU; resume_state<=PLAY; lives<=3; difficulty<=1; two_ball_mode<=0;
            score_bcd<=0; high_bcd<=0; charge<=0; charge_div<=0;
            charging<=0; charge_falling<=0; prepare<=0; launch<=0; bonus_timer<=720;
            bonus_target<=0; rng<=16'hACE1; anim<=0;
            combo<=1; combo_timer<=0; mission_progress<=0; target_progress<=0;
            table_progress<=0; spinner_phase<=0; spinner_timer<=0; spinner_div<=0;
            save_timer<=0; launch_save_eligible<=1;
            feature_event<=0; feature_timer<=0; last_award_bcd<=0;
            award_valid_1<=0; award_valid_2<=0; award_units_1<=0; award_bcd_2<=0;
            score_half<=0;
            for(i=0;i<14;i=i+1) flash_timer[i]<=0;
        end else begin
            rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};
            prepare<=0; launch<=0;

            // The award pipeline accepts a transaction every clock and commits
            // scores even after a pause or drain. Only a new game flushes it.
            award_valid_1<=accepts_hit;
            if(accepts_hit) award_units_1<=multiplied_units +
                (bonus_hit ? 7'd5 : 7'd0) + (mission_complete ? 7'd10 : 7'd0) +
                (target_complete ? 7'd5 : 7'd0) + (rollover_complete ? 7'd6 : 7'd0) +
                (bank_complete ? 7'd8 : 7'd0);
            award_valid_2<=award_valid_1;
            if(award_valid_1) begin
                award_bcd_2<=points_to_bcd(credit_half_units[7:1]);
                score_half<=credit_half_units[0];
            end
            if(award_valid_2) begin
                score_bcd<=add_bcd(score_bcd,award_bcd_2);
                last_award_bcd<=award_bcd_2;
            end
            // Independent comparison keeps the high-score path short.
            if(score_bcd>high_bcd) high_bcd<=score_bcd;

            if(tick && state!=PAUSE) begin
                anim<=anim+1'b1;
                for(i=0;i<14;i=i+1)
                    if(flash_timer[i]!=0) flash_timer[i]<=flash_timer[i]-1'b1;
                if(feature_timer!=0) begin
                    feature_timer<=feature_timer-1'b1;
                    if(feature_timer==1) feature_event<=0;
                end
            end
            if(tick && state==PLAY) begin
                if(spinner_timer!=0) begin
                    spinner_timer<=spinner_timer-1'b1;
                    spinner_div<=spinner_div+1'b1;
                    if(spinner_div==3) spinner_phase<=spinner_phase+1'b1;
                end
                if(combo_timer!=0) begin
                    combo_timer<=combo_timer-1'b1;
                    if(combo_timer==1) combo<=1;
                end
                // The launch grace begins when the ball leaves its lane.
                if(save_timer!=0 && !in_lane) save_timer<=save_timer-1'b1;
                if(!bonus_hit) begin
                    if(bonus_timer==0) begin
                        bonus_timer<=720;
                        bonus_target<=rng[1:0]==3 ? 0 : rng[1:0];
                    end else bonus_timer<=bonus_timer-1'b1;
                end
            end
            if(accepts_hit) begin
                combo<=scoring_combo; combo_timer<=480;
                mission_progress<=mission_complete ? 3'd0 : mission_next;
                target_progress<=target_complete ? 2'd0 : target_next;
                table_progress<={bank_complete ? 3'd0 : bank_next,
                    rollover_complete ? 3'd0 : rollover_next};
                for(i=0;i<14;i=i+1) if(hit_events[i]) flash_timer[i]<=24;
                if(hit_events[8]) begin
                    spinner_phase<=spinner_phase+3;
                    spinner_timer<=120; spinner_div<=0;
                end
                if(bonus_hit) begin
                    bonus_timer<=720;
                    bonus_target<=rng[1:0]==3 ? 0 : rng[1:0];
                end
                if(target_complete) save_timer<=1440;
                if(hit_feature!=0) begin feature_event<=hit_feature; feature_timer<=240; end
            end
            if(nudge_press && state==PLAY && (!accepts_hit || hit_feature==0)) begin
                feature_event<=6; feature_timer<=240;
            end

            // Returning to the menu preserves the session high score.
            if(menu_press) begin
                state<=MENU; charging<=0; charge<=0; charge_div<=0;
                charge_falling<=0; prepare<=1;
            end else if(new_game) begin
                state<=READY; score_bcd<=0; lives<=3; prepare<=1; two_ball_mode<=two_ball_select;
                charge<=0; charge_div<=0; charging<=0; charge_falling<=0; bonus_timer<=720;
                bonus_target<=rng[1:0]==3 ? 0 : rng[1:0];
                combo<=1; combo_timer<=0; mission_progress<=0; target_progress<=0;
                table_progress<=0; spinner_phase<=0; spinner_timer<=0; spinner_div<=0;
                save_timer<=0; launch_save_eligible<=1;
                feature_event<=0; feature_timer<=0; last_award_bcd<=0;
                award_valid_1<=0; award_valid_2<=0;
                score_half<=0;
                for(i=0;i<14;i=i+1) flash_timer[i]<=0;
            end else if(drained && accepts_play_event) begin
                charge<=0; charge_div<=0; charging<=0; charge_falling<=0;
                combo<=1; combo_timer<=0;
                if(save_timer!=0 || target_complete) begin
                    save_timer<=0; prepare<=1; launch_save_eligible<=0;
                    if(!mission_complete && !target_complete && !rollover_complete && !bank_complete) begin
                        feature_event<=4; feature_timer<=240;
                    end
                    if(next_life_paused) begin state<=PAUSE; resume_state<=READY; end
                    else state<=READY;
                end else if(lives<=1) begin lives<=0; state<=OVER; end
                else begin
                    lives<=lives-1'b1; prepare<=1; launch_save_eligible<=1;
                    if(next_life_paused) begin state<=PAUSE; resume_state<=READY; end
                    else state<=READY;
                end
            end else case(state)
                MENU: begin
                    if(level_left) difficulty<=difficulty==0 ? 2 : difficulty-1'b1;
                    else if(level_right) difficulty<=difficulty==2 ? 0 : difficulty+1'b1;
                end
                READY: begin
                    if(pause_press) begin resume_state<=READY; state<=PAUSE; end
                    else if(launch_down) begin
                        charging<=1;
                        if(tick) begin
                            charge_div<=charge_div+1'b1;
                            // 60 power steps/second: 0 -> 63 -> 0 while held.
                            // Reverse on arrival so neither endpoint adds a pause.
                            if(charge_div==3) begin
                                if(charge_falling) begin
                                    if(charge<=1) begin charge<=0; charge_falling<=0; end
                                    else charge<=charge-1'b1;
                                end else begin
                                    if(charge>=62) begin charge<=63; charge_falling<=1; end
                                    else charge<=charge+1'b1;
                                end
                            end
                        end
                    end else if(charging) begin
                        // A tap still gives enough energy to leave the lane.
                        if(charge<16) charge<=16;
                        launch<=1; state<=PLAY; charging<=0;
                        if(launch_save_eligible) save_timer<=720;
                        launch_save_eligible<=0;
                    end
                end
                PLAY: if(pause_press) begin resume_state<=PLAY; state<=PAUSE; end
                PAUSE: if(pause_press || start_press) begin
                    state<=resume_state;
                    charging<=0; charge<=0; charge_div<=0; charge_falling<=0;
                end
                default: state<=state==OVER ? OVER : MENU;
            endcase
        end
    end
endmodule
`default_nettype wire
