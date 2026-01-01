`timescale 1ns / 1ps
`default_nettype none

module main_top(
    input wire JP1,
    input wire JP2,
    input wire JP3,
    input wire JP4,
    input wire pll_inst1_CLKOUT0,
    input wire pll_inst1_CLKOUT1,
    input wire C7M_n,
    input wire RESET_n,
    input wire CFGIN_n,
    input wire [23:1] A,
    input wire RW_n,
    input wire UDS_n,
    input wire LDS_n,
    input wire AS_CPU_n,
    input wire VPA_n,
    input wire [2:0] FC,
    input wire DTACK_MB_n,
    input wire SD_MISO,
    input wire SD_CD_n,
    input wire BOSS_n_IN,
    input wire BR_n_IN,
    input wire BG_n_IN,
    input wire BGACK_n,
    input wire BG_68SEC000_n,
    input wire E_IN,
    input wire AS_MB_n_IN,
    input wire [15:0] D_IN,
    output wire [15:0] D_OUT,
    output wire [15:0] D_OE,
    output wire CFGOUT_n,
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
    output wire SD_SS_n,
    output wire SD_SCLK,
    output wire SD_MOSI,
    output wire INT2_n,
    output reg E_OE = 1'b0,
    output reg BR_68SEC000_n = 1'b1,
    output reg BOSS_n_OUT = 1'b0,
    output reg BOSS_n_OE = 1'b0,
    output reg BR_n_OUT = 1'b1,
    output reg BR_n_OE = 1'b1,
    output reg BG_n_OUT = 1'b1,
    output reg BG_n_OE = 1'b0
);

/*
Jumper descriptions (with external 10k pull-ups: closed = LOW, open = HIGH):
JP1: 7 MHz / Turbo (closed = 7MHz, open = Turbo)
JP2: E-CLK (closed = generate E, open = use external E)
JP3: ROM overlay (closed = enabled, open = disabled)
JP4: 4/8 MB SRAM (closed = 4MB, open = 8MB)
*/

//=============================================================================
// Clock and Reset Management
//=============================================================================

wire C100M = pll_inst1_CLKOUT1;
wire C7M = ~C7M_n;

// Generate turbo clock (~44 MHz from ~89 MHz PLL)
reg turbo_clk = 1'b0;
always @(posedge pll_inst1_CLKOUT0) begin
    turbo_clk <= ~turbo_clk;
end

// CPU clock selection
reg cpu_speed_switch = 1'b0;
assign CLKCPU = cpu_speed_switch ? turbo_clk : C7M;

//=============================================================================
// Synchronize cpu_speed_switch to C7M domain
//=============================================================================

reg [2:0] cpu_speed_switch_sync_c7m;
always @(posedge C7M) begin
    if (!RESET_n) begin
        cpu_speed_switch_sync_c7m <= 3'd0;
    end else begin
        cpu_speed_switch_sync_c7m <= {cpu_speed_switch_sync_c7m[1:0], cpu_speed_switch};
    end
end
wire cpu_speed_switch_c7m = cpu_speed_switch_sync_c7m[2];

//=============================================================================
// Boot Timer and Speed Switch Control
//=============================================================================

localparam BOOT_7M_LIMIT = 30'd300000000;   // 3 seconds at 100 MHz
reg [29:0] b_count = 30'd0;

localparam DEBOUNCE_LIMIT = 21'd2000000;    // 20 ms at 100 MHz
reg [20:0] d_count = 21'd0;

reg switch_state = 1'b0;
reg switch_request = 1'b0;

// Initialize switch_state based on JP1
initial begin
    switch_state = JP1;
end

// Synchronize AS_CPU_n and DTACK_CPU_n to C100M for safe clock switching
reg [2:0] as_cpu_n_sync_c100m;
reg [2:0] dtack_cpu_n_sync_c100m;

always @(posedge C100M) begin
    as_cpu_n_sync_c100m <= {as_cpu_n_sync_c100m[1:0], AS_CPU_n};
    dtack_cpu_n_sync_c100m <= {dtack_cpu_n_sync_c100m[1:0], DTACK_CPU_n};
end

wire bus_idle_c100m = as_cpu_n_sync_c100m[2] && dtack_cpu_n_sync_c100m[2];

