// ============================================================================
// m6800.v  --  Spitfire 2000: E clock and 6800-cycle emulation
//
// The MC68SEC000 has no VPA, VMA or E pins at all, so when Gary answers a
// cycle with VPA this block runs the entire synchronous 6800 cycle on the
// CPU's behalf and hands it back a normal DTACK.
//
// TWO E MODES
//   Socket empty  -> we generate E (7M/10, six low then four high).
//   Socket filled -> the socketed 68000's E keeps free-running even while it
//                    is arbitrated off the bus and even while RESET is
//                    asserted, so we must NOT drive E. We phase-lock to it.
//
// We do not trust JP2 alone to tell us which. Driving E into another driver
// is the one configuration mistake here that fights real silicon, so the
// block LISTENS FIRST: E stays tri-stated for ~144 us (about ten E periods)
// and only drives if nothing else is toggling it. JP2 then selects between
// "generate" and "there should be an external E", and e_ready reports which
// of the four combinations we actually landed in. JP2 open with no external
// E is a configuration error, and e_ready staying low holds the CPU in reset
// rather than letting it run into a machine whose CIAs will never tick.
//
// WHY THE CAPTURE POINT IS NOT TAKEN FROM THE COUNTER
//   A real 68000 latches 6800 data on E's falling edge. In generate mode our
//   own e_pin register gives us that edge exactly. In sync mode we only learn
//   E has fallen one clock after the fact, which is one clock too late -- the
//   8520 has let go by then. So the capture enable uses the LIVE signal in
//   both modes: the last clock edge at which E still reads high. Everything
//   else (VMA placement) comes off the locked counter, where being a clock
//   out either way is harmless because it sits deep in the E-low phase.
// ============================================================================

