`timescale 1ns / 1ps

module clock(
    input wire C80M,
    output reg C40M
);

always @ (posedge C80M) begin
    C40M <= ~C40M;
end

endmodule
