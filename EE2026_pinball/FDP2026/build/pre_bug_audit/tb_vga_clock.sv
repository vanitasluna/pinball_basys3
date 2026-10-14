`timescale 1ns/1ps
module tb_vga_clock;
    reg clk=0,reset=1;
    wire pixel_clk,locked;
    realtime previous_edge;
    integer i;
    always #5 clk=~clk;
    pinball_vga_clock dut(.*);
    task check_period;
        begin
            repeat(8) @(posedge pixel_clk);
            previous_edge=$realtime;
            for(i=0;i<20;i=i+1) begin
                @(posedge pixel_clk);
                if($realtime-previous_edge<24.99 || $realtime-previous_edge>25.01)
                    $fatal(1,"Pixel clock is not exactly 40 MHz");
                if(!locked) $fatal(1,"Clock lost lock during period check");
                previous_edge=$realtime;
            end
        end
    endtask
    initial begin
        #200;reset=0;
        wait(locked);check_period();
        @(negedge clk);reset=1;
        #200;
        if(locked) $fatal(1,"MMCM reset did not clear lock");
        @(negedge clk);reset=0;
        wait(locked);check_period();
        $display("PASS tb_vga_clock: real MMCM locks, produces 40 MHz and relocks after reset");
        $finish;
    end
    initial begin #200000; $fatal(1,"MMCM lock timeout");end
endmodule
