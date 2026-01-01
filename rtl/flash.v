`timescale 1ns / 1ps

module flash (
    input wire [23:16] A,
    input wire AS_CPU_n,
    input wire CLKCPU,
    input wire RESET_n,
    input wire DS_n,
    input wire RW_n,
    input wire JP3,
    input wire CPU_SPEED_SWITCH,
    output wire FLASH_ACCESS,
    output wire FLASH_A19,
    output reg FLASH_WE_n = 1'b1,
    output reg FLASH_OE_n = 1'b1,
    output reg DTACK_n = 1'b1
);

// ROM overlay and mapping control
reg OVL;
reg maprom_enabled;

// Wait state configuration
reg [2:0] wait_states;
reg [2:0] wait_counter;

// Synchronize AS_CPU_n to CLKCPU domain
reg [2:0] as_cpu_n_sync;
wire as_cpu_n_sync_out = as_cpu_n_sync[2];
wire as_cpu_n_rising = (as_cpu_n_sync[2:1] == 2'b01);
wire as_cpu_n_falling = (as_cpu_n_sync[2:1] == 2'b10);

always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        as_cpu_n_sync <= 3'b111;
    end else begin
        as_cpu_n_sync <= {as_cpu_n_sync[1:0], AS_CPU_n};
    end
end

// Configure wait states based on CPU speed
// Flash is slow, needs wait states in turbo mode
always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        wait_states <= 3'd0;
    end else begin
        wait_states <= CPU_SPEED_SWITCH ? 3'd3 : 3'd0;
    end
end

// Flash address decode
// Force bank 1 (A19=1) for early boot overlay when OVL is set
assign FLASH_A19 = A[19] || OVL;

// Determine if this is a flash access
assign FLASH_ACCESS = (A[23:20] == 4'hA     && !maprom_enabled)              || // $A00000-AFFFFF
                      (A[23:20] == 4'b0     &&  maprom_enabled && OVL)       || // $000000-0FFFFF - Early boot overlay
                      (A[23:19] == 5'b11111 &&  maprom_enabled)              || // $F80000-FFFFFF
                      (A[23:19] == 5'b11100 &&  maprom_enabled);                // $E00000-E7FFFF

// DTACK state machine
localparam DTACK_IDLE = 2'b00;
localparam DTACK_WAIT = 2'b01;
localparam DTACK_ASSERTED = 2'b10;

reg [1:0] dtack_state;

always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        DTACK_n <= 1'b1;
        wait_counter <= 3'd0;
        dtack_state <= DTACK_IDLE;
    end else begin
        case (dtack_state)
            DTACK_IDLE: begin
                DTACK_n <= 1'b1;
                wait_counter <= 3'd0;
                if (!as_cpu_n_sync_out && FLASH_ACCESS) begin
                    dtack_state <= DTACK_WAIT;
                end
            end
            
            DTACK_WAIT: begin
                if (wait_counter >= wait_states) begin
                    DTACK_n <= 1'b0;
                    dtack_state <= DTACK_ASSERTED;
                end else begin
                    wait_counter <= wait_counter + 3'd1;
                    DTACK_n <= 1'b1;
                end
            end
            
            DTACK_ASSERTED: begin
                DTACK_n <= 1'b0;
                if (as_cpu_n_rising) begin
                    DTACK_n <= 1'b1;
                    dtack_state <= DTACK_IDLE;
                end
            end
            
            default: begin
                dtack_state <= DTACK_IDLE;
                DTACK_n <= 1'b1;
            end
        endcase
        
        // Override: Always deassert DTACK when AS goes high or no flash access
        if (as_cpu_n_rising || !FLASH_ACCESS) begin
            DTACK_n <= 1'b1;
            wait_counter <= 3'd0;
            dtack_state <= DTACK_IDLE;
        end
    end
end

// ROM overlay and flash control logic
always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        FLASH_OE_n <= 1'b1;
        FLASH_WE_n <= 1'b1;
        OVL <= 1'b1;
        maprom_enabled <= ~JP3; // Enable flash overlay based on jumper
    end else begin
        // Disable ROM overlay after write to CIA-A ($BFE001)
        // This is the standard Amiga overlay disable mechanism
        if (A[23:16] == 8'hBF && !as_cpu_n_sync_out && !RW_n && !DS_n) begin
            OVL <= 1'b0;
        end
        
        // Flash output enable (for reads)
        if (FLASH_ACCESS && !as_cpu_n_sync_out) begin
            FLASH_OE_n <= !RW_n;  // OE active when reading
        end else begin
            FLASH_OE_n <= 1'b1;
        end
        
        // Flash write enable (for writes)
        // Only allow writes when maprom is disabled (protect Kickstart)
        if (FLASH_ACCESS && !as_cpu_n_sync_out) begin
            FLASH_WE_n <= RW_n || DS_n || maprom_enabled;
        end else begin
            FLASH_WE_n <= 1'b1;
        end
    end
end

endmodule
