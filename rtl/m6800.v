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
Synchronous 6800 Bus Emulation - Phase 2D (1-stage sync)

Reduced from 2-stage to 1-stage synchronizers for fastest response.
This is necessary for fast peripherals like SDBox-v3 when listening to external E.

At 7MHz:
- 1-stage delay = ~140ns (vs 280ns for 2-stage)
- Minimal metastability protection
- Fast enough for SDBox-v3 and other fast 6800 peripherals

Trade-off:
- Reduced metastability protection vs 2-stage
- But E_IN from internal CPU is a slow, clean signal (~709kHz)
- At 7MHz, even 1 stage provides reasonable protection for such slow signals
- Critical for SDBox-v3 to work when listening to external E
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
// External E Synchronization (1-stage)
//=============================================================================
reg e_in_sync;           // Single stage - just one flip-flop
reg e_in_prev;           // Previous value for edge detection
reg [3:0] e_cnt = 4'd0;
reg e_sync_reset = 1'b0;

always @(negedge C7M) begin
    if (!RESET_n) begin
        e_in_sync <= 1'b1;
        e_in_prev <= 1'b1;
        e_cnt <= 4'd0;
        e_sync_reset <= 1'b0;
    end else begin
        // 1-stage synchronizer for E_IN
        e_in_prev <= e_in_sync;
        e_in_sync <= E_IN;
        
        // Detect falling edge (1→0)
        if (e_in_prev == 1'b1 && e_in_sync == 1'b0) begin
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
// VPA_n Synchronization (1-stage)
//=============================================================================
reg vpa_n_sync;

always @(negedge C7M) begin
    if (!RESET_n)
        vpa_n_sync <= 1'b1;
    else
        vpa_n_sync <= VPA_n;
end

wire vpa_n_s = vpa_n_sync;

//=============================================================================
// AS_CPU_n Synchronization (1-stage)
//=============================================================================
reg as_cpu_n_sync;

always @(negedge C7M) begin
    if (!RESET_n)
        as_cpu_n_sync <= 1'b1;
    else
        as_cpu_n_sync <= AS_CPU_n;
end

wire as_cpu_n_s = as_cpu_n_sync;

//=============================================================================
// VMA_n Logic (same as Phase 2C, just with 1-stage sync)
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
// M6800_DTACK_n Logic (same as Phase 2C, just with 1-stage sync)
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
