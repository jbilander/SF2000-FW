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
    output reg [15:12] DATA_OUT = 4'hF,
    output wire DATA_OE,
    output reg [7:5] BASE_RAM = 3'd0,
    output reg [7:0] BASE_SD = 8'd0,
    output wire RAM_CONFIGURED_n,
    output wire SD_CONFIGURED_n,
    output wire CFGOUT_n
);

/*
Zorro II AutoConfig Implementation

This module implements the Zorro II autoconfiguration protocol for two devices:
1. RAM_CARD  - Fast RAM (4MB or 8MB based on JP4)
2. SD_CARD   - SD card controller I/O device (64KB)

The autoconfiguration sequence:
1. KickStart reads configuration data from $E80000-$E8FFFF
2. KickStart writes base address to configure the device
3. Device can be "shut up" if KickStart doesn't want to configure it
*/

localparam RAM_CARD = 1'b0;
localparam SD_CARD  = 1'b1;

localparam CONFIGURING_RAM = 2'b11;
localparam CONFIGURING_SD  = 2'b10;

localparam [15:0] MFG_ID      = 16'h144A; // 5194    - OAHR (Open Amiga Hardware Repository)
localparam [7:0]  RAM_PROD_ID = 8'd10;    // 5194/10 - SF2000, Memory Master (4M/8M)
localparam [7:0]  SD_PROD_ID  = 8'd11;    // 5194/11 - SF2000, SD card controller I/O device (64K)
localparam [15:0] SERIAL      = 16'd0;

// Configuration state
reg [1:0] configured_n;
reg [1:0] shutup_n;
reg [1:0] config_out_n;

