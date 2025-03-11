module sdcard(
    input C100M,
    input RESET_n,

    input [23:1] ADDR,
    input access,
    input RW,
    input ds_n,

    output dtack_n,

    input [15:0] data_in,
    output reg [15:0] data_out,
    output data_oe,

    output INT2_n,

    output SS_n,
    output SCLK,
    output MOSI,
    input MISO,
    input CD_n
);

// Register addresses
localparam ADDR_CLKDIV = 0;
localparam ADDR_SLAVE_SEL = 1;
localparam ADDR_CARD_DET = 2;
localparam ADDR_STATUS = 3;
localparam ADDR_SHIFT_REG = 4;
localparam ADDR_INTREQ = 5;
localparam ADDR_INTENA = 6;
localparam ADDR_INTACT = 7;

// Decode CPU control signals
wire wr_access = access && !ds_n && !RW;
wire rd_access = access && !ds_n && RW;

assign data_oe = rd_access;
assign dtack_n = !access;

reg [2:0] reset_sync;
reg reset_filtered;

always @(posedge C100M) begin
    reset_sync <= {reset_sync[1:0], !RESET_n};

    if (reset_sync[2] == reset_sync[1])
        reset_filtered <= reset_sync[2];
end

reg [2:0] wr_sync;
reg [2:0] rd_sync;

always @(posedge C100M) begin
    wr_sync <= {wr_sync[1:0], wr_access};
    rd_sync <= {rd_sync[1:0], rd_access};
end

wire wr_strobe = wr_sync[2:1] == 2'b01;
wire rd_strobe = rd_sync[2:1] == 2'b01;

// Card Detect (CD) handling
reg [2:0] cd_sync;
reg [19:0] cd_debounce_counter;
reg cd_stable;
reg cd_changed;

always @(posedge C100M) begin
    cd_sync <= {cd_sync[1:0], !CD_n};

    if (cd_sync[2] != cd_sync[1]) begin
        cd_debounce_counter <= 20'd1000000; // 10 milliseconds
    end else if (cd_debounce_counter == 20'd0) begin
        if (cd_stable != cd_sync[2]) begin
            cd_stable <= cd_sync[2];
            cd_changed <= 1'b1;
        end
    end else begin
        cd_debounce_counter <= cd_debounce_counter - 20'd1;
    end

    if (wr_strobe && ADDR[3:1] == ADDR_INTREQ && data_in[0]) begin
        cd_changed <= 1'b0;
    end
end

// Interrupt handling
wire [15:0] int_req = {15'd0, cd_changed};
reg [15:0] int_ena;
wire [15:0] int_act = int_req & int_ena;

wire any_int_act = |int_act;

assign INT2_n = !(any_int_act);

always @(posedge C100M) begin
    if (reset_filtered) begin
        int_ena <= 16'd0;
    end else begin
        if (wr_strobe && ADDR[3:1] == ADDR_INTENA) begin
            int_ena = data_in;
        end
    end
end

// Slave Select (SS) handling
reg slave_select;
assign SS_n = !slave_select;

always @(posedge C100M) begin
    if (reset_filtered) begin
        slave_select <= 1'b0;
    end else begin
        if (wr_strobe && ADDR[3:1] == ADDR_SLAVE_SEL) begin
            slave_select = data_in[0];
        end
    end
end

// SPI shifting

// Max clk_div = 255 => min SCLK = 195 kHz
reg [7:0] clk_div;
reg [1:0] mode;
reg [12:0] new_rx_length;
reg set_rx_length;

wire shifter_wr_req = wr_strobe && ADDR[3:1] == ADDR_SHIFT_REG;
wire shifter_rd_req = rd_strobe && ADDR[3:1] == ADDR_SHIFT_REG;

wire [7:0] shifter_data_in = data_in[7:0];
wire [7:0] shifter_data_out;

wire in_full;
wire out_full;
wire shifter_busy;

shifter shifter_inst(
    .clk(C100M),
    .reset(reset_filtered),

    .clk_div(clk_div),
    .mode(mode),

    .new_rx_length(new_rx_length),
    .set_rx_length(set_rx_length),

    .wr_req(shifter_wr_req),
    .rd_req(shifter_rd_req),

    .data_in(shifter_data_in),
    .data_out(shifter_data_out),

    .in_full(in_full),
    .out_full(out_full),
    .busy(shifter_busy),

    .MISO(MISO),
    .MOSI(MOSI),
    .SCLK(SCLK)
);

always @(posedge C100M) begin
    if (reset_filtered) begin
        mode <= 2'd0;
        set_rx_length <= 1'b0;
    end else begin
        set_rx_length <= 1'b0;

        if (wr_strobe && ADDR[3:1] == ADDR_CLKDIV) begin
            clk_div <= data_in[7:0];
        end

        if (wr_strobe && ADDR[3:1] == ADDR_CARD_DET) begin
            mode <= data_in[15:14];
            new_rx_length <= data_in[12:0];
            set_rx_length <= 1'b1;
        end
    end
end

// Latch data for CPU reads
always @(posedge C100M) begin
    if (rd_strobe) begin
        case (ADDR[3:1])
            ADDR_CLKDIV: data_out <= {8'd0, clk_div};
            ADDR_SLAVE_SEL: data_out <= {15'd0, slave_select};
            ADDR_CARD_DET: data_out <= {15'd0, cd_stable};
            ADDR_STATUS: data_out <= {13'd0, in_full, out_full, shifter_busy};
            ADDR_SHIFT_REG: data_out <= {8'd0, shifter_data_out};
            ADDR_INTREQ: data_out <= int_req;
            ADDR_INTENA: data_out <= int_ena;
            ADDR_INTACT: data_out <= int_act;
        endcase
    end
end

endmodule
