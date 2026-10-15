## Reading the source efficiently

Read interfaces before long calculation blocks. For every module, write a small card containing its clock, reset, inputs, output meanings, units and latency. For `pinball_collision`, write "pure combinational; stable snapshot in; corrected physical state out." For `pinball_game`, write "100 MHz registers; some actions each clock, most timers on tick; score pipeline can finish while paused." These cards make a large module understandable before every arithmetic detail is familiar.

Use this reading order: Top; input and clock modules; game; physics; collision; effects; scene packers; renderers; display timing and protected interfaces; constraints and tests. The order follows dependencies without demanding that you understand the expensive geometry first. In the top, search for a module name, then trace each named port back to its declaration and producer.

| Question | Source location to inspect |
| --- | --- |
| Which button controls a feature? | Top's `buttons`, `button_press`, mouse predicates and instance ports |
| Who changes the game state? | `pinball_game` state transitions and command priorities |
| Why did score change? | Accepted hit mask, collection/combo logic and award pipeline |
| Why did the ball bounce? | Collision snapshots, corrected outputs and contact priority |
| Why did the ball stay blue? | `save_timer`, `in_lane`, pause state and display snapshot |
| Why is an old position still visible? | Physics commit, producer bundle and next frame boundary |
| Why is an object not clickable? | Logical action bounds in Top and hover bounds in both renderers |
| Why does simulation pass but hardware fail? | Constraints, routed timing, resets, physical interface and the programmed bitstream |

Source search examples, from the project folder:

```powershell
rg -n 'prepare|launch|drained|hit_events' FDP2026.srcs/sources_1/new
rg -n 'save_timer|save_protected' FDP2026.srcs/sources_1/new
rg -n 'collision_busy|collision_wait|load_second' FDP2026.srcs/sources_1/new
rg -n 'frame_begin|oled_transfer|vga_transfer' FDP2026.srcs/sources_1/new
```

A signal named similarly in two files is not automatically the same net. Instance connections and bundle unpacking establish the relationship. Conversely, a file may contain multiple modules, so looking only for matching file names can miss the scene unpackers.

## Build a new game in stages

Treat the following as a development plan for an original implementation. Keep a working version at every stage, and state a pass condition before adding complexity. Choose your own table and rules; reuse the underlying design principles and supplied interface modules appropriately.

### Stage 1: prove the physical outputs

Create a small top that exposes the board clock and the OLED connector. Generate a buffered 6.25 MHz clock and connect the provided OLED interface. Feed a constant RGB565 color; then add coordinate-derived color bars. The pass condition is a reliable startup picture, correct colors and the expected corners. Do not start debugging physics while the OLED still shows a blank screen.

Keep VGA independent at first. Generate its proper pixel clock and raster counters, display color bars, and check every active pixel and porch in simulation. The physical pass condition is a stable picture at the intended mode through the converter. A signal on the VGA pins is not enough: the monitor must recognize the clock, sync lengths and polarity.

### Stage 2: prove input events and persistent state

Implement a synchronized, debounced button and a one-bit register that toggles on its press event. Observe it on an LED. Hold the button, tap it quickly, and inject simulated bounce. Each accepted press must toggle once. Test two channels together before assuming the filter is independent.

Then implement a small menu state register. A state changes on an action pulse and remains stable between actions. Add reset. At this point you should be able to explain each register's initial value and which exact condition updates it.

### Stage 3: draw a movable object

Store one integer or fixed-point coordinate and increment it at a slow enable. Draw a rectangle or ball from that coordinate. It should move at the same speed regardless of display refresh. Pause its position with a control, then resume. Verify bounds before permitting the object to leave the screen.

Add a whole-frame snapshot. Change the live coordinate deliberately halfway through a frame; the current frame should retain its old position, and the next frame should use the new one. This experiment demonstrates tearing and the purpose of a scene register more clearly than merely reading the definition.

### Stage 4: make a one-ball physical game

