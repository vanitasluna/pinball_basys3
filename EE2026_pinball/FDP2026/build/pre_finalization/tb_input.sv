`timescale 1ns/1ps
module tb_input;
    reg clk=0, reset=1;
    reg [4:0] raw=0;
    wire [4:0] down, pressed;
    integer rises[0:4];
    reg [4:0] previous_pressed=0;
    integer i;
    always #5 clk=~clk;
    pinball_input #(.STABLE_CYCLES(8)) dut
        (.clk(clk),.reset(reset),.raw(raw),.down(down),.pressed(pressed));

    // Count public events, and reject repeated pulses during a held press.
    always @(posedge clk) begin
        #1;
        if (!reset) begin
            if ($isunknown({down,pressed})) $fatal(1,"Unknown debounced input");
            if ((previous_pressed & pressed)!=0) $fatal(1,"Pressed event lasts more than one cycle");
            for (integer k=0;k<5;k=k+1)
                if(pressed[k]) rises[k]=rises[k]+1;
            previous_pressed=pressed;
        end else previous_pressed=0;
    end
    task cycles(input integer n);
        repeat(n) begin @(posedge clk); #2; end
    endtask
    task drive(input [4:0] value);
        @(negedge clk); raw=value;
    endtask

    initial begin
        for(i=0;i<5;i=i+1) rises[i]=0;
        cycles(3); @(negedge clk); reset=0;
        // Several glitches shorter than the debounce interval must disappear.
        drive(5'b00001); cycles(3);
        drive(0); cycles(4);
        drive(5'b00001); cycles(5);
        drive(0); cycles(12);
        if(down!=0 || rises[0]!=0) $fatal(1,"Contact bounce created a press");

        drive(5'b00001); cycles(9);
        if(down[0]) $fatal(1,"Input accepted before synchronization and eight stable samples");
        cycles(1);
        if(down!=5'b00001 || rises[0]!=1) $fatal(1,"Stable press was not accepted once");
        cycles(30);
        if(rises[0]!=1) $fatal(1,"Held button repeated its event");

        // Keep button 0 held, press button 1 cleanly, and bounce button 2.
        // A bouncing channel must not reset another channel's debounce count.
        drive(5'b00111); cycles(3);
        drive(5'b00011); cycles(3);
        drive(5'b00111); cycles(4);
        if(!down[1] || rises[1]!=1 || down[2] || rises[2]!=0)
            $fatal(1,"Independent button debounce failed");
        cycles(6);
        if(down!=5'b00111 || rises[2]!=1) $fatal(1,"Third button failed to settle");

        drive(0); cycles(3);
        drive(5'b00111); cycles(3);
        if(down!=5'b00111) $fatal(1,"Release bounce released a held button");
        drive(0); cycles(12);
        if(down!=0 || rises[0]!=1 || rises[1]!=1 || rises[2]!=1)
            $fatal(1,"Release generated a rising event");
        drive(5'b11000); cycles(12);
        if(down!=5'b11000 || rises[3]!=1 || rises[4]!=1)
            $fatal(1,"Simultaneous independent presses failed");
        @(negedge clk); reset=1; cycles(2);
        if(down!=0 || pressed!=0) $fatal(1,"Reset failed to clear inputs");
        $display("PASS tb_input: bounce rejection, exact settling, simultaneous independent buttons, single-cycle events");
        $finish;
    end
    initial begin #100000; $fatal(1,"tb_input timeout"); end
endmodule
