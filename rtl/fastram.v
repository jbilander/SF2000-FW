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
    output wire OE_BANK0_n,
    output wire OE_BANK1_n,
    output wire WE_BANK0_ODD_n,
    output wire WE_BANK1_ODD_n,
    output wire WE_BANK0_EVEN_n,
    output wire WE_BANK1_EVEN_n,
    output wire RAM_ACCESS,
    output reg DTACK_n = 1'b1
);

/*
Fast RAM Controller - Conditional Registered OE/WE

KEY INSIGHT:
- At 7 MHz: Combinatorial OE/WE works fine (always worked!)
- At turbo: Need registered OE/WE for longer write pulses (stable writes)

Solution: Use registered OE/WE only at turbo speeds!

This way:
- 7 MHz: Fast, combinatorial (DMA/HCII+8 works) ✅
- Turbo: Registered negedge WE (stable, reliable writes) ✅
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
// Registered OE/WE Signals (for turbo mode)
//=============================================================================

reg OE_BANK0_n_reg = 1'b1;
reg OE_BANK1_n_reg = 1'b1;
reg WE_BANK0_ODD_n_reg = 1'b1;
reg WE_BANK1_ODD_n_reg = 1'b1;
reg WE_BANK0_EVEN_n_reg = 1'b1;
reg WE_BANK1_EVEN_n_reg = 1'b1;

// OE registered on posedge
always @(posedge CLKCPU or posedge AS_n) begin
    if (AS_n) begin
        OE_BANK0_n_reg <= 1'b1;
        OE_BANK1_n_reg <= 1'b1;
    end else begin
        OE_BANK0_n_reg <= !(first_4MB_access && RW_n && !DS_n);
        OE_BANK1_n_reg <= !(second_4MB_access && RW_n && !DS_n);
    end
end

// WE registered on negedge (for maximum write time)
always @(negedge CLKCPU or posedge AS_n) begin
    if (AS_n) begin
        WE_BANK0_ODD_n_reg <= 1'b1;
        WE_BANK1_ODD_n_reg <= 1'b1;
        WE_BANK0_EVEN_n_reg <= 1'b1;
        WE_BANK1_EVEN_n_reg <= 1'b1;
    end else begin
        WE_BANK0_ODD_n_reg <= !(first_4MB_access && !RW_n && !LDS_n);
        WE_BANK1_ODD_n_reg <= !(second_4MB_access && !RW_n && !LDS_n);
        WE_BANK0_EVEN_n_reg <= !(first_4MB_access && !RW_n && !UDS_n);
        WE_BANK1_EVEN_n_reg <= !(second_4MB_access && !RW_n && !UDS_n);
    end
end

//=============================================================================
// Combinatorial OE/WE Signals (for 7 MHz mode)
//=============================================================================

wire OE_BANK0_n_comb = first_4MB_access && RW_n && !DS_n ? 1'b0 : 1'b1;
wire OE_BANK1_n_comb = second_4MB_access && RW_n && !DS_n ? 1'b0 : 1'b1;

wire WE_BANK0_ODD_n_comb = first_4MB_access && !RW_n && !LDS_n ? 1'b0 : 1'b1;
wire WE_BANK1_ODD_n_comb = second_4MB_access && !RW_n && !LDS_n ? 1'b0 : 1'b1;

wire WE_BANK0_EVEN_n_comb = first_4MB_access && !RW_n && !UDS_n ? 1'b0 : 1'b1;
wire WE_BANK1_EVEN_n_comb = second_4MB_access && !RW_n && !UDS_n ? 1'b0 : 1'b1;

//=============================================================================
// Output Mux: Registered at turbo, Combinatorial at 7 MHz
//=============================================================================

assign OE_BANK0_n = CPU_SPEED_SWITCH ? OE_BANK0_n_reg : OE_BANK0_n_comb;
assign OE_BANK1_n = CPU_SPEED_SWITCH ? OE_BANK1_n_reg : OE_BANK1_n_comb;

assign WE_BANK0_ODD_n = CPU_SPEED_SWITCH ? WE_BANK0_ODD_n_reg : WE_BANK0_ODD_n_comb;
assign WE_BANK1_ODD_n = CPU_SPEED_SWITCH ? WE_BANK1_ODD_n_reg : WE_BANK1_ODD_n_comb;

assign WE_BANK0_EVEN_n = CPU_SPEED_SWITCH ? WE_BANK0_EVEN_n_reg : WE_BANK0_EVEN_n_comb;
assign WE_BANK1_EVEN_n = CPU_SPEED_SWITCH ? WE_BANK1_EVEN_n_reg : WE_BANK1_EVEN_n_comb;

//=============================================================================
// DTACK Generation
//=============================================================================

reg [2:0] wait_counter;
wire [2:0] wait_states = CPU_SPEED_SWITCH ? 3'd0 : 3'd0;

always @(posedge CLKCPU or posedge AS_CPU_n) begin

    if (AS_CPU_n) begin
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
