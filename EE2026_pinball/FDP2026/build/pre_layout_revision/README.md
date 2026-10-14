# EE2026 FPGA Pinball Arcade

Pinball for the Basys 3, targeting **xc7a35tcpg236-1**. The primary display is a **96 x 64 Pmod OLEDrgb on JA**. A simultaneous **native 640 x 480 VGA renderer** draws the same game with crisp curves, a glossy ball, beveled rails, a larger HUD, particles and subpixel motion. The OLED uses a compact renderer of the same live game state. A mouse is optional; every game action is available on the board.

The implementation follows the supplied EE2026 proposal's physics, collision, graphics, and game/input components. The proposal's scheduling and member-responsibility text was treated as background. The user's hardware specification determines the OLED display and FPGA part. The supplied `Oled_Display.v`, `Mouse_Control.vhd` (`MouseCtl`), and its `Ps2Interface.vhd` dependency are preserved byte for byte.

## Play

| Control | Action |
| --- | --- |
| Center (C) | Start/restart; hold/release to launch a ready ball; during play, nudge once per two seconds |
| Left / right (L / R) | Corresponding flipper; select difficulty on the menu |
| Up (U) | Pause/resume |
| Down (D) | Return to menu, preserving the high score |
| SW0 | Enable optional mouse controls |
| SW15 | Full system reset, including OLED startup and high score |
| Mouse left / right | Corresponding flipper during play |
| Mouse middle | Hold/release to charge/launch; click during play to nudge |
| Mouse left on menu | Start; click the left/right half of the difficulty row to change level |
| Mouse left at game over | Restart |

Press C to start, then hold C and release it to launch. Holding C through the start transition charges the first ball immediately. A quick tap gives a useful minimum charge. Full charge takes approximately 1.05 seconds. There are three physical lives; ball saves can return a drained ball without spending a life.

- **Combos:** score another contact within two seconds to grow the multiplier from x1 through x4. Bumpers start at 50 points and side targets at 100. After two seconds without a hit, the multiplier returns to x1.
- **Gold bumper:** the periodically selected gold bumper adds a flat 250 points, then the bonus is consumed.
- **Bumper mission:** hit all three bumpers to collect an extra 500 points. The mission lights reset so the reward can be earned again.
- **Side-target pair:** light both side targets to collect an extra 250 points and a six-second ball-save window.
- **Launch grace:** each new physical life gets a three-second ball-save window after the ball exits the shooter lane. A saved relaunch does not renew that window. Saving a ball consumes the active save, avoiding an unlimited loop.
- **Nudge:** press C or click the mouse middle button during play to give a small upward and inward impulse. It is limited to once every two seconds and has no effect in the launcher lane.

A base contact is multiplied by the combo; mission, target-pair and gold rewards are added afterward. Score saturates at 9999 and appears on both screens and the four-digit seven-segment display. The best score survives restarts until SW15 or power cycling. Pause freezes physics and feature timers while allowing an already accepted collision transaction to finish.


LEDs 0-2 show remaining lives; LED3 shows enabled mouse activity; LEDs4-8 show charge; LEDs9-10 show difficulty; LED11 shows an active bonus; LED12 shows the shooter lane; LED13 shows play; LED14 shows pause; LED15 shows game over.

## Connect and program

1. Connect the Pmod OLEDrgb to **JA**, observing the module and board ground/power markings. This design uses the color OLEDrgb, not the monochrome Pmod OLED.
2. Connect the Basys 3 PROG USB port to the PC. Optionally connect a USB HID mouse directly to the board's separate USB-A host port and enable SW0.
3. Open `FDP2026.xpr` in Vivado 2025.2. `My_Top_Module` is the top and the device is `xc7a35tcpg236-1`. All source files and used pins are already registered.
4. Program `build/pinball_basys3.bit` in Hardware Manager when available, or run Generate Bitstream. Allow the OLED startup sequence to finish before expecting a picture.
5. VGA is optional. The output uses 640 x 480 timing, 800 x 525 total pixels, at 25 MHz (approximately 59.52 Hz). A VGA-to-HDMI converter must support that input timing. The table occupies 576 x 384; the remaining native pixels carry the score, missions, combo/save indicators, and control instructions. Individual native pixels render curved objects and fine text; VGA is no longer a duplicated OLED bitmap. Both screens run simultaneously and share the same gameplay and controls.

| JA signal | Bus bit | FPGA pin |
| --- | --- | --- |
| CS | 0 | J1 |
| SDIN | 1 | L2 |
| Unused, driven low | 2 | J2 |
| SCLK | 3 | G2 |
| D/C | 4 | H1 |
| RESN | 5 | K2 |
| VCCEN | 6 | H2 |
| PMODEN | 7 | G3 |

## Build and verify

From this project directory in PowerShell:

```powershell
& 'D:\2025.2\Vivado\bin\vivado.bat' -mode batch -source scripts/build.tcl -log build/vivado.log -journal build/vivado.jou
& .\scripts\simulate.ps1
python .\scripts\verify_project.py
python .\scripts\render_previews.py
```

