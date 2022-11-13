`timescale 1ns / 1ps

module clock(
    input C7M,
    input OSC_CLK_X1,
    input RESET_n,
    input CPU_SPEED_SWITCH,
    input JP2,
    input JP3,
    input JP4,
    input AS_CPU_n,
    input DTACK_CPU_n,
    output CLKCPU
);

reg [3:0] clksel0 = 4'b0001;
reg [3:0] clksel1 = 4'b0001;

wire [2:0] clksel = {JP2, JP3, JP4};
wire dcs0_out; //dynamic clock selector 0
wire dcs1_out; //dynamic clock selector 1
wire clk_turbo = JP2 ? dcs1_out : dcs0_out;
wire C14M;
wire C21M;
wire C28M;
wire C33M;
wire C42M;
wire C50M;
wire C100M;

//assign CLKCPU = CPU_SPEED_SWITCH ? C7M : clk_turbo;

assign CLKCPU = C7M;

always @(posedge C7M) begin

    case (clksel)

      3'b000: clksel0 <= 4'b0001; //Internal Oscillator CLK
      3'b001: clksel0 <= 4'b0010; //C14M
      3'b010: clksel0 <= 4'b0100; //C21M
      3'b011: clksel0 <= 4'b1000; //C28M
      3'b100: clksel1 <= 4'b0001; //C33M
      3'b101: clksel1 <= 4'b0010; //C42M
      3'b110: clksel1 <= 4'b0100; //C50M
      3'b111: clksel1 <= 4'b1000; //Oscillator CLK

      default: begin
                clksel0 <= 4'b0001; //C7M
                clksel1 <= 4'b0001; //C33M
               end

    endcase

end

//dynamic clock selector (DCS)
Gowin_DCS dcs0(
    .clkout(dcs0_out),  //output clkout
    .clksel(clksel0),   //input [3:0] clksel
    .clk0(C7M),         //input 4'b0001
    .clk1(C14M),        //input 4'b0010
    .clk2(C21M),        //input 4'b0100
    .clk3(C28M)         //input 4'b1000
);

//dynamic clock selector (DCS)
Gowin_DCS dcs1(
    .clkout(dcs1_out),  //output clkout
    .clksel(clksel1),   //input [3:0] clksel
    .clk0(C33M),        //input 4'b0001
    .clk1(C42M),        //input 4'b0010
    .clk2(C50M),        //input 4'b0100
    .clk3(OSC_CLK_X1)   //input 4'b1000
);

//PLL
Gowin_rPLL_6x gen_C14M_C21M_and_C42M(
    .clkout(C42M),
    .clkoutd(C21M),
    .clkoutd3(C14M),
    .reset(!RESET_n),
    .clkin(C7M)
);


Gowin_rPLL gen_C33M_C50M_and_C100M(
    .clkout(C100M), //output clkout
    .clkoutd(C50M), //output clkoutd
    .clkoutd3(C33M), //output clkoutd3
    .reset(!RESET_n), //input reset
    .clkin(OSC_CLK_X1) //input clkin
);


//DIV with 3.5
Gowin_CLKDIV_100M_to_28M gen_C28M(
    .clkout(C28M),
    .hclkin(OSC_CLK_X1),
    .resetn(RESET_n)
);

endmodule
