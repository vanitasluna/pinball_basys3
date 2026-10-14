`timescale 1ns/1ps
// Eight ballistic sparks and eight subpixel trail samples. The physical
// scene receives all particles atomically at its display-frame boundary.
module pinball_effects(input clk,reset,tick,active,prepare,hit_enable,trail_reset,
    input [13:0] hit_events, input [14:0] ball_x_fp, input [13:0] ball_y_fp,
    input [14:0] hit_x_fp, input [13:0] hit_y_fp,
    output [79:0] particle_x,particle_y, output [31:0] particle_life,
    output [79:0] trail_x,trail_y, output reg [7:0] trail_valid,
    output [55:0] oled_trail_x, output [47:0] oled_trail_y);
    reg signed [14:0] px[0:7],py[0:7];
    reg signed [7:0] vx[0:7],vy[0:7];
    reg [3:0] life[0:7];
    reg [14:0] tx[0:7]; reg [13:0] ty[0:7];
    reg [1:0] phase;
    reg [9:0] emitter_x,emitter_y;
    integer i;
    // Emit at the corrected impact position, including every new object.
    // Eightfold native scaling is wiring, not a hardware multiplier.
    always @* begin
        emitter_x=10'd16+{3'b0,hit_x_fp[14:5]};
        emitter_y=10'd32+{1'b0,hit_y_fp[13:5]};
    end
    genvar g;
    generate for(g=0;g<8;g=g+1) begin: outputs
        assign particle_x[g*10+:10]=px[g]<0 ? 10'd0 : px[g][13:4];
        assign particle_y[g*10+:10]=py[g]<0 ? 10'd0 : py[g][13:4];
        assign particle_life[g*4+:4]=life[g];
        assign trail_x[g*10+:10]=10'd16+tx[g][14:5];
        assign trail_y[g*10+:10]=10'd32+{1'b0,ty[g][13:5]};
        assign oled_trail_x[g*7+:7]=tx[g][14:8];
        assign oled_trail_y[g*6+:6]=ty[g][13:8];
    end endgenerate
    always @(posedge clk) begin
        if(reset || prepare) begin
            phase<=0;trail_valid<=0;
            for(i=0;i<8;i=i+1) begin
                px[i]<=0;py[i]<=0;vx[i]<=0;vy[i]<=0;life[i]<=0;
                tx[i]<=0;ty[i]<=0;
            end
        end else begin
            if(tick && active) begin
                phase<=phase+1'b1;
                if(phase==3) begin
                    trail_valid<={trail_valid[6:0],1'b1};
                    tx[0]<=ball_x_fp;ty[0]<=ball_y_fp;
                    for(i=1;i<8;i=i+1) begin tx[i]<=tx[i-1];ty[i]<=ty[i-1];end
                end
                for(i=0;i<8;i=i+1) if(life[i]!=0) begin
                    px[i]<=px[i]+vx[i];py[i]<=py[i]+vy[i];
                    if(vy[i]<96) vy[i]<=vy[i]+1'b1;
                    if(phase==3) life[i]<=life[i]-1'b1;
                    if(px[i]<0 || px[i]>=12800 || py[i]<0 || py[i]>=9600) life[i]<=0;
                end
            end
            // A collision accepted before pause may finish during it. Preserve
            // its burst, then freeze its motion until play resumes.
            if(hit_enable && |hit_events) begin
                for(i=0;i<8;i=i+1) begin
                    px[i]<=$signed({1'b0,emitter_x,4'b0});
                    py[i]<=$signed({1'b0,emitter_y,4'b0});
                    life[i]<=15;
                    case(i)
                        0:begin vx[i]<=-64;vy[i]<=-42;end
                        1:begin vx[i]<=-42;vy[i]<=-64;end
                        2:begin vx[i]<=0;vy[i]<=-74;end
                        3:begin vx[i]<=42;vy[i]<=-64;end
                        4:begin vx[i]<=64;vy[i]<=-42;end
                        5:begin vx[i]<=53;vy[i]<=16;end
                        6:begin vx[i]<=0;vy[i]<=42;end
                        7:begin vx[i]<=-53;vy[i]<=16;end
                    endcase
                end
            end
            // Switching to the surviving gold ball must not connect its new
            // trail to the white ball's old path. Keep existing impact sparks.
            if(trail_reset) begin
                phase<=0; trail_valid<=0;
                for(i=0;i<8;i=i+1) begin tx[i]<=0; ty[i]<=0; end
            end
        end
    end
endmodule