Use signed Q8 X/Y positions and velocities, a fixed update enable and gravity. Add walls, then one bumper, then two flippers and a drain. Separate collision detection from position ownership. Start with axis responses before implementing swept corners. Verify movement numerically in a testbench; a plausible-looking animation can still hide a wrong sign or unit.

Give the controller a launch pulse and the physics engine a final-drain pulse. Implement READY and PLAY first. Add lives and OVER. Every drain must produce exactly one state transition; resetting or preparing during a calculation must cancel stale results. A quick shot should have a minimum usable power, and a released flipper should not sustain play indefinitely.

### Stage 5: make scoring reliable

Choose a score representation and a range. Binary arithmetic is simple, but decimal displays require conversion. BCD simplifies four-digit output while requiring decimal carry logic. Define the minimum award unit and how fractions are retained. Derive intermediate widths from the maximum possible transaction, not from a typical hit.

Send contact pulses rather than continuous overlap levels. Add an arming flag and exit hysteresis so a long contact scores once. Test back-to-back awards, saturation, a drain following a hit, and a new game with pending awards. These are module-interaction tests, not just tests of an isolated adder.

### Stage 6: add interface quality

Add a score/lives HUD, game-state prompts and charge meter before elaborate decoration. Tie indicators to the authoritative state: protection must come from the same timer used by the save rule, and ball lamps must reflect actual visibility. Keep controls readable in both resolutions.

Then add flash timers, trails and a small particle pool. Draw them behind the active ball and physical objects. Add optional mouse input by translating it into existing game actions. Use one logical control coordinate system for both renderers, with visible hover bounds agreeing with accepted clicks.

### Stage 7: add moving geometry and a second ball

Only after single-ball play works, introduce moving object positions and velocities. Use previous and next centres consistently in collision tests; reflecting in the object's velocity frame should transfer motion predictably. Make drawn and physical positions originate from the same stored state.

For two balls, first estimate the cost of a second full collision engine. If it is too large, share one engine using a selector, isolated operand registers, staging and a controller. Test atomic position commits and separately delivered scoring events. Define whether balls interact physically and whether lives/protection are per ball or per turn. The current project deliberately chooses pass-through balls and turn-wide saves.

### Stage 8: implement and measure each substantial addition

Run synthesis and routed implementation while there is still time to change the architecture. A tiny source edit can lengthen a graphics priority chain; a multiplication inside an unrolled loop can duplicate DSPs many times. Simulation cannot tell you the final resource use or path delay.

When the design reaches its target clocks, freeze a version with its bitstream, source hashes, tests and reports. Program exactly that bitstream for the demonstration. Modifying source after the successful build does not modify the FPGA or the old programming file.

## Verification: prove contracts with self-checking tests

A useful test describes an input sequence and the expected result, event count and timing. A waveform is valuable for diagnosis, but a passing trace that nobody checked is weak evidence. The project uses SystemVerilog testbenches and XSim to reject incorrect behaviour with assertions/fatal checks and to print an explicit PASS marker.

| Testbench | Main contract it checks |
| --- | --- |
| `tb_input` | Bounce rejection, independent buttons, exact settling, one-cycle events and long-interval counter overflow |
| `tb_game` | State priorities, triangle charge, fractional/BCD scoring, collections, finite saves, high score and saturation |
| `tb_physics` | Motion, launch powers/difficulties, speed bounds, moving tracks, pause/cancellation and flippers |
| `tb_multiball` | Shared engine, atomic pair commits, independent contacts, survivor/final drains and nudges |
| `tb_two_ball_game` | Real physics-to-rules interactions, pair scoring, carry, saves and last-drain sequencing |
| `tb_collision` | Contact responses, finite swept corners, near misses, visible guides and flipper underside clearance |
| `tb_vga` | A complete raster, coordinates, sync widths, RGB conversion and black porches |
| `tb_vga_clock` | Actual FPGA MMCM simulation lock, 40 MHz and relock after reset |
| `tb_renderer` | OLED geometry, states, fonts, masks, protection, trails and complete pixel frames |
| `tb_effects` | Spark origins, bank replacement, trail handoff, pause, lifetime and prepare clearing |
| `tb_vga_renderer` | Native geometry/UI, pixels, layer priority, fractional positions and complete frames |
| `tb_top` | Debounced/mouse actions, scene bundle coherence, real protected modules and JC SPI sequencing |

