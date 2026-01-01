`timescale 1ns / 1ps

module m6800(
    input wire JP2,
    input wire C7M,
    input wire RESET_n,
    input wire VPA_n,
    input wire CPUSPACE,
    input wire AS_CPU_n,
    input wire E_IN,
    output reg E_OUT = 1'b1,
    output reg VMA_n = 1'b1,
    output reg M6800_DTACK_n = 1'b1
);

/*
E Clock Generation and 6800 Bus Cycle Emulation

The E clock is a 709 kHz (approximately) clock used for 6800-style peripherals.
It's derived from 7.09 MHz C7M by dividing by 10.

E clock phases:
- Counts 0-4: E is high
- Counts 5-9: E is low

VMA (Valid Memory Address) is asserted at count 3 during a valid 6800 cycle
DTACK is asserted at count 9 (end of E low) during a valid 6800 cycle

JP2 closed: Generate E internally
JP2 open:   Synchronize to external E
*/

// E clock generation counter
reg [3:0] e_counter;
reg [3:0] e_cnt;

// Synchronize external E clock
reg [2:0] e_in_sync;
wire e_in_stable = e_in_sync[2];
wire e_falling_edge = (e_in_sync[2:1] == 2'b10);
wire e_rising_edge = (e_in_sync[2:1] == 2'b01);

// Synchronize VPA_n
reg [2:0] vpa_n_sync;
wire vpa_n_stable = vpa_n_sync[2];
wire vpa_asserted = !vpa_n_stable;

// Synchronize AS_CPU_n
reg [2:0] as_cpu_n_sync;
wire as_cpu_n_stable = as_cpu_n_sync[2];
wire as_asserted = !as_cpu_n_stable;
wire as_rising = (as_cpu_n_sync[2:1] == 2'b01);

// 6800 cycle detection
reg in_6800_cycle;

// Synchronizers
always @(posedge C7M) begin
    if (!RESET_n) begin
        e_in_sync <= 3'b111;
        vpa_n_sync <= 3'b111;
        as_cpu_n_sync <= 3'b111;
    end else begin
        e_in_sync <= {e_in_sync[1:0], E_IN};
        vpa_n_sync <= {vpa_n_sync[1:0], VPA_n};
        as_cpu_n_sync <= {as_cpu_n_sync[1:0], AS_CPU_n};
    end
end

// E clock generation (when JP2 is closed - internal E generation)
always @(posedge C7M) begin
    if (!RESET_n) begin
        e_counter <= 4'd5;
        E_OUT <= 1'b1;
    end else begin
        if (e_counter == 4'd9) begin
            e_counter <= 4'd0;
        end else begin
            e_counter <= e_counter + 4'd1;
        end
        
        // E_OUT transitions
        if (e_counter == 4'd5) begin
            E_OUT <= 1'b0;  // Start of E low period
        end else if (e_counter == 4'd0) begin
            E_OUT <= 1'b1;  // Start of E high period
        end
    end
end

// E clock counter synchronization (when JP2 is open - external E)
// Synchronize internal counter to external E clock falling edge
always @(posedge C7M) begin
    if (!RESET_n) begin
        e_cnt <= 4'd0;
    end else begin
        if (e_falling_edge) begin
            // Sync to falling edge of external E
            e_cnt <= 4'd5;
        end else if (e_cnt == 4'd9) begin
            e_cnt <= 4'd0;
        end else begin
            e_cnt <= e_cnt + 4'd1;
        end
    end
end

// Select which counter to use based on JP2
wire [3:0] active_count = JP2 ? e_cnt : e_counter;

// 6800 bus cycle state machine
localparam M6800_IDLE = 2'b00;
localparam M6800_VMA_WAIT = 2'b01;
localparam M6800_ACTIVE = 2'b10;

reg [1:0] m6800_state;

always @(posedge C7M) begin
    if (!RESET_n) begin
        m6800_state <= M6800_IDLE;
        in_6800_cycle <= 1'b0;
        VMA_n <= 1'b1;
        M6800_DTACK_n <= 1'b1;
    end else begin
        case (m6800_state)
            M6800_IDLE: begin
                VMA_n <= 1'b1;
                M6800_DTACK_n <= 1'b1;
                in_6800_cycle <= 1'b0;
                
                // Enter 6800 cycle when VPA is asserted and AS is active
                if (vpa_asserted && as_asserted) begin
                    m6800_state <= M6800_VMA_WAIT;
                    in_6800_cycle <= 1'b1;
                end
            end
            
            M6800_VMA_WAIT: begin
                // Assert VMA at count 3
                if (active_count == 4'd3) begin
                    // Only assert VMA if not in CPU space
                    // CPUSPACE is high when FC2-FC0 = 111 (interrupt acknowledge)
                    VMA_n <= CPUSPACE;
                    m6800_state <= M6800_ACTIVE;
                end
                
                // If AS deasserts before VMA, abort
                if (as_rising) begin
                    m6800_state <= M6800_IDLE;
                    in_6800_cycle <= 1'b0;
                end
            end
            
            M6800_ACTIVE: begin
                // Assert DTACK at count 9 (end of E low)
                if (active_count == 4'd9) begin
                    // DTACK follows VMA (only assert if VMA is asserted)
                    M6800_DTACK_n <= VMA_n;
                end
                
                // Exit cycle when AS deasserts
                if (as_rising) begin
                    VMA_n <= 1'b1;
                    M6800_DTACK_n <= 1'b1;
                    m6800_state <= M6800_IDLE;
                    in_6800_cycle <= 1'b0;
                end
            end
            
            default: begin
                m6800_state <= M6800_IDLE;
            end
        endcase
        
        // Override: If VPA deasserts, abort the cycle
        if (!vpa_asserted && in_6800_cycle) begin
            VMA_n <= 1'b1;
            M6800_DTACK_n <= 1'b1;
            m6800_state <= M6800_IDLE;
            in_6800_cycle <= 1'b0;
        end
    end
end

endmodule
