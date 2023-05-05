module flash (
    input [23:1] A,
    input AS_CPU_n,
    input CLKCPU,
    input RESET_n,
    input DS_n,
    input RW_n,
    input JP2,
    input JP3,
    input JP4,
    input JP9,
    input CPU_SPEED_SWITCH,
    input FLASH_BUSY_n,
    output FLASH_ACCESS,
    output FLASH_A19,
    output FLASH_RESET_n,
    output reg FLASH_WE_n = 1'b1,
    output reg FLASH_OE_n = 1'b1,
    output reg DTACK_n = 1'b1
);

reg OVL;
reg maprom_enabled;
reg [2:0] counter;

wire [2:0] clksel = {JP2, JP3, JP4};
wire [2:0] delay_cnt = !CPU_SPEED_SWITCH && (clksel == 3'b101 || clksel == 3'b110) ? (JP9 ? 3'd2 : 3'd3) : 3'd0;

assign FLASH_A19 = A[19] || OVL; // Force bank 1 for early boot overlay.
assign FLASH_RESET_n = RESET_n;

assign FLASH_ACCESS = A[23:20] == 4'hA     && !maprom_enabled               || // $A00000-AFFFFF
                      A[23:20] == 4'b0     &&  maprom_enabled && OVL        || // $000000-0FFFFF - Early boot overlay
                      A[23:19] == 5'b11111 &&  maprom_enabled               || // $F80000-FFFFFF
                      A[23:19] == 5'b11100 &&  maprom_enabled;                 // $E00000-E7FFFF

always @(posedge CLKCPU or posedge AS_CPU_n) begin

    if (AS_CPU_n) begin
        DTACK_n <= 1'b1;
        counter <= 'd0;
    end else begin

        if (FLASH_ACCESS) begin
            if (counter == delay_cnt) begin
                DTACK_n <= !FLASH_ACCESS;
                counter <= 'd0;
            end else begin
                DTACK_n <= 1'b1;
                counter <= counter + 1'b1;
            end
        end else begin
            DTACK_n <= 1'b1;
            counter <= 'd0;
        end

    end
end

always @(posedge CLKCPU) begin

    if (!RESET_n) begin

        FLASH_OE_n     <= 1;
        FLASH_WE_n     <= 1;
        OVL            <= 1;
        maprom_enabled <= ~JP9; // Enable flash overlay at next boot

    end else begin

        if (A[23:16] == 8'hBF && !AS_CPU_n && !RW_n) begin
            OVL <= 0; // Disable rom overlay after CIA write
        end

        if (FLASH_ACCESS) begin
            FLASH_OE_n <= AS_CPU_n || !RW_n;
            FLASH_WE_n <= AS_CPU_n || RW_n || DS_n || maprom_enabled;
        end else begin
            FLASH_OE_n <= 1;
            FLASH_WE_n <= 1;
        end

    end
end

endmodule