`default_nettype none

module m6800 #(
    parameter [3:0] E_VMA_AT   = 4'd1,     // e_cnt at which VMA asserts
    parameter integer LISTEN_W = 10        // 2^10 clocks ~= 144 us of listening
)(
    input  wire        clk,
    input  wire        bus_owned,
    input  wire        jp2_gen_e,          // ~JP2: jumper closed = generate E

    // pins
    input  wire        e_in,
    output wire        e_out,
    output wire        e_oe,
    output wire        vma_n_out,
    output wire        vma_n_oe,

    // bus cycle interface
    input  wire        as_cpu_n,           // live pin
    input  wire        as_cpu_q,           // 2FF synchronised
    input  wire        vpa_q,              // 2FF synchronised
    input  wire        rw_n,
    input  wire [15:0] d_in,

    // results back to main_top
    output wire        as_release,         // force AS_MB high, slave is done
    output wire        ack,                // our DTACK to the local CPU
    output wire        drive_d,            // replay captured data
    output wire [15:0] data,
    output wire        e_ready,            // an E source exists
    output wire        busy                // a 6800 cycle is in progress
);

    // ---- listen window: is something else already driving E? ---------------
    reg [LISTEN_W-1:0] listen_cnt  = {LISTEN_W{1'b0}};
    reg                listen_done = 1'b0;
    reg                e_in_r      = 1'b0;
    reg                armed       = 1'b0;   // e_in_r only valid from clock 2
    reg          [3:0] e_edges     = 4'd0;

    // TWO THINGS THIS MUST GET RIGHT, both learned the hard way:
    //
    //  1. e_in_r starts at 0, but with an empty socket the E line idles HIGH
    //     (pulled up, and held high by io_weak_pullup through configuration).
    //     Comparing against the uninitialised register on clock 1 registers a
    //     phantom edge and vetoes our own E driver forever -- the CIAs then
    //     never tick and the machine sits with a black screen and both LEDs
    //     stuck on. Hence `armed`: no edge detection until e_in_r is real.
    //
    //  2. One edge is not evidence. E is floating on a long trace when the
    //     socket is empty, so a single crosstalk glitch must not be able to
    //     disable E generation. A real E gives ~200 edges in this window;
    //     requiring 8 leaves a wide margin either way.
    always @(posedge clk) begin
        e_in_r <= e_in;
        armed  <= 1'b1;
        if (!listen_done) begin
            listen_cnt <= listen_cnt + {{(LISTEN_W-1){1'b0}}, 1'b1};
            if (armed && (e_in ^ e_in_r) && !(&e_edges))
                e_edges <= e_edges + 4'd1;
            if (&listen_cnt) listen_done <= 1'b1;
        end
    end

    wire e_ext_seen = (e_edges >= 4'd8);
    wire e_drive    = listen_done & jp2_gen_e & ~e_ext_seen;
    assign e_ready = listen_done & (e_drive | e_ext_seen);

    // ---- E counter: free-running when we generate, phase-locked when not ---
    reg  [3:0] e_cnt = 4'd0;
    reg        e_pin = 1'b0;

    wire [3:0] e_nxt   = (e_cnt == 4'd9) ? 4'd0 : e_cnt + 4'd1;
    wire       e_rise_x = ~e_in_r &  e_in;
    wire       e_fall_x =  e_in_r & ~e_in;

    // We first SEE an external edge one clock after it happened, so the
    // reload values are 7 and 1 rather than 6 and 0.
    wire [3:0] e_set = e_drive   ? e_nxt
                     : e_rise_x  ? 4'd7
                     : e_fall_x  ? 4'd1
                     :             e_nxt;

    always @(posedge clk) begin
        e_cnt <= e_set;
        e_pin <= (e_set >= 4'd6);
    end

    assign e_out = e_pin;
    assign e_oe  = e_drive;

    // Live E, and the edge on which the cycle terminates.
    wire e_now  = e_drive ? e_pin : e_in;
    wire e_fall = e_drive ? (e_cnt == 4'd9) : e_fall_x;

    // ---- sequencer ---------------------------------------------------------
    localparam VP_IDLE = 3'd0, VP_WAIT = 3'd1, VP_EHI  = 3'd2,
               VP_HOLD = 3'd3, VP_ACK  = 3'd4, VP_DONE = 3'd5;

    reg  [2:0] vp_st    = VP_IDLE;
    reg [15:0] cia_data = 16'h0000;
    reg        vma_lo   = 1'b0;
    reg        as_rel   = 1'b0;
    reg        rep_d    = 1'b0;
    reg        loc_ack  = 1'b0;

    // Tracks the bus while E is high and freezes on the last clock edge at
    // which E still reads high -- where a real 68000 latches.
    always @(posedge clk) if (e_now) cia_data <= d_in;

    always @(posedge clk) begin
        // Every state below exists only inside a bus cycle, so "no AS" is both
        // the idle condition and the exit path. Clearing on the LIVE AS means
        // nothing leaks into the next cycle, which is what made rev A guru.
        if (!bus_owned || as_cpu_n) begin
            vp_st   <= VP_IDLE;
            vma_lo  <= 1'b0;
            as_rel  <= 1'b0;
            rep_d   <= 1'b0;
            loc_ack <= 1'b0;
        end else case (vp_st)

        VP_IDLE:
            if (!as_cpu_q && !vpa_q) vp_st <= VP_WAIT;

        // AS_MB stays asserted throughout, exactly as on a real 68000.
        VP_WAIT:
            if (e_cnt == E_VMA_AT) begin
                vma_lo <= 1'b1;                 // E low, ~700 ns before it rises
                vp_st  <= VP_EHI;
            end

        VP_EHI:
            if (e_fall) vp_st <= VP_HOLD;       // cia_data froze on this edge

        // VMA held past E's fall, as the real CPU does in S18/S19. Without
        // this an 8520 write gets no chip-select hold at all.
        VP_HOLD: begin
            vma_lo <= 1'b0;
            as_rel <= 1'b1;                     // release the slave first
            vp_st  <= VP_ACK;
        end

        VP_ACK: begin
            rep_d   <= rw_n;                    // reads replay; writes need nothing
            loc_ack <= 1'b1;
            vp_st   <= VP_DONE;
        end

        VP_DONE: ;                              // wait here until AS_CPU negates

        default: vp_st <= VP_IDLE;
        endcase
    end

    assign vma_n_out = ~vma_lo;
    assign vma_n_oe  = bus_owned;

    assign as_release = as_rel;
    assign ack        = loc_ack;
    assign drive_d    = rep_d;                  // set to rw_n in VP_ACK: reads only
    assign data       = cia_data;
    assign busy       = (vp_st != VP_IDLE);

endmodule

`default_nettype wire
