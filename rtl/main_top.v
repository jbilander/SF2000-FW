`timescale 1ns / 1ps

module main_top(
    input C14M,
    input RESET_n,
    input pll_inst1_CLKOUT0,
    input pll_inst1_CLKOUT1,
    input JP1,
    input AS_CPU_n,
    input VPA_n,
    input [2:0] FC,
    input DTACK_MB_n,
    output E_OUT,
    output CLKCPU,
    output DTACK_CPU_n,
    output AS_MB_n
);

/*
Jumper descriptions:
JP1: 7 MHz / Turbo
JP2: E-CLK
JP3: Rom overlay
JP4: 4/8 MB SRAM
*/

wire C7M;
wire C40M;
wire C50M;

wire m6800_dtack_n;

assign DTACK_CPU_n = DTACK_MB_n & m6800_dtack_n;
assign AS_MB_n = AS_CPU_n;

clock clkcontrol(
    .JP1(JP1),
    .C14M(C14M),
    .C80M(pll_inst1_CLKOUT0),
    .C100M(pll_inst1_CLKOUT1),
    .C7M(C7M),
    .C40M(C40M),
    .C50M(C50M),
    .CLKCPU(CLKCPU)
);

m6800 m6800_bus(
    .C7M(C7M),
    .RESET_n(RESET_n),
    .VPA_n(VPA_n),
    .CPUSPACE(&FC),
    .AS_CPU_n(AS_CPU_n),
    .E_OUT(E_OUT),
    .VMA_n(VMA_n),
    .M6800_DTACK_n(m6800_dtack_n)
);

endmodule
