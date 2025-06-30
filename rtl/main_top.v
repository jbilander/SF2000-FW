`timescale 1ns / 1ps
`default_nettype none

module main_top(

    input wire JP2,
    input wire C7M_n,
    input wire RESET_n,
    input wire AS_CPU_n,
    input wire VPA_n,
    input wire [2:0] FC,
    input wire DTACK_MB_n,
    input wire BOSS_n_IN,
    input wire BR_n_IN,
    input wire BG_n_IN,
    input wire BGACK_n,
    input wire BG_68SEC000_n,
    input wire E_IN,
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
    output wire AS_MB_n,
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
reg enable_dma;

wire C7M = ~C7M_n;
wire m6800_dtack_n;
//wire ds_n = LDS_n & UDS_n;  // Data Strobe
//wire [7:5] base_ram;        // base address for the RAM_CARD in Z2-space. (A23-A21)
//wire [7:0] base_sdio;       // base address for the SDIO_CARD in Z2-space. (A23-A16)

//wire ram_configured_n;      // keeps track if RAM_CARD is autoconfigured ok.
//wire ram_access;            // keeps track if local SRAM is being accessed.
//wire sdio_configured_n;     // keeps track if SDIO_CARD is autoconfigured ok.
//wire sdio_access;           // keeps track if the SDIO is being accessed.

assign CLKCPU = C7M;
assign DTACK_CPU_n = DTACK_MB_n & m6800_dtack_n;
assign AS_MB_n = AS_CPU_n;

assign OE_BANK0_n = 1'b1;
assign OE_BANK1_n = 1'b1;
assign WE_BANK0_ODD_n = 1'b1;
assign WE_BANK1_ODD_n = 1'b1;
assign WE_BANK0_EVEN_n = 1'b1;
assign WE_BANK1_EVEN_n = 1'b1;

//Bootstrapping and bus arbitration
always @ (negedge RESET_n or posedge C7M) begin

    if (!RESET_n) begin

        bootstrap <= 1'b1;
        enable_dma <= 1'b0;
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
                    enable_dma <= 1'b1;

                end else begin //Plugged into a A500 or A2000 rev 4

                    BR_n_OE <= !BG_n_IN;
                    enable_dma <= BG_n_IN; //The socketed internal 68k cpu has to be removed to enable DMA.

                end
            end

        end else begin

            if (enable_dma) begin

                BR_n_OE <= 1'b0;
                BR_68SEC000_n <= BR_n_IN & BGACK_n; //Three to two wire bus arbitration mapping

                BG_n_OE <= 1'b1;
                BG_n_OUT <= BG_68SEC000_n;

            end
        end
    end
end

/*
clock clkcontrol(
    .JP1(JP1),
    .C14M(C14M),
    .C80M(pll_inst1_CLKOUT0),
    .C100M(pll_inst1_CLKOUT1),
    .C7M(C7M),
    .C40M(C40M),
    .C50M(C50M),
    .CLKCPU(CLKCPU)
);
*/

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


/*
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
    .D_OUT(D_OUT[15:12]),
    .D_OE(D_OE[15:12]),
    .BASE_RAM(base_ram[7:5]),
    .BASE_SDIO(base_sdio[7:0]),
    .RAM_CONFIGURED_n(ram_configured_n),
    .SDIO_CONFIGURED_n(sdio_configured_n),
    .CFGOUT_n(CFGOUT_n)
);

fastram ramcontrol(
    .A(A[23:21]),
    .JP4(JP4),
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
*/

endmodule
