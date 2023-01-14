module flash (
  input [23:1] A,
  input CLKCPU,
  input RESET_n,
  input AS_n,
  input DS_n,
  input RW_n,
  input enable_maprom,
  output flash_access,
  output FLASH_BUSY_n,
  output flash_dtack_n,
  output reg FLASH_WE_n,
  output reg FLASH_OE_n,
  output FLASH_RESET_n,
  output FLASH_A19
);

reg OVL;
reg maprom_enabled;
reg [1:0] dtack = 0;

assign FLASH_A19 = A[19] || OVL; // Force bank 1 for early boot overlay.
assign FLASH_RESET_n = RESET_n;

assign flash_access = A[23:20] == 4'hA     && !maprom_enabled        || // $A00000-AFFFFF
                      A[23:20] == 4'b0     &&  maprom_enabled && OVL || // $000000-0FFFFF - Early boot overlay
                      A[23:19] == 5'b11111 &&  maprom_enabled        || // $F80000-FFFFFF
                      A[23:19] == 5'b11100 &&  maprom_enabled;          // $E00000-E7FFFF

assign flash_dtack_n = dtack[1];

always @(posedge CLKCPU or posedge AS_n) begin
  if (AS_n) begin
    dtack <= 2'b11;
  end else begin
    dtack[1:0] <= {dtack[0], ~(flash_access && !AS_n)};
  end
end

always @(posedge CLKCPU) begin
  if (!RESET_n) begin
    FLASH_OE_n     <= 1;
    FLASH_WE_n     <= 1;
    OVL            <= 1;
    maprom_enabled <= enable_maprom; // Enable flash overlay at next boot
  end else begin
    if (A[23:16] == 8'hBF && !AS_n && !RW_n) begin
      OVL <= 0; // Disable rom overlay after CIA write
    end
    if (flash_access) begin
      FLASH_OE_n <= AS_n || !RW_n;
      FLASH_WE_n <= AS_n || RW_n || DS_n || maprom_enabled;
    end else begin
      FLASH_OE_n    <= 1;
      FLASH_WE_n    <= 1;
    end
  end
end

endmodule