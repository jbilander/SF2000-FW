`timescale 1ns / 1ps

module main_top(
    input C7M,
    input OSC_CLK,
    input RESET_n,
    input SW1,
    input JP2,
    input JP3,
    input JP4,
    input AS_CPU_n,
    input VPA_n,
    input [2:0] FC,
    output CLKCPU,
    output E,
    output VMA_n
);

wire m6800_dtack_n;

clock clkcontrol(
    .C7M(C7M),
    .OSC_CLK(OSC_CLK),
    .RESET_n(RESET_n),
    .SW1(SW1),
    .JP2(JP2),
    .JP3(JP3),
    .JP4(JP4),
    .AS_CPU_n(AS_CPU_n),
    .CLKCPU(CLKCPU)
);

m6800 m6800_bus(
	.C7M(C7M),
	.RESET_n(RESET_n),
	.VPA_n(VPA_n),
	.CPUSPACE(&FC),
	.AS_CPU_n(AS_CPU_n),
	.E(E),
	.VMA_n(VMA_n),
	.M6800_DTACK_n(m6800_dtack_n)
);

endmodule
