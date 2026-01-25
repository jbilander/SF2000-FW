
# PLL Constraints
#################
create_clock -period 140.00 C7M_n

# turbo_clk (25 MHz): PLL 100 MHz / 4, drives CLKCPU in turbo mode.
# Using create_clock because Efinity cannot trace create_generated_clock
# through the global clock buffer from the PLL output to this FF.
create_clock -period 40.00 -name turbo_clk [get_pins {turbo_clk~FF|Q}]

# CDC: Three asynchronous clock domains.
# All cross-domain paths use 2-stage synchronizers — no timing analysis needed.
set_clock_groups -asynchronous \
    -group {C7M_n} \
    -group {turbo_clk} \
    -group {pll_inst1_CLKOUT1}

# False paths: Quasi-static autoconfig registers (C7M domain)
# These only change during boot autoconfig and are completely static
# during normal operation. Eliminates false hold violations on
# base_ram/ram_configured_n → fastram OE/WE paths that waste PnR effort.
# Using get_cells -from (Efinity rejects get_pins |Q as a startpoint).
set_false_path -from [get_cells {base_ram[*]~FF}]
set_false_path -from [get_cells {ram_configured_n~FF}]
set_false_path -from [get_cells {sd_configured_n~FF}]
