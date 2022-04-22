`timescale 1ns / 1ps

module main_top(
	input C7M,
	input CDAC,
    input OSC_CLK,
	output CLKCPU,
    output reg TEST = 1'b1,
    output reg TEST2 = 1'b1
    );

wire C14M = C7M ^ CDAC;

assign CLKCPU = C14M;
 
always @(posedge C14M) begin
	TEST <= ~TEST;
end

always @(posedge OSC_CLK) begin
	TEST2 <= ~TEST2;
end

endmodule
