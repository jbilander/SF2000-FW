`timescale 1ns / 1ps

module fastram(
    input wire CLKCPU,
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

assign OE_BANK0_n = first_4MB_access && RW_n && !DS_n ? 1'b0 : 1'b1;
assign OE_BANK1_n = second_4MB_access && RW_n && !DS_n ? 1'b0 : 1'b1;

assign WE_BANK0_ODD_n = first_4MB_access && !RW_n && !LDS_n ? 1'b0 : 1'b1;
assign WE_BANK1_ODD_n = second_4MB_access && !RW_n && !LDS_n ? 1'b0 : 1'b1;

assign WE_BANK0_EVEN_n = first_4MB_access && !RW_n && !UDS_n ? 1'b0 : 1'b1;
assign WE_BANK1_EVEN_n = second_4MB_access && !RW_n && !UDS_n ? 1'b0 : 1'b1;

always @(posedge CLKCPU or posedge AS_CPU_n) begin

    if (AS_CPU_n) begin

        DTACK_n <= 1'b1;

    end else begin

        DTACK_n <= !RAM_ACCESS;

    end
end

endmodule
