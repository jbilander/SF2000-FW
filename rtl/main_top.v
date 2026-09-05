// ============================================================================
// main_top.v  --  Spitfire 2000
//
// M1  transparent 7 MHz, socket empty.
// M2  socketed CPU stays installed; E generation or phase-lock; warm reset.
// M3  Zorro II autoconfig and 8 MB fast RAM.
// M4  SD card: second autoconfig board, boot ROM, spisd.device.
// M5  DMA: a Zorro master can read and write the fast RAM.
//
// STILL MISSING: maprom, clockport, turbo.
//
// WHAT CHANGED FROM M1 (rev B)
//
//  * The motherboard 68000 no longer has to be pulled. We assert /BR to it,
//    wait for /BG, then hold /BR asserted forever and never assert /BGACK --
//    Gary inserts an extra wait state if it sees BGACK, and with two-wire
//    arbitration the 68000 stays off the bus for as long as BR is held.
//
//  * BR_68SEC000_n is now driven: our own CPU is held off the bus whenever we
//    do not own the motherboard bus. That is what makes the reset path safe.
//
//  * WARM RESET RE-ARBITRATION. RESET is one shared open-drain net running to
//    both CPUs, so Ctrl-A-A (or our own CPU executing RESET) resets the
//    socketed 68000 too and it will try to drive the bus again. There is no
//    way to hold one CPU in reset and not the other. So instead: any RESET
//    assertion drops bus_owned, which simultaneously asserts /BR to our CPU,
//    tri-states AS_MB and VMA, and stops forwarding DTACK so our CPU simply
//    stalls in wait states. Once RESET releases we wait for /BG again before
//    taking over. Neither CPU can drive the bus during the window.
//
//  * E generation and the whole 6800 cycle moved to m6800.v, which either
//    generates E or phase-locks to the socketed CPU's free-running E. It
//    listens before driving, so a wrong JP2 setting cannot fight real
//    silicon. Reset release is gated on its e_ready.
//
// Interrupt acknowledge deliberately stays here: on this board an IACK never
// involves VMA or E, it only shares the DTACK and data-drive plumbing.
//
// M3 ADDS: Zorro II autoconfig (manuf 5194, product 10) and the 8 MB SRAM.
//   JP4 closed  -> one 4 MB entry, bank 0 only. U16/U17 stay silent because
//                  their OE and WE are never asserted; CE is tied to GND so
//                  that is the only thing keeping them off the data bus.
//   JP4 open    -> one 8 MB entry, both banks.
//   The base comes from the $48 write, so a 4 MB board lands wherever the
//   session puts it ($200000 or $600000), or shuts up on a $4C write.
//
// DMA: a Zorro master (A2091, A590, GVP HC+8 in amnesia mode) can be granted
//   the bus and read or write the fast RAM directly. The FETs already put the
//   master's address on the SRAM pins, so this is control signals only. Not
//   possible on an A500 or Braunschweig with the socketed CPU installed:
//   there we must hold /BR low forever to keep that CPU off the bus, and a
//   wired-OR line we are pulling cannot also be an input. bus_arbiter only
//   sets dma_capable when BR is free.
//
// Address decode is a magnitude compare on A23-A20, not a prefix match: Zorro
// II memory space starts at $200000, so neither 4 MB slot is 4 MB-aligned.
// The SRAM still takes A21-A1 directly -- any contiguous 4 MB window covers
// every A21-A1 value exactly once, so the mapping is a bijection even though
// it is rotated relative to the bus address.
//
// ============================================================================

