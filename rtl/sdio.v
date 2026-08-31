// SPDX-License-Identifier: GPL-2.0-only
// ============================================================================
// sdio.v  --  Spitfire 2000: boot ROM window for the SD card board
//
// The driver lives in U13 (SST39LF040), byte-wide on D0-D7. CPU A1-A15 drive
// the chip's A0-A14 and ROM_B1 (jumper J11) drives A15, so 32 KB of ROM
// content occupies the full 64 KB of a Zorro II I/O board, readable at odd
// byte addresses. That is the classic Amiga boot-ROM arrangement, and it is
// why 64 KB is exactly the right autoconfig size.
//
// A 64 KB board is 64 KB aligned, so a plain 8-bit compare on A23-A16 is
// enough -- unlike fast RAM, which needs a magnitude compare because no 4 MB
// slot inside Zorro II memory space is 4 MB aligned.
//
// The ROM drives D0-D7 through the FETs directly; the FPGA never drives data
// for a ROM read, it only asserts OE and answers with DTACK.
//
// ROM and registers share this window and cannot be separated by address --
// the driver's register offsets and the DiagArea are both fixed relative to
// the board base by the ROM image. So they are separated in TIME instead:
// reads before the first write are expansion.library's DiagCopy, reads after
// are the driver. SD_ENABLED latches on that first write and kills the ROM,
// which is what keeps the ROM and the FPGA off D0-D7 simultaneously.
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none

module sdio(
    input  wire [23:16] A_HIGH,
    input  wire         RW_n,
    input  wire         AS_CPU_n,
    input  wire   [7:0] BASE_SDIO,
    input  wire         SDIO_CONFIGURED,
    input  wire         SD_ENABLED,        // first write has happened: ROM off
    output wire         ROM_OE_n,
    output wire         SDIO_ACCESS,
    output wire         SDIO_ACCESS_ADDR   // decoded from the address only
);

// SDIO_ACCESS_ADDR deliberately excludes AS. main_top ORs it into
// AS_MB_n_OUT, which AS_CPU_n already forces high when no cycle is running,
// so including AS would only drag this compare onto the path to the pin.
assign SDIO_ACCESS_ADDR = SDIO_CONFIGURED && (A_HIGH == BASE_SDIO);
assign SDIO_ACCESS      = SDIO_ACCESS_ADDR && !AS_CPU_n;
assign ROM_OE_n         = !(SDIO_ACCESS && RW_n && !SD_ENABLED);

endmodule

`default_nettype wire
