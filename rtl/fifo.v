// SPDX-License-Identifier: GPL-2.0-only
/*
 * SPI SD card controller
 *
 * Copyright (C) 2025 Niklas Ekström
 */
module fifo(
    input clk,
    input sclr,
    input rdreq,
    input wrreq,
    input [7:0] data,
    output [7:0] q,
    output [4:0] usedw,
    output empty,
    output reg full
);

reg [7:0] ram [31:0];

reg [4:0] wr_ptr;
reg [4:0] rd_ptr;

assign q = ram[rd_ptr];

assign usedw = wr_ptr - rd_ptr; // This value is incorrect (zero) if fifo is full.
assign empty = wr_ptr == rd_ptr && !full;

wire do_write = wrreq && !full;
wire do_read = rdreq && !empty;

always @(posedge clk) begin
    if (sclr) begin
        wr_ptr <= 5'd0;
        rd_ptr <= 5'd0;
        full <= 1'b0;
    end else begin
        if (do_write) begin
            ram[wr_ptr] <= data;
            wr_ptr <= wr_ptr + 5'd1;
        end

        if (do_read) begin
            rd_ptr <= rd_ptr + 5'd1;
        end

        if (do_read)
            full <= 1'b0;
        else if (do_write && wr_ptr + 5'd1 == rd_ptr)
            full <= 1'b1;
    end
end

endmodule
