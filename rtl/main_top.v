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
    output CLKCPU
);

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

endmodule
