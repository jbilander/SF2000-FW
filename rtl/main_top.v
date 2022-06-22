`timescale 1ns / 1ps

module main_top(
    input C7M,
    input OSC_CLK,
    input RESET_n,
    input CFGIN_n,
    input [23:1] A,
    input SW1,
    input JP2,
    input JP3,
    input JP4,
    input JP6,
    input JP7,
    input RW_n,
    input UDS_n,
    input LDS_n,
    input VPA_n,
    input [2:0] FC,
    input AS_CPU_n,
    output CFGOUT_n,
    output CLKCPU,
    output E,
    output VMA_n,
    inout [15:0] D
);

/*
Jumper descriptions:
SW1: 7 Mhz / Turbo
JP2: Turbo speed selector
JP3: Turbo speed selector
JP4: Turbo speed selector
JP5: generate E-CLK
JP6: 4/8 MB
JP7: Autoboot IDE
*/

wire ds_n = LDS_n & UDS_n;  //Data Strobe
wire m6800_dtack_n;
wire [7:5] base_ram;        // base address for the RAM_CARD in Z2-space. (A23-A21)
wire [7:0] base_ide;        // base address for the IDE_CARD in Z2-space. (A23-A16)

wire ram_configured_n;      // keeps track if RAM_CARD is autoconfigured ok.
//wire ram_access;            // keeps track if local SRAM is being accessed.
wire ide_configured_n;      // keeps track if IDE_CARD is autoconfigured ok.
//wire ide_access;            // keeps track if the IDE is being accessed.

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

autoconfig_zii autoconfig(
    .C7M(C7M),
    .CFGIN_n(CFGIN_n),
    .JP6(JP6),
    .JP7(JP7),
    .AS_CPU_n(AS_CPU_n),
    .RESET_n(RESET_n),
    .DS_n(ds_n),
    .RW_n(RW_n),
    .A_HIGH(A[23:16]),
    .A_LOW(A[6:1]),
    .D_HIGH_NYBBLE(D[15:12]),
    .BASE_RAM(base_ram[7:5]),
    .BASE_IDE(base_ide[7:0]),
    .RAM_CONFIGURED_n(ram_configured_n),
    .IDE_CONFIGURED_n(ide_configured_n),
    .CFGOUT_n(CFGOUT_n)
);

endmodule
