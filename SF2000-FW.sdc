####################################################################################
# SF2000 Accelerator - Comprehensive Timing Constraints
####################################################################################

####################################################################################
# CLOCK DEFINITIONS
####################################################################################

# External input clocks
create_clock -period 140.00 -name C7M_n -waveform {0 70} [get_ports C7M_n]
create_clock -period 50.00 -name OSC_CLK -waveform {0 25} [get_ports OSC_CLK]

# PLL output clocks (assuming 20 MHz crystal input)
# PLL config: 20 MHz * 80 / 2 = 800 MHz internal VCO
# CLKOUT0: 800 MHz / 9 ≈ 88.89 MHz
# CLKOUT1: 800 MHz / 8 = 100 MHz
create_clock -period 11.236 -name pll_clkout0 [get_ports pll_inst1_CLKOUT0]
create_clock -period 10.00 -name pll_clkout1 [get_ports pll_inst1_CLKOUT1]

# Generated clock - turbo_clk is divided from pll_clkout0
# This is the ~44.44 MHz CPU clock in turbo mode
create_generated_clock -name turbo_clk \
    -source [get_ports pll_inst1_CLKOUT0] \
    -divide_by 2 \
    [get_registers {turbo_clk}]

####################################################################################
# CLOCK GROUPS - Define Asynchronous Clock Domains
####################################################################################

# These clock domains are asynchronous to each other
set_clock_groups -asynchronous \
    -group {C7M_n} \
    -group {pll_clkout0 turbo_clk} \
    -group {pll_clkout1}

####################################################################################
# INPUT TIMING CONSTRAINTS
####################################################################################

# 68000 Bus Signals (referenced to C7M)
# Based on 68000 timing: Address valid to AS low = ~50ns
# AS low to Data valid = ~70ns at 7.14 MHz
set_input_delay -clock C7M_n -max 20.0 [get_ports {A[*]}]
set_input_delay -clock C7M_n -min 0.0 [get_ports {A[*]}]

set_input_delay -clock C7M_n -max 15.0 [get_ports {D_IN[*]}]
set_input_delay -clock C7M_n -min 0.0 [get_ports {D_IN[*]}]

set_input_delay -clock C7M_n -max 10.0 [get_ports {RW_n UDS_n LDS_n AS_CPU_n AS_MB_n_IN}]
set_input_delay -clock C7M_n -min 0.0 [get_ports {RW_n UDS_n LDS_n AS_CPU_n AS_MB_n_IN}]

set_input_delay -clock C7M_n -max 15.0 [get_ports {FC[*]}]
set_input_delay -clock C7M_n -min 0.0 [get_ports {FC[*]}]

# Control signals
set_input_delay -clock C7M_n -max 15.0 [get_ports {VPA_n DTACK_MB_n}]
set_input_delay -clock C7M_n -min 0.0 [get_ports {VPA_n DTACK_MB_n}]

# Bus arbitration signals
set_input_delay -clock C7M_n -max 15.0 [get_ports {BR_n_IN BG_n_IN BGACK_n BG_68SEC000_n}]
set_input_delay -clock C7M_n -min 0.0 [get_ports {BR_n_IN BG_n_IN BGACK_n BG_68SEC000_n}]

# E clock input
set_input_delay -clock C7M_n -max 15.0 [get_ports E_IN]
set_input_delay -clock C7M_n -min 0.0 [get_ports E_IN]

# BOSS detection
set_input_delay -clock C7M_n -max 20.0 [get_ports BOSS_n_IN]
set_input_delay -clock C7M_n -min 0.0 [get_ports BOSS_n_IN]

# Configuration inputs (static, can be relaxed)
set_input_delay -clock C7M_n -max 50.0 [get_ports {CFGIN_n}]
set_input_delay -clock C7M_n -min 0.0 [get_ports {CFGIN_n}]

# SD Card signals (referenced to pll_clkout1 = 100 MHz)
set_input_delay -clock pll_clkout1 -max 5.0 [get_ports {SD_MISO SD_CD_n}]
set_input_delay -clock pll_clkout1 -min 0.0 [get_ports {SD_MISO SD_CD_n}]

# Reset (asynchronous, but add constraint for coverage)
set_input_delay -clock C7M_n -max 20.0 [get_ports RESET_n]
set_input_delay -clock C7M_n -min 0.0 [get_ports RESET_n]

# Jumper settings (static)
set_false_path -from [get_ports {JP1 JP2 JP3 JP4}]

####################################################################################
# OUTPUT TIMING CONSTRAINTS
####################################################################################

# 68000 Bus Outputs
# DTACK must meet 68000 setup time: ~30ns before AS rising edge
set_output_delay -clock C7M_n -max 15.0 [get_ports DTACK_CPU_n]
set_output_delay -clock C7M_n -min -5.0 [get_ports DTACK_CPU_n]

# Data bus outputs
set_output_delay -clock C7M_n -max 20.0 [get_ports {D_OUT[*] D_OE[*]}]
set_output_delay -clock C7M_n -min -5.0 [get_ports {D_OUT[*] D_OE[*]}]

