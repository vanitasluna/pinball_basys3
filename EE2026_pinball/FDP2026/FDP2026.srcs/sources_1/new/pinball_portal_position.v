`timescale 1ns / 1ps
`default_nettype none

// Four safe portal sites per table family. The geometry checker verifies
// these centers against full moving-object sweeps in all 64 layouts.
// Minor variants and diamond profiles share clearance, keeping the ROM small.
module pinball_portal_position (
    input wire [5:0] layout_id,
    input wire [1:0] slot,
    output wire [6:0] x,
    output wire [5:0] y
);
    reg [12:0] center;
    always @* begin
        case ({layout_id[5],layout_id[3:2],slot})
            5'd0: center={7'd12,6'd14};
            5'd1: center={7'd34,6'd43};
            5'd2: center={7'd54,6'd37};
            5'd3: center={7'd72,6'd30};
            5'd4: center={7'd12,6'd14};
            5'd5: center={7'd42,6'd43};
            5'd6: center={7'd50,6'd14};
            5'd7: center={7'd78,6'd23};
            5'd8: center={7'd12,6'd14};
            5'd9: center={7'd34,6'd43};
            5'd10: center={7'd50,6'd14};
            5'd11: center={7'd72,6'd33};
            5'd12: center={7'd12,6'd14};
            5'd13: center={7'd35,6'd43};
            5'd14: center={7'd50,6'd14};
            5'd15: center={7'd78,6'd23};
            5'd16: center={7'd9,6'd14};
            5'd17: center={7'd34,6'd43};
            5'd18: center={7'd55,6'd30};
            5'd19: center={7'd78,6'd38};
            5'd20: center={7'd9,6'd15};
            5'd21: center={7'd34,6'd43};
            5'd22: center={7'd51,6'd14};
            5'd23: center={7'd78,6'd38};
            5'd24: center={7'd9,6'd15};
            5'd25: center={7'd34,6'd43};
            5'd26: center={7'd51,6'd14};
            5'd27: center={7'd78,6'd38};
            5'd28: center={7'd9,6'd15};
            5'd29: center={7'd34,6'd43};
            5'd30: center={7'd51,6'd14};
            5'd31: center={7'd78,6'd38};
            default: center={7'd12,6'd14};
        endcase
    end
    assign {x,y}=center;
endmodule
`default_nettype wire

