`timescale 1ns / 1ps
`default_nettype none

module main_top(
    input wire JP2,
    input wire JP3,           // Flash ROM Kickstart overlay enable
    input wire JP4,
    input wire C7M_n,
    input wire pll_inst1_CLKOUT1,  // 100 MHz from PLL
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
    
    // SD Card signals
    input wire SD_MISO,
    input wire SD_CD_n,
    output wire SD_SS_n,
    output wire SD_SCLK,
    output wire SD_MOSI,
    
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
    output wire FLASH_A19,
    output wire FLASH_WE_n,
    output wire FLASH_OE_n,
    output wire INT2_n,
    output wire E_OE
);

wire C100M = pll_inst1_CLKOUT1;
wire C7M = ~C7M_n;
wire m6800_dtack_n;
wire ram_dtack_n;
wire sdcard_dtack_n;
wire flash_dtack_n;
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

// SD card signals
wire sd_data_oe;
wire [15:0] sd_data_out;
reg sd_enabled;

// Fast RAM signals
wire ram_access;

// Flash ROM signals
wire flash_access;

// SD card access detection
wire sdcard_access = !sd_configured_n && (A[23:16] == base_sd) && !AS_CPU_n;

// Combined signals
wire as_n = BG_68SEC000_n ? AS_CPU_n : AS_MB_n_IN;
wire ds_n = LDS_n & UDS_n;

// AS control - don't drive AS to motherboard when accessing local RAM, SD card, or Flash
wire as_mobo_n = AS_CPU_n | ram_access | sdcard_access | flash_access;

assign CLKCPU = C7M;
assign DTACK_CPU_n = DTACK_MB_n & m6800_dtack_n & ram_dtack_n & sdcard_dtack_n & flash_dtack_n;
assign AS_MB_n_OUT = as_mobo_n;
assign AS_MB_n_OE = BG_68SEC000_n | !AS_CPU_n;  // Keep driving until cycle completes

// Data bus - autoconfig or SD card
assign D_OUT = ac_data_oe ? {ac_data_out, 12'd0} : sd_data_out;
assign D_OE = ac_data_oe | (sd_data_oe & sd_enabled) ? 16'hFFFF : 16'd0;

// SD Card Driver ROM Overlay - enable ROM read before SD card is enabled
wire rom_access = sdcard_access && RW_n && !sd_enabled;
assign ROM_OE_n = !rom_access;

// SD card enable on first write
always @(negedge RESET_n or posedge CLKCPU) begin
    if (!RESET_n) begin
        sd_enabled <= 1'b0;
    end else begin
        if (sdcard_access && !ds_n && !RW_n) begin
            sd_enabled <= 1'b1;
        end
    end
end

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

//=============================================================================
// SD Card Controller
//=============================================================================

sdcard sdcontrol(
    .C100M(C100M),
    .CLKCPU(CLKCPU),
    .RESET_n(RESET_n),
    .ADDR(A[4:1]),
    .ACCESS(sdcard_access),
    .RW_n(RW_n),
    .UDS_n(UDS_n),
    .LDS_n(LDS_n),
    .AS_CPU_n(AS_CPU_n),
    .DS_n(ds_n),
    .CPU_SPEED_SWITCH(1'b0),  // Not using turbo mode yet
    .D_IN(D_IN[15:0]),
    .MISO(SD_MISO),
    .CD_n(SD_CD_n),
    .DATA_OE(sd_data_oe),
    .INT2_n(INT2_n),
    .SS_n(SD_SS_n),
    .SCLK(SD_SCLK),
    .MOSI(SD_MOSI),
    .DTACK_n(sdcard_dtack_n),
    .DATA_OUT(sd_data_out[15:0])
);

//=============================================================================
// Flash ROM Controller (Kickstart Overlay)
//=============================================================================

flash romoverlay(
    .A(A[23:16]),
    .AS_CPU_n(AS_CPU_n),
    .CLKCPU(CLKCPU),
    .RESET_n(RESET_n),
    .DS_n(ds_n),
    .RW_n(RW_n),
    .JP3(JP3),
    .CPU_SPEED_SWITCH(1'b0),  // Not using turbo mode yet
    .FLASH_ACCESS(flash_access),
    .FLASH_A19(FLASH_A19),
    .FLASH_WE_n(FLASH_WE_n),
    .FLASH_OE_n(FLASH_OE_n),
    .DTACK_n(flash_dtack_n)
);

endmodule
