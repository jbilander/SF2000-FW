// ============================================================================
// fastram.v  --  Spitfire 2000: fast RAM decode and SRAM control
//
// Four IS61WV20488 (2M x 8) as two 4 MB banks:
//   bank 0 = U14 (even byte, D15-D8, UDS) + U15 (odd byte, D7-D0, LDS)
//   bank 1 = U16 (even)                   + U17 (odd)
//
// A21-A1 run from the connector straight to the chips and never enter the
// FPGA, so this module only decodes and drives the six control lines.
//
// TWO THINGS THAT LOOK WRONG BUT ARE NOT
//
//  1. The compare is a MAGNITUDE compare on A23-A20, not a prefix match.
//     Zorro II memory space starts at $200000, so no 4 MB slot inside it is
//     4 MB-aligned -- $200000-$5FFFFF spans A23:A20 = 2 through 5, which no
//     prefix covers. Base and size are both whole megabytes, so comparing the
//     top nibble is sufficient and costs about four LUTs. It also means any
//     1 MB-aligned base works, not just $200000 and $600000.
//
//  2. The SRAM still takes A21-A1 unmodified even though the window is not
//     aligned to it. Any contiguous 4 MB range covers every A21-A1 value
//     exactly once, so the mapping is a bijection -- rotated relative to the
//     bus address, which memory does not care about.
//
// The same decode serves both masters. When our CPU owns the bus, cyc comes
// from AS_CPU; when a Zorro master has been granted it, cyc comes from AS_MB
// and the master drives the address itself -- which reaches the SRAM pins
// through the FETs without the FPGA touching it. Only the control lines
// differ, so a DMA cycle is the same decode with a different strobe.
//
// CONTROL LINES ARE REGISTERED ON ASSERTION and released combinationally.
// The decode is a magnitude compare fed by signals that reach the FPGA by
// different routes -- AS_CPU direct, the address and strobes through the
// CBT FETs -- so a purely combinational OE/WE can in principle glitch. The
// SRAM commits a write in 8 ns, so a glitch that narrow is enough to corrupt
// a location. Requiring the decode to be stable across a clock edge means a
// glitch can no longer produce a write at all.
//
// The release stays combinational on purpose: a registered release would hold
// WE one clock past AS, into the next cycle, where the address has already
// changed -- writing the right data to the wrong place. Assert late, release
// early, and WE is only ever low strictly inside the window where the address
// is guaranteed stable.
//
// With 4 MB configured, bank 1 is simply never selected. The SRAMs have CE
// tied to GND, so their OE and WE being held inactive is the only thing
// keeping U16/U17 off the shared data bus -- and it works whether or not
// those two chips are actually fitted.
// ============================================================================

`default_nettype none

module fastram #(
    parameter RAM_WAIT = 0               // 1 adds a wait state, for margin
)(
    input  wire       clk,
    input  wire       cyc,               // a cycle we should answer: ours or a
                                         //   granted master's (see above)
    input  wire [3:0] a_hi,              // A23-A20
    input  wire       rw_n,
    input  wire       uds_n,
    input  wire       lds_n,

    input  wire       configured,        // autoconfig has placed us
    input  wire [3:0] base_nib,          // A23-A20 of the configured base
    input  wire       size_4mb,          // JP4 closed

    output wire       sel,               // this cycle is ours
    output wire       sel_addr,          // same, decoded from the address only
    output wire       ack,               // DTACK for it
    output wire       bank1,

    output wire       oe_bank0_n,
    output wire       oe_bank1_n,
    output wire       we_bank0_even_n,
    output wire       we_bank0_odd_n,
    output wire       we_bank1_even_n,
    output wire       we_bank1_odd_n
);

    // Offset from the configured base, in 1 MB units. A borrow out of bit 4
    // means the address is below the base.
    wire [4:0] nib_off = {1'b0, a_hi} - {1'b0, base_nib};
    wire       in_span = size_4mb ? (nib_off[3:2] == 2'b00)   // 4 units = 4 MB
                                  : (nib_off[3]   == 1'b0);   // 8 units = 8 MB

    // sel_addr deliberately excludes AS. main_top ORs it into AS_MB_n_OUT,
    // which AS_CPU_n already forces high when no cycle is running, so adding
    // AS here would only drag it through this comparator on the way to the
    // pin. The address is valid at S1, half a clock before AS falls at S2.
    assign sel_addr = configured & ~nib_off[4] & in_span;
    assign sel      = cyc & sel_addr;
    assign bank1    = ~size_4mb & nib_off[2];

    // Stable across a clock edge before anything is driven.
    reg  sel_r = 1'b0;
    reg  ack_r = 1'b0;
    always @(posedge clk) begin
        sel_r <= sel;
        ack_r <= sel;
    end

    wire act = sel & sel_r;
    wire rd  = act &  rw_n;
    wire wr  = act & ~rw_n;

    // Zero wait states is comfortable: 10 ns SRAM against a 560 ns cycle, and
    // the CPU latches read data about three clocks after AS falls. RAM_WAIT 1
    // is there if a machine ever proves marginal.
    assign ack = (RAM_WAIT == 0) ? sel : (sel & ack_r);

    // WE additionally needs the strobes, which a 68000 asserts at S4 on a
    // write, so the data is already valid by then.
    assign oe_bank0_n      = ~(rd & ~bank1);
    assign oe_bank1_n      = ~(rd &  bank1);
    assign we_bank0_even_n = ~(wr & ~bank1 & ~uds_n);
    assign we_bank0_odd_n  = ~(wr & ~bank1 & ~lds_n);
    assign we_bank1_even_n = ~(wr &  bank1 & ~uds_n);
    assign we_bank1_odd_n  = ~(wr &  bank1 & ~lds_n);

endmodule

`default_nettype wire
