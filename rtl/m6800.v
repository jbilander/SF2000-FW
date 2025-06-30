`timescale 1ns / 1ps

module m6800(
    input wire JP2,
    input wire C7M,
    input wire RESET_n,
    input wire VPA_n,
    input wire CPUSPACE,
    input wire AS_CPU_n,
    input wire E_IN,
    output reg E_OUT,
    output reg VMA_n = 1'b1,
    output reg M6800_DTACK_n = 1'b1
);

reg e = 1'b1;               //used for syncing e_cnt (JP2 open)
reg [3:0] e_cnt;            //counter for incoming E (JP2 open)
reg [3:0] e_counter = 'd5;  //counter for generating E (JP2 closed)

always @(negedge C7M) begin

    if (e_counter == 'd5) begin
        E_OUT <= 1'b1;
    end

    if (e_counter == 'd9) begin
        e_counter <= 'd0;
        E_OUT <= 1'b0;
    end else begin
        e_counter <= e_counter + 1'b1;
    end

end

//syncs e_cnt on falling edge of incoming E (JP2 open)
always @(negedge E_IN) begin
    e <= 1'b0;
end

//This is for when incoming E is being used (JP2 open)
always @(negedge C7M) begin

    if (!e) begin
        if (e_cnt == 'd9) begin
            e_cnt <= 'd0;
        end else begin
            e_cnt <= e_cnt + 1'b1;
        end
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

            if (!JP2) begin
                if (e_counter == 'd3) begin
                    VMA_n <= CPUSPACE;
                end
            end else begin
                if (e_cnt == 'd3) begin
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

            if (!JP2) begin
                if (e_counter == 'd9) begin
                    M6800_DTACK_n <= VMA_n;
                end
            end else begin
                if (e_cnt == 'd9) begin
                    M6800_DTACK_n <= VMA_n;
                end
            end

        end
    end

end


endmodule
