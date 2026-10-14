`timescale 1ns/1ps
module tb_effects;
    reg clk=0;always #5 clk=~clk;
    reg reset=1,tick=0,active=1,prepare=0;
    reg hit_enable=1,trail_reset=0;
    reg [13:0]hit_events=0;
    reg [14:0]ball_x_fp=39*256+128;
    reg [13:0]ball_y_fp=43*256+128;
    reg [14:0]hit_x_fp=39*256+128;
    reg [13:0]hit_y_fp=43*256+128;
    wire [79:0]particle_x,particle_y,trail_x,trail_y;
    wire [31:0]particle_life;
    wire [7:0]trail_valid;
    wire [55:0]oled_trail_x;
    wire [47:0]oled_trail_y;
    pinball_effects dut(.*);
    task step;@(negedge clk);tick=1;@(negedge clk);tick=0;endtask
    reg [79:0]saved_particles,saved_trail;
    reg [39:0]saved_first_burst,saved_second_burst;
    initial begin
        repeat(3)@(negedge clk);reset=0;
        @(negedge clk);hit_events=1;@(negedge clk);hit_events=0;
        if(particle_life!==32'h0000ffff || particle_x[9:0]!=332 || particle_y[9:0]!=380)
            $fatal(1,"Bumper spark spawn failed");
        repeat(4)step();
        if(particle_x[9:0]>=332 || particle_y[9:0]>=380) $fatal(1,"Sparks did not move");
        if(!trail_valid[0] || trail_x[9:0]!=332 || trail_y[9:0]!=380 || oled_trail_x[6:0]!=39)
            $fatal(1,"Subpixel trail scaling failed");
        // New stand-up contact also emits at the ball's impact location.
        saved_first_burst=particle_x[39:0];
        @(negedge clk);hit_events=14'h2000;@(negedge clk);hit_events=0;
        if(particle_life!==32'hffffeeee || particle_x[49:40]!=332 || particle_y[49:40]!=380 ||
           particle_x[39:0]!=saved_first_burst)
            $fatal(1,"New object spark spawn failed");
        // Ball 2 impacts have their own origin without moving the primary trail.
        saved_second_burst=particle_x[79:40];
        @(negedge clk);hit_x_fp=58*256+64;hit_y_fp=24*256+64;hit_events=14'h0002;
        @(negedge clk);hit_events=0;
        if(particle_life!==32'hffffffff || particle_x[9:0]!=482 || particle_y[9:0]!=226 ||
           particle_x[79:40]!=saved_second_burst || trail_x[9:0]!=332)
            $fatal(1,"Second-ball impact lost either origin or displaced the trail");
        active=0;saved_particles=particle_x;saved_trail=trail_x;
        repeat(8)step();
        if(particle_x!=saved_particles || trail_x!=saved_trail) $fatal(1,"Pause changed effects");
        // An in-flight impact can finish after pause, but its particles must
        // remain frozen rather than disappearing or moving behind the pause.
        @(negedge clk);hit_x_fp=42*256;hit_y_fp=35*256;hit_events=4;
        @(negedge clk);hit_events=0;
        if(particle_life!==32'hffffffff || particle_x[49:40]!=352 || particle_y[49:40]!=312 ||
           particle_x[9:0]!=482 || particle_y[9:0]!=226)
            $fatal(1,"Paused in-flight impact was discarded");
        saved_particles=particle_x;repeat(8)step();
        if(particle_x!=saved_particles || particle_life!==32'hffffffff)
            $fatal(1,"Paused in-flight sparks moved or expired");
        hit_enable=0;
        @(negedge clk);hit_x_fp=58*256;hit_events=2;
        @(negedge clk);hit_events=0;
        if(particle_x!=saved_particles) $fatal(1,"Inactive screen accepted a stale impact");
        hit_enable=1;
        // A survivor handoff clears only history, preserving impact particles.
        @(negedge clk);trail_reset=1;
        @(negedge clk);trail_reset=0;
        if(trail_valid!=0 || particle_x!=saved_particles || particle_life!==32'hffffffff)
            $fatal(1,"Survivor handoff retained a ghost trail or cleared impact particles");
        ball_x_fp=55*256+64;ball_y_fp=38*256+128;
        active=1;repeat(4)step();
        if(trail_valid!==1 || trail_x[9:0]!=458 || trail_y[9:0]!=340)
            $fatal(1,"Surviving ball did not start a clean fractional trail");
        active=1;repeat(64)step();
        if(particle_life!=0 || trail_valid!=255) $fatal(1,"Particle expiry or trail history failed");
        @(negedge clk);prepare=1;@(negedge clk);prepare=0;
        if(trail_valid!=0 || particle_life!=0) $fatal(1,"Prepare did not clear effects");
        $display("PASS tb_effects: two retained impact bursts, completed origins, paused late bursts, clean survivor trail, subpixel motion, expiry, prepare");$finish;
    end
endmodule
