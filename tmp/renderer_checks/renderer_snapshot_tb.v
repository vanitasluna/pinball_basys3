`timescale 1ns/1ps
module renderer_snapshot_tb;
reg [6:0] x=0, ball_x=89, cursor_x=0;
reg [5:0] y=0, ball_y=55, charge=0, cursor_y=0;
reg [2:0] state=0, left_angle=0, right_angle=0;
reg [15:0] score_bcd=16'h1285, high_bcd=16'h4290;
reg [1:0] lives=3, difficulty=1, bonus_target=1;
reg [4:0] hit_flash=0;
reg [7:0] anim=8'h30;
reg bonus_active=1, cursor_visible=0;
wire [15:0] pixel;
integer frame, xx, yy, fd;
reg [255:0] filename;
pinball_renderer dut(x,y,state,ball_x,ball_y,left_angle,right_angle,
score_bcd,high_bcd,lives,difficulty,charge,hit_flash,bonus_target,
bonus_active,anim,cursor_x,cursor_y,cursor_visible,pixel);
initial begin
 for(frame=0;frame<8;frame=frame+1) begin
  case(frame)
   0: begin state=0; difficulty=1; end
   1: begin state=0; difficulty=0; end
   2: begin state=0; difficulty=2; end
   3: begin state=1; difficulty=1; charge=43; end
   4: begin state=2; ball_x=45;ball_y=30;end
   5: begin state=2; left_angle=4;right_angle=4;ball_x=45;ball_y=49;end
   6: begin state=3;end
   7: begin state=4;lives=0;end
  endcase
  $sformat(filename,"frame_%0d.ppm",frame);
  fd=$fopen(filename,"w");
  $fwrite(fd,"P3\n96 64\n255\n");
  for(yy=0;yy<64;yy=yy+1) begin
   for(xx=0;xx<96;xx=xx+1) begin
    x=xx;y=yy;#1;
    if (^pixel===1'bx) begin $display("Unknown pixel frame %0d x%0d y%0d",frame,xx,yy);$finish;end
    $fwrite(fd,"%0d %0d %0d\n",(pixel[15:11]*255)/31,(pixel[10:5]*255)/63,(pixel[4:0]*255)/31);
   end
  end
  $fclose(fd);
 end
 $display("RENDERER SNAPSHOTS PASS");
 $finish;
end
endmodule
