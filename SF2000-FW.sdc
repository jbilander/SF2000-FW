# ============================================================================
# SF2000-FW.sdc
#
# Three clock domains once the PLL is back:
#   C7M_n              7.09 MHz PAL / 7.16 MHz NTSC, from CCK^CCKQ via U7.
#                      Constrained at the NTSC period, the shorter of the two.
#   pll_inst1_CLKOUT1  100 MHz, sdcard.v's C100M.
#   pll_inst1_CLKOUT0   80 MHz, halved in fabric to 40 MHz for turbo (M5).
#
# C7M is on GPIOL_24_CLK0, which reaches the global clock tree but is NOT a
# PLL reference input, so the PLL free-runs against it. set_clock_groups here
# is load-bearing, not boilerplate: every handshake between the SD block and
# the bus is a genuine clock-domain crossing.
# ============================================================================

create_clock -period 139.50 C7M_n
create_clock -period  10.00 -name c100m [get_ports {pll_inst1_CLKOUT1}]

set_clock_groups -asynchronous \
    -group {C7M_n} \
    -group {c100m}

# c80m stays commented until M5 gives it a consumer. Nothing uses CLKOUT0 yet,
# so it is swept out of the netlist and this would report "No ports matched".
# create_clock -period 12.50 -name c80m [get_ports {pll_inst1_CLKOUT0}]
# (and add c80m to the set_clock_groups above)


# ---- combinational pin-to-pin paths ----------------------------------------
# Neither touches a flop, so STA ignores them unless asked. AS must reach the
# motherboard early in S2, and Gary's DTACK must get back to the CPU before
# its S4 falling-edge sample. Both have ~70 ns of real margin at 7 MHz; 20 ns
# is a generous ceiling that will still flag a bad placement. Currently 3.6 ns
# and 4.0 ns.
set_max_delay 20.0 -from [get_ports {AS_CPU_n}]      -to [get_ports {AS_MB_n_OUT}]
set_max_delay 20.0 -from [get_ports {DTACK_MB_n_IN}] -to [get_ports {DTACK_CPU_n}]


# ---- asynchronous inputs ---------------------------------------------------
# VPA, DTACK, BG and RESET come from Gary/Buster on the machine's own clock and
# all enter through 2-stage synchronisers. Left commented because without
# set_input_delay on these ports the analyser is not looking at them anyway.
#
# set_false_path -from [get_ports {VPA_n}]
# set_false_path -from [get_ports {DTACK_MB_n_IN}]
# set_false_path -from [get_ports {BG_n_IN}]
# set_false_path -from [get_ports {RESET_n_IN}]


# ---- M5, turbo -------------------------------------------------------------
# turbo_clk is c80m halved by a fabric flop. create_clock rather than
# create_generated_clock because Efinity cannot trace the latter through the
# global clock buffer from the PLL output to that FF.
#
# create_clock -period 25.00 -name turbo_clk [get_pins {turbo_clk~FF|Q}]
# (and add turbo_clk to the set_clock_groups above)

# ---- M3 leftovers, no longer needed ----------------------------------------
# The autoconfig registers are quasi-static but no longer sit on a path that
# needs excluding; fastram's decode is combinational from the address.
#
# set_false_path -from [get_cells {base_ram[*]~FF}]
# set_false_path -from [get_cells {ram_configured_n~FF}]
# set_false_path -from [get_cells {sd_configured_n~FF}]