# AS to motherboard
set_output_delay -clock C7M_n -max 15.0 [get_ports {AS_MB_n_OUT AS_MB_n_OE}]
set_output_delay -clock C7M_n -min -5.0 [get_ports {AS_MB_n_OUT AS_MB_n_OE}]

# Bus arbitration outputs
set_output_delay -clock C7M_n -max 15.0 [get_ports {BR_68SEC000_n BR_n_OUT BR_n_OE BG_n_OUT BG_n_OE}]
set_output_delay -clock C7M_n -min -5.0 [get_ports {BR_68SEC000_n BR_n_OUT BR_n_OE BG_n_OUT BG_n_OE}]

# E clock output
set_output_delay -clock C7M_n -max 15.0 [get_ports {E_OUT E_OE}]
set_output_delay -clock C7M_n -min -5.0 [get_ports {E_OUT E_OE}]

# VMA output
set_output_delay -clock C7M_n -max 15.0 [get_ports VMA_n]
set_output_delay -clock C7M_n -min -5.0 [get_ports VMA_n]

# BOSS output
set_output_delay -clock C7M_n -max 15.0 [get_ports {BOSS_n_OUT BOSS_n_OE}]
set_output_delay -clock C7M_n -min -5.0 [get_ports {BOSS_n_OUT BOSS_n_OE}]

# CPU clock output (can be either C7M or turbo_clk)
# Using max constraint for worst case
set_output_delay -clock C7M_n -max 10.0 [get_ports CLKCPU]
set_output_delay -clock C7M_n -min -5.0 [get_ports CLKCPU]

# SRAM control signals (fast outputs, minimal delay)
set_output_delay -clock turbo_clk -max 5.0 [get_ports {OE_BANK0_n OE_BANK1_n}]
set_output_delay -clock turbo_clk -min -2.0 [get_ports {OE_BANK0_n OE_BANK1_n}]

set_output_delay -clock turbo_clk -max 5.0 [get_ports {WE_BANK0_ODD_n WE_BANK1_ODD_n WE_BANK0_EVEN_n WE_BANK1_EVEN_n}]
set_output_delay -clock turbo_clk -min -2.0 [get_ports {WE_BANK0_ODD_n WE_BANK1_ODD_n WE_BANK0_EVEN_n WE_BANK1_EVEN_n}]

# Flash control signals
set_output_delay -clock turbo_clk -max 8.0 [get_ports {FLASH_A19 FLASH_WE_n FLASH_OE_n ROM_OE_n}]
set_output_delay -clock turbo_clk -min -2.0 [get_ports {FLASH_A19 FLASH_WE_n FLASH_OE_n ROM_OE_n}]

# SD Card SPI signals (referenced to pll_clkout1 = 100 MHz)
set_output_delay -clock pll_clkout1 -max 5.0 [get_ports {SD_SS_n SD_SCLK SD_MOSI}]
set_output_delay -clock pll_clkout1 -min -2.0 [get_ports {SD_SS_n SD_SCLK SD_MOSI}]

# Interrupt output
set_output_delay -clock pll_clkout1 -max 8.0 [get_ports INT2_n]
set_output_delay -clock pll_clkout1 -min -2.0 [get_ports INT2_n]

# Config out
set_output_delay -clock C7M_n -max 15.0 [get_ports CFGOUT_n]
set_output_delay -clock C7M_n -min -5.0 [get_ports CFGOUT_n]

####################################################################################
# FALSE PATHS
####################################################################################

# Asynchronous resets
set_false_path -from [get_ports RESET_n] -to [all_registers]

# Static configuration signals
set_false_path -from [get_ports {JP1 JP2 JP3 JP4}] -to [all_registers]

# Cross-domain signals that have proper synchronizers
# (Add these after implementing synchronizers in the design)
# set_false_path -from [get_clocks C7M_n] -to [get_clocks pll_clkout1]
# set_false_path -from [get_clocks pll_clkout1] -to [get_clocks C7M_n]

####################################################################################
# MULTICYCLE PATHS
####################################################################################

# SD card interface has slower timing requirements
# Can use 2-cycle paths for some signals if needed
# set_multicycle_path -setup 2 -from [get_clocks pll_clkout1] -to [get_ports {SD_*}]
# set_multicycle_path -hold 1 -from [get_clocks pll_clkout1] -to [get_ports {SD_*}]

####################################################################################
# DESIGN CONSTRAINTS
####################################################################################

# Maximum transition time (to avoid signal integrity issues)
set_max_transition 2.0 [current_design]

# Maximum fanout (to ensure proper drive strength)
set_max_fanout 20 [current_design]

# Maximum capacitance
set_max_capacitance 0.5 [all_outputs]

####################################################################################
# NOTES FOR DESIGNER
####################################################################################
# 
# 1. After implementing clock domain crossing synchronizers, uncomment and
#    refine the false path constraints between clock domains
#
# 2. Verify that all critical paths meet timing in both 7MHz and turbo modes
#
# 3. Pay special attention to setup/hold violations in the synthesis report
#
# 4. The SRAM control signals (OE/WE) have tight timing - may need adjustment
#    based on actual SRAM part specifications
#
# 5. Consider adding timing exceptions for specific paths if needed after
#    initial timing analysis
#
####################################################################################