// Boot timer and switch debounce (C100M domain)
always @(posedge C100M) begin
    if (!RESET_n) begin
        d_count <= 21'd0;
        b_count <= 30'd0;
        switch_state <= JP1;
        switch_request <= 1'b0;
    end else begin
        // Boot timer
        if (b_count != BOOT_7M_LIMIT) begin
            b_count <= b_count + 30'd1;
        end
        
        // JP1 switch debounce
        if (switch_state != JP1 && d_count < DEBOUNCE_LIMIT) begin
            d_count <= d_count + 21'd1;
        end else if (d_count == DEBOUNCE_LIMIT) begin
            switch_state <= JP1;
            d_count <= 21'd0;
        end else begin
            d_count <= 21'd0;
        end
        
        // Request speed switch after boot period
        if (b_count == BOOT_7M_LIMIT) begin
            switch_request <= 1'b1;
        end
        
        // Only switch when bus is idle for safety
        if (switch_request && bus_idle_c100m) begin
            cpu_speed_switch <= switch_state;
            switch_request <= 1'b0;
        end
    end
end

//=============================================================================
// Signal Definitions and DTACK Aggregation
//=============================================================================

wire m6800_dtack_n;
wire ram_dtack_n;
wire flash_dtack_n;
wire sdcard_dtack_n;

wire ac_data_oe;
wire sd_data_oe;
wire [15:12] ac_data_out;
wire [15:0] sd_data_out;

wire [7:5] base_ram;
wire [7:0] base_sd;

wire ram_configured_n;
wire ram_access;
wire sd_configured_n;
wire sdcard_access;
wire flash_access;

reg sd_enabled = 1'b0;
wire ds_n = LDS_n & UDS_n;

// SD card access detection
assign sdcard_access = !sd_configured_n && (A[23:16] == base_sd) && !AS_CPU_n;

