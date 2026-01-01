`timescale 1ns / 1ps

module fastram(
    input wire CLKCPU,
    input wire RESET_n,
    input wire [23:21] A,
    input wire JP4,
    input wire RW_n,
    input wire UDS_n,
    input wire LDS_n,
    input wire AS_CPU_n,
    input wire AS_n,
    input wire DS_n,
    input wire [7:5] BASE_RAM,
    input wire RAM_CONFIGURED_n,
    input wire CPU_SPEED_SWITCH,
    output reg OE_BANK0_n = 1'b1,
    output reg OE_BANK1_n = 1'b1,
    output reg WE_BANK0_ODD_n = 1'b1,
    output reg WE_BANK1_ODD_n = 1'b1,
    output reg WE_BANK0_EVEN_n = 1'b1,
    output reg WE_BANK1_EVEN_n = 1'b1,
    output wire RAM_ACCESS,
    output reg DTACK_n = 1'b1
);

/*
Amiga memory map Z2-space:

              A 23  22  21
200000-3FFFFF    0   0   1  // 2MB
400000-5FFFFF    0   1   0  // 2MB
600000-7FFFFF    0   1   1  // 2MB
800000-9FFFFF    1   0   0  // 2MB
*/

// Address decoding (combinatorial)
wire first_4MB_access  = !AS_n && !RAM_CONFIGURED_n && ( (A == BASE_RAM) || (A == (BASE_RAM + 3'b001)) );
wire second_4MB_access = !AS_n && !RAM_CONFIGURED_n && JP4 && ( (A == (BASE_RAM + 3'b010)) || (A == (BASE_RAM + 3'b011)) );

assign RAM_ACCESS = JP4 ? (first_4MB_access || second_4MB_access) : first_4MB_access;

// Synchronize AS_CPU_n to CLKCPU domain
reg [2:0] as_cpu_n_sync;
wire as_cpu_n_sync_out = as_cpu_n_sync[2];
wire as_cpu_n_rising = (as_cpu_n_sync[2:1] == 2'b01);
wire as_cpu_n_falling = (as_cpu_n_sync[2:1] == 2'b10);

always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        as_cpu_n_sync <= 3'b111;
    end else begin
        as_cpu_n_sync <= {as_cpu_n_sync[1:0], AS_CPU_n};
    end
end

// DTACK generation with programmable wait states
reg [1:0] wait_states;
reg [1:0] wait_counter;

// Configure wait states based on CPU speed
// Turbo mode needs wait states for SRAM access
// 7MHz mode can use zero wait states
always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        wait_states <= 2'd0;
    end else begin
        wait_states <= CPU_SPEED_SWITCH ? 2'd1 : 2'd0;
    end
end

// DTACK state machine
localparam DTACK_IDLE = 2'b00;
localparam DTACK_WAIT = 2'b01;
localparam DTACK_ASSERTED = 2'b10;

reg [1:0] dtack_state;

always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        DTACK_n <= 1'b1;
        wait_counter <= 2'd0;
        dtack_state <= DTACK_IDLE;
    end else begin
        case (dtack_state)
            DTACK_IDLE: begin
                DTACK_n <= 1'b1;
                wait_counter <= 2'd0;
                if (!as_cpu_n_sync_out && RAM_ACCESS) begin
                    dtack_state <= DTACK_WAIT;
                end
            end
            
            DTACK_WAIT: begin
                if (wait_counter >= wait_states) begin
                    DTACK_n <= 1'b0;
                    dtack_state <= DTACK_ASSERTED;
                end else begin
                    wait_counter <= wait_counter + 2'd1;
                    DTACK_n <= 1'b1;
                end
            end
            
            DTACK_ASSERTED: begin
                DTACK_n <= 1'b0;
                if (as_cpu_n_rising) begin
                    DTACK_n <= 1'b1;
                    dtack_state <= DTACK_IDLE;
                end
            end
            
            default: begin
                dtack_state <= DTACK_IDLE;
                DTACK_n <= 1'b1;
            end
        endcase
        
        // Override: Always deassert DTACK when AS goes high or no RAM access
        if (as_cpu_n_rising || !RAM_ACCESS) begin
            DTACK_n <= 1'b1;
            wait_counter <= 2'd0;
            dtack_state <= DTACK_IDLE;
        end
    end
end

// Output enable and write enable generation (registered for better timing)
always @(posedge CLKCPU) begin
    if (!RESET_n) begin
        OE_BANK0_n <= 1'b1;
        OE_BANK1_n <= 1'b1;
        WE_BANK0_ODD_n <= 1'b1;
        WE_BANK1_ODD_n <= 1'b1;
        WE_BANK0_EVEN_n <= 1'b1;
        WE_BANK1_EVEN_n <= 1'b1;
    end else begin
        // Output enables (for reads)
        OE_BANK0_n <= !(first_4MB_access && RW_n && !DS_n && !as_cpu_n_sync_out);
        OE_BANK1_n <= !(second_4MB_access && RW_n && !DS_n && !as_cpu_n_sync_out);
        
        // Write enables (for writes)
        // Note: WE should be asserted when DS is valid and RW is low
        WE_BANK0_ODD_n <= !(first_4MB_access && !RW_n && !LDS_n && !as_cpu_n_sync_out);
        WE_BANK1_ODD_n <= !(second_4MB_access && !RW_n && !LDS_n && !as_cpu_n_sync_out);
        WE_BANK0_EVEN_n <= !(first_4MB_access && !RW_n && !UDS_n && !as_cpu_n_sync_out);
        WE_BANK1_EVEN_n <= !(second_4MB_access && !RW_n && !UDS_n && !as_cpu_n_sync_out);
    end
end

endmodule
