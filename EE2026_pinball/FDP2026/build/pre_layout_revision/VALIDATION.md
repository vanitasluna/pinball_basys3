# Validation - 13 October 2026 (Asia/Singapore)

The polished design was built with Vivado 2025.2 for xc7a35tcpg236-1. Bitstream generation completed at 18:05:13. The programming file is `build/pinball_basys3.bit` (1,166,883 bytes); the authoritative batch log is `build/polished.log`.

## Routed implementation

- Setup worst slack: **+1.061 ns**; setup total negative slack: 0.000 ns; zero failing endpoints.
- Hold worst slack: **+0.039 ns**; hold total negative slack: 0.000 ns; zero failing endpoints.
- DRC: zero errors. Seven advisory warnings recommend pipelining the two native graphics DSPs. The current combinational graphics paths meet their timing constraints. Bitstream generation completed successfully.
- Final batch build: zero errors and zero critical warnings. Ordinary synthesis warnings include trimmed unused bits and the supplied OLED driver's zero-width replication expression; no protected driver was edited.
- No unconstrained internal endpoints. Collision snapshot paths use scoped setup-16/hold-15 constraints; only asynchronous physical outputs use the explicit 100 ns propagation bound. The forwarded OLED SCLK is a clock output, not a pixel-data endpoint.
- Vivado opened the saved XPR and verified the design top, FPGA part, implementation-only timing file, default simulation top, simulation timescale/runtime and compile order with the new modules.

| Resource | Used / available | Utilization |
| --- | --- | --- |
| Slice LUTs | 11574 / 20800 | 55.64% |
| Slice Registers | 2354 / 41600 | 5.66% |
| DSPs | 2 / 90 | 2.22% |
| Block RAM Tile | 0 / 50 | 0.00% |
| Bonded IOB | 60 / 106 | 56.60% |
| BUFGCTRL | 3 / 32 | 9.38% |

LUT use increased from **41.71% to 55.64%**, a rise of 13.93 percentage points. The additional logic implements native VGA graphics, animation, particle/trail state and arcade rules. The prior working source and bitstream remain under `build/baseline/`.

VGA renders at native 640 x 480 with independent detail and Q8 subpixel ball positioning; it shares game state with the compact 96 x 64 OLED renderer. The pixel clock remains 25 MHz with an 800 x 525 total frame (approximately 59.52 Hz). Game logic runs at 100 MHz, physics at a 240 Hz enable, and OLED at 6.25 MHz.

## Simulation and source integrity

| Bench | Result and coverage |
| --- | --- |
| tb_input | PASS: bounce rejection, independent simultaneous inputs, settling and one-cycle press events |
| tb_game | PASS: FSM, charge, x1-x4 combo/expiry, bumper mission, target-pair reward, finite launch/target saves, consecutive pipelined scores, late pause hits/drains, nudge feedback, lives, saturation, restart and high score |
| tb_physics | PASS: 11,400 assertions; minimum/full launch on all three difficulties, lane exit, eventual idle drains, pause, bounded velocity, flippers, scoring rearm, exact 16-clock commit, isolated operands, prepare cancellation, queued nudge and fractional coordinates |
| tb_collision | PASS: 18 focused checks covering walls, all bumper/target event bits, moving/resting flippers, guides and below-surface rejection |
| tb_vga | PASS: full 800 x 525 frame, sync widths, native 640 x 480 coordinates, RGB565 conversion and porch blanking |
| tb_renderer | PASS: six complete 96 x 64 RGB565 screens; 36,864 pixels without unknown values; feature lamps, rings, trails, glossy ball and ball visibility over award cards/text |
| tb_effects | PASS: eight-particle bursts, fractional native trail mapping, ballistic motion, pause, lifetime expiry and prepare clearing |
| tb_vga_renderer | PASS: six complete 640 x 480 RGB565 screens; 1,843,200 pixels without unknown values; circle edges, Q8 positioning, actual x4 glyph, ball visibility over cards/text/particles and no stale point awards on save/nudge notifications |
| tb_top | PASS: real mixed Verilog/VHDL protected drivers, power-on reset, mouse configuration, completed-packet click dispatch, JA mapping, 25 OLED SPI setup commands, initial pixels and absent-mouse fallback |

The three supplied driver SHA-256 hashes match their original values. `scripts/verify_project.py` checks those hashes, the part and registered source paths. `build/manifest.json` records final source, testbench, simulation log and bitstream hashes, timing margins and resource use.

`docs/display_preview.png`, `docs/vga_preview.png` and `docs/dual_display_preview.png` contain pixels from the actual RTL renderers, visually inspected after the final rendering fixes. The two renderer benches use independent demonstration fixtures.

The top bench accelerates long OLED waits through testbench force/release. This preserves the protected source and tests command/pixel sequencing; it does not prove physical power sequencing delays. Mouse click dispatch tests abstract complete controller packets; a real USB HID mouse still needs a board check.

## Still requiring the physical board

No Basys 3 was programmed in this session. Verify OLED connector orientation and startup, actual game feel, all controls, combos/missions, target and launch saves, nudge cooldown, three unsaved drains, high-score retention, mouse compatibility, and optional VGA-to-HDMI conversion. The high score is session memory and resets with SW15 or power cycling.
