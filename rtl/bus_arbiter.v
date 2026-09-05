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
// GRANTING THE BUS TO A ZORRO MASTER IS A RELAY, NOT A SEQUENCE. Only /BR and
// /BG are wired to our 68SEC000 -- two-wire arbitration -- so it cannot see
// /BGACK for itself. That is exactly why an external /BGACK has to be relayed
// into its /BR: without it our CPU would come back onto the bus the moment the
// master dropped /BR, while the master still held the bus via /BGACK. Pass
// /BR or /BGACK through to its /BR, pass its /BG straight back out, and let
// the CPU do the rest. Two clocks of synchroniser and nothing else.
//
// An earlier state machine here walked BR -> ask our CPU -> wait for BG ->
// assert BG -> wait for BGACK -> negate BG, and it hung a B2000 with a GVP
// HC8+ during enumeration. Two reasons it was wrong. It triggered only on /BR,
// so a master asserting /BGACK without a fresh request got no response and we
// kept driving the bus against it. And it imposed our idea of the protocol's
// timing on a master that has its own.
//
// The relay also removes the deadlock the state machine existed to avoid.
// bus_owned only drops when BGACK is actually asserted, and by then our CPU
// has already finished its cycle and tri-stated -- so DTACK forwarding is
// still live for the whole time the CPU needs it.
//
// Once we are the CPU, /BR reverses
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
    output wire took_bus,         // startup: we hold the motherboard bus
    output wire running,          // startup: reset released, CPU let go
    output wire sane,             // /BR and /BGACK seen idle high: relay live
    output wire relayed,          // an external /BR or /BGACK reached our CPU
    output wire master_took,      // a master actually took it (/BGACK asserted)
    output wire cpu_present,      // a socketed CPU answered our request
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
               ST_LOST    = 4'd6,  ST_REACQ   = 4'd7;

    reg  [3:0] st       = ST_SETTLE;
    reg [21:0] cnt      = 22'd0;
    reg        b2000    = 1'b0;
    reg        bg_seen  = 1'b0;    // a real CPU granted: the socket is populated
    reg        br_a     = 1'b0;
    reg        boss_a   = 1'b0;
    reg        arbiter  = 1'b0;    // BR is free, BG is ours to drive
    reg        took     = 1'b0;    // startup done: the bus is ours to hand out
    reg        rst_hold = 1'b1;
    reg  [3:0] sane_cnt = 4'd0;
    reg        arb_sane = 1'b0;    // /BR and /BGACK have been seen idle high

    // BEFORE TRUSTING /BR AND /BGACK, CHECK THEY ARE ALIVE. Both idle high on
    // a healthy machine, so a few clocks of both high proves the lines exist
    // and are pulled up. Until that is proven we keep the bus and run our own
    // CPU, because the relay hands our CPU's bus away on either line going
    // low -- and a line that is stuck low, unconnected, or on a machine that
    // does not drive it would otherwise park the CPU forever with no cycles
    // at all. Degraded means no DMA; it does not mean a black screen.
    //
    // On a healthy board this sets within a few clocks of ST_RUN and nothing
    // is lost. If DMA never works but the machine boots, one of these two
    // lines is the thing to put a scope on.
    always @(posedge clk)
        if (!took || !br_q || !bgack_q) sane_cnt <= 4'd0;
        else if (sane_cnt != 4'd15)     sane_cnt <= sane_cnt + 4'd1;

    always @(posedge clk)
        if (!reset_q)                arb_sane <= 1'b0;
        else if (sane_cnt == 4'd15)  arb_sane <= 1'b1;

    always @(posedge clk) begin
        cnt <= cnt + 22'd1;
        case (st)

        ST_SETTLE:                          // rails, pull-ups, JP1's ~2 ms RC
            if (cnt >= T_SETTLE[21:0]) begin
                b2000 <= boss_n_in;         // 4k7 on a B2000 beats our pulldown
                // On a B2000, go straight to BOSS and never touch /CBR. BOSS
                // is the supported way to become the CPU there: Buster sees
                // it, asserts /BR to the onboard 68000, that CPU grants and
                // tri-states, and U303 holds it off via /BGACK afterwards.
                //
                // The old path asked for the bus first and sat holding /CBR
                // for the full 20 ms timeout -- nothing ever answered, so
                // bg_seen never set anyway -- and only then asserted BOSS.
                // That left a 30 ms window with Buster part-way through an
                // arbitration it could not finish, which is the one thing we
                // did that a normal A2000 accelerator does not.
                st    <= boss_n_in ? ST_TAKE : ST_REQ;
            end

        ST_REQ: begin                       // ask the socketed CPU for the bus
            br_a <= 1'b1;
            if (!bg_q) begin bg_seen <= 1'b1; st <= ST_TAKE; end
            else if (cnt >= T_ARB_TO[21:0])  st <= ST_TAKE;
        end

        ST_TAKE: begin
            took <= 1'b1;
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
                took <= 1'b0;
                cnt   <= 22'd0;
                st    <= ST_LOST;
            end

        ST_LOST:
            if (reset_q) begin
                cnt <= 22'd0;
                st  <= ST_REACQ;
            end

        ST_REACQ:                           // socketed CPU should re-grant at once
            if (!bg_q || cnt >= T_ARB_TO[21:0]) begin
                took <= 1'b1;
                st    <= ST_RUN;
            end

        default: st <= ST_SETTLE;
        endcase
    end

    assign reset_n_out = 1'b0;
    assign reset_n_oe  = rst_hold;
    assign hlt_n_out   = 1'b0;
    assign hlt_n_oe    = rst_hold;
    assign br_n_out    = 1'b0;
    assign br_n_oe     = br_a;
    assign boss_n_out  = 1'b0;
    assign boss_n_oe   = boss_a;

    // Straight through from our own CPU's grant, but ONLY when the socket is
    // empty.
    //
    // /BGACK tri-states a 68000's address, data and control outputs -- it does
    // NOT tri-state /BG, which stays driven on pin 11. So on a B2000 with the
    // socketed CPU still fitted, BOSS switches that CPU off the bus but it
    // goes on driving /BG, and Buster reads that line. If we drove it too,
    // two totem-pole outputs would share one net: invisible while nobody is
    // requesting, a fight the moment either tries to grant.
    //
    // It is also unnecessary. Buster's /BR reaches the socketed CPU's pin 13
    // as well as us, so that CPU already answers the request itself. Leave it
    // to do the job, and only drive /BG when there is no CPU there to do it.
    assign bg_n_out    = bg68_q;
    assign bg_n_oe     = arbiter & ~bg_seen;

    // Ask our CPU to step off while we do not hold the bus, or while an
    // external master is either requesting it or already holding it. Watching
    // BGACK as well as BR is what lets a master that reacquires the bus
    // without issuing a fresh request still be honoured -- the state machine
    // this replaced watched only BR and would drive the bus against it.
    assign br_68sec000_n = took & (arb_sane ? (br_q & bgack_q) : 1'b1);

    // A master holds the bus exactly when BGACK is asserted, and everything
    // the rest of the design keys off follows from that single fact.
    assign dma_active    = arbiter & arb_sane & ~bgack_q;
    assign dma_capable   = arbiter;
    assign bus_owned     = took & (arb_sane ? bgack_q : 1'b1);

    // Status for the diagnostic LED. Efinity will not let another module reach
    // in for st, and it is right not to.
    assign took_bus      = took;
    assign running       = (st == ST_RUN);
    assign sane          = arb_sane;
    assign relayed       = took & arb_sane & (~br_q | ~bgack_q);
    assign master_took   = took & arb_sane & ~bgack_q;
    assign cpu_present   = boss_a;      // long blink now means "BOSS asserted"

endmodule

`default_nettype wire