// Data bus outputs
assign D_OUT = ac_data_oe ? {ac_data_out, 12'd0} : sd_data_out;
assign D_OE = (ac_data_oe | (sd_data_oe & sd_enabled)) ? 16'hFFFF : 16'd0;

// ROM overlay access (before SD is enabled)
wire rom_access = sdcard_access && RW_n && !sd_enabled;
assign ROM_OE_n = !rom_access;

// SD enable logic (enable SD interface on first write)
always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        sd_enabled <= 1'b0;
    end else begin
        if (sdcard_access && !ds_n && !RW_n) begin
            sd_enabled <= 1'b1;
        end
    end
end

//=============================================================================
// Motherboard Interface Synchronization
//=============================================================================

reg mobo_dtack_n = 1'b1;
reg mobo_as_n = 1'b1;

// Synchronize AS_CPU_n to C7M domain
reg [2:0] as_cpu_n_sync_c7m;
wire as_cpu_n_c7m = as_cpu_n_sync_c7m[2];
wire as_cpu_n_rising_c7m = (as_cpu_n_sync_c7m[2:1] == 2'b01);

always @(posedge C7M) begin
    if (!RESET_n) begin
        as_cpu_n_sync_c7m <= 3'b111;
    end else begin
        as_cpu_n_sync_c7m <= {as_cpu_n_sync_c7m[1:0], AS_CPU_n};
    end
end

// AS_n selection (CPU or motherboard)
wire as_n = BG_68SEC000_n ? AS_CPU_n : AS_MB_n_IN;

// AS to motherboard generation
wire as_mobo_n = AS_CPU_n | ram_access | flash_access | sdcard_access;

// Motherboard synchronization
always @(posedge C7M) begin
    if (!RESET_n) begin
        mobo_as_n <= 1'b1;
        mobo_dtack_n <= 1'b1;
    end else begin
        if (as_cpu_n_rising_c7m) begin
            mobo_as_n <= 1'b1;
            mobo_dtack_n <= 1'b1;
        end else if (!as_cpu_n_c7m) begin
            mobo_as_n <= as_mobo_n;
            mobo_dtack_n <= DTACK_MB_n;
        end
    end
end

// DTACK and AS motherboard outputs
wire dtack_mobo_n = cpu_speed_switch_c7m ? mobo_dtack_n : DTACK_MB_n;
assign DTACK_CPU_n = dtack_mobo_n & m6800_dtack_n & ram_dtack_n & flash_dtack_n & sdcard_dtack_n;
assign AS_MB_n_OUT = cpu_speed_switch_c7m ? mobo_as_n : as_mobo_n;
assign AS_MB_n_OE = BG_68SEC000_n;

//=============================================================================
// Bus Arbitration State Machine
//=============================================================================

/*
Improved 3-wire to 2-wire bus arbitration

3-wire (Amiga side):   BR_n, BG_n, BGACK_n
2-wire (68SEC000 CPU): BR_n, BG_n

State machine properly sequences:
1. DMA device asserts BR_n (Bus Request)
2. We pass BR to CPU as BR_68SEC000_n
3. CPU grants bus with BG_68SEC000_n
4. We pass BG to DMA device as BG_n_OUT
5. DMA device acknowledges with BGACK_n
6. We can release BR_68SEC000_n
7. When DMA done (BR_n and BGACK_n deassert), release BG_n_OUT
*/

localparam BUS_IDLE = 3'd0;
localparam BUS_BR_REQUESTED = 3'd1;
localparam BUS_BG_GRANTED = 3'd2;
localparam BUS_BGACK_ASSERTED = 3'd3;
localparam BUS_RELEASE_BR = 3'd4;

reg [2:0] bus_arb_state = BUS_IDLE;
reg dma_en = 1'b0;

// Synchronize bus arbitration signals to C7M
reg [2:0] br_n_in_sync;
reg [2:0] bg_68sec000_n_sync;
reg [2:0] bgack_n_sync;

always @(posedge C7M) begin
    if (!RESET_n) begin
        br_n_in_sync <= 3'b111;
        bg_68sec000_n_sync <= 3'b111;
        bgack_n_sync <= 3'b111;
    end else begin
        br_n_in_sync <= {br_n_in_sync[1:0], BR_n_IN};
        bg_68sec000_n_sync <= {bg_68sec000_n_sync[1:0], BG_68SEC000_n};
        bgack_n_sync <= {bgack_n_sync[1:0], BGACK_n};
    end
end

wire br_n_stable = br_n_in_sync[2];
wire bg_68sec000_stable = bg_68sec000_n_sync[2];
wire bgack_stable = bgack_n_sync[2];

// Bus arbitration state machine
always @(posedge C7M) begin
    if (!RESET_n) begin
        bus_arb_state <= BUS_IDLE;
        BR_68SEC000_n <= 1'b1;
        BG_n_OUT <= 1'b1;
    end else begin
        if (dma_en) begin
            case (bus_arb_state)
                BUS_IDLE: begin
                    BR_68SEC000_n <= 1'b1;
                    BG_n_OUT <= 1'b1;
                    
                    // DMA device requests bus
                    if (!br_n_stable) begin
                        BR_68SEC000_n <= 1'b0;  // Request bus from CPU
                        bus_arb_state <= BUS_BR_REQUESTED;
                    end
                end
                
                BUS_BR_REQUESTED: begin
                    // Wait for CPU to grant bus
                    if (!bg_68sec000_stable) begin
                        BG_n_OUT <= 1'b0;  // Grant bus to DMA device
                        bus_arb_state <= BUS_BG_GRANTED;
                    end
                    
                    // If BR cancels before grant, return to idle
                    if (br_n_stable) begin
                        BR_68SEC000_n <= 1'b1;
                        bus_arb_state <= BUS_IDLE;
                    end
                end
                
                BUS_BG_GRANTED: begin
                    // Wait for DMA device to acknowledge
                    if (!bgack_stable) begin
                        bus_arb_state <= BUS_BGACK_ASSERTED;
                    end
                    
                    // If BG is removed by CPU, return to idle
                    if (bg_68sec000_stable) begin
                        BG_n_OUT <= 1'b1;
                        BR_68SEC000_n <= 1'b1;
                        bus_arb_state <= BUS_IDLE;
                    end
                end
                
                BUS_BGACK_ASSERTED: begin
                    // DMA device has the bus, can release BR
                    BR_68SEC000_n <= 1'b1;
                    bus_arb_state <= BUS_RELEASE_BR;
                end
                
                BUS_RELEASE_BR: begin
                    // Wait for DMA to complete (both BR and BGACK released)
                    if (bgack_stable && br_n_stable) begin
                        BG_n_OUT <= 1'b1;
                        bus_arb_state <= BUS_IDLE;
                    end
                    // If only BGACK released but BR still active, another DMA cycle
                    else if (bgack_stable && !br_n_stable) begin
                        BR_68SEC000_n <= 1'b0;
                        bus_arb_state <= BUS_BR_REQUESTED;
                    end
                end
                
                default: begin
                    bus_arb_state <= BUS_IDLE;
                    BR_68SEC000_n <= 1'b1;
                    BG_n_OUT <= 1'b1;
                end
            endcase
        end else begin
            // DMA not enabled
            BR_68SEC000_n <= 1'b1;
            BG_n_OUT <= 1'b1;
            bus_arb_state <= BUS_IDLE;
        end
    end
end

//=============================================================================
// Bootstrap and Board Detection
//=============================================================================

reg bootstrap = 1'b1;

// Synchronize BOSS_n and BG_n_IN for detection
reg [2:0] boss_n_sync;
reg [2:0] bg_n_in_sync;

always @(posedge C7M) begin
    if (!RESET_n) begin
        boss_n_sync <= 3'b111;
        bg_n_in_sync <= 3'b111;
    end else begin
        boss_n_sync <= {boss_n_sync[1:0], BOSS_n_IN};
        bg_n_in_sync <= {bg_n_in_sync[1:0], BG_n_IN};
    end
end

wire boss_n_stable = boss_n_sync[2];
wire bg_n_in_stable = bg_n_in_sync[2];

// Bootstrap sequence
always @(posedge C7M) begin
    if (!RESET_n) begin
        bootstrap <= 1'b1;
        dma_en <= 1'b0;
        BOSS_n_OE <= 1'b0;
        BR_n_OE <= 1'b1;
        BG_n_OE <= 1'b0;
        E_OE <= 1'b0;
    end else begin
        if (bootstrap) begin
            bootstrap <= 1'b0;
            
            // Detect board type and configure
            if (bg_n_in_stable != 1'b0 || JP2 != 1'b0) begin
                // E clock configuration
                E_OE <= !JP2;
                
                if (boss_n_stable) begin
                    //============================================
                    // Plugged into B2000 (A2000 rev 6)
                    //============================================
                    BOSS_n_OUT <= 1'b0;
                    BOSS_n_OE <= 1'b1;
                    BR_n_OE <= 1'b0;      // Don't drive BR_n
                    BG_n_OE <= 1'b1;      // Drive BG_n
                    dma_en <= 1'b1;       // Enable DMA arbitration
                end else begin
                    //============================================
                    // Plugged into A500 or A2000 rev 4
                    //============================================
                    BOSS_n_OUT <= 1'b0;
                    BOSS_n_OE <= 1'b0;
                    BR_n_OE <= !bg_n_in_stable;  // Drive BR_n if BG is pulled up
                    BG_n_OE <= 1'b0;
                    
                    // DMA only enabled if internal CPU is removed (BG pulled up)
                    dma_en <= bg_n_in_stable;
                end
            end
        end
    end
end

//=============================================================================
// Module Instantiations
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

fastram ramcontrol(
    .CLKCPU(CLKCPU),
    .RESET_n(RESET_n),
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
    .CPU_SPEED_SWITCH(cpu_speed_switch),
    .OE_BANK0_n(OE_BANK0_n),
    .OE_BANK1_n(OE_BANK1_n),
    .WE_BANK0_ODD_n(WE_BANK0_ODD_n),
    .WE_BANK1_ODD_n(WE_BANK1_ODD_n),
    .WE_BANK0_EVEN_n(WE_BANK0_EVEN_n),
    .WE_BANK1_EVEN_n(WE_BANK1_EVEN_n),
    .RAM_ACCESS(ram_access),
    .DTACK_n(ram_dtack_n)
);

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
    .CPU_SPEED_SWITCH(cpu_speed_switch),
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

flash romoverlay(
    .A(A[23:16]),
    .AS_CPU_n(AS_CPU_n),
    .CLKCPU(CLKCPU),
    .RESET_n(RESET_n),
    .DS_n(ds_n),
    .RW_n(RW_n),
    .JP3(JP3),
    .CPU_SPEED_SWITCH(cpu_speed_switch),
    .FLASH_A19(FLASH_A19),
    .FLASH_ACCESS(flash_access),
    .FLASH_OE_n(FLASH_OE_n),
    .FLASH_WE_n(FLASH_WE_n),
    .DTACK_n(flash_dtack_n)
);

endmodule
