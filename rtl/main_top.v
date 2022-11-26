`timescale 1ns / 1ps

module main_top(
    input C7M,
    input RESET_n,
    input CFGIN_n,
    input [23:1] A,
    input OSC_CLK_X1,
    input SW1,
    input JP2,
    input JP3,
    input JP4,
    input JP5,
    input JP6,
    input JP7,
    input JP8,
    input RW_n,
    input UDS_n,
    input LDS_n,
    input AS_CPU_n,
    input VPA_n,
    input [2:0] FC,
    input DTACK_MB_n,
    input BGACK_n,
    input BG_68SEC000_n,
    output BR_68SEC000_n,
    output CFGOUT_n,
    output CLKCPU,
    output VMA_n,
    output OE_BANK0_n,
    output OE_BANK1_n,
    output WE_BANK0_ODD_n,
    output WE_BANK1_ODD_n,
    output WE_BANK0_EVEN_n,
    output WE_BANK1_EVEN_n,
    output ROM_B1,
    output ROM_B2,
    output ROM_WE_n,
    output ROM_OE_n,
    output IDE_IOR_n,
    output IDE_IOW_n,
    output [1:0] IDE_CS_n,
    output DTACK_CPU_n,
    inout BR_n,
    inout BG_n,
    inout E,
    inout AS_MB_n,
    inout [15:0] D
);

/*
Jumper descriptions:
     Closed/Open
SW1: 7 Mhz / Turbo
JP2: Turbo speed selector
JP3: Turbo speed selector
JP4: Turbo speed selector
JP5: generate E-CLK
JP6: 4/8 MB
JP7: Autoboot IDE OFF/ON
JP8: Oktagon/Oktapus. IDE-driver
JP9: Rom override ON/OFF
*/

reg cpu_speed_switch = 1'b1;
reg rom_pin2 = 1'b0;
reg rom_pin31 = 1'b1;

wire ds_n = LDS_n & UDS_n;      // Data Strobe
wire [7:5] base_ram;            // base address for the RAM_CARD in Z2-space. (A23-A21)
wire [7:0] base_ide;            // base address for the IDE_CARD in Z2-space. (A23-A16)

wire ram_configured_n;          // keeps track if RAM_CARD is autoconfigured ok.
wire ram_access;                // keeps track if local SRAM is being accessed.
wire ide_configured_n;          // keeps track if IDE_CARD is autoconfigured ok.
wire ide_access;                // keeps track if the IDE is being accessed.

wire m6800_dtack_n;

assign DTACK_CPU_n = DTACK_MB_n & m6800_dtack_n;
assign AS_MB_n = AS_CPU_n;

assign ROM_B1 = JP8;
assign ROM_B2 = rom_pin2;
assign ROM_WE_n = rom_pin31;


clock clkcontrol(
    .C7M(C7M),
    .OSC_CLK_X1(OSC_CLK_X1),
    .RESET_n(RESET_n),
    .CPU_SPEED_SWITCH(cpu_speed_switch),
    .JP2(JP2),
    .JP3(JP3),
    .JP4(JP4),
    .AS_CPU_n(AS_CPU_n),
    .DTACK_CPU_n(DTACK_CPU_n),
    .CLKCPU(CLKCPU)
);

m6800 m6800_bus(
    .C7M(C7M),
    .JP5(JP5),
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

fastram ramcontrol(
    .A(A[23:21]),
    .JP6(JP6),
    .RW_n(RW_n),
    .UDS_n(UDS_n),
    .LDS_n(LDS_n),
    .AS_n(AS_CPU_n),
    .DS_n(ds_n),
    .BASE_RAM(base_ram[7:5]),
    .RAM_CONFIGURED_n(ram_configured_n),
    .OE_BANK0_n(OE_BANK0_n),
    .OE_BANK1_n(OE_BANK1_n),
    .WE_BANK0_ODD_n(WE_BANK0_ODD_n),
    .WE_BANK1_ODD_n(WE_BANK1_ODD_n),
    .WE_BANK0_EVEN_n(WE_BANK0_EVEN_n),
    .WE_BANK1_EVEN_n(WE_BANK1_EVEN_n),
    .RAM_ACCESS(ram_access)
);

ata idecontrol(
    .CLKCPU(CLKCPU),
    .RESET_n(RESET_n),
    .A_HIGH(A[23:16]),
    .A12(A[12]),
    .A13(A[13]),
    .RW_n(RW_n),
    .AS_CPU_n(AS_CPU_n),
    .BASE_IDE(base_ide[7:0]),
    .IDE_CONFIGURED_n(ide_configured_n),
    .ROM_OE_n(ROM_OE_n),
    .IDE_IOR_n(IDE_IOR_n),
    .IDE_IOW_n(IDE_IOW_n),
    .IDE_CS_n(IDE_CS_n[1:0]),
    .IDE_ACCESS(ide_access)
);

endmodule
