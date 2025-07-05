`timescale 1ns / 1ps

module autoconfig_zii(
    input wire C7M,
    input wire CFGIN_n,
    input wire JP4,
    input wire AS_CPU_n,
    input wire RESET_n,
    input wire DS_n,
    input wire RW_n,
    input wire [23:16] A_HIGH,
    input wire [6:1] A_LOW,
    input wire [15:12] D_IN,
    output reg [15:12] D_OUT,
    output wire [15:12] D_OE,
    output reg [7:5] BASE_RAM,
    output reg [7:0] BASE_SDIO,
    output wire RAM_CONFIGURED_n,
    output wire SDIO_CONFIGURED_n,
    output wire CFGOUT_n
);

localparam RAM_CARD  = 1'b0;
localparam SDIO_CARD = 1'b1;

localparam CONFIGURING_RAM  = 2'b11;
localparam CONFIGURING_SDIO = 2'b10;

localparam [15:0] MFG_ID        = 16'h082C; // 2092   - BSC
localparam [7:0]  RAM_PROD_ID   = 8'd8;     // 2092/8 - Oktagon 2008, BSC Memory Master (8M)
localparam [7:0]  SDIO_PROD_ID  = 8'd6;     // 2092/6 - Oktagon 2008, BSC I/O device (64K)
localparam [15:0] SERIAL        = 16'd0;

// SysInfo reports it as a BSC Oktagon 2008 Z2 memory and a BSC Oktagon I/O device.

reg [1:0] configured_n = 2'b11;
reg [1:0] shutup_n = 2'b11;
reg [1:0] config_out_n = 2'b11;

wire autoconfig_access = !CFGIN_n && CFGOUT_n && (A_HIGH == 8'hE8) && !AS_CPU_n;
//wire [1:0] config_out_n = configured_n & shutup_n;

assign RAM_CONFIGURED_n = configured_n[RAM_CARD];
assign SDIO_CONFIGURED_n = configured_n[SDIO_CARD];

assign CFGOUT_n = |config_out_n;
assign D_OE  = autoconfig_access && RW_n && !DS_n ? 4'hF : 4'h0;


always @(negedge RESET_n or posedge C7M or posedge AS_CPU_n) begin

    if (!RESET_n) begin

        config_out_n <= 2'b11;

    end else begin

        if (AS_CPU_n) config_out_n <= configured_n & shutup_n;

    end
end

always @(negedge RESET_n or posedge C7M) begin

    if (!RESET_n) begin

        configured_n <= 2'b11;
        shutup_n <= 2'b11;

    end else begin

        if(autoconfig_access && !DS_n) begin

            if (RW_n) begin

                // AutoConfig Read sequence. Here is where we publish the RAM and I/O port size and hardware attributes.

                // All nibbles except 00,02,40 and 42 must be inverted

                case (A_LOW)

                    6'h00: begin
                        if (config_out_n == CONFIGURING_RAM)  D_OUT <= 4'b1110;                 // (00) 1110 Link into memory free list
                        if (config_out_n == CONFIGURING_SDIO) D_OUT <= 4'b1101;                 // (00) 1101 Optional ROM vector valid
                    end
                    6'h01: begin
                        if (config_out_n == CONFIGURING_RAM)  D_OUT <= JP4 ? 4'b0000 : 4'b0111; // (02) 8 or 4 MB RAM
                        if (config_out_n == CONFIGURING_SDIO) D_OUT <= 4'b0001;                 // (02) 64KB
                    end
                    6'h02: begin
                        if (config_out_n == CONFIGURING_RAM)  D_OUT <= ~RAM_PROD_ID[7:4];       // (04) Product number RAM
                        if (config_out_n == CONFIGURING_SDIO) D_OUT <= ~SDIO_PROD_ID[7:4];      // (04) Product number SDIO
                    end
                    6'h03: begin
                        if (config_out_n == CONFIGURING_RAM)  D_OUT <= ~RAM_PROD_ID[3:0];       // (06) Product number RAM
                        if (config_out_n == CONFIGURING_SDIO) D_OUT <= ~SDIO_PROD_ID[3:0];      // (06) Product number SDIO
                    end

                    6'h04: D_OUT <= ~4'b1100;            // (08) 1100 Board can be shut up and has preference to be put in 8 Meg space.
                    6'h05: D_OUT <= ~4'b0000;            // (0A) 0000 Reserved

                    6'h08: D_OUT <= ~MFG_ID[15:12];      // (10) Manufacturer ID
                    6'h09: D_OUT <= ~MFG_ID[11:8];       // (12) Manufacturer ID
                    6'h0A: D_OUT <= ~MFG_ID[7:4];        // (14) Manufacturer ID
                    6'h0B: D_OUT <= ~MFG_ID[3:0];        // (16) Manufacturer ID

                    /*
                    6'h0C: D_OUT <= 4'hF;                // (18) Serial number, byte 0 (msb)
                    6'h0D: D_OUT <= 4'hF;                // (1A) ----------"----------
                    6'h0E: D_OUT <= 4'hF;                // (1C) Serial number, byte 1
                    6'h0F: D_OUT <= 4'hF;                // (1E) ----------"----------
                    */

                    6'h10: D_OUT <= ~SERIAL[15:12];      // (20) Serial number, byte 2
                    6'h11: D_OUT <= ~SERIAL[11:8];       // (22) ----------"----------
                    6'h12: D_OUT <= ~SERIAL[7:4];        // (24) Serial number, byte 3 (lsb)
                    6'h13: D_OUT <= ~SERIAL[3:0];        // (26) ----------"----------
					
                    /*
                    //Optional ROM vector, these two bytes are the offset from the board's base address
                    6'h14: if (config_out_n == CONFIGURING_SDIO) D_OUT <= ~4'b0000;   // (28) ROM vector high byte high nybble
                    6'h15: if (config_out_n == CONFIGURING_SDIO) D_OUT <= ~4'b0000;   // (2A) ROM vector high byte low nybble
                    6'h16: if (config_out_n == CONFIGURING_SDIO) D_OUT <= ~4'b0000;   // (2C) ROM vector low byte high nybble
                    */
                    6'h17: if (config_out_n == CONFIGURING_SDIO) D_OUT <= ~4'b0001;  // (2E) Rom vector low byte low nybble

                    6'h20: D_OUT <= 4'd0;                // (40) Because this card does not generate INT's
                    6'h21: D_OUT <= 4'd0;                // (42) Because this card does not generate INT's

                    default: D_OUT <= 4'hF;

                endcase

            end else begin

                // AutoConfig Write sequence. Here is where we receive from the OS the base address for the RAM.

                case (A_LOW)

                    6'h24: begin    // Written Second (48)
                        if (config_out_n == CONFIGURING_RAM) begin
                            BASE_RAM[7:5] <= D_IN[15:13];        //A23,A22,A21 is sufficient as base. (2 MB chunks)
                            configured_n[RAM_CARD] <= 1'b0;
                        end
                        if (config_out_n == CONFIGURING_SDIO) begin
                            BASE_SDIO[7:4] <= D_IN;
                            configured_n[SDIO_CARD] <= 1'b0;
                        end
                    end
                    6'h25: begin    // Written first (4A)
                        if (config_out_n == CONFIGURING_SDIO) BASE_SDIO[3:0] <= D_IN;
                    end
                    6'h26: begin    // (4C) "Shut up" address, if KS decides to not configure a specific device
                        if (config_out_n == CONFIGURING_RAM) shutup_n[RAM_CARD] <= 1'b0;
                        if (config_out_n == CONFIGURING_SDIO) shutup_n[SDIO_CARD] <= 1'b0;
                    end

                endcase

            end
        end
    end
end


endmodule
