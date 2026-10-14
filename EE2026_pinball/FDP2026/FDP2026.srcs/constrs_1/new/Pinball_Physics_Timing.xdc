# Implementation-only constraints: read after synthesis maps registers.
# Physics snapshots are latched on tick and held unchanged; each collision
# result is captured exactly 16 system-clock edges later. Two-ball mode
# stages its first result, switches operands on a separate clock, then commits
# both after the second 16-clock window. Only these isolated calculation paths
# and their staging/atomically committed state receive
# a multicycle exception; controls retain 10 ns timing.
set collision_sources [get_cells -hierarchical -filter {REF_NAME =~ FD* && NAME =~ physics/collision_*_reg* && NAME !~ physics/collision_busy_reg* && NAME !~ physics/collision_wait_reg*}]
set collision_destinations [get_cells -hierarchical -filter {REF_NAME =~ FD* && (NAME =~ physics/position_*_reg* || NAME =~ physics/position2_*_reg* || NAME =~ physics/velocity_*_reg* || NAME =~ physics/velocity2_*_reg* || NAME =~ physics/stage_*_reg* || NAME =~ physics/pending_hits_reg* || NAME =~ physics/pending_drain_wait_reg* || NAME =~ physics/hit_events_reg* || NAME =~ physics/hit_armed*_reg* || NAME =~ physics/cooldown*_reg* || NAME =~ physics/ball1_in_lane_reg* || NAME =~ physics/ball2_in_lane_reg* || NAME =~ physics/ball1_alive_reg* || NAME =~ physics/ball2_alive_reg* || NAME =~ physics/launched*_reg* || NAME =~ physics/drained_reg* || NAME =~ physics/moving_bumper_y_fp_reg* || NAME =~ physics/moving_bumper_x_fp_reg* || NAME =~ physics/moving_bumper_y_positive_reg* || NAME =~ physics/moving_bumper_x_positive_reg*)}]
set_multicycle_path 16 -setup -from $collision_sources -to $collision_destinations
set_multicycle_path 15 -hold -from $collision_sources -to $collision_destinations

# These outputs have no 100 MHz receiving clock: LEDs/seven-segment are
# human-visible, PMODEN is a power enable, and PS/2 uses an asynchronous
# handshake with microsecond protocol delays in the supplied controller.
# Bound their actual register-to-pin propagation to 100 ns. OLED SPI data
# and VGA remain timed against their synchronous interface clocks below.
set_max_delay 100 -datapath_only -from [get_clocks sys_clk_pin] -to [get_ports {led[*] seg[*] an[*] dp PS2Clk PS2Data JC[7]}]
