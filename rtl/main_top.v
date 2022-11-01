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
    output DTACK_CPU_n,
    inout BR_n,
    inout BG_n,
    inout E,
    inout AS_MB_n,
    inout [15:0] D
);

/*
    input JP8,
    output SPI_CS_n,
    output ROM_OE_n,
    output ROM_WE_n,
    output ROM_B1,
    output ROM_B2,
    output IDE_IOR_n,
    output IDE_IOW_n,
    output [1:0] IDE_CS_n
*/

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

reg init = 1'b1;
reg dma_n = 1'b1;
reg bus_req_n = 1'b1;
reg br2_n = 1'b1;

reg cpu_speed_switch = 1'b1;
reg dtack_mobo_n = 1'b1;
reg fast_dtack_n = 1'b1;
reg as_mobo_n = 1'b1;
reg [23:0] counter;

localparam cnt_max_value = 24'd10000000;

wire ds_n = LDS_n & UDS_n;      // Data Strobe
wire [7:5] base_ram;            // base address for the RAM_CARD in Z2-space. (A23-A21)
wire [7:0] base_ide;            // base address for the IDE_CARD in Z2-space. (A23-A16)

wire ram_configured_n;          // keeps track if RAM_CARD is autoconfigured ok.
wire ram_access;                // keeps track if local SRAM is being accessed.
wire ide_configured_n;          // keeps track if IDE_CARD is autoconfigured ok.
//wire ide_access;                // keeps track if the IDE is being accessed.

wire as_n = dma_n ? AS_CPU_n : AS_MB_n;
wire m6800_dtack_n;

assign BR_n = bus_req_n ? 1'b0 : 1'bZ;
assign BR_68SEC000_n = br2_n ? BR_n & BGACK_n : 1'bZ;
assign BG_n = dma_n ? 1'bZ : 1'b0;
assign AS_MB_n = dma_n ? as_mobo_n : 1'bZ;

wire mb_dtack_n = cpu_speed_switch ? DTACK_MB_n : dtack_mobo_n;
assign DTACK_CPU_n = mb_dtack_n & m6800_dtack_n & fast_dtack_n;

//Set the CPU speed switch after the PLL generated clocks have stabilized, we boot on 7 MHz...
always @(negedge RESET_n or posedge AS_CPU_n) begin
    if (!RESET_n) begin
        cpu_speed_switch <= 1'b1;
    end else begin
        cpu_speed_switch <= (counter == cnt_max_value) ? SW1 : 1'b1;
    end
end

//Handle synchronization with motherboard
always @(negedge RESET_n or posedge C7M or posedge AS_CPU_n) begin

    if (!RESET_n) begin

        as_mobo_n <= 1'b1;
        dtack_mobo_n <= 1'b1;

    end else begin

        if (AS_CPU_n) begin

            as_mobo_n <= 1'b1;
            dtack_mobo_n <= 1'b1;

        end else begin

            as_mobo_n <= ram_access;
            dtack_mobo_n <= DTACK_MB_n;

        end
    end

end

//Handle fast dtack
always @(posedge CLKCPU or posedge AS_CPU_n) begin
    
    if (AS_CPU_n) begin
        fast_dtack_n <= 1'b1;
    end else begin
        fast_dtack_n <= ~ram_access;
    end
end


//Handle initialize and bus arbitration
always @(negedge RESET_n or posedge C7M) begin

    if (!RESET_n) begin

        init <= 1'b1;
        dma_n <= 1'b1;
        bus_req_n <= 1'b1;
        br2_n <= 1'b1;
        counter <= 1'b0;

    end else begin 

        if (counter != cnt_max_value) begin
            counter <= counter + 1'b1;
        end
        
        if (init) begin
            if (JP5) begin  //JP5 is true when jumper is open. E-CLK is being generated by internal 68k.

                if (!BG_n && AS_MB_n && BGACK_n && DTACK_MB_n) begin
                    //The 68SEC000 is released to master the bus. The internal 68k is off the bus now, still generating E-clk though.
                    init <= 1'b0;
                    br2_n <= 1'b0;
                end

            end else begin //JP5 is false when jumper is closed. No internal 68k in socket, E-clk will be generated by Accelerator card.

                if (!BG_68SEC000_n && AS_CPU_n) begin
                    //The 68SEC000 is released to master the bus.
                    init <= 1'b0;
                    bus_req_n <= 1'b0;
                end
            end
        end else begin

            if (!JP5 && !BG_68SEC000_n) begin
                if (AS_CPU_n && DTACK_CPU_n) begin
                    dma_n <= 1'b0;  //Allows other bus master, DMA from A590, GVP or similar.
                end 
            end else begin
                dma_n <= 1'b1;
            end
        end
    end
end

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
    .RAM_ACCESS(ram_access)
);

/*
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
*/

endmodule
