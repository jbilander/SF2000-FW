`timescale 1ns / 1ps
`default_nettype none

module main_top(
    input wire JP2,
    input wire C7M_n,
    input wire RESET_n,
    input wire AS_CPU_n,
    input wire VPA_n,
    input wire [2:0] FC,
    input wire DTACK_MB_n,
    input wire E_IN,
    input wire AS_MB_n_IN,
    output wire E_OUT,
    output wire CLKCPU,
    output wire VMA_n,
    output wire OE_BANK0_n,
    output wire OE_BANK1_n,
    output wire WE_BANK0_ODD_n,
    output wire WE_BANK1_ODD_n,
    output wire WE_BANK0_EVEN_n,
    output wire WE_BANK1_EVEN_n,
    output wire DTACK_CPU_n,
    output wire AS_MB_n_OUT,
    output wire AS_MB_n_OE,
    output wire ROM_OE_n,
    output wire FLASH_WE_n,
    output wire FLASH_OE_n,
    output wire INT2_n,
    output wire E_OE,
    output wire BR_68SEC000_n
);

wire C7M = ~C7M_n;
wire m6800_dtack_n;

assign CLKCPU = C7M;
assign AS_MB_n_OUT = AS_CPU_n;
assign AS_MB_n_OE = 1'b1;
assign E_OE = !JP2;
assign DTACK_CPU_n = DTACK_MB_n & m6800_dtack_n;
assign OE_BANK0_n = 1'b1;
assign OE_BANK1_n = 1'b1;
assign WE_BANK0_ODD_n = 1'b1;
assign WE_BANK1_ODD_n = 1'b1;
assign WE_BANK0_EVEN_n = 1'b1;
assign WE_BANK1_EVEN_n = 1'b1;
assign ROM_OE_n = 1'b1;
assign FLASH_WE_n = 1'b1;
assign FLASH_OE_n = 1'b1;
assign INT2_n = 1'b1;
assign BR_68SEC000_n = 1'b1;

m6800 m6800_bus(
    .JP2(JP2),
    .C7M(C7M),
    .RESET_n(RESET_n),
    .VPA_n(VPA_n),
    .CPUSPACE(&FC),
    .AS_CPU_n(AS_CPU_n),
    .E_IN(E_IN),
    .E_OUT(E_OUT),
    .VMA_n(VMA_n),
    .M6800_DTACK_n(m6800_dtack_n)
);

endmodule
