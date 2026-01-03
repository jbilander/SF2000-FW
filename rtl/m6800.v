`timescale 1ns / 1ps
`default_nettype none

module m6800(
    input wire JP2,
    input wire C7M,
    input wire RESET_n,
    input wire VPA_n,
    input wire CPUSPACE,
    input wire AS_CPU_n,
    input wire E_IN,
    output reg E_OUT = 1'b1,
    output reg VMA_n = 1'b1,
    output reg M6800_DTACK_n = 1'b1
);

/*
Synchronous 6800 Bus Emulation - Phase 2C (2-stage sync)

Reduced from 3-stage to 2-stage synchronizers for faster response.
This is necessary for time-critical peripherals like floppy disk controller.

At 7MHz:
- 2-stage delay = ~280ns (vs 420ns for 3-stage)
- Still provides metastability protection
- Fast enough for floppy disk timing requirements

Trade-off:
- Slightly less metastability protection than 3-stage
- But at 7MHz, 2 stages is still very safe
- Critical for floppy disk to work
*/

//=============================================================================
// E-CLK Generation Counter (unchanged)
//=============================================================================
reg [3:0] e_counter = 4'd5;

always @(negedge C7M) begin
    if (!RESET_n) begin
        e_counter <= 4'd5;
        E_OUT <= 1'b1;
    end else begin
        if (e_counter == 4'd5) begin
            E_OUT <= 1'b1;
        end
        
        if (e_counter == 4'd9) begin
            e_counter <= 4'd0;
            E_OUT <= 1'b0;
        end else begin
            e_counter <= e_counter + 4'd1;
        end
    end
end

//=============================================================================
// External E Synchronization (2-stage)
//=============================================================================
reg [1:0] e_in_sync;     // Changed from [2:0] to [1:0]
reg [3:0] e_cnt = 4'd0;
reg e_sync_reset = 1'b0;

always @(negedge C7M) begin
    if (!RESET_n) begin
        e_in_sync <= 2'b11;  // 2 stages
        e_cnt <= 4'd0;
        e_sync_reset <= 1'b0;
    end else begin
        // 2-stage synchronizer for E_IN
        e_in_sync <= {e_in_sync[0], E_IN};
        
        // Detect falling edge (1→0)
        if (e_in_sync[1:0] == 2'b10) begin
            e_sync_reset <= 1'b1;
        end
        
        // Counter logic
        if (e_sync_reset) begin
            e_cnt <= 4'd0;
            e_sync_reset <= 1'b0;
        end else begin
            if (e_cnt == 4'd9) begin
                e_cnt <= 4'd0;
            end else begin
                e_cnt <= e_cnt + 4'd1;
            end
        end
    end
end

//=============================================================================
// VPA_n Synchronization (2-stage)
//=============================================================================
reg [1:0] vpa_n_sync;    // Changed from [2:0] to [1:0]

always @(negedge C7M) begin
    if (!RESET_n)
        vpa_n_sync <= 2'b11;
    else
        vpa_n_sync <= {vpa_n_sync[0], VPA_n};
end

wire vpa_n_s = vpa_n_sync[1];  // Use bit [1] instead of [2]

//=============================================================================
// AS_CPU_n Synchronization (2-stage)
//=============================================================================
reg [1:0] as_cpu_n_sync; // Changed from [2:0] to [1:0]

always @(negedge C7M) begin
    if (!RESET_n)
        as_cpu_n_sync <= 2'b11;
    else
        as_cpu_n_sync <= {as_cpu_n_sync[0], AS_CPU_n};
end

wire as_cpu_n_s = as_cpu_n_sync[1];  // Use bit [1] instead of [2]

//=============================================================================
// VMA_n Logic (same as Phase 2B, just with 2-stage sync)
//=============================================================================
always @(negedge C7M) begin
    if (!RESET_n) begin
        VMA_n <= 1'b1;
    end else begin
        if (vpa_n_s) begin
            VMA_n <= 1'b1;
        end else begin
            if (!JP2) begin
                // Internal E generation
                if (e_counter == 4'd3) begin
                    VMA_n <= CPUSPACE;
                end
            end else begin
                // External E
                if (e_cnt == 4'd3) begin
                    VMA_n <= CPUSPACE;
                end
            end
        end
    end
end

//=============================================================================
// M6800_DTACK_n Logic (same as Phase 2B, just with 2-stage sync)
//=============================================================================
always @(negedge C7M) begin
    if (!RESET_n) begin
        M6800_DTACK_n <= 1'b1;
    end else begin
        if (as_cpu_n_s) begin
            M6800_DTACK_n <= 1'b1;
        end else begin
            if (!JP2) begin
                // Internal E generation
                if (e_counter == 4'd9) begin
                    M6800_DTACK_n <= VMA_n;
                end
            end else begin
                // External E
                if (e_cnt == 4'd9) begin
                    M6800_DTACK_n <= VMA_n;
                end
            end
        end
    end
end

endmodule