`default_nettype none

module main_top #(
    parameter integer CLK_HZ    = 7_159_090,   // NTSC: the faster machine
    parameter integer T_SETTLE  = CLK_HZ/100,        // 10 ms; these are
    parameter integer T_ARB_TO  = CLK_HZ/50,         // MINIMUM durations, so
    parameter integer T_RESET   = (CLK_HZ*15)/100,   // size them off NTSC
    parameter integer LISTEN_W  = 10
)(
    input  wire        C7M_n,
    input  wire        OSC_CLK,
    input  wire        pll_inst1_CLKOUT0,   // 80 MHz, halved to 40 MHz in M5
    input  wire        pll_inst1_CLKOUT1,   // 100 MHz, sdcard.v's C100M
    output wire        CLKCPU,

    input  wire [23:1] A,
    input  wire [15:0] D_IN,
    output wire [15:0] D_OUT,
    output wire [15:0] D_OE,
    input  wire  [2:0] FC,
    input  wire        RW_n,
    input  wire        UDS_n,
    input  wire        LDS_n,
    input  wire        BERR_n,

    input  wire        AS_CPU_n,
    input  wire        AS_MB_n_IN,
    output wire        AS_MB_n_OUT,
    output wire        AS_MB_n_OE,
    output wire        DTACK_CPU_n,
    input  wire        DTACK_MB_n_IN,
    output wire        DTACK_MB_n_OUT,
    output wire        DTACK_MB_n_OE,

    input  wire        BR_n_IN,
    output wire        BR_n_OUT,
    output wire        BR_n_OE,
    input  wire        BG_n_IN,
    output wire        BG_n_OUT,
    output wire        BG_n_OE,
    output wire        BR_68SEC000_n,
    input  wire        BG_68SEC000_n,
    input  wire        BGACK_n,
    input  wire        BOSS_n_IN,
    output wire        BOSS_n_OUT,
    output wire        BOSS_n_OE,

    input  wire        VPA_n,
    input  wire        E_IN,
    output wire        E_OUT,
    output wire        E_OE,
    input  wire        VMA_n_IN,
    output wire        VMA_n_OUT,
    output wire        VMA_n_OE,
    input  wire        RESET_n_IN,
    output wire        RESET_n_OUT,
    output wire        RESET_n_OE,
    input  wire        HLT_n_IN,
    output wire        HLT_n_OUT,
    output wire        HLT_n_OE,
    input  wire  [2:0] IPL_n,
    input  wire        INT2_n_IN,
    output wire        INT2_n_OUT,
    output wire        INT2_n_OE,
    input  wire        INT6_n,

    input  wire        CFGIN_n,
    output wire        CFGOUT_n,

    input  wire        JP1,
    input  wire        JP2,
    input  wire        JP3,
    input  wire        JP4,

    output wire        OE_BANK0_n,
    output wire        OE_BANK1_n,
    output wire        WE_BANK0_EVEN_n,
    output wire        WE_BANK0_ODD_n,
    output wire        WE_BANK1_EVEN_n,
    output wire        WE_BANK1_ODD_n,
    output wire        FLASH_OE_n,
    output wire        FLASH_WE_n,
    output wire        FLASH_A19,
    output wire        ROM_OE_n,

    output wire        SD_SS_n,
    output wire        SD_SCLK,
    output wire        SD_MOSI,
    input  wire        SD_MISO,
    input  wire        SD_CD_n
);

    // ---- clock -------------------------------------------------------------
    // U7 gives the inverse of C7M. Leave is_clock_inverted FALSE on the
    // C7M_n gclk; inverting twice puts the CPU 180 deg out of phase with Gary.
    wire clk = ~C7M_n;
    assign CLKCPU = clk;

    // ---- synchronisers -----------------------------------------------------
    reg [1:0] s_as_cpu = 2'b11, s_vpa = 2'b11, s_bg = 2'b11, s_reset = 2'b11;
    reg [1:0] s_cfgin  = 2'b11, s_br = 2'b11, s_bgack = 2'b11, s_bg68 = 2'b11;
    always @(posedge clk) begin
        s_as_cpu <= {s_as_cpu[0], AS_CPU_n};
        s_vpa    <= {s_vpa[0],    VPA_n};
        s_bg     <= {s_bg[0],     BG_n_IN};
        s_reset  <= {s_reset[0],  RESET_n_IN};
        s_cfgin  <= {s_cfgin[0],  CFGIN_n};
        s_br     <= {s_br[0],     BR_n_IN};
        s_bgack  <= {s_bgack[0],  BGACK_n};
        s_bg68   <= {s_bg68[0],   BG_68SEC000_n};
    end
    wire as_cpu_q = s_as_cpu[1];
    wire vpa_q    = s_vpa[1];
    wire bg_q     = s_bg[1];
    wire reset_q  = s_reset[1];
    wire cfgin_q  = s_cfgin[1];
    wire br_q     = s_br[1];
    wire bgack_q  = s_bgack[1];
    wire bg68_q   = s_bg68[1];

    // ---- bus arbitration, reset and machine detection -----------------------
    wire bus_owned, e_ready, dma_active, dma_capable, arb_took, arb_running;
    wire arb_sane, arb_relayed, arb_mtook, arb_cpu;

    bus_arbiter #(
        .T_SETTLE (T_SETTLE),
        .T_ARB_TO (T_ARB_TO),
        .T_RESET  (T_RESET)
    ) u_arb (
        .clk           (clk),
        .reset_q       (reset_q),
        .bg_q          (bg_q),
        .br_q          (br_q),
        .bgack_q       (bgack_q),
        .bg68_q        (bg68_q),
        .boss_n_in     (BOSS_n_IN),
        .e_ready       (e_ready),
        .bus_owned     (bus_owned),
        .dma_active    (dma_active),
        .dma_capable   (dma_capable),
        .took_bus      (arb_took),
        .running       (arb_running),
        .sane          (arb_sane),
        .relayed       (arb_relayed),
        .master_took   (arb_mtook),
        .cpu_present   (arb_cpu),
        .reset_n_out   (RESET_n_OUT),
        .reset_n_oe    (RESET_n_OE),
        .hlt_n_out     (HLT_n_OUT),
        .hlt_n_oe      (HLT_n_OE),
        .br_n_out      (BR_n_OUT),
        .br_n_oe       (BR_n_OE),
        .bg_n_out      (BG_n_OUT),
        .bg_n_oe       (BG_n_OE),
        .boss_n_out    (BOSS_n_OUT),
        .boss_n_oe     (BOSS_n_OE),
        .br_68sec000_n (BR_68SEC000_n)
    );

    // ---- cycle classification ----------------------------------------------
    wire cpu_as     = ~AS_CPU_n;
    wire ds_n       = UDS_n & LDS_n;
    wire iack       = cpu_as & (FC == 3'b111) & bus_owned;
    wire [7:0] avec = 8'd24 + {5'd0, A[3:1]};       // autovectors 25..31

    // ---- interrupt acknowledge ---------------------------------------------
    // AVEC is strapped high through RN5 and cannot be driven, so the only way
    // to end an IACK is DTACK plus a vector byte. AS is never forwarded: Gary
    // decodes $FFFFFx as ROM and would drive the same data bus we are.
    reg       vec_d    = 1'b0;
    reg       iack_ack = 1'b0;
    reg [1:0] iack_dly = 2'd0;

    always @(posedge clk) begin
        if (!bus_owned || AS_CPU_n) begin
            vec_d    <= 1'b0;
            iack_ack <= 1'b0;
            iack_dly <= 2'd0;
        end else if (!as_cpu_q && FC == 3'b111) begin
            if (iack_dly == 2'd1) begin     // one clock for the bus to clear
                vec_d    <= 1'b1;
                iack_ack <= 1'b1;
            end else
                iack_dly <= iack_dly + 2'd1;
        end
    end

    // ---- 6800 / E ----------------------------------------------------------
    wire m68_as_rel, m68_ack, m68_drive_d, m68_busy;
    wire [15:0] m68_data;

    m6800 #(.LISTEN_W(LISTEN_W)) u_m6800 (
        .clk        (clk),
        .bus_owned  (bus_owned),
        .jp2_gen_e  (~JP2),
        .e_in       (E_IN),
        .e_out      (E_OUT),
        .e_oe       (E_OE),
        .vma_n_out  (VMA_n_OUT),
        .vma_n_oe   (VMA_n_OE),
        .as_cpu_n   (AS_CPU_n),
        .as_cpu_q   (as_cpu_q),
        .vpa_q      (vpa_q),
        .rw_n       (RW_n),
        .d_in       (D_IN),
        .as_release (m68_as_rel),
        .ack        (m68_ack),
        .drive_d    (m68_drive_d),
        .data       (m68_data),
        .e_ready    (e_ready),
        .busy       (m68_busy)
    );

    // ---- autoconfig: two boards, chained ------------------------------------
    // ram.cfgout -> sd.cfgin, and the pin comes from the last one, so the
    // external CFGOUT cannot assert until both boards have configured.
    wire        size_4mb = ~JP4;                   // JP4 closed = 4 MB
    wire        cyc      = cpu_as & bus_owned;

    wire        acr_sel, acr_sel_addr, acr_ack, acr_configured, acr_cfgout_n;
    wire [15:0] acr_data;
    wire  [3:0] acr_doe;
    wire  [7:0] acr_base;

    autoconfig_zii #(
        .PRODUCT_ID (8'd10),                       // Spitfire 2000, RAM
        .MEMLIST    (1'b1),
        .DIAGVALID  (1'b0)
    ) u_acfg_ram (
        .clk        (clk),
        .reset      (~reset_q),                    // a real board clears on RESET
        .cfgin_n    (cfgin_q),
        .cfgout_n   (acr_cfgout_n),
        .size_code  (size_4mb ? 3'b111 : 3'b000),  // 4 MB : 8 MB
        .cyc        (cyc),
        .a          (A),
        .rw_n       (RW_n),
        .uds_n      (UDS_n),
        .d_in       (D_IN),
        .sel        (acr_sel),
        .sel_addr   (acr_sel_addr),
        .ack        (acr_ack),
        .d_out      (acr_data),
        .d_oe_nib   (acr_doe),
        .configured (acr_configured),
        .base       (acr_base)
    );

    wire        acs_sel, acs_sel_addr, acs_ack, acs_configured;
    wire [15:0] acs_data;
    wire  [3:0] acs_doe;
    wire  [7:0] acs_base;

    // sfsd.rom's DiagArea is DAC_NIBBLEWIDE | DAC_CONFIGTIME, da_Size 852,
    // DiagPoint +0x0E, name "spisd.device", and it sits at ROM byte 0.
    //
    // DIAG_VEC is 1, not 0, because U13 hangs off D0-D7 -- the LOWER byte,
    // which a 68000 reaches with LDS at ODD addresses. So ROM byte N is at
    // base + 2N + 1 and the DiagArea starts at offset 1. expansion.library
    // reads from base + er_InitDiagVec stepping by 2, so an even vector would
    // land every read on an even byte, where nothing drives the bus.
    //
    // If enumeration hangs, try 16'h0000, then DIAGVALID 1'b0 -- which boots
    // normally with the ROM merely readable, and is a clean bisect point.
    autoconfig_zii #(
        .PRODUCT_ID (8'd11),                       // Spitfire 2000, SD Card
        .MEMLIST    (1'b0),                        // I/O board, not free RAM
        .DIAGVALID  (1'b1),
        .DIAG_VEC   (16'h0001)
    ) u_acfg_sd (
        .clk        (clk),
        .reset      (~reset_q),
        .cfgin_n    (acr_cfgout_n),                // chained behind the RAM
        .cfgout_n   (CFGOUT_n),
        .size_code  (3'b001),                      // 64 KB
        .cyc        (cyc),
        .a          (A),
        .rw_n       (RW_n),
        .uds_n      (UDS_n),
        .d_in       (D_IN),
        .sel        (acs_sel),
        .sel_addr   (acs_sel_addr),
        .ack        (acs_ack),
        .d_out      (acs_data),
        .d_oe_nib   (acs_doe),
        .configured (acs_configured),
        .base       (acs_base)
    );

    wire        ac_sel      = acr_sel      | acs_sel;
    wire        ac_sel_addr = acr_sel_addr | acs_sel_addr;
    wire        ac_ack      = acr_ack      | acs_ack;
    wire [15:0] ac_data     = acr_sel ? acr_data : acs_data;
    wire  [3:0] ac_doe      = acr_doe      | acs_doe;

    // ---- SD card: shared window, ROM then registers --------------------------
    // The ROM and the registers occupy the same 64 KB and cannot be split by
    // address, so they are split in time. sd_enabled latches on the first
    // write to the window: reads before it are expansion.library copying the
    // DiagArea, reads after are the driver. Cleared by RESET so the next
    // enumeration sees the ROM again.
    //
    // The implicit contract is that the driver writes a register before it
    // reads one. DiagCopy runs at CONFIGTIME and the driver much later, so
    // nothing plausible sits between them -- but a read-before-write would
    // silently return ROM data rather than failing loudly.
    reg  sd_enabled = 1'b0;
    wire sd_sel, sd_sel_addr;

    always @(posedge clk)
        if (!reset_q)                          sd_enabled <= 1'b0;
        else if (sd_sel && !ds_n && !RW_n)     sd_enabled <= 1'b1;

    sdio u_sdio (
        .A_HIGH           (A[23:16]),
        .RW_n             (RW_n),
        .AS_CPU_n         (AS_CPU_n),
        .BASE_SDIO        (acs_base),
        .SDIO_CONFIGURED  (acs_configured),
        .SD_ENABLED       (sd_enabled),
        .ROM_OE_n         (ROM_OE_n),
        .SDIO_ACCESS      (sd_sel),
        .SDIO_ACCESS_ADDR (sd_sel_addr)
    );

    wire        sd_data_oe, sd_int2_n, sd_dtack_n;
    wire [15:0] sd_data;

    sdcard u_sdcard (
        .C100M            (pll_inst1_CLKOUT1),
        .CLKCPU           (clk),
        .RESET_n          (reset_q),
        .ADDR             (A[4:1]),
        .ACCESS           (sd_sel),            // whole window: also DTACKs ROM reads
        .RW_n             (RW_n),
        .UDS_n            (UDS_n),
        .LDS_n            (LDS_n),
        .AS_CPU_n         (AS_CPU_n),
        .DS_n             (ds_n),
        .D_IN             (D_IN),
        .MISO             (SD_MISO),
        .CD_n             (SD_CD_n),
        .CPU_SPEED_SWITCH (1'b0),              // becomes the turbo flag in M5
        .DATA_OE          (sd_data_oe),
        .INT2_n           (sd_int2_n),
        .SS_n             (),                  // LED in this build
        .SCLK             (SD_SCLK),
        .MOSI             (SD_MOSI),
        .DTACK_n          (sd_dtack_n),
        .DATA_OUT         (sd_data)
    );

    // INT2 is a wired-OR line shared with the whole machine through a
    // permanently-on FET: drive 0 or release, never drive 1.
    assign INT2_n_OUT = 1'b0;
    assign INT2_n_OE  = ~sd_int2_n;

    // ---- fast RAM -----------------------------------------------------------
    // A master drives AS on the motherboard side and the address reaches the
    // SRAM through the FETs, so the same decode serves it. dma_active is just
    // "BGACK is asserted", so this follows the master's own cycle directly
    // rather than any state of ours.
    wire dma_cyc = dma_active & ~AS_MB_n_IN;
    wire ram_sel, ram_sel_addr, ram_ack;

    // RAM_WAIT 1 adds a wait state. Zero is comfortable on paper -- 10 ns SRAM
    // against a 560 ns cycle -- but it is the cheapest experiment available if
    // a machine shows rare fast RAM errors, so it is exposed here rather than
    // buried as a default inside the module.
    fastram #(
        .RAM_WAIT (0)
    ) u_fastram (
        .clk             (clk),
        .cyc             (cyc | dma_cyc),
        .a_hi            (A[23:20]),
        .rw_n            (RW_n),
        .uds_n           (UDS_n),
        .lds_n           (LDS_n),
        .configured      (acr_configured),
        .base_nib        (acr_base[7:4]),
        .size_4mb        (size_4mb),
        .sel             (ram_sel),
        .sel_addr        (ram_sel_addr),
        .ack             (ram_ack),
        .bank1           (),
        .oe_bank0_n      (OE_BANK0_n),
        .oe_bank1_n      (OE_BANK1_n),
        .we_bank0_even_n (WE_BANK0_EVEN_n),
        .we_bank0_odd_n  (WE_BANK0_ODD_n),
        .we_bank1_even_n (WE_BANK1_EVEN_n),
        .we_bank1_odd_n  (WE_BANK1_ODD_n)
    );

    // ---- pin drivers --------------------------------------------------------
    // AS is withheld for anything we answer ourselves. Gary qualifies every
    // decode on AS, so this is what keeps the motherboard out of the cycle.
    //
    // The OR terms are decoded from the ADDRESS ONLY, not qualified with AS.
    // AS_CPU_n already forces this high when no cycle is running, so adding AS
    // to the other terms changes nothing logically but drags it through the
    // whole address comparator -- that alone took this path from 2.9 ns to
    // 11.2 ns. Address and FC are valid at S1, half a clock before AS falls at
    // S2, so the decode is settled by the time it matters.
    wire iack_addr = bus_owned & (FC == 3'b111);
    assign AS_MB_n_OUT = AS_CPU_n | iack_addr | m68_as_rel
                       | (bus_owned & ram_sel_addr) | (bus_owned & ac_sel_addr)
                       | (bus_owned & sd_sel_addr);
    assign AS_MB_n_OE  = bus_owned;

    // Gary answers a 6800 cycle with VPA and never with DTACK, so forwarding
    // is safe until we know which it is. Qualified with live AS so our own
    // acknowledge cannot leak into the following cycle.
    wire loc_ack   = iack_ack | m68_ack | ram_ack | ac_ack | (sd_sel & ~sd_dtack_n);
    wire fwd_dtack = bus_owned & ~iack & ~m68_busy & ~ram_sel & ~ac_sel & ~sd_sel;
    assign DTACK_CPU_n    = (fwd_dtack ? DTACK_MB_n_IN : 1'b1) & ~(loc_ack & cpu_as);
    // Gary DTACKs expansion space anyway to stop the machine hanging on
    // missing hardware, but we are the actual responder, so ack it ourselves.
    // Open drain, wire-ORed with Gary's open-collector output.
    assign DTACK_MB_n_OUT = 1'b0;
    assign DTACK_MB_n_OE  = dma_cyc & ram_sel;

    // On a RAM read the SRAM drives the bus directly through the FETs; the
    // FPGA drives data only for the autovector and autoconfig nibbles.
    // The FETs are strapped on, so anything we drive here appears on the
    // motherboard bus too. We cannot stop the SRAM doing that on a fast RAM
    // read, but we can keep the FPGA's own share of the bus as short and as
    // narrow as possible.
    //
    // Gated on a data strobe rather than on AS. A 68000 asserts AS at S2 and
    // the strobes at S4, and latches read data at S6, so driving from S2
    // occupied the bus for two clocks longer than anything needed it -- right
    // across the window where the previous cycle's driver is still turning off
    // and the address is settling. A read cycle with neither strobe asserted
    // transfers nothing, so not driving it is correct by definition.
    wire [15:0] lanes = {{8{~UDS_n}}, {8{~LDS_n}}};
    wire        drive = cpu_as & bus_owned & (~UDS_n | ~LDS_n);
    // On a ROM read the SST39LF040 drives D0-D7 itself, so sd_data_oe is
    // qualified with sd_enabled -- that is what keeps the ROM and the FPGA
    // off the same lines.
    wire sd_drive = sd_data_oe & sd_enabled;
    assign D_OUT = vec_d    ? {8'h00, avec}
                 : ac_sel   ? ac_data
                 : sd_drive ? sd_data
                 :            m68_data;
    assign D_OE  = vec_d       & drive ? 16'h00FF
                 : ac_sel      & drive ? {ac_doe, 12'h000}
                 : sd_drive    & drive ? lanes
                 : m68_drive_d & drive ? lanes
                 :                       16'h0000;

    // ---- DIAGNOSTIC LED (temporary) -----------------------------------------
    // The B2000 + HC8+ hang happens before any code runs, so there is no Guru,
    // no screen and no serial to read. This blinks the SD LED to say how far
    // we got. Count the blinks, then a gap, then it repeats:
    //
    //   1  we took the bus
    //   2  reset released, our CPU is running
    //   3  the RAM board configured
    //   4  the SD board configured -- CFGOUT asserted, chain handed onward
    //   5  /BR and /BGACK seen idle high, so the arbitration relay is live
    //   6  an external /BR or /BGACK was relayed to our CPU
    //   7  a master actually took the bus (/BGACK asserted)
    //
    // Once a master has read or written our fast RAM the LED stops counting
    // and simply lights whenever that is happening -- solid through a disk
    // transfer means DMA into our RAM, confirmed at the pins.
    //
    // A LONG blink at the end of the sequence means BOSS was asserted, i.e.
    // we detected a B2000 and took the bus that way. No long blink means an
    // A500 or Braunschweig, where we take it by holding /BR instead.
    //
    // Four means we finished our part and the fault is downstream. Stopping at
    // four when a DMA card is fitted means /BR or /BGACK is not idling high --
    // so we never relay, and that card waits for a grant that never comes.
    //
    // Drives the SD LED, so nothing has to be wired or reconfigured to read
    // it. The SD CARD DOES NOT WORK IN THIS BUILD -- SD_SS_n is the LED line.
    // The driver still loads and simply finds no card, which is a path the
    // machine already handles.
    //
    // DELETE THIS BLOCK and restore SD_SS_n to u_sdcard when done.
    // Ground truth for "is the GVP really DMAing into OUR fast RAM?". This is
    // a master holding the bus via BGACK and addressing our SRAM -- it cannot
    // be the CPU bouncing through chip RAM, because then we are not in a DMA
    // cycle at all. Once seen, the LED stops reporting stages and follows DMA
    // activity instead, stretched to ~150 ms so the eye can see it.
    reg [19:0] dma_str  = 20'd0;
    reg        dma_ever = 1'b0;
    always @(posedge clk)
        if (dma_cyc & ram_sel) begin dma_str <= {20{1'b1}}; dma_ever <= 1'b1; end
        else if (|dma_str)          dma_str <= dma_str - 20'd1;

    reg [26:0] dled = 27'd0;
    reg  [2:0] dstage = 3'd0;
    always @(posedge clk) begin
        dled <= dled + 27'd1;
        if      (arb_mtook)      dstage <= 3'd7;
        else if (arb_relayed)    dstage <= 3'd6;
        else if (arb_sane &&
                 acs_configured) dstage <= 3'd5;
        else if (acs_configured) dstage <= 3'd4;
        else if (acr_configured) dstage <= 3'd3;
        else if (arb_running)    dstage <= 3'd2;
        else if (arb_took)       dstage <= 3'd1;
    end
    // Short blinks count the stage; one long blink after them if BOSS was
    // asserted, taking three slots so it cannot be miscounted.
    //
    // Deliberately slow, because the point is for a person to count them by
    // eye: each slot is ~1.2 s at 7 MHz, so a blink is 0.6 s on and 0.6 s off
    // and the whole cycle is about 19 s. Widen dled if it needs to be slower
    // still -- bit 22 sets the blink rate and bits 26:23 the slot.
    wire dled_short = (dled[26:23] < {1'b0, dstage}) & dled[22];
    wire dled_long  = arb_cpu & (dled[26:23] >= {1'b0, dstage} + 4'd2)
                              & (dled[26:23] <  {1'b0, dstage} + 4'd5);
    wire dled_on    = dma_ever ? (|dma_str) : (dled_short | dled_long);
    assign SD_SS_n = ~dled_on;                   // LED lights when SS is low

    // ---- parked -------------------------------------------------------------
    assign FLASH_OE_n      = 1'b1;
    assign FLASH_WE_n      = 1'b1;   // also the FPGA TEST_N pin -- keep high
    assign FLASH_A19       = 1'b0;

    wire _unused = &{1'b0, OSC_CLK, BERR_n, IPL_n, INT2_n_IN, INT6_n,
                     BG_68SEC000_n, JP1, JP3, pll_inst1_CLKOUT0,
                     AS_MB_n_IN, BR_n_IN, VMA_n_IN, HLT_n_IN, 1'b0};

endmodule

`default_nettype wire
