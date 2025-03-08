create_clock -name C100M -period 10 -waveform {0 5} [get_ports {OSC_CLK_X1}]
create_clock -name C7M -period 141.044 -waveform {0 70.522} [get_ports {C7M}]
set_clock_groups -exclusive -group [get_clocks {C7M}] -group [get_clocks {C100M}]