// Synchronize AS_CPU_n to C7M domain
reg [2:0] as_cpu_n_sync;
wire as_cpu_n_stable = as_cpu_n_sync[2];
wire as_asserted = !as_cpu_n_stable;
wire as_rising = (as_cpu_n_sync[2:1] == 2'b01);
wire as_falling = (as_cpu_n_sync[2:1] == 2'b10);

// Synchronize DS_n
reg [2:0] ds_n_sync;
wire ds_n_stable = ds_n_sync[2];
wire ds_asserted = !ds_n_stable;

// Autoconfig space access detection
wire autoconfig_access = !CFGIN_n && CFGOUT_n && (A_HIGH == 8'hE8) && as_asserted;
wire autoconfig_read = autoconfig_read && RW_n && ds_asserted;
wire autoconfig_write = autoconfig_access && !RW_n && ds_asserted;

// Output enable for data bus
assign DATA_OE = autoconfig_access && RW_n && ds_asserted;

// Configuration status outputs
assign RAM_CONFIGURED_n = configured_n[RAM_CARD];
assign SD_CONFIGURED_n = configured_n[SD_CARD];
assign CFGOUT_n = |config_out_n;

// Synchronizers
always @(posedge C7M) begin
    if (!RESET_n) begin
        as_cpu_n_sync <= 3'b111;
        ds_n_sync <= 3'b111;
    end else begin
        as_cpu_n_sync <= {as_cpu_n_sync[1:0], AS_CPU_n};
        ds_n_sync <= {ds_n_sync[1:0], DS_n};
    end
end

// CFGOUT control - updates on AS rising edge
always @(posedge C7M) begin
    if (!RESET_n) begin
        config_out_n <= 2'b11;
    end else begin
        if (as_rising) begin
            config_out_n <= configured_n & shutup_n;
        end
    end
end

// Main autoconfiguration state machine
always @(posedge C7M) begin
    if (!RESET_n) begin
        configured_n <= 2'b11;
        shutup_n <= 2'b11;
        BASE_RAM <= 3'd0;
        BASE_SD <= 8'd0;
        DATA_OUT <= 4'hF;
    end else begin
        // Process autoconfig accesses
        if (autoconfig_access && ds_asserted) begin
            if (RW_n) begin
                // AutoConfig Read Sequence
                // All nibbles except 00,02,40,42 must be inverted
                
                case (A_LOW)
                    // Type and size (er_Type, er_Product, er_Flags, er_Reserved)
                    6'h00: begin
                        if (config_out_n == CONFIGURING_RAM) 
                            DATA_OUT <= 4'b1110;  // (00) 1110 Link into memory free list
                        if (config_out_n == CONFIGURING_SD)  
                            DATA_OUT <= 4'b1101;  // (00) 1101 Optional ROM vector valid
                    end
                    
                    6'h01: begin
                        if (config_out_n == CONFIGURING_RAM) 
                            DATA_OUT <= JP4 ? 4'b0000 : 4'b0111; // (02) 8 or 4 MB RAM
                        if (config_out_n == CONFIGURING_SD)  
                            DATA_OUT <= 4'b0001;                 // (02) 64KB
                    end
                    
                    // Product number
                    6'h02: begin
                        if (config_out_n == CONFIGURING_RAM) 
                            DATA_OUT <= ~RAM_PROD_ID[7:4];
                        if (config_out_n == CONFIGURING_SD)  
                            DATA_OUT <= ~SD_PROD_ID[7:4];
                    end
                    
                    6'h03: begin
                        if (config_out_n == CONFIGURING_RAM) 
                            DATA_OUT <= ~RAM_PROD_ID[3:0];
                        if (config_out_n == CONFIGURING_SD)  
                            DATA_OUT <= ~SD_PROD_ID[3:0];
                    end
                    
                    // Flags and reserved
                    6'h04: DATA_OUT <= ~4'b1100;  // (08) Can be shut up, prefers 8MB space
                    6'h05: DATA_OUT <= ~4'b0000;  // (0A) Reserved
                    
                    // Manufacturer ID
                    6'h08: DATA_OUT <= ~MFG_ID[15:12];
                    6'h09: DATA_OUT <= ~MFG_ID[11:8];
                    6'h0A: DATA_OUT <= ~MFG_ID[7:4];
                    6'h0B: DATA_OUT <= ~MFG_ID[3:0];
                    
                    // Serial number
                    6'h10: DATA_OUT <= ~SERIAL[15:12];
                    6'h11: DATA_OUT <= ~SERIAL[11:8];
                    6'h12: DATA_OUT <= ~SERIAL[7:4];
                    6'h13: DATA_OUT <= ~SERIAL[3:0];
                    
                    // ROM vector (for SD card only)
                    6'h17: begin
                        if (config_out_n == CONFIGURING_SD) 
                            DATA_OUT <= ~4'b0001;  // (2E) ROM vector low byte
                    end
                    
                    // Interrupt configuration
                    6'h20: DATA_OUT <= 4'd0;  // (40) No interrupts
                    6'h21: DATA_OUT <= 4'd0;  // (42) No interrupts
                    
                    default: DATA_OUT <= 4'hF;
                endcase
                
            end else begin
                // AutoConfig Write Sequence
                // Base address configuration
                
                case (A_LOW)
                    6'h24: begin  // (48) Base address high nibble
                        if (config_out_n == CONFIGURING_RAM) begin
                            BASE_RAM[7:5] <= D_IN[15:13];  // A23,A22,A21 (2MB chunks)
                            configured_n[RAM_CARD] <= 1'b0;
                        end
                        if (config_out_n == CONFIGURING_SD) begin
                            BASE_SD[7:4] <= D_IN;
                            configured_n[SD_CARD] <= 1'b0;
                        end
                    end
                    
                    6'h25: begin  // (4A) Base address low nibble (written first for SD)
                        if (config_out_n == CONFIGURING_SD) begin
                            BASE_SD[3:0] <= D_IN;
                        end
                    end
                    
                    6'h26: begin  // (4C) "Shut up" address
                        if (config_out_n == CONFIGURING_RAM) 
                            shutup_n[RAM_CARD] <= 1'b0;
                        if (config_out_n == CONFIGURING_SD) 
                            shutup_n[SD_CARD] <= 1'b0;
                    end
                endcase
            end
        end
    end
end

endmodule
