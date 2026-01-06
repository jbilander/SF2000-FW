`timescale 1ns / 1ps
`default_nettype none

module bus_arbiter(
    input wire C7M,
    input wire RESET_n,
    input wire JP2,
    
    // Internal 68000 arbitration
    input wire BG_n_IN,
    output reg BR_n_OUT,
    output reg BR_n_OE,
    
    // B2000 BOSS signal
    input wire BOSS_n_IN,
    output reg BOSS_n_OUT,
    output reg BOSS_n_OE,
    
    // 68SEC000 arbitration
    input wire BG_68SEC000_n,
    output reg BR_68SEC000_n,
    
    // External DMA arbitration (Zorro 3-way)
    input wire BR_n_IN,
    input wire BGACK_n,
    output reg BG_n_OUT,
    output reg BG_n_OE,
    
    // Status outputs
    output reg dma_en,
    output reg E_OE,
    output wire cpu_detected,
    output wire is_b2000
);

/*
Hybrid Bus Arbiter

Takes KEY working elements from user's proven firmware:
1. BR_68SEC000_n = 0 at reset (hold 68SEC000!)
2. Fast bootstrap check (not 100 clocks)
3. Condition: (BG_n_IN != 0 || JP2 != 0)
4. BOSS_n_IN HIGH = B2000

Keeps BETTER structure from previous attempt:
1. Synchronizers for metastability protection
2. Cleaner state machine
3. Clear mode separation
*/

//=============================================================================
// Synchronizers for Metastability Protection
//=============================================================================

reg [1:0] bg_n_in_sync;
reg [1:0] boss_n_in_sync;
reg [1:0] bg_68sec_sync;
reg [1:0] br_n_in_sync;
reg [1:0] bgack_sync;

always @(posedge C7M) begin
    if (!RESET_n) begin
        bg_n_in_sync <= 2'b11;
        boss_n_in_sync <= 2'b11;
        bg_68sec_sync <= 2'b11;
        br_n_in_sync <= 2'b11;
        bgack_sync <= 2'b11;
    end else begin
        bg_n_in_sync <= {bg_n_in_sync[0], BG_n_IN};
        boss_n_in_sync <= {boss_n_in_sync[0], BOSS_n_IN};
        bg_68sec_sync <= {bg_68sec_sync[0], BG_68SEC000_n};
        br_n_in_sync <= {br_n_in_sync[0], BR_n_IN};
        bgack_sync <= {bgack_sync[0], BGACK_n};
    end
end

wire bg_from_cpu = bg_n_in_sync[1];
wire boss_detected = boss_n_in_sync[1];
wire bg_from_68sec = !bg_68sec_sync[1];
wire br_from_ext = !br_n_in_sync[1];
wire bgack_from_ext = !bgack_sync[1];

//=============================================================================
// Bootstrap Detection (Fast - 3 clocks for synchronizers)
//=============================================================================

localparam BOOT_INIT = 2'b00;
localparam BOOT_WAIT_SYNC = 2'b01;
localparam BOOT_CHECK = 2'b10;
localparam BOOT_DONE = 2'b11;

reg [1:0] boot_state;
reg [1:0] sync_wait;
reg cpu_installed;
reg machine_is_b2000;

always @(posedge C7M) begin
    if (!RESET_n) begin
        boot_state <= BOOT_INIT;
        sync_wait <= 2'b00;
        cpu_installed <= 1'b0;
        machine_is_b2000 <= 1'b0;
    end else begin
        case (boot_state)
            BOOT_INIT: begin
                // Wait for synchronizers to settle
                sync_wait <= 2'b00;
                boot_state <= BOOT_WAIT_SYNC;
            end
            
            BOOT_WAIT_SYNC: begin
                // Wait 3 clocks for synchronizers
                if (sync_wait == 2'b11) begin
                    boot_state <= BOOT_CHECK;
                end else begin
                    sync_wait <= sync_wait + 2'b01;
                end
            end
            
            BOOT_CHECK: begin
                // Use working condition from proven firmware:
                // If no CPU response (BG_n_IN != 0) OR JP2 open (JP2 != 0)
                if (bg_from_cpu != 1'b0 || JP2 != 1'b0) begin
                    
                    // Check if CPU is actually present
                    cpu_installed <= (bg_from_cpu == 1'b0); // LOW = CPU present
                    
                    // Check machine type (BOSS_n_IN HIGH = B2000)
                    machine_is_b2000 <= boss_detected; // HIGH = B2000
                    
                end
                boot_state <= BOOT_DONE;
            end
            
            BOOT_DONE: begin
                // Stay here
            end
            
            default: boot_state <= BOOT_INIT;
        endcase
    end
end

assign cpu_detected = cpu_installed;
assign is_b2000 = machine_is_b2000;

//=============================================================================
// Bus Arbitration Control
//=============================================================================

always @(posedge C7M) begin
    if (!RESET_n) begin
        // CRITICAL: Hold BOTH CPUs at reset!
        BR_68SEC000_n <= 1'b0;  // Hold 68SEC000 (from working firmware!)
        BR_n_OUT <= 1'b0;       // Hold internal 68000
        BR_n_OE <= 1'b1;        // Enable BR output
        
        BOSS_n_OUT <= 1'b1;
        BOSS_n_OE <= 1'b0;
        
        BG_n_OUT <= 1'b1;
        BG_n_OE <= 1'b0;
        
        dma_en <= 1'b0;
        E_OE <= 1'b0;
        
    end else begin
        
        if (boot_state == BOOT_CHECK) begin
            // Configuration phase - happens in BOOT_CHECK state
            
            // Release 68SEC000 immediately (from working firmware)
            BR_68SEC000_n <= 1'b1;
            
            // Set E_OE based on JP2
            E_OE <= !JP2;
            
            if (bg_from_cpu != 1'b0 || JP2 != 1'b0) begin
                
                if (boss_detected) begin
                    // Mode 1: B2000 (BOSS_n_IN = HIGH)
                    BOSS_n_OUT <= 1'b0;     // Assert BOSS
                    BOSS_n_OE <= 1'b1;      // Enable BOSS
                    BR_n_OE <= 1'b0;        // Stop driving BR to internal CPU
                    dma_en <= 1'b1;         // Enable DMA
                    
                end else begin
                    // Mode 2/3: A500 or no CPU
                    BR_n_OE <= !bg_from_cpu;     // Drive BR only if CPU present
                    dma_en <= bg_from_cpu;       // Enable DMA only if no CPU
                end
            end
            
        end else if (boot_state == BOOT_DONE) begin
            // After bootstrap - handle DMA arbitration
            
            if (dma_en) begin
                // Mode 1 or Mode 3: DMA enabled
                BR_n_OE <= 1'b0;                           // Don't drive BR to internal CPU
                BR_68SEC000_n <= BR_n_IN & BGACK_n;        // 3-to-2 mapping (your elegant formula!)
                
                BG_n_OE <= 1'b1;                           // Drive BG to external DMA
                BG_n_OUT <= BG_68SEC000_n;                 // Pass through 68SEC000's BG
                
            end else begin
                // Mode 2: A500 with CPU, no DMA
                // Keep BR asserted to internal CPU, 68SEC000 runs system
            end
        end
    end
end

endmodule

