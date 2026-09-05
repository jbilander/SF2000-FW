// ============================================================================
// autoconfig_zii.v  --  Spitfire 2000: Zorro II autoconfig for the RAM board
//
// Manufacturer 5194 (0x144A, the shared OAHR ID). Registered at
// https://oahr.github.io/oahr/ -- product 10 "Spitfire 2000, RAM",
// product 11 "Spitfire 2000, SD Card".
//
// One instance per board. Chain them by feeding one instance's cfgout_n into
// the next one's cfgin_n and taking the pin from the last: the external
// CFGOUT then cannot assert until every board has configured, which is what a
// real backplane does.
//
// PROTOCOL NOTES THAT ARE EASY TO GET WRONG
//
//  * Nibbles are presented on D15-D12 only, at even byte offsets. Each
//    logical byte is split: high nibble at offset N, low nibble at N+2.
//
//  * Every register is read INVERTED except offsets $00 and $02. That
//    exception exists so er_Type is recognisable: expansion.library checks
//    bits 7-6 == 11 for a Zorro II board, which only works if it is true
//    data. Get this backwards and the board simply never appears.
//
//  * The base is latched as a full byte, A23-A16, because a 64 KB I/O board
//    is only 64 KB aligned -- $E90000 needs the low nibble. This handles both
//    conventions for how it arrives: a single byte write to $48 carrying both
//    nibbles in D15-D8, or a write to $4A with the low nibble in D15-D12
//    followed by $48 with the high nibble. lo_seen picks between them.
//    Writing $48 is what configures the board either way.
//
//  * A write to $4C (ec_ShutUp) means "do not appear at all". CFGOUT is
//    asserted either way, so the chain continues.
//
//  * /RESET clears the configuration, as a real board does. Kickstart runs
//    RESET early and enumerates afterwards.
// ============================================================================

