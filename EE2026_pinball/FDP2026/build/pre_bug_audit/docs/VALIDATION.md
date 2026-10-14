# Validation — 2026-10-14 (Asia/Singapore)

The selectable one/two-ball game with original anime-style circuit-cat reactions on both OLED and native VGA was built with Vivado 2025.2 for xc7a35tcpg236-1. Bitstream generation completed at 2026-10-14T14:56:45+08:00. The programming file is `build/pinball_basys3.bit` (1,539,599 bytes), and the authoritative batch log is `build/anime_fx_final.log`.

## Routed implementation

- Setup worst slack: **+0.178 ns**; TNS 0.000 ns; zero failing endpoints.
- Hold worst slack: **+0.052 ns**; THS 0.000 ns; zero failing endpoints.
- DRC: zero errors and 187 advisory warnings. Consult `build/drc.rpt` for the recommendations. Bitstream generation succeeded.
- Final batch build: zero errors and zero critical warnings. Ordinary warnings include trimmed bits, the supplied OLED driver's zero-width replication expression, and recommendations for graphics/physics DSP pipelining.
- No unconstrained internal endpoints. Scoped collision snapshot paths use setup-16/hold-15 constraints. Asynchronous physical outputs have the explicit 100 ns propagation bound; OLED SPI and VGA retain their clock-based requirements.
- The 100→40 MHz scene crossing is fully timed, including its 5 ns minimum setup window. Graphics fields are registered in the producer domain before each display takes its frame snapshot; no false path hides the scene transfer.
- Vivado opened the saved XPR and verified the FPGA part, design/simulation tops, source compile order, implementation-only timing file and simulation settings.

| Resource | Used / available | Utilization |
| --- | --- | --- |
| Slice LUTs | 18327 / 20800 | 88.11% |
| Slice Registers | 3560 / 41600 | 8.56% |
| DSPs | 54 / 90 | 60.00% |
| Block RAM Tile | 0 / 50 | 0.00% |
| Bonded IOB | 60 / 106 | 56.60% |
| BUFGCTRL | 4 / 32 | 12.50% |

The preceding visual-polish revision used 86.71% LUTs; this anime-reaction revision uses **88.11%**. The prior bitstream, checkpoint, reports and RTL are under `build/pre_anime_fx/`. Earlier versions remain under `build/pre_visual_polish/`, `build/pre_protection_blue/`, `build/pre_polish/`, `build/pre_menu_mode/`, `build/pre_multiball/`, `build/pre_charge_bounce/`, `build/pre_motion/`, `build/ja_previous/`, `build/pre_layout_revision/` and `build/baseline/`.

The OLED uses **JC** and remains 96×64 at 6.25 MHz. Point awards retain their half-point units and carry, preserving small awards; whole-point scores still saturate at 9999. VGA is native **800×600**, using a real MMCM-generated **40 MHz** pixel clock, 1056×628 total frame, positive H/V sync, and approximately 60.317 Hz. Physics uses a fixed 240 Hz enable on the 100 MHz game clock. Native eightfold scaling retains Q8 fractional ball motion and uses no full-frame buffer.

## Simulation and source integrity

Both renderer benches and top-level integration were rerun for the anime-reaction revision. The other nine passing logs are retained from the preceding review; their RTL dependencies are unchanged and the validation script checks freshness against each bench's dependencies. Renderer captures also verify that queued white/gold positions match physics preparation coordinates.

