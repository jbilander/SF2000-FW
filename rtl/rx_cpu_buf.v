// SPDX-License-Identifier: GPL-2.0-only
/*
 * SPI SD card controller
 *
 * Copyright (C) 2025 Niklas Ekström
 */
module rx_cpu_buf(
    input clk,
    input reset,
    input rd_byte,
    input rd_word,
    input fifo_has_data,
    input [7:0] data,
    output [15:0] q,
    output empty,
    output full
);

// A property of this module is that: !u_full => !l_full
// This means that the valid u_full/l_full combinations are:
// u_full l_full
//      0      0
//      1      0
//      1      1

// Hence, the combination u_full=0, l_full=1 is not allowed.

reg [7:0] u;
reg [7:0] l;

assign q = {u, l};

reg u_full;
reg l_full;

assign empty = !u_full; // !l_full is implied
assign full = l_full;   // u_full is implied

always @(posedge clk) begin
    if (reset) begin
        u_full <= 1'b0;
        l_full <= 1'b0;
    end else begin
        if (rd_byte) begin
            u <= l_full ? l : data;
            u_full <= l_full || fifo_has_data;
            l_full <= 1'b0;
        end else if (rd_word) begin
            u_full <= 1'b0;
            l_full <= 1'b0;
        end else begin
            if (!u_full) begin
                u <= data;
                u_full <= fifo_has_data;
            end else if (!l_full) begin
                l <= data;
                l_full <= fifo_has_data;
            end
        end
    end
end

endmodule
