// SPDX-License-Identifier: GPL-2.0-only
/*
 * SPI SD card controller
 *
 * Copyright (C) 2025 Niklas Ekström
 */
module sdcard(
    input C100M,
    input CLKCPU,
    input RESET_n,

    input [23:1] ADDR,
    input access,
    input RW,
    input UDS_n,
    input LDS_n,

    output dtack_n,
    output reg ROM_OE_n,

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
localparam ADDR_SHIFT_CTRL = 4;
localparam ADDR_INTREQ = 5;
localparam ADDR_INTENA = 6;
localparam ADDR_INTACT = 7;

// Decode CPU control signals
wire ds_n = UDS_n && LDS_n;

wire wr_access = access && !ds_n && !RW;
wire rd_access = access && !ds_n && RW && sd_enabled;
wire rom_access = access && RW && !sd_enabled; // ROM enabled before first write

reg sd_enabled = 0;

always @(posedge CLKCPU or negedge RESET_n) begin
    if (!RESET_n) begin
        sd_enabled <= 1'b0;
        ROM_OE_n <= 1'b1;
    end else begin
        if (wr_access)
            sd_enabled <= 1'b1; // Enable SD interface on first write

        if (rom_access) begin
            ROM_OE_n <= 1'b0;
        end else begin
            ROM_OE_n <= 1'b1;
        end
    end
end

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

    if (wr_strobe && ADDR[4:1] == ADDR_INTREQ && data_in[0]) begin
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
        if (wr_strobe && ADDR[4:1] == ADDR_INTENA) begin
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
        if (wr_strobe && ADDR[4:1] == ADDR_SLAVE_SEL) begin
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

// CPU TX/RX buffers
wire [15:0] tx_cb_data;
wire [7:0] tx_cb_q;
wire tx_cb_wr_byte;
wire tx_cb_wr_word;
wire tx_cb_fifo_has_space;
wire tx_cb_empty;
wire tx_cb_full;

wire [7:0] rx_cb_data;
wire [15:0] rx_cb_q;
wire rx_cb_fifo_has_data;
wire rx_cb_rd_byte;
wire rx_cb_rd_word;
wire rx_cb_empty;
wire rx_cb_full;

// FIFOs
wire [7:0] tx_fifo_data;
wire [7:0] tx_fifo_q;
wire [4:0] tx_fifo_used;
wire tx_fifo_full;
wire tx_fifo_empty;
wire tx_fifo_wr_req;
wire tx_fifo_rd_req;

wire [7:0] rx_fifo_data;
wire [7:0] rx_fifo_q;
wire [4:0] rx_fifo_used;
wire rx_fifo_full;
wire rx_fifo_empty;
wire rx_fifo_wr_req;
wire rx_fifo_rd_req;

// Shifter
wire [7:0] shifter_tx;
wire [7:0] shifter_rx;
wire shifter_tx_full;
wire shifter_rx_full;
wire shifter_tx_wr_req;
wire shifter_rx_rd_req;
wire shifter_busy;

// Connect cpu -> tx_cb -> tx_fifo -> shifter_tx
assign tx_cb_data = data_in;

assign tx_cb_wr_byte = wr_strobe && ADDR[4] && !UDS_n && LDS_n;
assign tx_cb_wr_word = wr_strobe && ADDR[4] && !UDS_n && !LDS_n;

assign tx_fifo_data = tx_cb_q;
assign tx_fifo_wr_req = !tx_fifo_full && !tx_cb_empty;
assign tx_cb_fifo_has_space = !tx_fifo_full;

assign shifter_tx = tx_fifo_q;
assign shifter_tx_wr_req = !shifter_tx_full && !tx_fifo_empty;
assign tx_fifo_rd_req = !shifter_tx_full && !tx_fifo_empty;

// Connect shifter_rx -> rx_fifo -> rx_cb -> cpu
assign rx_fifo_data = shifter_rx;
assign rx_fifo_wr_req = shifter_rx_full && !rx_fifo_full;
assign shifter_rx_rd_req = shifter_rx_full && !rx_fifo_full;

assign rx_cb_data = rx_fifo_q;
assign rx_fifo_rd_req = !rx_cb_full && !rx_fifo_empty;
assign rx_cb_fifo_has_data = !rx_fifo_empty;

assign rx_cb_rd_byte = rd_strobe && ADDR[4] && !UDS_n && LDS_n;
assign rx_cb_rd_word = rd_strobe && ADDR[4] && !UDS_n && !LDS_n;

tx_cpu_buf tx_cb(
    .clk(C100M),
    .reset(reset_filtered),
    .wr_byte(tx_cb_wr_byte),
    .wr_word(tx_cb_wr_word),
    .fifo_has_space(tx_cb_fifo_has_space),
    .data(tx_cb_data),
    .q(tx_cb_q),
    .empty(tx_cb_empty),
    .full(tx_cb_full)
);

rx_cpu_buf rx_cb(
    .clk(C100M),
    .reset(reset_filtered),
    .fifo_has_data(rx_cb_fifo_has_data),
    .rd_byte(rx_cb_rd_byte),
    .rd_word(rx_cb_rd_word),
    .data(rx_cb_data),
    .q(rx_cb_q),
    .empty(rx_cb_empty),
    .full(rx_cb_full)
);

fifo tx_fifo(
    .clk(C100M),
    .sclr(reset_filtered),
    .rdreq(tx_fifo_rd_req),
    .wrreq(tx_fifo_wr_req),
    .data(tx_fifo_data),
    .q(tx_fifo_q),
    .usedw(tx_fifo_used),
    .empty(tx_fifo_empty),
    .full(tx_fifo_full)
);

fifo rx_fifo(
    .clk(C100M),
    .sclr(reset_filtered),
    .rdreq(rx_fifo_rd_req),
    .wrreq(rx_fifo_wr_req),
    .data(rx_fifo_data),
    .q(rx_fifo_q),
    .usedw(rx_fifo_used),
    .empty(rx_fifo_empty),
    .full(rx_fifo_full)
);

shifter shifter_inst(
    .clk(C100M),
    .reset(reset_filtered),

    .clk_div(clk_div),
    .mode(mode),

    .new_rx_length(new_rx_length),
    .set_rx_length(set_rx_length),

    .wr_req(shifter_tx_wr_req),
    .rd_req(shifter_rx_rd_req),

    .data_in(shifter_tx),
    .data_out(shifter_rx),

    .in_full(shifter_tx_full),
    .out_full(shifter_rx_full),

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

        if (wr_strobe && ADDR[4:1] == ADDR_CLKDIV) begin
            clk_div <= data_in[7:0];
        end

        if (wr_strobe && ADDR[4:1] == ADDR_SHIFT_CTRL) begin
            mode <= data_in[15:14];
            new_rx_length <= data_in[12:0];
            set_rx_length <= 1'b1;
        end
    end
end

wire [5:0] tx_fifo_len = {tx_fifo_full, tx_fifo_used};
wire [5:0] rx_fifo_len = {rx_fifo_full, rx_fifo_used};

wire [5:0] tx_cb_len = tx_cb_empty ? 6'd0 : (tx_cb_full ? 6'd2 : 6'd1);
wire [5:0] rx_cb_len = rx_cb_empty ? 6'd0 : (rx_cb_full ? 6'd2 : 6'd1);

wire [5:0] tx_len = tx_fifo_len + tx_cb_len;
wire [5:0] rx_len = rx_fifo_len + rx_cb_len;

wire tx_atleast_half_empty = tx_len < 6'd16;
wire rx_atleast_half_full = rx_len >= 6'd16;

wire [15:0] status = {9'd0, shifter_busy, tx_atleast_half_empty, rx_atleast_half_full, tx_cb_full, tx_cb_empty, rx_cb_full, rx_cb_empty};

// Latch data for CPU reads
always @(posedge C100M) begin
    if (rd_strobe) begin
        case (ADDR[4:1])
            ADDR_CLKDIV: data_out <= {8'd0, clk_div};
            ADDR_SLAVE_SEL: data_out <= {15'd0, slave_select};
            ADDR_CARD_DET: data_out <= {15'd0, cd_stable};
            ADDR_STATUS: data_out <= status;
            ADDR_SHIFT_CTRL: data_out <= 16'd0;
            ADDR_INTREQ: data_out <= int_req;
            ADDR_INTENA: data_out <= int_ena;
            ADDR_INTACT: data_out <= int_act;
            default: data_out <= rx_cb_q;
        endcase
    end
end

endmodule