| Bench | Result and coverage |
| --- | --- |
| tb_input | PASS: bounce rejection, independent simultaneous inputs, settling and single-cycle events |
| tb_game | PASS: latched one/two-ball mode; half-point carry across adjacent transactions, drains and pause, new-game fraction flush, maximum simultaneous 55 award; continuous charge sweeps/releases/resets, fourteen contacts, repeatable collections, spinner, x1–x4 combos, finite saves, saturation, high score and late pause/drain transactions and simultaneous drain/pause/resume priority |
| tb_physics | PASS: 42,337 checks; complete shared track period (four vertical/three horizontal cycles), endpoint/direction bounds, moving-surface contacts, moving-centre score hysteresis, atomic motion/ball commit; minimum/light/full launches and eventual idle drains in all three difficulties, speed bounds, revised swept target/sling rebounds, new sensor rearming, nudge, isolated 16-clock collision commit, prepare/reset cancellation, pause and fractional coordinates |
| tb_multiball | PASS: 13,847 checks; one-shot pair launch; both lane exits at minimum/light/full power in all difficulties; 33-clock atomic pair/world commit, world advancement once, independent rearm/cooldown, separate same-object hit pulses, either-ball-first drains, final drain after event flush, natural unattended pair drains on every power/difficulty combination, shared nudge, a nudge queued between snapshots, pause and reset/prepare cancellation |
| tb_two_ball_game | PASS: 74 checks of real physics→rules integration; paired release/power, separately credited same-bumper contacts and fractions, partial/final drains, finite pair saves, queued final awards, pause completion and menu/reset cancellation |
| tb_collision | PASS: 75 focused checks for relative-velocity rebounds, stationary balls struck by moving surfaces, grazing swept contacts/near misses, swept stand-up/slingshot corner hits and near misses, smaller ball/bumpers, walls, targets, flippers and guides |
| tb_vga | PASS: complete 1056×628 frame; all 480,000 active pixels, positive sync widths, native coordinates, RGB565 conversion and porch blanking |
| tb_vga_clock | PASS: actual FPGA MMCM model locks, generates 40 MHz and relocks after reset |
| tb_renderer | PASS: sixteen complete OLED frames (98,304 pixels), reaction reward/nudge/saved poses, event filtering, 120/121 expiry, hidden modal states and READY-only saved placement; persistent score/hearts during awards, bounded visible-cursor hover, save-countdown boundaries, live-ball indicators and segmented charge; protected/unprotected ball and fading trail palettes, U/mouse mode menu, queued pair, two visible balls and survivor; independent visibility, no drained ghosts, pause, ball priority over cursor, bottom/right cursor clipping, complete prompts/digits, moving geometry/lamps/spinner and stale-award rejection |
| tb_effects | PASS: two alternating four-spark bursts preserve separate rapid impact positions; replacing the oldest burst, late paused bursts, clean survivor history and rejection of inactive impacts; native fractional scaling, ballistic motion, pause, expiry and prepare clearing |
| tb_vga_renderer | PASS: sixteen complete 800×600 frames (7,680,000 pixels), original reaction mascot and comic captions, event filtering, expiry and state/HUD/ball priority; chamfered buttons and visible-cursor hover, save-countdown boundaries, configured-mode/survivor chip and segmented charge; protected/unprotected ball and fading trail palettes, paired/queued/surviving balls, native second-ball fraction, independent visibility, no ghosts, no extra sprite multipliers, aligned action rows, unclipped resume/restart messages, state-specific footers, ball priority over cursor, suppressed stale MENU/OVER game statuses, moving geometry and stale-award rejection |
| tb_top | PASS: complete mouse button/cursor packets, bounded start/resume/restart widgets and ignored title/margin clicks, first-bundle trail masking during survivor handoff; real debounced U presses, single toggle on hold, mouse mode-row toggles using final packet Y, ignored SW1 in menu/play, simultaneous U/C capture, choice persistence and U pause/resume during play; simultaneous middle-button pair launch, atomic second-ball coordinates/masks/mode on both displays, world advancement once, mixed protected drivers, reset, complete-packet clicks, JC map, 25 OLED commands, pixels and absent-mouse fallback |

The open lower-field descent test from y38 to y53 takes 51 ticks (**212.5 ms**), and both flippers fully raise within four ticks (**16.7 ms**). These are measured design targets; contacts can change the ball path. The top configures board input debounce to five milliseconds.

Native VGA menu prompts align with the OLED logical mouse regions: ball-mode selection lies in rows 22–29, difficulty lies in rows 30–39, start lies in rows 43–47, pause resume in 39–45 and game-over restart in 49–53. The action column is x24–72; difficulty spans x22–73. SW0 remains the mouse enable.

