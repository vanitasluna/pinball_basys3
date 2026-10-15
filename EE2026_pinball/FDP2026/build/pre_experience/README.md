# EE2026 FPGA Pinball Arcade

Pinball for the Basys 3, targeting **xc7a35tcpg236-1**. The primary display is a **96 x 64 Pmod OLEDrgb on JC**. A simultaneous **native 800 x 600 VGA renderer** draws the same game with crisp curves, a glossy ball, beveled rails, a larger HUD, particles and subpixel motion. The OLED uses a compact renderer of the same live game state. A mouse is optional; every game action is available on the board.

The finalized routed build uses **88.37% of LUTs** (18,380/20,800), **8.56% of registers**, 54 of 90 DSPs and no block RAM. All twelve simulation suites passed, including the reproduced-and-fixed long-interval debounce overflow. An independent geometry oracle passed 18,231 bounded bumper segment checks. Worst setup/hold slack is +0.380/+0.052 ns, with zero failing endpoints. The programming file is `build/pinball_basys3.bit`. Finalization retains the preceding bug-audit build's resource counts and gameplay. See `docs/VALIDATION.md` for review coverage, full reports and pending physical board checks.

The implementation follows the supplied EE2026 proposal's physics, collision, graphics, and game/input components. The proposal's scheduling and member-responsibility text was treated as background. The user's hardware specification determines the OLED display and FPGA part. The supplied `Oled_Display.v`, `Mouse_Control.vhd` (`MouseCtl`), and its `Ps2Interface.vhd` dependency are preserved byte for byte.

## Play

| Control | Action |
| --- | --- |
| Center (C) | Start/restart; hold/release to launch a ready ball; during play, nudge once per two seconds |
| Left / right (L / R) | Corresponding flipper; select difficulty on the menu |
| Up (U) | Menu: toggle one/two balls; during a game: pause/resume |
| Down (D) | Return to menu, preserving the high score |
| SW0 | Enable optional mouse controls |
| SW15 | Full system reset, including OLED startup and high score |
| Mouse left / right | Corresponding flipper during play |
| Mouse middle | Hold/release to charge/launch; click during play to nudge |
| Mouse left on menu | Click the ball-mode row to toggle one/two balls; click difficulty arrows to change level; click Start to begin |
| Mouse left while paused | Click the Resume prompt |
| Mouse left at game over | Click the Restart prompt |

Choose one or two balls in the menu by pressing U or clicking the ball-mode row, then press C to start. The label shows `U: 1 BALL` or `U: 2 BALL`. SW1 has no effect. The menu remembers your choice until full reset; the current game keeps its mode until the next start. Hold C and release it to launch; two-ball mode launches both together with the same selected power. The second ball is gold and enters the table on a slightly different path. Both use the same flippers and nudge. A turn continues until every ball drains; a save restores the selected number of balls, and an unprotected final drain spends one life. There are three lives. Balls pass through each other.

While C is held, the power meter repeatedly rises from 0 to 63 and falls back to 0, taking approximately 1.05 seconds each way (2.1 seconds per full cycle). Release at the power you want; a quick tap or release near zero still gives a useful minimum launch strength of 16. Mouse middle uses the same control. Holding C through the start transition charges immediately. All awards remain ten times smaller than the values used before the two-ball revision. Half-points accumulate internally; the OLED, VGA and seven-segment display show the whole-point total, which still saturates at 9999.

- **Combos:** score another contact within two seconds to grow the multiplier from x1 through x4. Bumpers start at 0.5 points and side targets at 1. After two seconds without a hit, the multiplier returns to x1. Both balls contribute separate scoring transactions.
- **Gold bumper:** the periodically selected gold bumper adds a flat 2.5 points, then the bonus is consumed.
- **Bumper mission:** hit all three bumpers to collect an extra 5 points. The mission lights reset so the reward can be earned again.
- **Side-target pair:** light both side targets to collect an extra 2.5 points and a six-second ball-save window.
- **Launch grace:** each new physical life gets a three-second ball-save window after the ball exits the shooter lane. A saved relaunch does not renew that window. Saving a ball consumes the active save, avoiding an unlimited loop.
- **Top rollover lanes:** pass through all three illuminated arches to earn an extra 3 points. Each lane scores once per visit per ball, and the lamps reset after completion.
- **Stand-up target bank:** hit all three small targets to collect an extra 4 points. They remain solid when lit and reset after the reward.
- **Spinner:** crossing the rotating paddle scores 0.5 base points and starts a short spin animation.
- **Slingshots:** two diamond kickers above the flippers return the ball with an inward impulse and score 0.5 base points.
- **Moving bumpers:** the left bumper travels vertically (x26, y22..28); the right travels horizontally (y22, x58..66). Both move at 3.75 logical pixels/second, and dotted paths mark their travel. The center bumper stays fixed.
- **Nudge:** press C or click the mouse middle button during play to give a small upward and inward impulse. It is limited to once every two seconds and has no effect in the launcher lane.

