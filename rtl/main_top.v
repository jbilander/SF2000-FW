`timescale 1ns / 1ps
`default_nettype none

module main_top(
    input wire JP2,
    input wire JP4,
    input wire C7M_n,
    input wire RESET_n,
    input wire AS_CPU_n,
    input wire VPA_n,
    input wire [2:0] FC,
    input wire DTACK_MB_n,
    input wire E_IN,
    input wire AS_MB_n_IN,
    
    // Full address and data bus
    input wire [23:1] A,
    input wire RW_n,
    input wire UDS_n,
    input wire LDS_n,
    input wire CFGIN_n,
    input wire [15:0] D_IN,
    
    output wire [15:0] D_OUT,
    output wire [15:0] D_OE,
    output wire CFGOUT_n,
    
    // Bus arbitration signals
    input wire BG_n_IN,
    input wire BR_n_IN,
    input wire BOSS_n_IN,
    input wire BGACK_n,
    input wire BG_68SEC000_n,
    
    output wire BR_n_OUT,
    output wire BR_n_OE,
    output wire BG_n_OUT,
    output wire BG_n_OE,
    output wire BOSS_n_OUT,
    output wire BOSS_n_OE,
    output wire BR_68SEC000_n,
    
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
    output wire E_OE
);

wire C7M = ~C7M_n;
wire m6800_dtack_n;
wire ram_dtack_n;
wire dma_en;
wire cpu_detected;
wire is_b2000;

// Autoconfig signals
wire ac_data_oe;
wire [15:12] ac_data_out;
wire [7:5] base_ram;
wire ram_configured_n;
wire sd_configured_n;
wire [7:0] base_sd;

// Fast RAM signals
wire ram_access;

// Combined signals (matching working firmware)
wire as_n = BG_68SEC000_n ? AS_CPU_n : AS_MB_n_IN;
wire ds_n = LDS_n & UDS_n;

// AS control - don't drive AS to motherboard when accessing local RAM
wire as_mobo_n = AS_CPU_n | ram_access;

assign CLKCPU = C7M;
assign DTACK_CPU_n = DTACK_MB_n & m6800_dtack_n & ram_dtack_n;
assign AS_MB_n_OUT = as_mobo_n;
assign AS_MB_n_OE = BG_68SEC000_n | !AS_CPU_n;  // Drive AS_MB_n when we have bus OR when a cycle is in progress

// Data bus (matching working firmware)
assign D_OUT = ac_data_oe ? {ac_data_out, 12'd0} : 16'd0;
assign D_OE = ac_data_oe ? 16'hFFFF : 16'd0;

// Tie unused signals
assign ROM_OE_n = 1'b1;
assign FLASH_WE_n = 1'b1;
assign FLASH_OE_n = 1'b1;
assign INT2_n = 1'b1;

//=============================================================================
// Bus Arbiter
//=============================================================================

bus_arbiter arbiter(
    .C7M(C7M),
    .RESET_n(RESET_n),
    .JP2(JP2),
    
    .BG_n_IN(BG_n_IN),
    .BR_n_OUT(BR_n_OUT),
    .BR_n_OE(BR_n_OE),
    
    .BOSS_n_IN(BOSS_n_IN),
    .BOSS_n_OUT(BOSS_n_OUT),
    .BOSS_n_OE(BOSS_n_OE),
    
    .BG_68SEC000_n(BG_68SEC000_n),
    .BR_68SEC000_n(BR_68SEC000_n),
    
    .BR_n_IN(BR_n_IN),
    .BGACK_n(BGACK_n),
    .BG_n_OUT(BG_n_OUT),
    .BG_n_OE(BG_n_OE),
    
    .dma_en(dma_en),
    .E_OE(E_OE),
    .cpu_detected(cpu_detected),
    .is_b2000(is_b2000)
);

//=============================================================================
// 6800 Bus Emulation
//=============================================================================

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

//=============================================================================
// Autoconfig
//=============================================================================

autoconfig_zii autoconfig(
    .C7M(C7M),
    .CFGIN_n(CFGIN_n),
    .JP4(JP4),
    .AS_CPU_n(AS_CPU_n),
    .RESET_n(RESET_n),
    .DS_n(ds_n),
    .RW_n(RW_n),
    .A_HIGH(A[23:16]),
    .A_LOW(A[6:1]),
    .D_IN(D_IN[15:12]),
    .DATA_OUT(ac_data_out[15:12]),
    .DATA_OE(ac_data_oe),
    .BASE_RAM(base_ram[7:5]),
    .BASE_SD(base_sd[7:0]),
    .RAM_CONFIGURED_n(ram_configured_n),
    .SD_CONFIGURED_n(sd_configured_n),
    .CFGOUT_n(CFGOUT_n)
);

//=============================================================================
// Fast RAM Controller
//=============================================================================

fastram ramcontrol(
    .CLKCPU(CLKCPU),
    .A(A[23:21]),
    .JP4(JP4),
    .RW_n(RW_n),
    .UDS_n(UDS_n),
    .LDS_n(LDS_n),
    .AS_CPU_n(AS_CPU_n),
    .AS_n(as_n),
    .DS_n(ds_n),
    .BASE_RAM(base_ram[7:5]),
    .RAM_CONFIGURED_n(ram_configured_n),
    .OE_BANK0_n(OE_BANK0_n),
    .OE_BANK1_n(OE_BANK1_n),
    .WE_BANK0_ODD_n(WE_BANK0_ODD_n),
    .WE_BANK1_ODD_n(WE_BANK1_ODD_n),
    .WE_BANK0_EVEN_n(WE_BANK0_EVEN_n),
    .WE_BANK1_EVEN_n(WE_BANK1_EVEN_n),
    .RAM_ACCESS(ram_access),
    .DTACK_n(ram_dtack_n)
);

endmodule

