# SF2000 Firmware Changelog: 8b70279 to 025ee20

Analysis of 19 commits made between commit 8b70279 (base: "Fix Fast RAM
stability: hybrid registered/combinatorial WE based on speed") and the
current HEAD (025ee20). Separates real fixes from red herrings and dead ends.

## Starting Point (8b70279)

- Turbo mode at 40 MHz (80 MHz PLL / 2)
- No expansion card support (GVP SCSI caused crashes)
- Single C7M-domain DTACK path for everything
- DTACK_MB_n was input-only (no DMA DTACK drive)
- INT2_n was an output (directly driven)
- No safety timing between bus cycles
- Async resets on AS_CPU_n edges (posedge AS_CPU_n in always blocks)
- No SDC constraints for turbo_clk or CDC
- All IO drive strengths at minimum (1)


## What Actually Fixed Things

These are the changes that solved real bugs, confirmed by testing. Each
one addressed a specific failure mode that could be reproduced.

### 1. BGACK_n synchronization on AS_MB_n_OE (025ee20) -- THE BIG ONE

**Bug**: Raw BGACK_n used combinatorially in `AS_MB_n_OE`. During DMA
transitions, ringing/reflections on the BGACK_n pin momentarily tri-stated
AS mid-cycle. Expansion cards saw AS deassert, released DTACK, and the CPU
hung forever waiting for DTACK to come back.

**Fix**: Replace raw `BGACK_n` with `bgack_sync2` (2-stage C100M sync).

```verilog
// Before:
assign AS_MB_n_OE = BG_68SEC000_n | !AS_CPU_n;
// After:
assign AS_MB_n_OE = (BG_68SEC000_n | !AS_CPU_n) & bgack_sync2;
```

**Evidence**: This single fix made GVP file copy, SysInfo drive test, and
stress test all work reliably. Biggest stability improvement of the entire
series.

### 2. BGACK_n 2-stage synchronizer for all downstream logic (083d844, 025ee20)

**Bug**: Raw BGACK_n feeding the `as_n` mux, fastram, sdcard_access, and
dtack_oe_reg could glitch during DMA transitions, causing the as_n mux to
momentarily select the wrong AS source. This could falsely reset the fastram
DTACK counter mid-cycle.

**Fix**: 2-stage C100M synchronizer, then 2-stage CLKCPU re-sync for
CPU-domain consumers.

```verilog
reg bgack_sync1, bgack_sync2;
always @(posedge C100M) begin
    bgack_sync1 <= BGACK_n;
    bgack_sync2 <= bgack_sync1;
end
```

**Evidence**: Required for stable DMA coexistence. Without it, as_n mux
glitches caused sporadic hangs under heavy DMA.

### 3. as_n mux: BGACK instead of BG (083d844)

**Bug**: `as_n` was selected by `BG_68SEC000_n` (Bus Grant), but BG can be
deasserted by the arbiter while BGACK is still held by the DMA master. This
caused the FPGA to switch AS source mid-DMA-cycle.

**Fix**: Use BGACK (bus ownership) as the mux select.

```verilog
// Before:
wire as_n = BG_68SEC000_n ? AS_CPU_n : AS_MB_n_IN;
// After:
wire as_n = bgack_sync2 ? AS_CPU_n : AS_MB_n_IN;
```

### 4. Bidirectional DTACK drive for DMA (88581e0)

**Bug**: DTACK_MB_n was input-only. When GVP DMA accessed the FPGA's fast
RAM, nothing drove DTACK on the motherboard bus. The DMA master hung waiting
for acknowledgement.

**Fix**: Made DTACK_MB_n bidirectional. FPGA drives DTACK LOW when DMA
accesses fast RAM and the RAM controller is ready.

```verilog
reg dtack_oe_reg;
always @(posedge CLKCPU) begin
    dtack_oe_reg <= (!bgack_cpu && ram_access && !ram_dtack_n);
end
assign DTACK_MB_n_OUT = 1'b0;
assign DTACK_MB_n_OE = dtack_oe_reg & !as_n;
```

### 5. C100M oversampled DTACK counter with pause-on-noise (8232f1d, 083d844)

**Bug**: Single C7M samples of DTACK are too noise-sensitive for expansion
cards. One noisy sample fires DTACK before the card has valid data, CPU
reads bus pull-ups (0xFFFF). Confirmed: C7M-only DTACK caused GVP to
return $FF/$FF status reads.

**Fix**: 100 MHz oversampling counter requires 12 consecutive LOW samples
(120ns) before asserting. Noise pauses the counter but doesn't reset it,
so genuine DTACK eventually accumulates even on a noisy bus.

**Evidence**: Directly confirmed by regression -- switching to C7M-only
DTACK in a later experiment caused immediate GVP $FF/$FF failures.

### 6. Safety countdown: precharge + setup timing (56c4953, 1671087)

**Bug**: At turbo speed, back-to-back expansion bus cycles don't give the
DTACK RC pullup enough time to discharge. Stale LOW DTACK from the previous
cycle gets accepted as valid DTACK for the new cycle.

**Fix**: Precharge (280ns) + setup (120ns) = 400ns minimum gap enforced
between bus cycles. Cannot be reduced below ~280ns precharge on a loaded bus
(confirmed by regression when reduced to 120ns).

```verilog
localparam [3:0] PRECHARGE_TICKS = 4'd7;   // 280ns at 25MHz
localparam [2:0] SETUP_TICKS = 3'd3;       // 120ns at 25MHz
```

### 7. turbo_as_gate: combinatorial AS/DTACK blocking (351227b, 51f3d43)

**Bug**: Stale mobo_as_n and mobo_dtack_n registers from the C7M domain
could leak through at the start of a new turbo cycle (no C7M edge may fall
in the short inter-cycle gap at 25MHz).

**Fix**: Triple-OR gate blocks both AS output and DTACK input until safety
is met.

```verilog
wire turbo_as_gate = mobo_as_n | AS_CPU_n | (cpu_speed_switch & !safety_ok);
```

This is used for AS output AND as the reset for the C100M DTACK counter,
preventing stale DTACK accumulation during the safety countdown.

### 8. Async reset elimination (dd95b84)

**Bug**: `posedge AS_n` / `posedge AS_CPU_n` async resets on DTACK and OE
registers caused recovery time violations when AS transitioned near a CLKCPU
edge. The register could go metastable and stick, permanently hanging DTACK.

**Fix**: Converted all async resets to synchronous checks. Instant AS
termination handled by combinatorial gates instead.

### 9. Turbo clock reduction: 40 MHz -> 25 MHz (51f3d43, 1671087)

**Bug**: 40 MHz crashed within 2-3 minutes. The 68SEC000 is rated for
20 MHz; 40 MHz exceeds the chip's timing margins.

**Fix**: Dropped to 20 MHz initially (stable 2h23m), then 25 MHz (stable
3h30m+). 25 MHz is the sweet spot -- 25% overclock while staying close
enough to spec. PLL source changed from 80 MHz/4 to 100 MHz/4.

### 10. SDC timing constraints (dd95b84, 1c6dae4)

**Bug**: No constraints for turbo_clk meant the placer/router didn't know
about the 25 MHz clock domain or CDC boundaries. Timing violations went
undetected.

**Fix**: Added create_clock for turbo_clk, set_clock_groups -asynchronous
for all three domains, and set_false_path for quasi-static autoconfig
registers.

### 11. INT2_n changed from output to input (88581e0)

**Bug**: INT2_n was directly driven as an output, but it's active on the
Amiga bus from other sources. Driving it could cause bus contention with
other interrupt sources.

**Fix**: Changed to input, disconnected SD card's INT2_n output.

### 12. Schmitt trigger on DTACK_MB_n_IN (51f3d43)

Enabled in the Interface Designer (peri.xml). Provides hardware-level
noise filtering on the DTACK input, complementing the C100M counter's
firmware-level filtering.

### 13. DMA address glitch filter in fastram (79f7008)

**Bug**: During DMA cycles targeting other devices (e.g. chip RAM), address
bus transitions could transiently match the SRAM address range, causing
SRAM OE/WE to glitch and briefly drive the data bus.

**Fix**: `safe_to_enable` gate in fastram.v requires address stability for
1 CLKCPU cycle during DMA before enabling OE/WE. CPU access bypasses the
filter for zero wait states.

### 14. DMA wait states in fastram (88581e0)

**Fix**: 6 wait states (150ns at 25MHz) for DMA access to SRAM, 0 for CPU.
Gives the slower DMA path time to set up stable addresses and data.

### 15. Bus arbiter CDC fix (025ee20)

**Bug**: BG_68SEC000_n from the 25 MHz turbo domain was passed through a
C7M register unsynchronized -- a CDC violation.

**Fix**: Use existing 2-stage synchronizer `bg_68sec_sync[1]`.

Note: BR_n_IN and BGACK_n were also changed to use their synchronizers,
but these signals are already C7M-synchronous (Zorro bus) so the sync adds
~280ns unnecessary latency. May want to revert those two back to raw.

### 16. Boot timer extension: 3s -> 5s (79f7008)

Gives expansion cards more time to initialize before the FPGA switches to
turbo mode. Helped Ariadne cold boot reliability (though Ariadne has a
separate hardware-level incompatibility).

### 17. IO drive strength increase: 1 -> 3 (79f7008, final state)

All bus-facing outputs (AS, DTACK_CPU, DTACK_MB, BR_68SEC000, D[15:0])
increased to maximum drive strength. Helps overcome the SN74CBT16211 FET
bus switch losses and loaded bus capacitance. Was reverted once (95495b3)
and re-applied -- ended up keeping it.

### 18. sdcard_access gated by BGACK (e32c6cd)

**Bug**: During DMA, addresses could transiently match the SD card's
autoconfig range, causing the FPGA to respond to an access meant for
another device.

**Fix**: Gate sdcard_access with `bgack_sync2` so it only matches during
CPU cycles.


## Red Herrings and Dead Ends

Changes that were tried, didn't help (or made things worse), and were
reverted. These are worth documenting to avoid repeating them.

### A. Disabling FPGA RAM entirely (c32cfd1)

Tried skipping RAM in autoconfig to avoid address contention with GVP.
This was a diagnostic step that confirmed the problem was in bus timing,
not address conflicts. Re-enabled once the real fixes were found.

### B. Reduced safety parameters (tried during 025ee20 session, reverted)

Reduced PRECHARGE 7->3, SETUP 3->1, DTACK_TICKS 12->6 to minimize the
DS-before-AS protocol violation window. Caused file copy hangs -- 120ns
precharge is too short for the bus RC pullup on a loaded Zorro bus.

### C. C7M-only expansion DTACK (tried during 025ee20 session, reverted)

Replaced the C100M counter path with a single C7M sample of DTACK for
expansion cards. Caused immediate GVP boot failure ($FF/$FF status reads).
A single C7M sample has no noise immunity -- one noisy sample fires DTACK
before the card has valid data on the bus.

### D. Armed gate on expansion DTACK path (51f3d43, removed in 025ee20 session)

The armed gate requires 6 consecutive HIGHs (~320ns) before allowing any
DTACK through. Works for legacy devices (slow DTACK, open-drain with
pullup), but deadlocks on expansion cards that respond faster than 320ns.
The C100M counter already provides stale DTACK protection for expansion,
making the armed gate redundant and harmful there.

### E. Drive strength increase/revert churn (f52d213, 95495b3)

Drive strength was increased, then reverted, then re-applied. The increase
helps marginally with signal integrity but didn't fix the core bugs (BGACK
glitch, missing DTACK drive, etc). It survived in the final build but was
never the difference between working and not working.

