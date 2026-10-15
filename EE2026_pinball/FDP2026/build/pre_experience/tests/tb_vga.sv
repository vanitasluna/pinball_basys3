`timescale 1ns/1ps
module tb_vga;
    reg clk=0, reset=1;
    wire [6:0] x;
    wire [5:0] y;
    wire [9:0] pixel_x,pixel_y;
    wire frame_begin;
    wire [3:0] red,green,blue;
    wire hsync,vsync;
    // Position-dependent colors detect incorrect scaling as well as bit slicing.
    wire [15:0] pixel={pixel_x[4:0],pixel_y[5:0],(pixel_x[4:0]^pixel_y[4:0])};
    integer expected_h,expected_v,hs_high,vs_high,image_pixels,frames;
    integer lx,ly;
    reg [15:0] expected_pixel;
    reg expected_hs,expected_vs,expected_inside;
    always #12.5 clk=~clk;
    pinball_vga dut(.clk(clk),.reset(reset),.pixel(pixel),.x(x),.y(y),
        .frame_begin(frame_begin),.pixel_x(pixel_x),.pixel_y(pixel_y),.red(red),.green(green),.blue(blue),
        .hsync(hsync),.vsync(vsync));

    initial begin
        repeat(3) @(posedge clk);
        @(negedge clk); reset=0;
        expected_h=0; expected_v=0; hs_high=0; vs_high=0; image_pixels=0; frames=0;
        repeat(1056*628) begin
            // The renderer sees the current coordinate before the output register.
            #1;
            expected_inside=expected_h>=16 && expected_h<784 && expected_v>=32 && expected_v<544;
            lx=expected_inside ? (expected_h-16)/8 : 0;
            ly=expected_inside ? (expected_v-32)/8 : 0;
            if(x!==lx || y!==ly) $fatal(1,"Eightfold table coordinate wrong at (%0d,%0d): %0d,%0d",expected_h,expected_v,x,y);
            if(frame_begin) frames=frames+1;
            if(frame_begin !== (expected_h==0 && expected_v==0)) $fatal(1,"Frame boundary incorrect");
            if(pixel_x!==(expected_h<800 ? expected_h : 0) || pixel_y!==(expected_v<600 ? expected_v : 0)) $fatal(1,"Native pixel coordinates incorrect");
            expected_pixel=pixel;
            expected_hs=(expected_h>=840 && expected_h<968);
            expected_vs=(expected_v>=601 && expected_v<605);
            @(posedge clk); #1;
            if($isunknown({x,y,red,green,blue,hsync,vsync,frame_begin})) $fatal(1,"Unknown VGA output");
            if(hsync!==expected_hs || vsync!==expected_vs) $fatal(1,"Sync timing wrong at (%0d,%0d)",expected_h,expected_v);
            if(expected_h<800 && expected_v<600) begin
                image_pixels=image_pixels+1;
                if({red,green,blue}!=={expected_pixel[15:12],expected_pixel[10:7],expected_pixel[4:1]})
                    $fatal(1,"RGB565 conversion incorrect at (%0d,%0d)",expected_h,expected_v);
            end else if({red,green,blue}!==12'd0) $fatal(1,"Blanking/border is not black");
            if(hsync) hs_high=hs_high+1;
            if(vsync) vs_high=vs_high+1;
            if(expected_h==1055) begin expected_h=0; expected_v=expected_v==627 ? 0 : expected_v+1; end
            else expected_h=expected_h+1;
            @(negedge clk);
        end
        if(frames!=1 || !frame_begin) $fatal(1,"Frame period is not 663168 clocks");
        if(hs_high!=128*628 || vs_high!=4*1056) $fatal(1,"Sync pulse widths incorrect");
        if(image_pixels!=800*600) $fatal(1,"Native VGA does not cover all 800x600 active pixels");
        $display("PASS tb_vga: 1056x628 frame, sync widths, native 800x600 coordinates, RGB565 conversion and porch blanking");
        $finish;
    end
    initial begin #20000000; $fatal(1,"tb_vga timeout"); end
endmodule
