`timescale 1ns / 1ps
`default_nettype none

module fastram(
    input wire CLKCPU,
    input wire CPU_SPEED_SWITCH,
    input wire [23:21] A,
    input wire JP4,
    input wire RW_n,
    input wire UDS_n,
    input wire LDS_n,
    input wire AS_CPU_n,
    input wire AS_n,
    input wire DS_n,
    input wire [7:5] BASE_RAM,
    input wire RAM_CONFIGURED_n,
    output reg OE_BANK0_n = 1'b1,
    output reg OE_BANK1_n = 1'b1,
    output reg WE_BANK0_ODD_n = 1'b1,
    output reg WE_BANK1_ODD_n = 1'b1,
    output reg WE_BANK0_EVEN_n = 1'b1,
    output reg WE_BANK1_EVEN_n = 1'b1,
    output wire RAM_ACCESS,
    output reg DTACK_n = 1'b1
);

/*
Fast RAM Controller - NEGEDGE WE for Maximum Write Time

This version uses NEGEDGE for WE assertion, giving maximum write pulse width.

Why negedge for writes:
1. At 40 MHz, cycle = 25ns, half-cycle = 12.5ns
2. Negedge WE asserts at t=12.5ns into cycle
3. Posedge DTACK asserts later (after wait states)
4. Gives WE maximum time before DTACK ends the cycle
5. Results in longer, more reliable write pulses

OE still uses posedge for reads (less critical).
*/

/*
Amiga memory map Z2-space:

              A 23  22  21
200000-3FFFFF    0   0   1  // 2MB
400000-5FFFFF    0   1   0  // 2MB
600000-7FFFFF    0   1   1  // 2MB
800000-9FFFFF    1   0   0  // 2MB
*/

wire first_4MB_access  = !AS_n && !RAM_CONFIGURED_n && ( (A == BASE_RAM) || (A == (BASE_RAM + 3'b001)) );
wire second_4MB_access = !AS_n && !RAM_CONFIGURED_n && JP4 && ( (A == (BASE_RAM + 3'b010)) || (A == (BASE_RAM + 3'b011)) );

assign RAM_ACCESS = JP4 ? (first_4MB_access || second_4MB_access) : first_4MB_access;

//=============================================================================
// OE Signals - Registered on posedge (reads)
//=============================================================================

always @(posedge CLKCPU or posedge AS_n) begin

    if (AS_n) begin
        OE_BANK0_n <= 1'b1;
        OE_BANK1_n <= 1'b1;
    end else begin
        OE_BANK0_n <= !(first_4MB_access && RW_n && !DS_n);
        OE_BANK1_n <= !(second_4MB_access && RW_n && !DS_n);
    end
    
end

//=============================================================================
// WE Signals - Registered on NEGEDGE for maximum write time (writes)
//=============================================================================

always @(negedge CLKCPU or posedge AS_n) begin

    if (AS_n) begin
        WE_BANK0_ODD_n <= 1'b1;
        WE_BANK1_ODD_n <= 1'b1;
        WE_BANK0_EVEN_n <= 1'b1;
        WE_BANK1_EVEN_n <= 1'b1;
    end else begin
        WE_BANK0_ODD_n <= !(first_4MB_access && !RW_n && !LDS_n);
        WE_BANK1_ODD_n <= !(second_4MB_access && !RW_n && !LDS_n);
        WE_BANK0_EVEN_n <= !(first_4MB_access && !RW_n && !UDS_n);
        WE_BANK1_EVEN_n <= !(second_4MB_access && !RW_n && !UDS_n);
    end
    
end

//=============================================================================
// DTACK Generation - Use AS_n for async reset (DMA-aware!)
//=============================================================================

reg [2:0] wait_counter;
wire [2:0] wait_states = CPU_SPEED_SWITCH ? 3'd2 : 3'd0;

// Use AS_n for async reset - DMA-aware (works for both CPU and DMA cycles)
always @(posedge CLKCPU or posedge AS_n) begin

    if (AS_n) begin
        DTACK_n <= 1'b1;
        wait_counter <= 3'd0;
    end else begin

        if (RAM_ACCESS) begin
            if (wait_counter < wait_states) begin
                DTACK_n <= 1'b1;
                wait_counter <= wait_counter + 3'd1;
            end else begin
                DTACK_n <= 1'b0;
            end
        end else begin
            DTACK_n <= 1'b1;
            wait_counter <= 3'd0;
        end

    end
end

endmodule
