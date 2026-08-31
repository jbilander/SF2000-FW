// ============================================================================
// bus_arbiter.v  --  Spitfire 2000: bus ownership, reset and machine detection
//
// Takes the bus from whatever CPU already has it, holds it, and gives it back
// cleanly across a reset.
//
//   B2000            assert BOSS once granted; Buster holds the onboard 68000
//                    off, so BR can be released.
//   A500 / A2000-A   no BOSS, so hold BR asserted forever and never assert
//                    BGACK -- Gary inserts an extra wait state if it sees
//                    BGACK, and two-wire arbitration keeps the 68000 off the
//                    bus for as long as BR is held.
//
// Which machine we are in is detected from BOSS: a B2000 has a 4k7 pull-up on
// it, and pin 20 is N.C. on every A500 and A500+, so a weak pulldown in the
// FPGA reads low there. Sampled once, after the settle delay.
//
// WARM RESET. RESET is a single shared open-drain net running to both CPUs,
// so Ctrl-A-A resets the socketed 68000 too and it will try to drive the bus
// again. There is no way to hold one CPU in reset and not the other. Instead,
// dropping bus_owned does four things at once: asserts /BR to our own CPU,
// tri-states AS_MB and VMA, and makes main_top stop forwarding DTACK -- so our
// CPU stalls in wait states rather than running into a bus it does not own.
// Neither CPU can drive during the window.
//
// GRANTING THE BUS TO A ZORRO MASTER. Once we are the CPU, /BR reverses
// direction: it stops being our request and becomes Buster's, or an A2091's.
// We can only see that if we are not holding it low ourselves, which is why
// BR is released on a B2000 (BOSS does the job) and on the arbitration
// timeout, which is conclusive evidence the socket is empty -- a real 68000
// grants in microseconds, so 20 ms means there is nobody there. On an A500
// with the socket populated we must hold BR forever, so DMA is impossible;
// arbiter stays low and we simply never grant.
//
// The handover order matters. Our own CPU is asked to leave FIRST, while
// bus_owned is still 1 so its current cycle can still be DTACKed to
// completion -- dropping bus_owned first would stop DTACK forwarding and
// deadlock a CPU that cannot finish the cycle it is in.
//
// ST_REL exists because RESET is the same net we have been holding low: it
// still reads low for a while after we let go, two clocks of synchroniser at
// minimum and longer while the line rises, or indefinitely if Gary is still
// asserting its own power-on reset. Going straight to ST_RUN saw that as "we
// lost the bus" and tore a cycle down under a CPU that had just started
// fetching.
// ============================================================================