U or a left mouse click on the ball-mode row toggles one/two balls in the menu. SW1 has no effect. The choice is remembered across menu visits and captured when starting a game; full reset restores one ball. One release launches white/gold balls from (89,56)/(89,60) using the same charge, with slightly different leftward lane exits. One remaining ball keeps the turn active. Only the final drain consumes a life or invokes a save; a save prepares the selected number of balls and does not renew launch grace. Balls do not collide with one another.

On both displays, a nonzero save timer colors both live balls bright blue and the existing trail in fading blue shades. Expiry or consumption restores the normal white/gold balls and ordinary trail. This uses the same frame-snapshotted timer as the save indicators; the palette cannot change partway through a frame. PAUSE keeps the protection state frozen. Protection remains global to the turn and only the final ball drain invokes a save.

The UI adds neon panels, cursor-hover feedback on the existing action regions, segmented launch power, a protection countdown and live-ball status. OLED score and lives remain visible during award feedback. Countdown seconds use fixed threshold comparisons rather than division. Native VGA remains a procedural 800×600 raster with fine text and Q8 motion, while OLED uses a compact version of the same visual language. The particle pool keeps the two most recent four-spark bursts, so quick contacts from both balls can remain visible together. Collision geometry and game rules are unchanged.

The original circuit cat cheers selected rewards, panics during nudge and shows relief after a saved turn. It appears only while the current selected feature has more than 120 ticks remaining, then disappears after its first half-second. Generic combo event2 is excluded because repeated contacts refresh it. PLAY uses the clear upper-left gap; READY saved reactions move below the OLED charge bar. MENU, PAUSE and OVER hide the cameo. Its poses use existing timer/animation fields, constant masks and the shared font. The mascot body stays behind trails and table objects; live balls remain above the mascot and captions. Both displays retain their normal score, lives, countdown and blue-protection cues. Existing feature data represents the latest notification rather than a queue of every closely spaced award. Three actual RTL reaction examples are in `docs/funny_preview.png`.

Holding C or mouse middle cycles the power meter 0→63→0 at 60 units/second (1.05 seconds each way). Release uses the selected value with a minimum launch strength of 16. Both display meters and charge LEDs consume the same charge signal. Pause freezes charge; resume, menu, new game, reset and the final ball's drain restart the rising sweep from zero.

The left bumper travels at x26/y22..28 and the right at y22/x58..66, both at 3.75 logical pixels/second. One collision engine processes the balls sequentially against the same world snapshot. One-ball motion commits after 16 clocks; paired motion/world commits after 33 clocks. Each snapshot has its own full 16-clock window; selector, event-queue and staging-to-final paths retain ordinary timing. First/second hit masks emit four clocks apart, and a final paired drain is delayed six clocks so neither award is lost. Reset/prepare cancel pending results/events; pause allows only an already accepted batch to finish. Each ball has independent cooldown and moving-center hysteresis.

Reviewed input debounce, seven-segment scanning, VGA timing, MMCM lock/reset and RGB conversion required no RTL changes. Protected driver SHA-256 hashes match their supplied versions. `build/manifest.json` records final source, testbench, simulation-log and bitstream hashes. Preview PNGs contain pixels from the actual RTL renderers and were inspected visually. Internet references and design choices are in `DESIGN_NOTES.md`.

## Physical board checks

No board was programmed during this revision. Verify short circuit-cat reward/nudge/saved reactions on both displays, expiration and modal hiding, hover buttons and persistent score/lives, protection countdown and live-ball status, paired impact bursts, bright blue balls/trails during launch and target protection, normal colors after expiry/consumption, OLED orientation/startup, U/mouse menu and bounded action clicks, completed mouse packets, corner rebounds, both balls launching and remaining visible, game feel, controls, fractional scoring, finite pair saves, partial/final drains, high score, optional mouse and the active VGA-to-HDMI converter's 800×600 support. High score resets with SW15 or power cycling. Top-level simulation accelerates long OLED waits and board debounce without changing the protected driver; it verifies sequencing, not actual power-up delays. Mouse integration tests use complete controller packets rather than a physical USB mouse.
