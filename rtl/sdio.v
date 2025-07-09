`timescale 1ns / 1ps

module sdio(
    input wire CLKCPU,
    input wire RESET_n,
    input wire [23:16] A_HIGH,
    input wire RW_n,
    input wire AS_CPU_n,
    input wire [7:0] BASE_SDIO,
    input wire SDIO_CONFIGURED_n,
    output wire ROM_OE_n,
    output wire SDIO_ACCESS
);

assign SDIO_ACCESS = !SDIO_CONFIGURED_n && (A_HIGH == BASE_SDIO) && !AS_CPU_n;
assign ROM_OE_n = !(SDIO_ACCESS && RW_n);

endmodule
