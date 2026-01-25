`timescale 1ns / 1ps
`default_nettype none

module main_top(
    input wire JP1,           // Turbo enable jumper, closed = 7 MHz, open = turbo
    input wire JP2,
    input wire JP3,           // Flash ROM Kickstart overlay enable
    input wire JP4,
    input wire pll_inst1_CLKOUT0,  // 80 MHz from PLL (unused)
    input wire pll_inst1_CLKOUT1,  // 100 MHz from PLL (turbo clock + C100M)
    input wire C7M_n,
    input wire RESET_n,
    input wire AS_CPU_n,
    input wire VPA_n,
    input wire [2:0] FC,
    input wire DTACK_MB_n_IN,
    output wire DTACK_MB_n_OUT,
    output wire DTACK_MB_n_OE,
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
    input wire INT2_n,
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
wire sdcard_access = !sd_configured_n && (A[23:16] == base_sd) && !AS_CPU_n && bgack_sync2;

// BGACK_n synchronization — raw BGACK_n glitches can corrupt the as_n mux
// and downstream DTACK logic. 2-stage C100M sync for all consumers.
reg bgack_sync1, bgack_sync2;
always @(posedge C100M) begin
    bgack_sync1 <= BGACK_n;
    bgack_sync2 <= bgack_sync1;
end

// 2-stage CLKCPU re-sync of bgack_sync2 (C100M -> CLKCPU CDC).
reg bgack_cpu_s1, bgack_cpu;
always @(posedge CLKCPU) begin
    bgack_cpu_s1 <= bgack_sync2;
    bgack_cpu <= bgack_cpu_s1;
end

// Select AS source by bus ownership (BGACK), not bus grant (BG).
// BG can deassert while the DMA master still holds BGACK.
wire as_n = bgack_sync2 ? AS_CPU_n : AS_MB_n_IN;
wire ds_n = LDS_n & UDS_n;

// AS control - don't drive AS to motherboard when accessing local RAM, SD card, or Flash
wire as_mobo_n = AS_CPU_n | ram_access | sdcard_access | flash_access;

//=============================================================================
// Turbo Mode - Tunable Timing Parameters
//=============================================================================
// These parameters control expansion bus timing in turbo mode.
// Adjust these values for hardware tuning without changing logic.

localparam [3:0] PRECHARGE_TICKS = 4'd7;         // Minimum gap between bus cycles (25MHz ticks, 280ns)
localparam [2:0] SETUP_TICKS = 3'd3;             // Minimum address setup time (25MHz ticks, 120ns)
localparam [3:0] EXPANSION_DTACK_TICKS = 4'd12;  // Consecutive C100M samples of DTACK LOW before asserting (120ns)

//=============================================================================
// Turbo Mode - Clock Generation (25 MHz from 100 MHz PLL)
//=============================================================================

reg turbo_clk_pre;
reg turbo_clk;
always @ (posedge pll_inst1_CLKOUT1) begin
    turbo_clk_pre <= ~turbo_clk_pre;  // 100 MHz → 50 MHz intermediate
    if (turbo_clk_pre)
        turbo_clk <= ~turbo_clk;      // 50 MHz → 25 MHz
end

//=============================================================================
// CPU Speed Switch with Debouncing
//=============================================================================

localparam BOOT_7M_LIMIT = 30'd500000000;   // 5 seconds at 100 MHz
reg [29:0] b_count;                         // boot on 7 MHz counter

localparam DEBOUNCE_LIMIT = 21'd2000000;    // 20 ms at 100 MHz
reg [20:0] d_count;                         // debounce counter

reg cpu_speed_switch;
reg switch_state = JP1 ? 1'b1 : 1'b0;       // Initialize at declaration like old firmware

//Handle cpu speed switch with debounce - EXACTLY like old firmware
always @(negedge RESET_n or posedge C100M) begin

    if (!RESET_n) begin

        d_count <= 1'b0;
        b_count <= 1'b0;
        cpu_speed_switch <= 1'b0;
        switch_state <= JP1;

    end else begin

        if (b_count != BOOT_7M_LIMIT) begin
            b_count <= b_count + 1'b1;
        end

        if (switch_state != JP1 && d_count < DEBOUNCE_LIMIT) begin

            d_count <= d_count + 1'b1;

        end else if (d_count == DEBOUNCE_LIMIT) begin

            switch_state <= JP1;
            d_count <= 1'b0;

        end else begin

            d_count <= 1'b0;

        end

        //Wait until bus-cycle has reached (S7) before hot-switching to new cpu speed
        if (AS_CPU_n && DTACK_CPU_n) begin

            //Set the CPU speed switch after autoconfigure and pll has stabilized, we boot on 7 MHz...
            cpu_speed_switch <= (b_count == BOOT_7M_LIMIT) ? switch_state : 1'b0;

        end
    end
end

//=============================================================================
// Motherboard Synchronization (C7M domain)
//=============================================================================

reg mobo_as_n = 1'b1;
reg mobo_dtack_n = 1'b1;

// Safety counters (CLKCPU domain)
// p_cnt: precharge — enforces minimum gap between bus cycles
// s_cnt: setup — enforces minimum address valid time
reg [3:0] p_cnt;
reg [2:0] s_cnt;
reg last_as_cpu;

always @(posedge CLKCPU) begin
    last_as_cpu <= AS_CPU_n;
    
    // Precharge Counter (Reset when AS High)
    if (AS_CPU_n && !last_as_cpu) begin
        p_cnt <= PRECHARGE_TICKS;
    end else if (p_cnt != 0) begin
        p_cnt <= p_cnt - 4'd1;
    end
    
    // Address Setup Counter (Starts counting when AS_CPU_n goes Low)
    // Address is valid when AS_CPU_n is Low.
    if (AS_CPU_n) begin
        s_cnt <= 3'd0;
    end else begin
        if (s_cnt <= SETUP_TICKS) begin
             s_cnt <= s_cnt + 3'd1;
        end
    end
end

wire safety_ok = (p_cnt == 0) && (s_cnt >= SETUP_TICKS);

// C7M-synchronous gate. Instant AS termination via combinatorial OR at AS_MB_n_OUT.
// mobo_dtack_n provides C7M-filtered DTACK for 7MHz bypass and turbo legacy access.
always @(posedge C7M or negedge RESET_n) begin
    if (!RESET_n) begin
        mobo_as_n <= 1'b1;
        mobo_dtack_n <= 1'b1;
    end else if (AS_CPU_n) begin
        mobo_as_n <= 1'b1;
        mobo_dtack_n <= 1'b1;
    end else begin
        if (cpu_speed_switch && !safety_ok)
            mobo_as_n <= 1'b1;
        else
            mobo_as_n <= as_mobo_n;
        if (!mobo_as_n)
            mobo_dtack_n <= DTACK_MB_n_IN;
        else
            mobo_dtack_n <= 1'b1;
    end
end

//=============================================================================
// Signal Assignments (with turbo mode support)
//=============================================================================

// Clock selection (hot-switchable)
assign CLKCPU = cpu_speed_switch ? turbo_clk : C7M;

// ----------------------------------------------------------------------------
// Selective DTACK Timing
// ----------------------------------------------------------------------------

// Address decoding: legacy devices use C7M DTACK path + armed gate,
// expansion devices use C100M oversampled DTACK counter.
wire is_chip_ram = (A[23:21] == 3'b000); // 000000-1FFFFF
wire is_cia      = (A[23:16] == 8'hBF);
wire is_custom   = (A[23:16] == 8'hDF);
wire is_kickstart = (A[23:16] >= 8'hF0); // F00000-FFFFFF
wire is_autoconfig = (A[23:16] == 8'hE8); // Autoconfig Space (0xE8xxxx)

wire is_legacy_access = is_chip_ram | is_cia | is_custom | is_kickstart | is_autoconfig;

// turbo_as_gate: blocks AS/DTACK until address setup + precharge are met
wire turbo_as_gate = mobo_as_n | AS_CPU_n | (cpu_speed_switch & !safety_ok);

// ----------------------------------------------------------------------------
// Expansion DTACK — C100M Pause-on-Noise Counter
// ----------------------------------------------------------------------------
// Requires DTACK_MB_n_IN to be sampled LOW for EXPANSION_DTACK_TICKS consecutive
// C100M cycles (120ns) before asserting mobo_dtack_n_fine. Noise glitches HIGH
// PAUSE the counter but do NOT reset it — genuine DTACK eventually accumulates.
// This gives far better noise immunity than a single C7M sample while keeping
// total latency bounded (~120ns counter + CLKCPU retime).
//
// Reset via turbo_as_gate synced to C100M. The counter only runs after AS is
// on the bus (safety_ok met, mobo_as_n LOW) — so stale DTACK from prior cycles
// or safety-countdown noise can't accumulate ticks prematurely.
reg turbo_gate_c100m_s1, turbo_gate_c100m_s2;
always @(posedge C100M) begin
    turbo_gate_c100m_s1 <= turbo_as_gate;
    turbo_gate_c100m_s2 <= turbo_gate_c100m_s1;
end

reg [3:0] dtack_cnt;
reg mobo_dtack_n_fine;
reg dtack_s1, dtack_s2;

always @(posedge C100M) begin
    if (turbo_gate_c100m_s2) begin
        dtack_cnt <= 4'd0;
        mobo_dtack_n_fine <= 1'b1;
        dtack_s1 <= 1'b1;
        dtack_s2 <= 1'b1;
    end else begin
        dtack_s1 <= DTACK_MB_n_IN;
        dtack_s2 <= dtack_s1;
        // Counter: only increments when DTACK is actively LOW.
        // When dtack_s2 goes HIGH (noise/glitch), counter PAUSES but
        // does NOT reset. Prevents noise from restarting the count
        // while still requiring genuine DTACK assertion.
        if (!dtack_s2) begin
            if (dtack_cnt < EXPANSION_DTACK_TICKS) begin
                dtack_cnt <= dtack_cnt + 1'b1;
                mobo_dtack_n_fine <= 1'b1;
            end else begin
                mobo_dtack_n_fine <= 1'b0;
            end
        end
    end
end

// CLKCPU CDC sync — mobo_dtack_n_fine transitions on C100M edges, CLKCPU is
// async to C100M. 2-stage sync for metastability protection. AS_CPU_n gate
// prevents stale values from leaking across cycle boundaries.
reg exp_dtack_sync1, exp_dtack_synced;
always @(posedge CLKCPU) begin
    if (AS_CPU_n) begin
        exp_dtack_sync1 <= 1'b1;
        exp_dtack_synced <= 1'b1;
    end else begin
        exp_dtack_sync1 <= mobo_dtack_n_fine;
        exp_dtack_synced <= exp_dtack_sync1;
    end
end

// CLKCPU-domain synchronizer: detect when physical DTACK has been released HIGH
// Only used for edge detection (noise-tolerant), not for the DTACK value itself.
reg legacy_dtack_sync1, legacy_dtack_sync2;
always @(posedge CLKCPU) begin
    legacy_dtack_sync1 <= DTACK_MB_n_IN;
    legacy_dtack_sync2 <= legacy_dtack_sync1;
end

// Armed gate: latches HIGH once DTACK has been confirmed HIGH for 6 consecutive
// CLKCPU samples (after 2-stage sync). Requires ~320ns of genuine HIGH from
// physical pin — rejects noise/ringing that briefly crosses VIH.
// Resets when AS_CPU_n goes HIGH (between cycles).
reg [2:0] dtack_high_cnt;
reg legacy_dtack_armed;
always @(posedge CLKCPU) begin
    if (AS_CPU_n) begin
        dtack_high_cnt <= 3'd0;
        legacy_dtack_armed <= 1'b0;
    end else if (!legacy_dtack_armed) begin
        if (legacy_dtack_sync2) begin
            if (dtack_high_cnt == 3'd5)
                legacy_dtack_armed <= 1'b1;
            else
                dtack_high_cnt <= dtack_high_cnt + 1'b1;
        end else begin
            dtack_high_cnt <= 3'd0;  // reset on any LOW — must be consecutive
        end
    end
end

// Turbo DTACK path selection:
// Legacy: mobo_dtack_n + m6800_dtack_n + turbo_as_gate + armed gate.
// Expansion: exp_dtack_synced + turbo_as_gate (C100M counter provides noise immunity).
// Armed gate is legacy-only — expansion devices respond before it can arm.
wire turbo_dtack_src = is_legacy_access ?
    ((mobo_dtack_n & m6800_dtack_n) | turbo_as_gate | !legacy_dtack_armed) :
    (exp_dtack_synced | turbo_as_gate);

wire dtack_mobo_n = cpu_speed_switch ? turbo_dtack_src : DTACK_MB_n_IN;

// In turbo mode, m6800_dtack_n is already gated inside turbo_dtack_src.
// In 7MHz mode, it must still be AND'd directly.
wire dtack_combined_n = dtack_mobo_n & (cpu_speed_switch ? 1'b1 : m6800_dtack_n) & ram_dtack_n & sdcard_dtack_n & flash_dtack_n;

assign DTACK_CPU_n = dtack_combined_n;

// AS to motherboard: turbo_as_gate in turbo mode (safety-gated), raw in 7MHz.
assign AS_MB_n_OUT = cpu_speed_switch ? turbo_as_gate : as_mobo_n;
// Tri-state AS during DMA (BGACK LOW). Uses bgack_sync2 — raw BGACK_n
// glitches can tri-state AS mid-cycle, hanging expansion cards.
assign AS_MB_n_OE = (BG_68SEC000_n | !AS_CPU_n) & bgack_sync2;

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
    .BGACK_n(bgack_sync2),
    .CPU_SPEED_SWITCH(cpu_speed_switch && bgack_sync2), // Force 7MHz mode during DMA (BGACK_n=0)
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
    .CPU_SPEED_SWITCH(cpu_speed_switch),
    .D_IN(D_IN[15:0]),
    .MISO(SD_MISO),
    .CD_n(SD_CD_n),
    .DATA_OE(sd_data_oe),
    .INT2_n(),                  // Directly active on bus — must not drive
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
    .CPU_SPEED_SWITCH(cpu_speed_switch),
    .FLASH_ACCESS(flash_access),
    .FLASH_A19(FLASH_A19),
    .FLASH_WE_n(FLASH_WE_n),
    .FLASH_OE_n(FLASH_OE_n),
    .DTACK_n(flash_dtack_n)
);

// ----------------------------------------------------------------------------
// Bidirectional DTACK Drive (DMA to FastRAM)
// ----------------------------------------------------------------------------
// Drive DTACK_MB_n LOW when a DMA master accesses FPGA fast RAM.
// Synchronous OE register + combinatorial AS gate for instant release.
reg dtack_oe_reg;
always @(posedge CLKCPU) begin
    dtack_oe_reg <= (!bgack_cpu && ram_access && !ram_dtack_n);
end

assign DTACK_MB_n_OUT = 1'b0;
assign DTACK_MB_n_OE = dtack_oe_reg & !as_n;

endmodule