`default_nettype none

module bus_arbiter #(
    parameter integer T_SETTLE = 71_591,      // 10 ms  @ 7.159 MHz
    parameter integer T_ARB_TO = 143_182,     // 20 ms
    parameter integer T_RESET  = 1_073_864    // 150 ms (68SEC000 wants 100)
)(
    input  wire clk,
    input  wire reset_q,          // synchronised RESET_n: high = released
    input  wire bg_q,             // synchronised BG_n from the slot
    input  wire br_q,             // synchronised BR_n: a master wants the bus
    input  wire bgack_q,          // synchronised BGACK_n: a master has it
    input  wire bg68_q,           // synchronised BG_n from our own 68SEC000
    input  wire boss_n_in,        // raw BOSS pin, sampled after settle
    input  wire e_ready,          // m6800 has an E source

    output wire bus_owned,        // we own the motherboard bus
    output wire dma_active,       // a Zorro master has been handed the bus
    output wire dma_capable,      // BR is free, so we can act as arbiter

    // pins, all open drain: drive 0 or release, never drive 1
    output wire reset_n_out,
    output wire reset_n_oe,
    output wire hlt_n_out,
    output wire hlt_n_oe,
    output wire br_n_out,
    output wire br_n_oe,
    output wire bg_n_out,
    output wire bg_n_oe,
    output wire boss_n_out,
    output wire boss_n_oe,
    output wire br_68sec000_n
);

    localparam ST_SETTLE  = 4'd0,  ST_REQ     = 4'd1,  ST_TAKE   = 4'd2,
               ST_HOLD    = 4'd3,  ST_REL     = 4'd4,  ST_RUN    = 4'd5,
               ST_LOST    = 4'd6,  ST_REACQ   = 4'd7,
               ST_DMA_REQ = 4'd8,  ST_DMA_GNT = 4'd9,
               ST_DMA_ACT = 4'd10, ST_DMA_END = 4'd11;

    reg  [3:0] st       = ST_SETTLE;
    reg [21:0] cnt      = 22'd0;
    reg  [7:0] dcnt     = 8'd0;    // short timeout for the handover
    reg  [2:0] brq_cnt  = 3'd0;    // /BR must be held, not glitched
    reg        b2000    = 1'b0;
    reg        bg_seen  = 1'b0;    // a real CPU granted: the socket is populated
    reg        br_a     = 1'b0;
    reg        boss_a   = 1'b0;
    reg        bg_a     = 1'b0;    // granting to a Zorro master
    reg        arbiter  = 1'b0;    // BR is free, BG is ours to drive
    reg        cpu_off  = 1'b0;    // asking our own 68SEC000 to leave
    reg        owned    = 1'b0;
    reg        rst_hold = 1'b1;

    // A real master holds /BR until it is granted, so require it low for four
    // consecutive clocks. Cheap insurance: /BR is a wired-OR line with only a
    // weak pull-up holding it, and on an A500 with the socket empty there is
    // no 68000 on the other end of it at all. A single glitch must not be able
    // to hand the bus to a master that is not there.
    always @(posedge clk)
        if (br_q) brq_cnt <= 3'd0;
        else if (brq_cnt != 3'd4) brq_cnt <= brq_cnt + 3'd1;

    wire br_held = (brq_cnt == 3'd4);

    always @(posedge clk) begin
        cnt <= cnt + 22'd1;
        case (st)

        ST_SETTLE:                          // rails, pull-ups, JP1's ~2 ms RC
            if (cnt >= T_SETTLE[21:0]) begin
                b2000 <= boss_n_in;         // 4k7 on a B2000 beats our pulldown
                st    <= ST_REQ;
            end

        ST_REQ: begin                       // ask the socketed CPU for the bus
            br_a <= 1'b1;
            if (!bg_q) begin bg_seen <= 1'b1; st <= ST_TAKE; end
            else if (cnt >= T_ARB_TO[21:0])  st <= ST_TAKE;
        end

        ST_TAKE: begin
            owned <= 1'b1;
            if (b2000) begin
                boss_a  <= 1'b1;            // Buster holds the onboard CPU off
                br_a    <= 1'b0;            // BR now means "someone wants it from us"
                arbiter <= 1'b1;
            end else if (!bg_seen) begin
                br_a    <= 1'b0;            // timed out: the socket is empty, so
                arbiter <= 1'b1;            // holding BR serves no purpose
            end                             // else: socket populated, hold BR, no DMA
            st <= ST_HOLD;
        end

        ST_HOLD:
            if (cnt >= T_RESET[21:0] && e_ready) begin
                rst_hold <= 1'b0;
                st       <= ST_REL;
            end

        ST_REL:                             // wait for the line to actually rise
            if (reset_q) st <= ST_RUN;

        ST_RUN:
            if (!reset_q) begin
                owned <= 1'b0;
                cnt   <= 22'd0;
                st    <= ST_LOST;
            end else if (arbiter && br_held) begin
                cpu_off <= 1'b1;            // our CPU leaves first, while we
                dcnt    <= 8'd0;            // still own the bus so it can finish
                st      <= ST_DMA_REQ;      // the cycle it is in
            end

        ST_DMA_REQ:
            if (!reset_q)                   st <= ST_LOST;
            else if (!bg68_q || &dcnt) begin
                owned <= 1'b0;              // now it is safe to let go
                bg_a  <= 1'b1;
                dcnt  <= 8'd0;
                st    <= ST_DMA_GNT;
            end else
                dcnt <= dcnt + 8'd1;

        // Waiting for the master to take the bus. Never wait here forever: if
        // BGACK does not arrive the CPU would sit parked off the bus and the
        // machine would freeze until a keyboard reset. Time out and take it
        // back instead.
        ST_DMA_GNT:
            if (!reset_q)      st <= ST_LOST;
            else if (!bgack_q) begin
                bg_a <= 1'b0;               // a 68000 negates BG once BGACK is seen
                st   <= ST_DMA_ACT;
            end else if (br_q || &dcnt) st <= ST_DMA_END;
            else dcnt <= dcnt + 8'd1;

        ST_DMA_ACT:                         // master owns the bus
            if (!reset_q)     st <= ST_LOST;
            else if (bgack_q) st <= ST_DMA_END;

        ST_DMA_END: begin
            bg_a    <= 1'b0;
            cpu_off <= 1'b0;
            owned   <= 1'b1;
            st      <= ST_RUN;
        end

        ST_LOST:
            if (reset_q) begin
                cnt <= 22'd0;
                st  <= ST_REACQ;
            end

        ST_REACQ:                           // socketed CPU should re-grant at once
            if (!bg_q || cnt >= T_ARB_TO[21:0]) begin
                owned <= 1'b1;
                st    <= ST_RUN;
            end

        default: st <= ST_SETTLE;
        endcase
    end

    assign bus_owned   = owned;

    assign reset_n_out = 1'b0;
    assign reset_n_oe  = rst_hold;
    assign hlt_n_out   = 1'b0;
    assign hlt_n_oe    = rst_hold;
    assign br_n_out    = 1'b0;
    assign br_n_oe     = br_a;
    assign boss_n_out  = 1'b0;
    assign boss_n_oe   = boss_a;

    // BG is a totem-pole output on the 68000 bus, so once we are the arbiter
    // we drive it high when idle and low when granting. Before takeover it is
    // an input -- that is how we learn we have been granted.
    assign bg_n_out    = ~bg_a;
    assign bg_n_oe     = arbiter;

    // Our own CPU is off the bus when we do not own it, or when we are asking
    // it to leave. Not gated on BG_68SEC000_n in the reset path: during reset
    // our CPU is tri-stated anyway and may not answer, and waiting for an
    // answer that never comes would deadlock the re-acquire. In the DMA path
    // we do wait for the grant, with a timeout.
    assign br_68sec000_n = owned & ~cpu_off;

    assign dma_active  = (st == ST_DMA_GNT) || (st == ST_DMA_ACT);
    assign dma_capable = arbiter;

endmodule

`default_nettype wire
