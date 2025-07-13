module tx_cpu_buf(
    input wire clk,
    input wire reset,
    input wire wr_byte,
    input wire wr_word,
    input wire fifo_has_space,
    input wire [15:0] data,
    output wire [7:0] q,
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

assign q = u;

reg u_full;
reg l_full;

assign empty = !u_full; // !l_full is implied
assign full = l_full;   // u_full is implied

always @(posedge clk) begin
    if (reset) begin
        u_full <= 1'b0;
        l_full <= 1'b0;
    end else begin
        if (wr_byte) begin
            if (!fifo_has_space && u_full) begin
                l <= data[15:8];
                l_full <= 1'b1;
            end else begin
                u <= data[15:8];
                u_full <= 1'b1;
            end
        end else if (wr_word) begin
            u <= data[15:8];
            l <= data[7:0];
            u_full <= 1'b1;
            l_full <= 1'b1;
        end else begin
            if (fifo_has_space && u_full) begin
                u <= l;
                u_full <= l_full;
                l_full <= 1'b0;
            end
        end
    end
end

endmodule
