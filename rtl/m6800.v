`timescale 1ns / 1ps

module m6800(
    input C7M,
    input JP5,
    input RESET_n,
    input VPA_n,
    input CPUSPACE,
    input AS_CPU_n,
    inout E,
    output reg VMA_n = 1'b1,
    output reg M6800_DTACK_n = 1'b1
);

reg ECLK = 1'b1;
reg [3:0] e_counter = 'd5;

assign E = JP5 ? 1'bZ : ECLK;

always @(negedge C7M) begin

    if (e_counter == 'd5) begin
        ECLK <= 1'b1;
    end

    if (e_counter == 'd9) begin
        e_counter <= 'd0;
        ECLK <= 1'b0;
    end else begin
        e_counter <= e_counter + 'd1;
    end
	
end

// Determine if current Bus Cycle is a 6800 type where VPA has been asserted.
always @(negedge RESET_n or negedge C7M or posedge VPA_n) begin
	
    if (!RESET_n) begin
        VMA_n <= 1'b1;
    end else begin
		
        if (VPA_n) begin
            VMA_n <= 1'b1;
        end else begin

            if (!JP5) begin
                if (e_counter == 'd3) begin
                    VMA_n <= CPUSPACE;
                end
            end else begin
                if (!E) begin
                    VMA_n <= CPUSPACE;
                end
            end

        end

    end

end

// Generate /DTACK if 6800 Bus Cycle has been emulated.
always @(negedge RESET_n or negedge C7M or posedge AS_CPU_n) begin

    if (!RESET_n) begin
        M6800_DTACK_n <= 1'b1;
    end else begin

        if (AS_CPU_n) begin
            M6800_DTACK_n <= 1'b1;
        end else begin

            if (!JP5) begin
                if (e_counter == 'd9) begin
                    M6800_DTACK_n <= VMA_n;
                end
            end else begin
                if (E) begin
                    M6800_DTACK_n <= VMA_n;
                end
            end

        end
    end

end

endmodule