The ball radius is one OLED pixel (previously two), and the bumper radius is three (previously four). The smaller geometry opens space for nine additional scoring contacts while preserving usable paths between objects. The large screen renders those same shapes with eight native pixels per logical table unit and Q8 ball movement.

The lower playfield limits downward ball speed to about 71 logical pixels per second. An open descent from y38 to the flipper pivots at y53 takes approximately 212.5 ms in the simulation. Flippers complete their raise in four physics ticks (16.7 ms), and the board input debounce is five milliseconds. A fresh press produces a stronger return than holding a raised flipper, allowing timing to matter while keeping descent readable. The upper playfield retains faster upward shots.

A base contact is multiplied by the combo; mission, lane, target-bank, target-pair and gold rewards are added afterward. Score saturates at 9999 and appears on both screens and the four-digit seven-segment display. The best score survives restarts until SW15 or power cycling. Pause freezes physics and feature timers while allowing an already accepted collision transaction to finish.

**Protected balls are bright blue on both displays, with a fading blue trail.** Both balls share that appearance in two-ball mode. When protection expires or is consumed, their normal white/gold colors and ordinary trail return. OLED shows S1 through S6 for the remaining ceiling seconds; native VGA shows SAFE with the same countdown. Pause freezes the protection timer; colors update at each display's frame boundary.

The interface uses navy/violet panels, cyan action borders and hover feedback, gold objectives, and magenta scoring effects. Mode, difficulty and action cards match their mouse regions; board controls remain visible on the prompts. OLED keeps score and hearts visible while its compact award badge replaces only combo/label space. Small lamps show which balls remain alive, while VGA uses a readable mode/survivor chip. Segmented charge gauges, moving rail lights, shaded flippers, subtle circuit patterns, illuminated object rims and fading impact sparks add feedback without changing collision geometry. Two rotating four-spark bursts retain rapid impacts from both balls instead of discarding the previous contact.

An original circuit cat adds short anime-style reactions on both screens: reward cheers, nudge panic and saved-ball relief. It uses a free upper-left table corner, with the saved READY pose shifted down to clear the OLED charge meter. VGA adds YATTA!, NANI! and PHEW! speech bubbles; OLED uses compact animated faces. Reactions last up to half a second of the current notification and stay hidden in menu, pause and game over. The mascot body stays behind trails and objects, and live balls remain above the effects. `docs/funny_preview.png` shows three actual RTL reaction examples.

Mouse clicks only activate the visible mode, difficulty, Start, Resume and Restart regions; clicking the title, score or margins does nothing. Button levels and cursor coordinates are published only after a complete mouse packet. If a drain and pause/resume arrive together, the prepared next life follows the requested pause state. Late impacts retain their effects through pause, and the surviving gold ball starts a clean trail after white drains. Live balls remain visible when the cursor overlaps them. Fast diagonal shots use swept collision checks at stand-up corners and sling tips, so they rebound instead of passing through those solid objects.


LEDs 0-2 show remaining lives; LED3 shows enabled mouse activity; LEDs4-8 show charge; LEDs9-10 show difficulty; LED11 shows an active bonus; LED12 shows the shooter lane; LED13 shows play; LED14 shows pause; LED15 shows game over.

## Connect and program

1. Connect the Pmod OLEDrgb to **JC**, observing the module and board ground/power markings. This design uses the color OLEDrgb, not the monochrome Pmod OLED.
2. Connect the Basys 3 PROG USB port to the PC. Optionally connect a USB HID mouse directly to the board's separate USB-A host port and enable SW0.
3. Open `FDP2026.xpr` in Vivado 2025.2. `My_Top_Module` is the top and the device is `xc7a35tcpg236-1`. All source files and used pins are already registered.
4. Program `build/pinball_basys3.bit` in Hardware Manager when available, or run Generate Bitstream. Allow the OLED startup sequence to finish before expecting a picture.
5. VGA is optional. The output uses 800 x 600 timing, 1056 x 628 total pixels, at 40 MHz (approximately 60.317 Hz). A VGA-to-HDMI converter must support that input timing. The table occupies 768 x 512; the remaining native pixels carry the score, missions, combo/save indicators, and control instructions. Individual native pixels render curved objects and fine text; VGA is no longer a duplicated OLED bitmap. Both screens run simultaneously and share the same gameplay and controls.