The collision tests include both a hit and a nearby trajectory that must miss. Testing only collisions can allow an oversized invisible hit region to pass. The renderer tests similarly check shape edges and points just outside them. Nondefault values in scene tests detect swapped or truncated fields that all-zero fixtures would hide.

The additional `build/final_physics_audit/` oracle compares 18,231 bounded segments against an independent rational geometric calculation. Independence matters: a test that repeats the exact RTL formula can reproduce the same mistake and report success. Random tests complement carefully chosen boundaries; they do not replace them or prove every possible state.

The top-level simulation accelerates long OLED startup waits and board debounce without changing the supplied driver. That makes protocol/state integration practical to test, but it does not measure physical startup delays. Its mouse packet fixtures check the game adapter at the protected controller's outputs, not the behavior of every real USB mouse. Physical tests still check panel startup, cabling, converter mode compatibility and game feel.

Teaching example of a self-check, not a complete testbench:

```verilog
// Drive away from the active sampling edge to avoid a testbench race.
@(negedge clk);
start_press = 1'b1;
@(posedge clk);
#1;  // Observe state after nonblocking updates.
if (state !== READY || !prepare)
    $fatal(1, "Start did not prepare a fresh turn");
```

Simulation-only time delays such as `#1` and `#5` belong in testbenches. They do not create reliable hardware delay in synthesizable game RTL. In the design, counters, clocks and register boundaries represent elapsed time.

## Vivado flow, constraints and resource reasoning

`FDP2026.xpr` is the saved project. The part and top module must match the board. A module existing on disk does not necessarily mean it is registered in the project's source set. `scripts/verify_project.py` checks registration, part selection, JC mapping, explicit-net guards and protected-driver hashes. `scripts/verify_vivado_project.tcl` checks the saved Vivado project settings and compile order.

`scripts/build.tcl` provides a repeatable batch flow. It reads the mixed VHDL and Verilog sources, reads board constraints, synthesizes the top, reads the implementation-only collision timing constraints after registers are mapped, then optimizes, places, physically optimizes, routes, reports and writes the programming file. It stops if worst setup or hold slack is negative. The board pin check also rejects a stale JA design when this project expects JC.

Understand three different questions. Elaboration asks whether modules, parameters and ports form a legal design. Simulation asks whether the model's behavior matches the expected contract. Synthesis/implementation ask which physical resources implement it and whether signals meet timing after routing. A syntax-correct program can fail any later question.

### Setup, hold and why constraints are not a speed-control trick

Setup requires data to arrive before its receiving edge; hold requires it to remain stable around the edge. Worst negative slack means at least one checked path misses its requirement. At 100 MHz, an ordinary single-cycle path has a 10 ns clock period; the native pixel circuit operates against a 25 ns pixel period. Clock uncertainty, skew, setup requirements and routing are included in the actual analysis, so a period is not all available logic time.

Board pins and generated clocks are in `Basys3_Master.xdc`. Asynchronous buttons/switches are exempted only into their first synchronizer stage. Related display clocks remain timed. The scene crossings must settle in the actual edge relationship, which can have only a 5 ns setup window. Putting producer registers before the crossing shortens it by removing derived graphics logic from that path.

The collision block's 16-cycle setup / 15-cycle hold exceptions apply to stable snapshot-to-result paths. They are justified by the scheduler's delayed capture, not by a desire to silence failures. The ordinary selector, control and queued-event paths must still meet normal timing. Changing the capture schedule requires reviewing those exceptions. For the general command semantics, see AMD's [UG903 multicycle-path syntax](https://docs.amd.com/r/2021.2-English/ug903-vivado-using-constraints/set_multicycle_path-Syntax); the project's exact scoped queries are in its XDC file.

