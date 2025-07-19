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
    output reg E_OE,
    output reg BR_68SEC000_n,
    output reg BOSS_n_OUT,
    output reg BOSS_n_OE,
    output reg BR_n_OUT,
    output reg BR_n_OE = 1'b1,
    output reg BG_n_OUT,
    output reg BG_n_OE

);

/*
Jumper descriptions:
JP1: 7 MHz / Turbo
JP2: E-CLK
JP3: Rom overlay
JP4: 4/8 MB SRAM
*/

reg bootstrap = 1'b1;
reg dma_en;
reg mobo_dtack_n = 1'b1;
reg mobo_as_n = 1'b1;
reg cpu_speed_switch;
reg switch_state = JP1 ? 1'b1 : 1'b0;
reg turbo_clk;
reg sd_enabled;

wire C100M = pll_inst1_CLKOUT1;
wire C7M = ~C7M_n;
wire m6800_dtack_n;
wire ram_dtack_n;
wire flash_dtack_n;
wire sdcard_dtack_n;

wire ac_data_oe;
wire sd_data_oe;
wire [15:12] ac_data_out;   // autoconfig data nybble out
wire [15:0] sd_data_out;
wire INT2_n;

wire as_n = BG_68SEC000_n ? AS_CPU_n : AS_MB_n_IN;
wire ds_n = LDS_n & UDS_n;  // Data Strobe
wire [7:5] base_ram;        // base address for the RAM_CARD in Z2-space. (A23-A21)
wire [7:0] base_sd;         // base address for the SDIO_CARD in Z2-space. (A23-A16)

wire ram_configured_n;      // keeps track if RAM_CARD is autoconfigured ok.
wire ram_access;            // keeps track if local SRAM is being accessed.
wire sd_configured_n;       // keeps track if SD_CARD is autoconfigured ok.
wire sdcard_access;         // keeps track if the SD card is being accessed.
wire flash_access;          // keeps track if the Flash is being accessed.

assign sdcard_access = !sd_configured_n && (A[23:16] == base_sd) && !AS_CPU_n;

assign D_OUT = ac_data_oe ? {ac_data_out, 12'd0} : sd_data_out;
assign D_OE = ac_data_oe | (sd_data_oe & sd_enabled) ? 16'hFFFF : 16'd0;

wire as_mobo_n = AS_CPU_n | ram_access | flash_access | sdcard_access;
wire dtack_mobo_n = cpu_speed_switch ? mobo_dtack_n : DTACK_MB_n;

assign CLKCPU = cpu_speed_switch ? turbo_clk : C7M;
assign DTACK_CPU_n = dtack_mobo_n & m6800_dtack_n & ram_dtack_n & flash_dtack_n & sdcard_dtack_n;
assign AS_MB_n_OUT = cpu_speed_switch ? mobo_as_n : as_mobo_n;
assign AS_MB_n_OE = BG_68SEC000_n;

//Handle access to the Flash ROM (39LF040)
wire rom_access = sdcard_access && RW_n && !sd_enabled; // ROM enabled before first write
assign ROM_OE_n = !rom_access;

always @(negedge RESET_n or posedge CLKCPU) begin
    if (!RESET_n) begin
        sd_enabled <= 1'b0;
    end else begin
        if (sdcard_access && !ds_n && !RW_n) begin
            sd_enabled <= 1'b1; // Enable SD interface on first write
        end
    end
end

localparam BOOT_7M_LIMIT = 30'd300000000;   // 3 seconds at 100 MHz
reg [29:0] b_count;                         // boot on 7 MHz counter

localparam DEBOUNCE_LIMIT = 21'd2000000;    // 20 ms at 100 MHz
reg [20:0] d_count;                         // debounce d_counter

//Handle cpu speed switch with debounce
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

//Generate the turbo clock
always @ (posedge pll_inst1_CLKOUT0) begin
    turbo_clk <= ~turbo_clk;
end

//Handle synchronization with motherboard
always @(negedge RESET_n or posedge C7M or posedge AS_CPU_n) begin

    if (!RESET_n) begin

        mobo_as_n <= 1'b1;
        mobo_dtack_n <= 1'b1;

    end else begin

        if (AS_CPU_n) begin

            mobo_as_n <= 1'b1;
            mobo_dtack_n <= 1'b1;

        end else begin

            mobo_as_n <= as_mobo_n;
            mobo_dtack_n <= DTACK_MB_n;

        end
    end
end

//Bootstrapping and bus arbitration
always @ (negedge RESET_n or posedge C7M) begin

    if (!RESET_n) begin

        bootstrap <= 1'b1;
        dma_en <= 1'b0;
        BOSS_n_OE <= 1'b0;
        BR_68SEC000_n <= 1'b0;
        BR_n_OUT <= 1'b0;
        BR_n_OE <= 1'b1;
        BG_n_OE <= 1'b0;

    end else begin

        if (bootstrap) begin

            bootstrap <= 1'b0;

            if (BG_n_IN != 0 || JP2 != 0) begin

                BR_68SEC000_n <= 1'b1;
                E_OE <= !JP2;

                if (BOSS_n_IN) begin //Plugged into a B2000

                    BOSS_n_OUT <= 1'b0;
                    BOSS_n_OE <= 1'b1;
                    BR_n_OE <= 1'b0;
                    dma_en <= 1'b1;

                end else begin //Plugged into a A500 or A2000 rev 4

                    BR_n_OE <= !BG_n_IN;
                    dma_en <= BG_n_IN; //The socketed internal 68k cpu has to be removed to enable DMA.

                end
            end

        end else begin

            if (dma_en) begin

                BR_n_OE <= 1'b0;
                BR_68SEC000_n <= BR_n_IN & BGACK_n; //Three to two wire bus arbitration mapping

                BG_n_OE <= 1'b1;
                BG_n_OUT <= BG_68SEC000_n;

            end
        end
    end
end

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