Create the `build` directory before choosing log/journal paths there. The batch build does not depend on the original author's desktop path. It reads the mixed Verilog/VHDL sources, synthesizes, applies implementation-only collision constraints after registers are mapped, places, routes, checks setup and hold slack, writes reports and checkpoints, then produces the bitstream. `simulate.ps1` accepts a `-VivadoBin` path if Vivado is installed elsewhere, and `-Tests tb_game` can run an individual bench. All nine benches are also registered in the project's simulation source set; `tb_top` is the default GUI simulation top. Preview generation requires Pillow. The self-checking tests check game rules, input debouncing, ball movement and collisions, VGA timing, complete renderer frames, and top-level OLED/mouse integration. Top-level simulation can accelerate OLED startup delays without changing the protected source; that test does not measure real power sequencing delays.

See `docs/display_preview.png`, `docs/vga_preview.png`, and `docs/dual_display_preview.png` for pixels produced by the actual RTL renderers. `docs/VALIDATION.md` records build results and remaining board checks. The prior working version and programming file are preserved under `build/baseline/`.

## Architecture and project knowledge

| Module | Responsibility |
| --- | --- |
| `My_Top_Module` | Clocks, power-on reset, mouse setup, optional controls, frame snapshots, display integration |
| `pinball_input` | Two-stage button synchronization, independent 10 ms debounce, single-cycle press events |
| `pinball_game` | FSM, lives, charge, pipelined BCD score, high score, combos, missions, target rewards and finite ball saves |
| `pinball_physics` | Q8 motion, gravity, velocity bounds, launcher lane, animated flippers, queued nudge and fractional VGA outputs |
| `pinball_collision` | Table interactions, position corrections, bouncing, hit masks |
| `pinball_renderer` | OLED table, 3 x 5 font, glossy ball, impact rings, mission/target lamps, combo/save HUD, trails and award toasts |
| `pinball_vga` | 640 x 480 pixel coordinates, active video, sync and RGB output |
| `pinball_vga_renderer` | Native raster graphics, circle distance circuits, 5 x 7 font, overlays, detailed HUD and feature celebrations |
| `pinball_effects` | Eight ballistic sparks and eight Q8 trail samples, frozen on pause and captured atomically by each display |
| `pinball_sevenseg` | Multiplexed active-low BCD score output |
| Protected supplied modules | OLED SPI/power sequencing and bidirectional PS/2 mouse protocol |

The 100 MHz board oscillator drives all game logic. Physics uses a **240 Hz clock enable**, not a new slow game clock. Each accepted update captures every collision operand into an isolated register bank. Those operands stay fixed for exactly **16 system clocks (160 ns)** before the collision result is committed. Scoped setup-16/hold-15 timing exceptions cover only that calculation; wait counters, controls, and all other paths retain their ordinary timing requirements. Reset or preparing a new ball cancels an outstanding calculation. Separate globally buffered divide-by-16 and divide-by-4 clocks drive the OLED and VGA. Related clocks are explicitly constrained. Each display captures the entire scene at its own frame boundary, preventing objects and scores changing partway through a frame. OLED pixels are supplied combinationally to the original driver's falling-edge logic.

The VGA renderer maps Q8 ball coordinates directly to native pixels, preserving motion finer than one OLED pixel. Eight trail samples are recorded at 60 Hz, and eight particles simulate short ballistic bursts at 240 Hz. The score pipeline accepts adjacent contact transactions and prevents long multiplier/decimal-carry paths from slowing the 100 MHz game domain.

Physics is fixed-point arithmetic rather than floating point. The table uses pixels as its spatial unit and includes gravity, acceleration, dissipative wall reflections, energized bumpers, two moving flippers, two side targets, a shooter lane and a central drain. Difficulty adjusts motion. Contacts are corrected before the next update and scoring is rearmed after separation. The simplified collision model avoids division by a changing value, square roots, and trigonometry; it is designed for this small FPGA and display.

The mouse module's real position ports are **12 bits**, despite stale comments about ten bits. The wrapper initializes its bounds to 95/63 and center to 48/32 after reset. The mouse stays on 100 MHz because its supplied PS/2 interface uses cycle counts for protocol delays. Board controls work independently of mouse detection. Normal restart leaves OLED power sequencing running; only full reset restarts the display. Human-visible outputs, the OLED power enable, and asynchronous PS/2 pins have a conservative 100 ns register-to-pin propagation bound rather than an invented 100 MHz receiving clock. The OLED SPI and VGA interfaces keep their clock-based output requirements.

Primary hardware references used during implementation:

- [Digilent Basys 3 reference manual](https://digilent.com/reference/_media/basys3:basys3_rm.pdf): 100 MHz oscillator, Artix-7 device, VGA, board buttons and USB HID to PS/2 translation.
- [Digilent Pmod OLEDrgb reference manual](https://digilent.com/reference/_media/pmod:pmod:pmodoledrgb_rm.pdf): 96 x 64 color display, SPI and power/control pin functions.
- [Digilent Basys 3 master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc): package pin assignments and PS/2 pullups.

## Physical demonstration checklist

Compilation and simulation cannot establish OLED wiring, mouse compatibility, converter support, or game feel on the real board. Verify the menu, hold/release launch, both flippers, combos and mission lamps, target rewards, finite launch/target saves, cooldown-limited nudge, pause, unsaved drains, restart/high score, optional mouse, and native VGA output. Tune gravity, launch impulse, flipper impulse, and restitution in the new physics/collision files if board testing suggests a change. Keep the supplied OLED and mouse files unchanged.
