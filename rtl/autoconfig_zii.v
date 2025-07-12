`timescale 1ns / 1ps

module autoconfig_zii(
    input C7M,
    input CFGIN_n,
    input JP6,
    input JP7,
    input AS_CPU_n,
    input RESET_n,
    input DS_n,
    input RW_n,
    input [23:16] A_HIGH,
    input [6:1] A_LOW,
    input [15:0] data_in,
    output [15:0] data_out,
    output data_oe,
    output reg [7:5] BASE_RAM,
    output reg [7:0] BASE_IDE,
    output reg [7:0] BASE_SD,
    output RAM_CONFIGURED_n,
    output IDE_CONFIGURED_n,
    output SD_CONFIGURED_n,
    output CFGOUT_n
);

localparam RAM_CARD = 2'b00;
localparam IDE_CARD = 2'b01;
localparam SD_CARD = 2'b10;

localparam CONFIGURING_RAM = 3'b111;
localparam CONFIGURING_IDE = 3'b110;
localparam CONFIGURING_SD  = 3'b100;

localparam [15:0] MFG_ID_OAHR     = 16'h144A; // 5194   - OAHR
localparam [15:0] MFG_ID_BSC      = 16'h082C; // 2092   - BSC

localparam [7:0]  RAM_PROD_ID = 8'd10;    // 5194/10 - J.Bilander SF2000 RAM
localparam [7:0]  IDE_PROD_ID = 8'd6;     // 2092/6 - Oktagon 2008, BSC I/O device / A1K.org Community IDE Controller by Matze (64K)
localparam [7:0]  SD_PROD_ID  = 8'd11;    // 5194/11 - J.Bilander SF2000 SD Card
localparam [15:0] SERIAL      = 16'd0;

/*
SysInfo reports it as a BSC Oktagon 2008 Z2 memory and a BSC Oktagon I/O device.
scsi.device v109.3 or oktagon.device v6.10, selectable via jumper.
*/

reg [3:0] data_nyb_out = 4'hF;
reg [2:0] config_out_n = 3'b111;
reg [2:0] configured_n = 3'b111;
reg [2:0] shutup_n = 3'b111;

wire autoconfig_access = !CFGIN_n && CFGOUT_n && (A_HIGH == 8'hE8) && !AS_CPU_n;

assign RAM_CONFIGURED_n = configured_n[RAM_CARD];
assign IDE_CONFIGURED_n = configured_n[IDE_CARD];
assign SD_CONFIGURED_n  = configured_n[SD_CARD];
assign CFGOUT_n = |config_out_n;

assign data_out = {data_nyb_out, 12'd0};
assign data_oe = autoconfig_access && RW_n && !DS_n;

always @(negedge RESET_n or posedge AS_CPU_n) begin

    if (!RESET_n) begin

        config_out_n <= 3'b111;

    end else begin

        config_out_n <= configured_n & shutup_n;

    end
end

always @(negedge RESET_n or posedge C7M) begin

    if (!RESET_n) begin

        configured_n <= 3'b111;
        shutup_n <= 3'b111;

    end else begin

        if(autoconfig_access && !DS_n) begin

            if (RW_n) begin

                // AutoConfig Read sequence. Here is where we publish the RAM and I/O port size and hardware attributes.

                // All nibbles except 00,02,40 and 42 must be inverted

                case (A_LOW)

                    6'h00: begin
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= 4'b1110;                 // (00) 1110 Link into memory free list
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= JP7 ? 4'b1101 : 4'b1100; // (00) 1101 Optional ROM vector valid
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= JP7 ? 4'b1101 : 4'b1100; // (00) 1101 Optional ROM vector valid
                    end
                    6'h01: begin
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= JP6 ? 4'b0000 : 4'b0111; // (02) 8 or 4 MB RAM
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= 4'b0001;                 // (02) 64KB
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= 4'b0001;                 // (02) 64KB
                    end
                    6'h02: begin
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= ~RAM_PROD_ID[7:4];       // (04) Product number RAM
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~IDE_PROD_ID[7:4];       // (04) Product number IDE
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= ~SD_PROD_ID[7:4];       // (04) Product number IDE
                    end
                    6'h03: begin
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= ~RAM_PROD_ID[3:0];       // (06) Product number RAM
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~IDE_PROD_ID[3:0];       // (06) Product number IDE
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= ~SD_PROD_ID[3:0];       // (06) Product number IDE
                    end

                    6'h04: data_nyb_out <= ~4'b1100;             // (08) 1100 Board can be shut up and has preference to be put in 8 Meg space.
                    6'h05: data_nyb_out <= ~4'b0000;             // (0A) 0000 Reserved

                    6'h08: begin                                                                      // (10) Manufacturer ID
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= ~MFG_ID_OAHR[15:12];
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= ~MFG_ID_OAHR[15:12];
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~MFG_ID_BSC[15:12];
                    end
                    6'h09: begin                                                                      // (12) Manufacturer ID
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= ~MFG_ID_OAHR[11:8];
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= ~MFG_ID_OAHR[11:8];
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~MFG_ID_BSC[11:8];
                    end
                    6'h0A: begin                                                                      // (14) Manufacturer ID
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= ~MFG_ID_OAHR[7:4];
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= ~MFG_ID_OAHR[7:4];
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~MFG_ID_BSC[7:4];
                    end
                    6'h0B: begin                                                                      // (16) Manufacturer ID
                        if (config_out_n == CONFIGURING_RAM) data_nyb_out <= ~MFG_ID_OAHR[3:0];
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= ~MFG_ID_OAHR[3:0];
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~MFG_ID_BSC[3:0];
                    end
                    /*
                    6'h0C: data_nyb_out <= 4'hF;                 // (18) Serial number, byte 0 (msb)
                    6'h0D: data_nyb_out <= 4'hF;                 // (1A) ----------"----------
                    6'h0E: data_nyb_out <= 4'hF;                 // (1C) Serial number, byte 1
                    6'h0F: data_nyb_out <= 4'hF;                 // (1E) ----------"----------
                    */

                    6'h10: data_nyb_out <= ~SERIAL[15:12];       // (20) Serial number, byte 2
                    6'h11: data_nyb_out <= ~SERIAL[11:8];        // (22) ----------"----------
                    6'h12: data_nyb_out <= ~SERIAL[7:4];         // (24) Serial number, byte 3 (lsb)
                    6'h13: data_nyb_out <= ~SERIAL[3:0];         // (26) ----------"----------
                    
                    //Optional ROM vector, these two bytes are the offset from the board's base address
                    /*
                    6'h14: if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~4'b0000;   // (28) ROM vector high byte high nybble
                    6'h15: if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~4'b0001;   // (2A) ROM vector high byte low nybble
                    6'h16: if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~4'b0000;   // (2C) ROM vector low byte high nybble
                    */
                    6'h17: begin
                        if (config_out_n == CONFIGURING_IDE) data_nyb_out <= ~4'b0001;   // (2E) Rom vector low byte low nybble
                        if (config_out_n == CONFIGURING_SD)  data_nyb_out <= ~4'b0001;   // (2E) Rom vector low byte low nybble
                    end

                    6'h20: data_nyb_out <= 4'd0;                 // (40) Because this card does not generate INT's
                    6'h21: data_nyb_out <= 4'd0;                 // (42) Because this card does not generate INT's

                    default: data_nyb_out <= 4'hF;

                endcase

            end else begin
	
                // AutoConfig Write sequence. Here is where we receive from the OS the base address for the RAM.

                case (A_LOW)

                    6'h24: begin    // Written Second (48)
                        if (config_out_n == CONFIGURING_RAM) begin
                            BASE_RAM[7:5] <= data_in[15:13];          //A23,A22,A21 is sufficient as base. (2 MB chunks)
                            configured_n[RAM_CARD] <= 1'b0;
                        end
                        if (config_out_n == CONFIGURING_IDE) begin 
                            BASE_IDE[7:4] <= data_in[15:12];
                            configured_n[IDE_CARD] <= 1'b0;
                        end
                        if (config_out_n == CONFIGURING_SD) begin 
                            BASE_SD[7:4] <= data_in[15:12];
                            configured_n[SD_CARD] <= 1'b0;
                        end
                    end
                    6'h25: begin    // Written first (4A)
                        //if (config_out_n == CONFIGURING_RAM) BASE_RAM[3:0] <= data_in[15:12];
                        if (config_out_n == CONFIGURING_IDE) BASE_IDE[3:0] <= data_in[15:12];
                        if (config_out_n == CONFIGURING_SD)  BASE_SD[3:0] <= data_in[15:12];
                    end
                    6'h26: begin    // (4C) "Shut up" address, if KS decides to not configure a specific device
                        if (config_out_n == CONFIGURING_RAM) shutup_n[RAM_CARD] <= 1'b0;
                        if (config_out_n == CONFIGURING_IDE) shutup_n[IDE_CARD] <= 1'b0;
                        if (config_out_n == CONFIGURING_SD) shutup_n[SD_CARD] <= 1'b0;
                    end

                endcase

            end
        end
    end
end


endmodule
