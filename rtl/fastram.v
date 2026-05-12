`timescale 1ns / 1ps
`default_nettype none

module fastram(
    input wire CLKCPU,
    input wire BGACK_n,
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

7 MHz: Combinatorial OE/WE (fast, DMA-compatible).
Turbo: Registered OE/WE on negedge for longer write pulses.
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

// Filter address glitches during external DMA.
// Address transitions can transiently match the SRAM range, causing
// OE/WE to glitch. Requires 1-clock address stability before enabling.
reg dma_ram_valid;
always @(posedge CLKCPU) begin
    if (AS_n)
        dma_ram_valid <= 1'b0;
    else
        dma_ram_valid <= RAM_ACCESS;
end

// Gate for combinatorial OE/WE:
// If DMA (!BGACK_n), requires 1-clock stability to prevent address glitches.
// If CPU (BGACK_n), bypasses filter for 0-wait-state performance.
wire safe_to_enable = BGACK_n ? 1'b1 : dma_ram_valid;

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
always @(posedge CLKCPU) begin
    if (AS_n) begin
        OE_BANK0_n_reg <= 1'b1;
        OE_BANK1_n_reg <= 1'b1;
    end else begin
        OE_BANK0_n_reg <= !(first_4MB_access && RW_n && !DS_n);
        OE_BANK1_n_reg <= !(second_4MB_access && RW_n && !DS_n);
    end
end

// WE registered on negedge (for maximum write time)
always @(negedge CLKCPU) begin
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

wire OE_BANK0_n_comb = first_4MB_access && safe_to_enable && RW_n && !DS_n ? 1'b0 : 1'b1;
wire OE_BANK1_n_comb = second_4MB_access && safe_to_enable && RW_n && !DS_n ? 1'b0 : 1'b1;

wire WE_BANK0_ODD_n_comb = first_4MB_access && safe_to_enable && !RW_n && !LDS_n ? 1'b0 : 1'b1;
wire WE_BANK1_ODD_n_comb = second_4MB_access && safe_to_enable && !RW_n && !LDS_n ? 1'b0 : 1'b1;

wire WE_BANK0_EVEN_n_comb = first_4MB_access && safe_to_enable && !RW_n && !UDS_n ? 1'b0 : 1'b1;
wire WE_BANK1_EVEN_n_comb = second_4MB_access && safe_to_enable && !RW_n && !UDS_n ? 1'b0 : 1'b1;

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

reg [3:0] wait_counter;
// DMA: 6 wait states for expansion card stability. CPU: 0 wait states.
wire [3:0] wait_states = (!BGACK_n) ? 4'd6 : 4'd0;

always @(posedge CLKCPU) begin

    if (AS_n) begin
        DTACK_n <= 1'b1;
        wait_counter <= 4'd0;
    end else begin

        if (RAM_ACCESS) begin
            if (wait_counter < wait_states) begin
                DTACK_n <= 1'b1;
                wait_counter <= wait_counter + 4'd1;
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