| JC signal | Bus bit | FPGA pin |
| --- | --- | --- |
| CS | 0 | K17 |
| SDIN | 1 | M18 |
| Unused, driven low | 2 | N17 |
| SCLK | 3 | P18 |
| D/C | 4 | L17 |
| RESN | 5 | M19 |
| VCCEN | 6 | P17 |
| PMODEN | 7 | R18 |

## Build and verify

From this project directory in PowerShell:

```powershell
$pinballProject=(Get-Location).Path
New-Item -ItemType Directory -Force -Path (Join-Path $pinballProject 'build') | Out-Null
& 'D:\2025.2\Vivado\bin\vivado.bat' -mode batch -source (Join-Path $pinballProject 'scripts/build.tcl') -log (Join-Path $pinballProject 'build/finalization.log') -journal (Join-Path $pinballProject 'build/finalization.jou')
& .\scripts\simulate.ps1
python .\scripts\verify_project.py
python .\scripts\render_previews.py
python .\scripts\record_validation.py --build-log finalization.log
```

Create the `build` directory before choosing log/journal paths there. The batch build does not depend on the original author's desktop path. It reads the mixed Verilog/VHDL sources, synthesizes, applies implementation-only collision constraints after registers are mapped, places, routes, checks setup and hold slack, writes reports and checkpoints, then produces the bitstream. `simulate.ps1` accepts a `-VivadoBin` path if Vivado is installed elsewhere, and `-Tests tb_game` can run an individual bench. All twelve benches are also registered in the project's simulation source set; `tb_top` is the default GUI simulation top. Preview generation requires Pillow. The self-checking tests check game rules, input debouncing, ball movement and collisions, VGA timing, complete renderer frames, and top-level OLED/mouse integration. Top-level simulation can accelerate OLED startup delays without changing the protected source; that test does not measure real power sequencing delays.

See `docs/DESIGN_NOTES.md` for the layout, moving-object integration, game-feel targets, internet references and suggested future features. See `docs/multiball_preview.png`, `docs/display_preview.png`, `docs/vga_preview.png`, and `docs/dual_display_preview.png` and `docs/moving_bumpers_preview.gif` for pixels produced by the actual RTL renderers. `docs/VALIDATION.md` records build results and remaining board checks. The menu-selection build before this bug-fix review is under `build/pre_polish/`. The previous SW1-selected two-ball programming file, checkpoint and reports are under `build/pre_menu_mode/`; the preceding single-ball revision is under `build/pre_multiball/`. The moving-bumper revision before bouncing launch power is under `build/pre_charge_bounce/`; the previous stationary-bumper programming file, checkpoint and reports are under `build/pre_motion/`. The prior JA files are under `build/ja_previous/`. The initial working version is preserved under `build/baseline/`; the previous 55.64% LUT programming file, routed checkpoint and reports are under `build/pre_layout_revision/`.

## Architecture and project knowledge

Read [the detailed code and rebuilding guide](docs/PROJECT_CODE_GUIDE.md), or its [printable PDF](output/pdf/EE2026_Pinball_Code_Guide.pdf), for module connections, EE2026 concepts, worked examples, display timing, verification and a staged plan for writing a new FPGA game. Guide sources and regeneration instructions are in [docs/guide_source](docs/guide_source/README.md).

The routed build before this visual polish is preserved under `build/pre_visual_polish/`, including its programming file, checkpoint, reports, RTL, previews and manifest. The preceding build before blue protection feedback remains under `build/pre_protection_blue/`.

The visual-polish build before circuit-cat reactions is preserved under `build/pre_anime_fx/`, including its programming file, checkpoint, reports, RTL and manifest.

The circuit-cat build before this bug audit is preserved under `build/pre_bug_audit/`, together with the failing reproduction logs. This audit fixes an invisible extension of the right guide beneath its flipper and overlapping trail samples that dimmed fresh motion on both OLED and VGA. All twelve simulation suites were rerun.

The complete design before finalization is preserved under `build/pre_finalization/`. The final review covers all custom RTL, protected interfaces, timing constraints and regression/build scripts. Custom RTL uses explicit ports, scoped rejection of implicit nets, sized state/timing constants and consistent assignment contracts. The reusable input counter now derives its width from the debounce interval, fixing overflow above 2^20 clocks while retaining the board's 5 ms setting. See `docs/DESIGN_NOTES.md` for the coding conventions and `docs/VALIDATION.md` for the final evidence.

