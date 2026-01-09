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
HYBRID 6800 Bus Emulation - Best of Both Worlds!

From OLD m6800.v (for turbo speed):
✅ Async resets on posedge VPA_n and posedge AS_CPU_n
✅ Fast response (<10ns) for 40 MHz turbo

From NEW m6800.v (for SD boot reliability):
✅ Proper external E synchronization with edge detection
✅ E_OUT initialized at declaration
✅ Structured e_cnt handling

This should work at both 7 MHz and 40 MHz AND allow SD boot!
*/

//=============================================================================
// E-CLK Generation Counter (from old m6800.v)
//=============================================================================
reg [3:0] e_counter = 4'd5;

always @(negedge C7M) begin

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

//=============================================================================
// External E Synchronization (from new m6800.v - PROPER edge detection)
//=============================================================================
reg e_in_sync;
reg e_in_prev;
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
// VMA_n Logic with ASYNCHRONOUS reset (from old m6800.v)
// CRITICAL for turbo mode!
//=============================================================================
always @(negedge RESET_n or negedge C7M or posedge VPA_n) begin

    if (!RESET_n) begin
        VMA_n <= 1'b1;
    end else begin

        if (VPA_n) begin
            VMA_n <= 1'b1;  // ← ASYNC response - immediate!
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
// M6800_DTACK_n Logic with ASYNCHRONOUS reset (from old m6800.v)
// CRITICAL for turbo mode!
//=============================================================================
always @(negedge RESET_n or negedge C7M or posedge AS_CPU_n) begin

    if (!RESET_n) begin
        M6800_DTACK_n <= 1'b1;
    end else begin

        if (AS_CPU_n) begin
            M6800_DTACK_n <= 1'b1;  // ← ASYNC response - immediate!
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
