`timescale 1ns / 1ps

module clock(
    input wire JP1,
    input wire C14M,
    input wire C80M,
    input wire C100M,
    output reg C7M,
    output reg C40M,
    output reg C50M,
    output wire CLKCPU
);

assign CLKCPU = JP1 ? C7M : C40M;

always @ (posedge C100M) begin
    C50M <= ~C50M;
end

always @ (posedge C80M) begin
    C40M <= ~C40M;
end

always @ (posedge C14M) begin
    C7M <= ~C7M;
end

endmodule