### Why source-code length is not resource cost

A multiplication can infer a DSP or a substantial LUT circuit. A constant shift may be mostly wiring. A combinational `for` loop normally unrolls into replicated hardware; it is not an economical CPU loop that takes one instruction per iteration. Conversely, a sequential controller with operand multiplexers can reuse one expensive circuit at different times, as the two-ball scheduler does.

A conditional table can infer logic or memory depending on size and style. Calling the font a ROM does not ensure block-RAM use; the measured current design uses zero block-RAM tiles. A full 800 x 600 RGB565 frame would require 7,680,000 bits, so this project avoids a full framebuffer and computes pixels from scene state.

The final routed reports show 88.37% LUTs, 8.56% registers and 60% DSPs. The remaining 11.63% LUT fraction is headroom, not a promise that any feature with a similar-looking source size will fit. Check both area and timing. More utilization is not automatically a better engineering result; extra logic should produce useful behavior, readability or performance.

## Build, inspect and program this exact project

Open `FDP2026.xpr` in Vivado and use `My_Top_Module` as design top, `tb_top` as the default simulation top. The part is `xc7a35tcpg236-1`. Source files use Verilog, while tests use SystemVerilog and supplied mouse logic uses VHDL. Do not change source languages indiscriminately to work around a warning.

From the project directory in PowerShell, a compact reproducible workflow is:

```powershell
$pinballProject = (Get-Location).Path
$pinballVivado = 'D:\2025.2\Vivado\bin\vivado.bat'
New-Item -ItemType Directory -Force -Path 'build' | Out-Null
& $pinballVivado -mode batch `
  -source (Join-Path $pinballProject 'scripts/build.tcl') `
  -log (Join-Path $pinballProject 'build/finalization.log') `
  -journal (Join-Path $pinballProject 'build/finalization.jou')
