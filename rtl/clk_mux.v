`timescale 1ns / 1ps

module clk_mux(
    input CLK1,
    input CLK2,
    input RESET_n,
    input CPU_SPEED_SWITCH,
    output CLKOUT
);

reg meta_1_off = 1'b0;
reg meta_1_on  = 1'b1;
reg sync_1_off = 1'b0;
reg sync_1_on  = 1'b1;

reg meta_2_off = 1'b1;
reg meta_2_on  = 1'b0;
reg sync_2_off = 1'b1;
reg sync_2_on  = 1'b0;

assign CLKOUT = (CLK1 & ~sync_1_off & sync_1_on) | (CLK2 & ~sync_2_off & sync_2_on);

always @(posedge CLK1 or negedge RESET_n) begin

    if(!RESET_n) begin

        meta_1_off <= 1'b0;
        sync_1_off <= 1'b0;
        meta_1_on  <= 1'b1;
        sync_1_on  <= 1'b1;

    end else begin

        // Switch off when not selected
        meta_1_off <= ~CPU_SPEED_SWITCH;
        sync_1_off <= meta_1_off;

        // Switch on when other clock (clk2) is off 
        meta_1_on  <= sync_2_off;
        sync_1_on  <= meta_1_on;

    end

end

always @(posedge CLK2 or negedge RESET_n) begin

    if(!RESET_n) begin

        meta_2_off <= 1'b1;
        sync_2_off <= 1'b1;
        meta_2_on  <= 1'b0;
        sync_2_on  <= 1'b0;

    end else begin

        // Switch off when not selected
        meta_2_off <= CPU_SPEED_SWITCH;
        sync_2_off <= meta_2_off;

        // Switch on when other clock (clk1) is off 
        meta_2_on  <= sync_1_off;
        sync_2_on  <= meta_2_on;

    end

end

endmodule