### F. Ariadne-specific fixes (79f7008, 083d844 -- partially)

Several changes were motivated by Ariadne compatibility: boot timer
extension, DMA glitch filter, BGACK sync. The BGACK sync and DMA glitch
filter genuinely help GVP and general DMA stability, but the Ariadne
itself has a hardware-level incompatibility with the SF2000 rev 2b (3.3V
output through FET bus switches is below 74HC CMOS VIH threshold). No
firmware fix can address this.


## Net Architecture Change Summary

The firmware went from a simple "pass-through with clock switching" to a
proper multi-clock-domain bus controller:

| Aspect | Before (8b70279) | After (025ee20) |
|--------|-------------------|------------------|
| Turbo clock | 40 MHz | 25 MHz |
| DTACK input | Single C7M sample | Dual path: C7M for legacy, C100M 12-tick counter for expansion |
| Bus cycle timing | None | 400ns safety gap (precharge + setup) |
| BGACK handling | Raw, unsynchronized | 2-stage C100M sync, 2-stage CLKCPU re-sync |
| DMA DTACK | Not supported | Bidirectional drive with 6 wait states |
| Async resets | On AS_CPU_n edges | All synchronous |
| SDC constraints | C7M only | All 3 clock domains, CDC groups, false paths |
| IO drive strength | Minimum (1) | Maximum (3) on bus outputs |
| DTACK_MB_n | Input only | Bidirectional (inout) |
| DTACK_MB_n input | No filtering | Schmitt trigger enabled |
| INT2_n | Output (driven) | Input (tri-stated) |
| Bus arbiter CDC | Raw signals | 2-stage synced (BG_68SEC000_n) |
