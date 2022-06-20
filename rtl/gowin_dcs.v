//Copyright (C)2014-2022 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.8.05
//Part Number: GW1N-UV9LQ144C6/I5
//Device: GW1N-9
//Created Time: Sun Jun 19 16:28:00 2022

module Gowin_DCS (clkout, clksel, clk0, clk1, clk2, clk3);

output clkout;
input [3:0] clksel;
input clk0;
input clk1;
input clk2;
input clk3;

wire gw_gnd;

assign gw_gnd = 1'b0;

DCS dcs_inst (
    .CLKOUT(clkout),
    .CLKSEL(clksel),
    .CLK0(clk0),
    .CLK1(clk1),
    .CLK2(clk2),
    .CLK3(clk3),
    .SELFORCE(gw_gnd)
);

defparam dcs_inst.DCS_MODE = "RISING";

endmodule //Gowin_DCS