& .\scripts\simulate.ps1
python .\scripts\verify_project.py
python .\scripts\render_previews.py
python .\scripts\record_validation.py --build-log finalization.log
```

Adapt the Vivado and Python executable paths to your computer. The simulation script accepts `-VivadoBin`. The preview script requires Pillow; recording uses Python's standard library and checks existing test/build evidence. The current recording script also expects the retained finalization baseline and geometry-audit evidence. It is a provenance recorder for this version, not a substitute for writing new tests when you create a new game.

For an individual regression, use `& .\scripts\simulate.ps1 -Tests tb_game`. For a short selection, pass a PowerShell array such as `-Tests @('tb_input','tb_top')`. The script's serial elaboration setting avoids a host-specific generated-C issue; it does not change the tested hardware behavior. The default GUI simulation runs for 100 microseconds, while some stand-alone benches need far longer. Use Run All or the batch script to reach their explicit PASS conditions.

Successful output goes to `build/pinball_basys3.bit`. In Hardware Manager, open the board target, associate that file with the FPGA and program it. Connect the color Pmod OLEDrgb to JC with the correct orientation. The PROG USB connection to the computer and USB-A mouse host connection have different roles. Allow the provided OLED startup to finish before interpreting a blank picture as a graphics bug.

Do not replace the provided display driver with an assumed monochrome OLED driver: this project expects the 96 x 64 color panel and RGB565. The active converter must accept 800 x 600 VGA. Optional peripherals should be tested separately from core gameplay so a cable problem is not mistaken for a physics error.

| JC bus bit | OLED signal | FPGA package pin |
| --- | --- | --- |
| 0 | CS | K17 |
| 1 | SDIN | M18 |
| 2 | Unused, driven low | N17 |
| 3 | SCLK | P18 |
| 4 | D/C | L17 |
| 5 | RESN | M19 |
| 6 | VCCEN | P17 |
| 7 | PMODEN | R18 |

## Debug symptoms by tracing the responsible contract

| Symptom | Likely layer and first useful checks |
| --- | --- |
| Blank OLED | Clock, startup/reset, JC mapping, power enables, driver pixel request; first test constant color |
| Monitor reports no signal | MMCM lock, 40 MHz, sync totals/polarity, converter compatibility; first test color bars |
| Wrong colors | RGB565 channel packing and VGA bit slices |
| U or menu click repeats | Press event versus held level; debounce or complete-packet edge history |
| Mouse flipper releases too early | Committed packet buttons versus raw controller button byte |
| Mouse click affects the wrong row | Dispatch uses previous packet Y or mismatched logical/native hit regions |
| Ball moves impossibly fast | Position/velocity scale, tick rate, signedness and clamping |
| Ball sticks or bounces backwards | Penetration correction, approach sign, repeated contact and cooldown |
| Ball hits an invisible wall | Rendered endpoint versus inflated collision endpoint and finite segment bounds |
| A corner is crossed without a rebound | Swept segment versus endpoint-only overlap |
| One collision scores continuously | Event mask validity, per-ball rearm flag, cooldown and exit envelope |
| Two balls give one award | Masks incorrectly ORed together, event queue spacing or score pipeline |
| More than three launches | Check finite save timer and turn/life semantics before assuming a life-count bug |
| Protection color disagrees with drain | Which scene/timer was captured, paused state and final-drain priority |
| A ghost trail joins two balls | Trail source handoff, clearing history and first-bundle validity mask |
| HUD flickers or sprite tears | Live values used during a frame instead of the frozen scene |
| Simulation passes, hardware fails intermittently | Negative routed slack, wrong clock/reset assumptions, unconstrained crossing or stale bitstream |

Debug the smallest failing module first. Force or model a known hit transaction to test rules before changing the collision detector. Inspect raw versus filtered contact masks before changing scoring. Capture the pixel value at one suspicious coordinate before rewriting a full renderer. Keep the baseline bitstream/source so you can compare behavior after an intentional change.

Three previous defects make useful examples. An overly broad right-guide X range created an invisible collision beneath a flipper. Painting fresh trail samples before old ones let old pixels dim the head. A fixed-width parameterized input counter wrapped before reaching a long terminal value. Their causes were geometry bounds, layer priority and finite-width state respectively; each needed a different kind of regression.

## Extending a finalized design without breaking its contracts

Before adding an object, define its logical geometry, its visual geometry, its contact bit or event type, its reward, its arming/exit envelope and any collection memory. Then update collision, physics filtering, rules, renderers and tests coherently. The present 14-bit masks have no spare bit. Expanding them changes arrays, interface widths, bundle widths and test fixtures; stealing a bit from another object silently changes gameplay.

Before changing ball count, estimate state storage and arithmetic separately. A third set of coordinates is cheap compared with a third collision circuit. A shared engine needs another scheduling slot and longer whole-world latency, while pending event/drain spacing and constraint endpoints must remain correct. The current two-ball design does not automatically generalize merely by changing a constant.

Before increasing resolution, derive a supported pixel clock and complete timing mode. Pixel rate determines the budget for computing each output pixel. A 65 MHz mode has a shorter combinational period than 40 MHz even if object geometry is unchanged. Increasing coordinates can also widen multipliers. A display resolution change therefore includes timing, arithmetic widths, layout, constraints and physical converter testing.

Before adding a graphic, determine its final layer and state visibility. A reward popup should not hide a ball or button. A repeated combo notification should not refresh a distracting animation indefinitely. Reuse existing timers and masks when appropriate, but make the behavior intentional rather than dependent on an unrelated field changing by chance.

## Questions you should be able to answer and explain

1. Which values are state registers, and which are combinational results? Show one of each in the source.
2. Why is the physics tick an enable instead of a clock? Calculate its period from the terminal count.
3. What does raw velocity -128 mean in pixels per step and per second?
4. Why does a moving bumper require both old and next centers, and relative velocity?
5. How can both endpoints of a movement be outside an object even though a collision occurs?
6. What makes the 16-cycle collision timing exception valid, and what change would invalidate it?
7. Why do two contacts on the same object need separate event transactions in two-ball mode?
8. What does pause stop, and what already accepted work is allowed to finish?
9. Why can a protected turn contain more launches than the life counter suggests?
10. What is the difference between binary 123 and BCD `16'h0123`? How is a half-point retained?
11. Which clock edge stores an OLED scene, and which edge advances the supplied SPI controller?
12. Why is a frozen many-bit scene safe here only with the stated related-clock timing assumptions?
13. Why is native VGA more detailed than simply enlarging the OLED image?
14. Why do all-zero bundle tests fail to expose some integration errors?
15. Why can a combinational loop increase resource use, while a sequential scheduler shares one circuit?
16. Which evidence establishes behavior, which establishes physical timing, and which still requires a real board?