| Module | Responsibility |
| --- | --- |
| `My_Top_Module` | Clocks, power-on reset, mouse setup, optional controls, frame snapshots, display integration |
| `pinball_input` | Two-stage button synchronization, independent 5 ms debounce configured by the top, single-cycle press events |
| `pinball_game` | Mode latch, lives, bouncing charge, half-point accumulation and pipelined BCD score, high score, combos, missions, finite saves and spinner animation |
| `pinball_physics` | Shared two-ball Q8 motion/collision scheduling, atomic pair/world commit, separate contact cooldowns, final-ball drains, gravity, speed bounds, flippers and queued nudge |
| `pinball_collision` | Table interactions, relative-velocity/swept bumper contacts, position corrections, bouncing, hit masks |
| `pinball_renderer` | OLED table, 3 x 5 font, glossy ball, impact rings, mission/target lamps, combo/save HUD, trails and award toasts |
| `pinball_vga` | 800 x 600 pixel coordinates, active video, sync and RGB output |
| `pinball_vga_renderer` | Native raster graphics, circle distance circuits, 5 x 7 font, overlays, detailed HUD and feature celebrations |
| `pinball_effects` | Two recent four-spark bursts at corrected contact locations and eight Q8 trail samples, frozen on pause and captured atomically by each display |
| `pinball_sevenseg` | Multiplexed active-low BCD score output |
| Protected supplied modules | OLED SPI/power sequencing and bidirectional PS/2 mouse protocol |

The 100 MHz board oscillator drives all game logic. Physics uses a **240 Hz clock enable**, not a new slow game clock. Each accepted update captures every collision operand, including previous/next moving-bumper centers and velocities, into an isolated register bank. Each ball's operands stay fixed for **16 system clocks (160 ns)** while the shared engine calculates its collision. One-ball motion commits after 16 clocks; a paired update commits both positions and moving-bumper centers/directions together after 33 clocks. Scoped setup-16/hold-15 timing exceptions cover only each isolated calculation; wait counters, controls, and all other paths retain their ordinary timing requirements. Reset or preparing a new ball cancels an outstanding calculation. A globally buffered divide-by-16 clock drives the OLED. A 7-series MMCM generates the standard 40 MHz VGA clock from the 100 MHz oscillator, with reset release synchronized after lock. Related clocks are explicitly constrained. Each display captures the entire scene at its own frame boundary, preventing objects and scores changing partway through a frame. OLED pixels are supplied combinationally to the original driver's falling-edge logic.

The VGA renderer maps Q8 ball coordinates directly to native pixels, preserving motion finer than one OLED pixel. Eight trail samples are recorded at 60 Hz. Eight particle slots hold the two most recent four-spark impacts and simulate ballistic motion at 240 Hz; a third contact replaces the oldest burst. The score pipeline accepts adjacent contact transactions and prevents long multiplier/decimal-carry paths from slowing the 100 MHz game domain.

Physics is fixed-point arithmetic rather than floating point. The table uses pixels as its spatial unit and includes gravity, acceleration, dissipative wall reflections, energized bumpers, two moving flippers, two side targets, three rollover lanes, a spinner, two energized slings, three stand-up targets, a shooter lane and a central drain. Difficulty adjusts motion. Contacts are corrected before the next update and scoring is rearmed after separation. The simplified collision model avoids division by a changing value, square roots, and trigonometry; it is designed for this small FPGA and display.

The mouse module's real position ports are **12 bits**, despite stale comments about ten bits. The wrapper initializes its bounds to 95/63 and center to 48/32 after reset. The mouse stays on 100 MHz because its supplied PS/2 interface uses cycle counts for protocol delays. Board controls work independently of mouse detection. Normal restart leaves OLED power sequencing running; only full reset restarts the display. Human-visible outputs, the OLED power enable, and asynchronous PS/2 pins have a conservative 100 ns register-to-pin propagation bound rather than an invented 100 MHz receiving clock. The OLED SPI and VGA interfaces keep their clock-based output requirements.

Primary hardware references used during implementation:

- [Digilent Basys 3 reference manual](https://digilent.com/reference/_media/basys3:basys3_rm.pdf): 100 MHz oscillator, Artix-7 device, VGA, board buttons and USB HID to PS/2 translation.
- [Digilent Pmod OLEDrgb reference manual](https://digilent.com/reference/_media/pmod:pmod:pmodoledrgb_rm.pdf): 96 x 64 color display, SPI and power/control pin functions.
- [Digilent Basys 3 master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc): package pin assignments and PS/2 pullups.

## Physical demonstration checklist

Compilation and simulation cannot establish OLED wiring, mouse compatibility, converter support, or game feel on the real board. Verify the menu, hold/release launch, both flippers, combos and mission lamps, target rewards, finite launch/target saves, cooldown-limited nudge, pause, unsaved drains, restart/high score, optional mouse, and native VGA output. Tune gravity, launch impulse, flipper impulse, and restitution in the new physics/collision files if board testing suggests a change. Keep the supplied OLED and mouse files unchanged.
