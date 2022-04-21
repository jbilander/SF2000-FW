`timescale 1ns / 1ps

module testbench;

	parameter real CLK_PERIOD = 140; // ≈7.14 MHz

	// Inputs
	reg C7M;
	reg CDAC;
	
	// Output
	wire C14M;

	// Instantiate the Unit Under Test (UUT)
	main_top uut (
		.C7M(C7M),
		.CDAC(CDAC),
		.C14M(C14M)
	);

	initial begin
		// Initialize Inputs
		C7M = 0;
		CDAC = 0;

		// Wait 100 ns for global reset to finish
		//#100;

		// Add stimulus here
		
		#2000 $finish;

	end
	
	initial begin
		#(CLK_PERIOD/4) CDAC = 1; //to make it 90 degrees out of phase with C7M
		forever CDAC = #(CLK_PERIOD/2) ~CDAC;
	end
	
	always #(CLK_PERIOD/2) C7M <= ~C7M;
      
endmodule
