//Copyright (C)2014-2022 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.8.05
//Part Number: GW1N-UV9LQ144C6/I5
//Device: GW1N-9
//Created Time: Mon Jun 20 15:25:35 2022

module Gowin_CLKDIV_100M_to_28M (clkout, hclkin, resetn);

output clkout;
input hclkin;
input resetn;

wire gw_gnd;

assign gw_gnd = 1'b0;

CLKDIV clkdiv_inst (
    .CLKOUT(clkout),
    .HCLKIN(hclkin),
    .RESETN(resetn),
    .CALIB(gw_gnd)
);

defparam clkdiv_inst.DIV_MODE = "3.5";
defparam clkdiv_inst.GSREN = "false";

endmodule //Gowin_CLKDIV_100M_to_28M
