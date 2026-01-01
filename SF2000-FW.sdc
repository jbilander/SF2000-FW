# SF2000 Accelerator - Timing Constraints
# Efinity has limited SDC support - only basic create_clock is supported
# PLL clocks are derived automatically from SF2000-FW_peri.xml

# Amiga 7MHz bus clock (actual period = 140ns = 7.14 MHz)
create_clock -period 140.00 C7M_n