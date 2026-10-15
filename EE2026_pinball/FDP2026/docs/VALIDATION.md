# Validation - 2026-10-15 (Asia/Singapore)

The mouse, mascot, moving-side-target and gentler-difficulty revision was routed for Basys 3 xc7a35tcpg236-1 using Vivado 2025.2. Bitstream generation completed at 2026-10-15T13:52:32+08:00. Program `build/pinball_basys3.bit` (1,529,403 bytes). Authoritative build log: `build/experience_final.log`. The preceding working design is preserved under `build/pre_experience/`.

## Routed implementation

- Setup worst slack **+0.101 ns**, hold worst slack **+0.046 ns**; zero failing endpoints and zero unconstrained internal endpoints.
- DRC: zero errors, 177 advisory warnings. Batch build: zero errors or critical warnings.
- One shared collision engine. Setup-16/hold-15 exceptions cover stable collision snapshots and delayed result registers, including side-target world state. Controls retain normal timing. Producer-to-frame scene crossings remain timed.
- Saved Vivado project part, tops, compile order and implementation-only timing file verified. OLED remains on JC; native VGA stays 800x600 at 40 MHz (about 60.317 Hz).

| Resource | Used / available | Utilization |
| --- | --- | --- |
| Slice LUTs | 19024 / 20800 | 91.46% |
| Slice Registers | 3749 / 41600 | 9.01% |
| DSPs | 51 / 90 | 56.67% |
| Block RAM Tile | 0 / 50 | 0.00% |
| Bonded IOB | 60 / 106 | 56.60% |
| BUFGCTRL | 4 / 32 | 12.50% |

Previous LUT utilization: 88.37%. Current: **91.46%**. Registers, DSPs and LUTs are separate limits; routed timing determines whether the revision works at the configured clocks.

## Behavior and regression evidence

Mouse coordinates now retain four raw counts per logical pixel in the supplied controller, giving quarter sensitivity without dropping small motion. Bounds 383/255 and center 192/128 map to logical 95/63 and 48/32. Click regions and held buttons still publish on complete packets. No supplied OLED, mouse or PS/2 source was changed.

The original circuit cat stays visible in MENU, READY, PLAY, PAUSE and OVER, using safe state-specific placement. Idle expressions alternate; fresh reward/nudge/save reactions temporarily override the idle face. Pause/game-over have contextual poses. Live balls, controls and score/lives remain readable. Both renderers consume the same scene state.

Left/right side-target centers travel vertically from y29 to y37, starting at y33 in opposite directions at 3.75 logical pixels/s. Actual rectangle geometry, progress lamps, collision centers, relative surface velocity, cooldown and rearm follow the moving targets. Old/new centers and directions are isolated with each collision transaction. Both balls see the same world step, and the full world commits once after the pair. Reset/preparation restore tracks; pause blocks new movement and permits an accepted calculation to complete.

| Difficulty | Gravity (logical pixels/s²) | Upper downward cap | Lower downward cap (y>=38) |
| --- | --- | --- | --- |
| Easy |112.5|105 pixels/s|45 pixels/s|
| Normal |225|127.5 pixels/s|56.25 pixels/s|
| Hard |450|150 pixels/s|67.5 pixels/s|

Easy alternates 0/1 Q8 gravity once per world step and shares that captured value between balls. Minimum/light/full launch reachability, finite unattended drains, speed limits and reaction-time descent are covered by simulations. Rules, half-point scoring, finite saves, mode selection, flipper timing and launch-power sweep remain intact.

All twelve self-checking suites were rerun on the current source. The recorder checks log freshness against actual dependencies. Exact pass summaries:

| Bench | Result |
| --- | --- |
| tb_input | PASS tb_input: bounce rejection, exact settling, simultaneous independent buttons, single-cycle events, long-interval overflow regression |
| tb_game | PASS tb_game: latched one/two-ball mode, half-point scoring/carry, bouncing charge, fourteen contacts, collections, combos, save, queued scores, simultaneous pause/resume/drain priorities, saturation |
| tb_physics | PASS tb_physics (95262 checks) |
| tb_multiball | PASS tb_multiball (36376 checks) |
| tb_two_ball_game | PASS tb_two_ball_game: 74 checks; selected pair launch, individual awards, fractional carry, pair lives/save, final-batch scoring, pause, menu/reset cancellation |
| tb_collision | PASS tb_collision (106 checks) |
| tb_vga | PASS tb_vga: 1056x628 frame, sync widths, native 800x600 coordinates, RGB565 conversion and porch blanking |
| tb_vga_clock | PASS tb_vga_clock: real MMCM locks, produces 40 MHz and relocks after reset |
| tb_renderer | PASS tb_renderer: persistent six-mood mascot, moving side banks, persistent HUD, independent two-ball visibility/menu/queued sprites, moving bumpers and sixteen complete frames (98304 pixels) |
| tb_effects | PASS tb_effects: two retained impact bursts, completed origins, paused late bursts, clean survivor trail, subpixel motion, expiry, prepare |
| tb_vga_renderer | PASS tb_vga_renderer: persistent six-mood cat, moving side banks, trail/HUD/ball priority, hover/countdown and sixteen complete frames (7680000 pixels) |
| tb_top | PASS tb_top: quarter-speed complete mouse packets, subpixel motion, endpoint clamps, aligned clicks, bounded start/resume/restart widgets, menu mode choice, ignored SW1, held-input rejection, simultaneous U/C capture, pause, survivor trail, paired launch, atomic frames, reset, protected drivers and JC SPI |

A fresh independent rational bumper-segment oracle passed 18,231 checks against the current collision module. Its inputs, bench and log are under `build/experience_geometry_audit/`. New moving rectangle contacts, swept near misses, rearm, bounds and two-ball consistency are exercised in the collision/physics suites. Source, bench, log and bitstream SHA256 hashes are recorded in `build/manifest.json`; the protected three-module hashes match the supplied versions.

Preview PNGs are generated from exact RGB565 renderer dumps. Inspect `docs/dual_display_preview.png`, `docs/display_preview.png`, `docs/vga_preview.png`, `docs/moving_bumpers_preview.png` and `docs/funny_preview.png`. These are deterministic rendered-state samples, not recordings of physical gameplay.

## Final review and physical follow-up

The completed change was reviewed again for signed arithmetic, reset/cancellation, event priority, shared-world timing, renderer clipping/layers, snapshot widths, mouse dispatch and source integrity. Fixes and tests are described in `docs/DESIGN_NOTES.md`.

The user confirmed the previous design works on hardware. This revision was verified in simulation and Vivado; no physical board was programmed during development. Confirm slower pointer feel and edge reachability, all-state cat placement, both moving target tracks, one/two-ball launches and returns on each difficulty, pause/resume and finite saves, OLED startup and VGA-to-HDMI compatibility on the board. SW15 resets high score; SW0 enables mouse; SW1 remains unused.

The 33-page teaching guide is explicitly a 14 October 2026 snapshot. This validation, the current README and RTL describe the revised mouse scaling, persistent cat, target tracks and difficulty profiles.
