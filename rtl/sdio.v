`timescale 1ns / 1ps

module sdio(
    input wire C7M,
	input wire CLKCPU,
	input wire RESET_n,
	input wire [23:16] A_HIGH,
	input wire RW_n,
	input wire AS_CPU_n,
	input wire [7:0] BASE_SDIO,
	input wire SDIO_CONFIGURED_n,
    output reg ROM_OE_n = 1'b1,
	output wire SDIO_ACCESS
);

assign SDIO_ACCESS = !SDIO_CONFIGURED_n && (A_HIGH == BASE_SDIO) && !AS_CPU_n;

always @(negedge RESET_n or posedge C7M) begin

	if (!RESET_n) begin

		ROM_OE_n <= 1'b1;
		
	end else if (SDIO_ACCESS) begin 

		if (RW_n) begin	//Read

			ROM_OE_n <= 1'b0;

		end else begin	//Write

			ROM_OE_n <= 1'b1;

		end

	end else begin

		ROM_OE_n <= 1'b1;

	end

end

endmodule