If you can explain these answers and implement the staged exercises, you have the foundations to design another interactive FPGA project. The new project's surface appearance may be different, but its engineering still consists of state, arithmetic, events, interfaces, timing and verification.

## Glossary and source references

| Term | Meaning in this guide |
| --- | --- |
| RTL | Register-transfer-level description of state and logic between registers |
| Combinational | Output depends on current inputs; no intended memory |
| Sequential | Registers retain state across clock edges |
| FSM | Stored operating state plus transition/output decisions |
| Datapath | Arithmetic, comparisons, multiplexers and registers operating on values |
| Clock enable | Condition deciding whether state updates on an existing clock edge |
| Q8 | This project's signed fixed-point values with eight fractional bits; divide by 256 |
| BCD | Four bits per decimal digit; valid digit values 0 through 9 |
| Snapshot | Captured values held as one calculation or display transaction |
| Atomic commit | Related results become visible together at one clock edge |
| Hysteresis | Different entry and exit thresholds prevent repeated toggling/contacts |
| Metastability | A register can take longer to resolve after an asynchronous edge near sampling |
| LUT | Configurable Boolean lookup logic resource |
| DSP | Dedicated arithmetic resource in the FPGA |
| BRAM | Dedicated block memory resource |
| MMCM / BUFG | Clock synthesis/management primitive and global clock buffer |
| Setup / hold slack | Margin relative to required data arrival/stability timing |
| SPI | Serial data interface used to send commands and pixels to the OLED |
| RGB565 / RGB444 | Packed color formats with 5/6/5 and 4/4/4 component bits |

The current RTL and its tests are the primary source for the implementation descriptions. Consult `README.md`, `docs/DESIGN_NOTES.md`, `docs/VALIDATION.md` and `build/manifest.json` for the current revision and hardware evidence. Source-code identifiers in this guide can be found directly with text search.

The supplied EE2026 project manual (Academic Year 2026-2027, Semester 1) supports the learning connection to OLED coordinates, RGB565, input actions, smooth movement, anode multiplexing and full integration. The local Lab 4 manual supports the connection to sequential circuits, counters, slower clocks and structural composition. These materials were read as educational source content; their schedules and exercise-specific control mappings do not replace this game's current controls.

The original pinball proposal describes the four components and intended physics/graphics/input features. Its extracted text and rendered pages are retained at workspace `tmp/pdfs/proposal.txt` and `proposal-1.png` through `proposal-5.png`. The original download path was unavailable during guide creation, so the retained extraction and page renders were used rather than inventing proposal details.

For further hardware and constraint reading, use the [Digilent Basys 3 manual](https://digilent.com/reference/_media/basys3/basys3_rm.pdf) and [AMD UG903 multicycle-path command explanation](https://docs.amd.com/r/2021.2-English/ug903-vivado-using-constraints/set_multicycle_path-Syntax). Vendor documentation teaches general interface/tool behavior; the project's code and reports establish the particular implementation explained here.

This guide documents a successfully simulated and routed design. No physical board was programmed while creating this guide. It explains the code and its evidence, and identifies the physical checks needed when you reproduce or modify it.
