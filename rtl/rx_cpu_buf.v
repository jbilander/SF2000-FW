module rx_cpu_buf(
    input wire clk,
    input wire reset,
    input wire rd_byte,
    input wire rd_word,
    input wire fifo_has_data,
    input wire [7:0] data,
    output wire [15:0] q,
    output wire empty,
    output wire full
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
