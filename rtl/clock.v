`timescale 1ns / 1ps

module clock(
    input wire C80M,
    input wire C100M,
    output reg C40M,
    output reg C50M
);

always @ (posedge C100M) begin
    C50M <= ~C50M;
end

always @ (posedge C80M) begin
    C40M <= ~C40M;
end

endmodule