`default_nettype none

module autoconfig_zii #(
    parameter [15:0] MANUF_ID   = 16'd5194,      // 0x144A
    parameter  [7:0] PRODUCT_ID = 8'd10,
    parameter [31:0] SERIAL     = 32'd0,
    parameter        MEMLIST    = 1'b1,          // ERTF_MEMLIST: add to free list
    parameter        DIAGVALID  = 1'b0,          // ERTF_DIAGVALID: has a boot ROM
    parameter [15:0] DIAG_VEC   = 16'h0000       // er_InitDiagVec: offset from the
)(                                               //   board base to the DiagArea
    input  wire        clk,
    input  wire        reset,          // RESET asserted: clear configuration
    input  wire        cfgin_n,
    output wire        cfgout_n,

    input  wire  [2:0] size_code,      // 000=8M 001=64K 010=128K .. 110=2M 111=4M
    input  wire        cyc,            // AS asserted and we own the bus
    input  wire [23:1] a,
    input  wire        rw_n,
    input  wire        uds_n,
    input  wire [15:0] d_in,

    output wire        sel,            // this cycle is ours: withhold AS_MB
    output wire        sel_addr,       // same, but decoded from the address only
    output wire        ack,            // our DTACK to the CPU
    output wire [15:0] d_out,
    output wire  [3:0] d_oe_nib,       // D15-D12 only

    output reg         configured,
    output reg   [7:0] base            // A23-A16 of the configured base
);

    reg  ac_done   = 1'b0;             // configured or shut up: chain moves on
    reg  wr_seen   = 1'b0;
    reg  lo_seen   = 1'b0;             // a $4A write supplied the low nibble
    reg  done_out  = 1'b0;             // ac_done, held until the cycle ends
    reg  ack_r     = 1'b0;

    // A board must not become active PART WAY THROUGH a bus cycle. The chain
    // here is internal and combinational, so the moment the board ahead of us
    // sets ac_done its cfgout falls, our cfgin falls, and we would latch the
    // very same $48 write that just configured it -- both boards landing on
    // the same base. A real backplane cannot do this because the boards are
    // physically separate; ours can. So sample activeness only between cycles.
    reg  armed     = 1'b0;
    wire ac_active = ~cfgin_n & ~ac_done;
    wire ac_space  = (a[23:16] == 8'hE8);

    always @(posedge clk)
        if (reset)     armed <= 1'b0;
        else if (!cyc) armed <= ac_active;

    // CFGOUT MUST NOT FALL MID-CYCLE. ac_done sets on the clock edge that sees
    // the $48 write, while AS is still asserted, so releasing CFGOUT straight
    // from it hands the next board a CFGIN that arrives part way through that
    // same write -- and a board without our armed guard will latch it and
    // configure itself at the same base.
    //
    // We found this inside our own chain and fixed it with armed. The same
    // race exists at the pin, and it matters more here: sitting in the
    // coprocessor slot our CFGOUT reaches a Zorro board earlier, relative to
    // the cycle, than a Zorro board's CFGOUT would.
    //
    // So publish ac_done only between cycles.
    always @(posedge clk)
        if (reset)     done_out <= 1'b0;
        else if (!cyc) done_out <= ac_done;

    assign sel_addr = armed & ac_active & ac_space;   // no AS: keeps it off
    assign sel      = cyc & sel_addr;                 // the AS_MB critical path
    assign cfgout_n = ~done_out;

    // ---- register file -----------------------------------------------------
    // ERT_ZORROII, then MEMLIST, DIAGVALID, CHAINEDCONFIG, then the size code.
    wire [7:0] er_type = {2'b11, MEMLIST, DIAGVALID, 1'b0, size_code};

    wire [5:0] idx = a[6:1];           // byte offset / 2
    reg  [3:0] nib;

    always @* begin
        case (idx)
        6'd0:  nib = er_type[7:4];                 // $00 er_Type hi
        6'd1:  nib = er_type[3:0];                 // $02 er_Type lo
        6'd2:  nib = PRODUCT_ID[7:4];              // $04 er_Product hi
        6'd3:  nib = PRODUCT_ID[3:0];              // $06 er_Product lo
        6'd4:  nib = 4'h0;                         // $08 er_Flags hi
        6'd5:  nib = 4'h0;                         // $0A er_Flags lo
        6'd8:  nib = MANUF_ID[15:12];              // $10 er_Manufacturer
        6'd9:  nib = MANUF_ID[11:8];               // $12
        6'd10: nib = MANUF_ID[7:4];                // $14
        6'd11: nib = MANUF_ID[3:0];                // $16
        6'd12: nib = SERIAL[31:28];                // $18 er_SerialNumber
        6'd13: nib = SERIAL[27:24];
        6'd14: nib = SERIAL[23:20];
        6'd15: nib = SERIAL[19:16];
        6'd16: nib = SERIAL[15:12];
        6'd17: nib = SERIAL[11:8];
        6'd18: nib = SERIAL[7:4];
        6'd19: nib = SERIAL[3:0];                  // $26
        6'd20: nib = DIAG_VEC[15:12];              // $28 er_InitDiagVec
        6'd21: nib = DIAG_VEC[11:8];               // $2A
        6'd22: nib = DIAG_VEC[7:4];                // $2C
        6'd23: nib = DIAG_VEC[3:0];                // $2E
        default: nib = 4'h0;
        endcase
    end

    // $00 and $02 true, everything else complemented.
    wire [3:0] rd_nib = (idx <= 6'd1) ? nib : ~nib;

    assign d_out    = {rd_nib, 12'h000};
    assign d_oe_nib = (sel & rw_n) ? 4'hF : 4'h0;

    // ---- configuration writes ----------------------------------------------
    // One shot per bus cycle, taken on the first edge where UDS is asserted so
    // the CPU has driven the data (a 68000 asserts the strobes at S4 on a
    // write). ack is delayed one clock so the latch is certainly done before
    // the CPU can end the cycle.
    always @(posedge clk) begin
        ack_r <= sel;
        if (reset) begin
            configured <= 1'b0;
            base       <= 8'h00;
            ac_done    <= 1'b0;
            wr_seen    <= 1'b0;
            lo_seen    <= 1'b0;
        end else if (!cyc) begin
            wr_seen <= 1'b0;
        end else if (sel && !rw_n && !uds_n && !wr_seen) begin
            wr_seen <= 1'b1;
            case (idx)
            6'd36: begin                            // $48 ec_BaseAddress
                base[7:4]  <= d_in[15:12];
                if (!lo_seen) base[3:0] <= d_in[11:8];
                configured <= 1'b1;
                ac_done    <= 1'b1;
            end
            6'd37: begin                            // $4A low nibble, if used
                base[3:0] <= d_in[15:12];
                lo_seen   <= 1'b1;
            end
            6'd38: begin                            // $4C ec_ShutUp
                configured <= 1'b0;
                ac_done    <= 1'b1;
            end
            default: ;
            endcase
        end
    end

    assign ack = ack_r & sel;          // qualified live so it drops with AS

endmodule

`default_nettype wire
