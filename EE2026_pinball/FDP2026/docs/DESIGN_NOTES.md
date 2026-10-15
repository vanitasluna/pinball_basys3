# Expanded table and game feel

## Experience tuning - 15 October 2026

The mouse wrapper configures the protected controller for raw bounds 383/255 and center 192/128, then divides complete coordinates by four. Fractional movement stays in the supplied controller, so small gestures accumulate and reversing direction responds immediately. Cursor drawing and click dispatch consume the same scaled coordinates; button semantics are unchanged. The supplied OLED and mouse modules remain byte-identical.

Both side target centers now move between y29 and y37, starting at 33 in opposite directions at 3.75 logical pixels/second. Drawn faces are centered at x6/78 with halfwidth 1 and halfheight 3; adding the radius-one ball gives collision halfwidth 2 and halfheight 4. OLED faces span x5..7/77..79; native VGA faces span x56..72/632..648. The final review removed an inherited extra renderer column so no visible edge extends beyond the collision geometry. Progress lamps move with the same centers. Relative old/new positions and surface velocities provide swept contacts and meaningful responses; per-ball cooldown/rearm tracks the current target. A coarse selector shares one rectangle sweep among five separated rectangles to limit arithmetic cost.

Targets use the same isolated transaction and 16/33-clock world commit as the bumpers and balls. Their positions and directions never advance once per ball. Side outputs are part of the 346-bit OLED and 639-bit native VGA frame snapshots. Scoped timing exceptions include only stable side snapshot-to-result paths; no crossing is hidden with a false path.

Gravity is Easy/Normal/Hard=0.5/1/2 Q8 units per step, corresponding to 112.5/225/450 logical pixels/s². Easy alternates 0/1 using one phase per accepted world transaction; the second ball uses the captured gravity and difficulty. Upper downward caps 112/136/160 and lower caps 48/60/72 give 105/127.5/150 and 45/56.25/67.5 pixels/s. Capped open y38 to y53 descent takes 80/64/54 physics steps, about 333/267/225 ms. All 64 launch powers are tested on all three levels in both modes; representative idle shots must eventually drain. Lives, saves, scoring, launch sweep and flipper response retain their earlier contracts.

The persistent procedural cat has idle, happy, wink, panic, sad and sleepy moods. Blink, bob and spontaneous expressions reuse the existing animation register; fresh events temporarily override idle. Event overrides expire at feature_timer 120, and pause/game-over moods take precedence over retained event codes. The face is present in every game state, with state-specific empty margins and a later redraw over modal panels. Trails, objects and live balls retain their higher gameplay priority. VGA speech boxes remain brief event reactions. READY placement clears the moving target faces and the charge meter.

The completed change was reread across all custom RTL. Focused tests check edge reachability and click alignment, all-state mascot visibility and clipping, old/new target bounds, moving surface approaches and near misses, pause/reset cancellation, correct per-ball rearming and exact shared-world commit timing. The current `VALIDATION.md` records the fresh build and regression evidence; the preceding working bitstream and sources are under `build/pre_experience/`.

## Final code review and coding conventions

Every custom RTL module and the supplied display/mouse interfaces were reviewed for state/event priority, bounded signed arithmetic, reset behavior and display timing. The supplied `Oled_Display.v`, `Mouse_Control.vhd` and `Ps2Interface.vhd` remain byte-identical. Custom Verilog uses explicit net/port types and a scoped `default_nettype none` guard, restored to `wire` after each file so the supplied sources compile normally. State encodings and key timing constants have explicit widths. Clocked state uses nonblocking assignments; combinational paths use blocking assignments with defaults and complete cases. Physics coordinates are signed Q8; unsigned display coordinates are clipped before drawing. Related display-clock crossings remain timed, and multicycle exceptions apply only to stable collision snapshots.

The reusable input filter sizes its counter from the positive `STABLE_CYCLES` parameter, with a minimum width of one bit. The old fixed 20-bit counter failed to accept a stable press when configured for 1,048,577 clocks. A public-input regression first reproduced that overflow, then passed with the derived width. The board still uses 500,000 clocks (5 ms); its controls and debounce duration are unchanged.

The final audit also checked all rules, physics, effects, display and integration benches. An independent rational geometry oracle checked 18,231 bounded bumper segments, including grazing hits and near misses. It is retained under `build/final_physics_audit/`; the preceding complete design is under `build/pre_finalization/`. Routed timing, protected-source hashes, source/test freshness and all twelve simulation results are recorded by `scripts/record_validation.py`.

The table uses the same logical coordinates and rules on the 96×64 OLED and native 800×600 VGA output. VGA maps a logical point to `(16 + 8*x, 32 + 8*y)` and keeps the ball's Q8 fraction. The ball radius is 1 logical pixel; bumpers have radius 3. Flippers retain their reach so the smaller ball remains catchable.

| Contact | Logical position | Behavior |
| --- | --- | --- |
| Three bumpers | Left x26/y22–28; right y22/x58–66; center (42,35) | Two move on bounded tracks; energized rebound; 0.5 base points; complete all for +5 |
| Two side targets | x6/78; centers y29..37 in opposite directions | Reflect; 1 base point; both award +2.5 and a six-second save |
| Three rollover lanes | x25,42,59; y12–16 | Pass through; 0.5 base points; all three award +3 |
| Spinner | (42,27), width 8 | Pass through; 0.5 base points; paddle continues turning briefly |
| Two diamond slings | (17,41), (69,41) | Energized radial/inward rebound; 0.5 base points |
| Three stand-up targets | x34,42,50; y19–21 | Permanent solid targets; 1 base point; all three award +4 |

Scoring contacts have independent cooldown and exit hysteresis. Remaining inside a sensor never produces repeated points, even after its cooldown expires. Stand-up targets stay solid after being lit; they are not drop targets.

The left bumper moves vertically over six logical pixels, and the right moves horizontally over eight. Both use Q8 steps of ±4 at 240 Hz, or 3.75 pixels/second. Their approximate full periods are 3.2 and 4.27 seconds. The tracks leave clear gaps to the top rollover arches, stand-up targets, spinner, slings, shooter lane and flippers. They remain above the slower lower-field reaction zone.

Moving centers, direction, previous center and velocity belong to one world snapshot shared by both balls. One-ball motion commits after 16 system clocks; a paired update commits both positions and moving centers together after 33 clocks. Each ball gets a full 16-clock isolated collision calculation with one clock between them to load the next operands. A prepared/reset ball cancels pending motion and queued hit/drain events. Pause permits only an already accepted batch to finish. A bumper collision uses velocity relative to the moving surface, then converts the rebound back to world velocity. Finite octagon-face sweeps catch grazing contacts without introducing hardware division. Each ball has its own cooldown and rearm state, measured from the live moving center.

Both displays snapshot the new centers as part of the whole scene. Native VGA retains the fraction; OLED floors it to its pixel grid. Dotted tracks are decorative guides. Bodies, lamps, gloss and flash rings follow the same centers. `moving_bumpers_preview.gif` illustrates three RTL position samples, rather than a real-time recording.

## One/two-ball mode and scoring

Pressing U or clicking the ball-mode row toggles between one and two balls in the menu. SW1 is ignored. The selection defaults to one ball after reset and is remembered across menu visits. It is sampled when a new game starts; mode clicks cannot start accidentally, and a simultaneous U/C press starts the new selection. Outside the menu, U remains pause/resume. Both ready balls launch from a single C/middle-button release with the same power. White starts at (89,56), gold at (89,60); both shoot leftward out of the lane, with different horizontal speeds. Balls pass through one another. A surviving ball keeps the turn active; only the final drain applies life/save rules. A save prepares the selected number of balls without renewing launch grace.

The scheduler shares the collision, acceleration, clamping and rearm arithmetic. Flippers and moving objects advance once per world tick, regardless of ball count. First-ball results are staged until the second calculation finishes. First/second scoring masks emit four clocks apart; a paired final drain follows six clocks after commit, keeping both transactions eligible for the rules pipeline. New staging/result banks use the same setup-16/hold-15 collision constraint; selector, queue and staging-to-final paths remain timed at 100 MHz.

The code review fixed a simultaneous drain/pause race: a prepared next life now follows the current pause/resume request, while a final game-over drain and return-to-menu retain priority. Mouse held controls and coordinates use complete packets; the dispatch edge still reads the latest final Y. Shared logical action regions are mode y22–29, difficulty y30–39, Start y43–47, Resume y39–45 and Restart y49–53. Their action column is x24–72 (difficulty x22–73). Blank, title and margin clicks cannot start or resume. Native restart geometry matches OLED, and state footers show only applicable controls.

Late collision bursts accepted before pause remain stored and frozen until resume. Trail history resets when white drains and gold survives; both producer bundles mask validity on that same first handoff edge, preventing a one-frame ghost. Live balls paint above the cursor during PLAY. OLED cursor arithmetic clips at the bottom edge. Native MENU/OVER suppress stale combo/save statuses left over from an exited game.

All point awards are another ten times smaller than the previous revision. One internal unit is 0.5 points, with a carry bit across transactions. Displays show whole points, so a small hit may add to the internal remainder before the visible score changes. The maximum simultaneous fourteen-contact transaction is now 55 points. Both balls contribute to the same combos and missions, and their separate hit masks preserve two awards even for the same object. Score still saturates at 9999. The shared trail follows white while it survives, then gold; impact sparks use the actual scoring ball's position. The gold native sprite uses bounded comparisons, adding no sprite multipliers.

## Physics choices

Physics uses a fixed 240 Hz enable, independent of either display. Motion and collision operands remain Q8. Collision snapshots hold all operands for 16 system clocks; reset or preparing a new ball cancels a pending calculation. Rendering takes a whole scene once per frame.

The side guides end at their flipper pivots: x21 on the left and x65 on the right. The bug audit corrected a right-guide threshold of x45 that extended an invisible surface beneath the flipper. A descending ball at (62,55) now continues through clear space instead of bouncing upward. Mirrored clearance tests cover all five flipper angles, and a separate contact confirms that the visible right guide still rebounds inward.

Stand-up targets and slings now sweep their finite clearance faces as well as checking the proposed point. A legal fast diagonal or horizontal step can enter and leave a corner while both endpoints remain outside; endpoint-only checks missed those impacts. One selected-face intercept per object shares two variable products, rejects near misses without division, and relies on the existing bounded step. Diamond slings transform x/y into x+y/x−y coordinates to reuse the rectangle helper. Focused mirrored hit/near-miss tests and natural freeplay verify these changes.

Horizontal speed remains limited to ±1 logical pixel per tick and upward speed to 1.25. Downward limits now depend on difficulty as documented above, with a separate gentler lower-field cap from y38. These are design targets for readable play; collisions redirect the path and players have different reaction times.

The flippers rise over four ticks, with an energized return while moving and a weaker return when held. Board buttons use a five-millisecond debounce; mouse controls bypass that board switch filter. Idle released flippers dissipate energy and let the ball roll toward the drain. Minimum, light and full launches are tested on all three difficulties, including eventual unattended drains.

Launch power changes by one unit every four physics ticks, or 60 units/second. Holding C or mouse middle repeatedly sweeps 0→63→0, reversing immediately at the endpoints without an extra dwell. Each half-cycle takes 1.05 seconds. Releasing captures the current power with a minimum of 16 so low-power shots still leave the lane. Pause freezes a held charge; resuming discards it and starts a fresh rising sweep. Menu, new game, reset and the final ball's drain also clear the sweep direction and divider. A partial two-ball drain keeps the turn active.

## Graphics and hardware budget

Dark navy keeps the white/silver ball visible. Cyan marks rails, magenta marks energized objects, and gold marks objectives. Lighting, expanding hit rings, ballistic sparks and fading trails show motion without shifting the collision geometry. Award feedback belongs in the HUD/footer so the playfield remains visible. The live ball is painted above other effects during play.

Both trail renderers paint the oldest sample first and the newest sample last. This preserves the bright trail head when a slow or returning ball revisits a pixel, including the blue protection palette. Invalid samples do not cover valid history; trails remain behind table objects and live balls. The old ordering failed explicit overlap tests on both displays before this correction.

Ball-save protection overrides both balls with a bright blue palette and changes the shared trail to fading blue shades. The existing frame-snapshotted save timer controls this palette on both OLED and native VGA, preserving frame consistency without adding any geometry or physics arithmetic. Unprotected balls retain their white/gold palettes. Expiry or consumption restores ordinary colors, while pause keeps the timer frozen. The save remains global to the turn; a partial two-ball drain still removes that ball.

800×600 uses a standard 40 MHz pixel clock and 1056×628 total frame, with positive H/V sync. An MMCM generates 40 MHz from 100 MHz; the video reset releases after lock. The external active VGA-to-HDMI converter must support this input mode. The FPGA sends analog VGA, and the converter produces HDMI.

The renderer generates pixels procedurally, without a full-frame buffer. Eightfold scaling uses shifts, small fonts share one glyph circuit, and fixed geometry avoids floating point or general square-root hardware. Resource use and routed timing are measured in `VALIDATION.md`; those reports, rather than a target percentage, determine whether the revision fits xc7a35tcpg236-1.

## Visual interface polish

Both displays use a navy/violet circuit-table theme, cyan action cues, gold goals and magenta contact lighting. Bright blue remains the protection cue. The OLED uses a shared 3×5 font and compact cards; VGA uses a shared 5×7 font, native curves and chamfered buttons. Hover requires a visible cursor and follows the existing logical click regions, including the difficulty band's left/right halves. No control or collision region moves with the decorative animation.

OLED award notifications occupy only x31..50, keeping score and all life hearts visible. S1..S6 shows ceiling seconds remaining; native VGA provides a larger SAFE countdown. Fixed comparisons at 240-tick boundaries avoid a hardware divider. Live-ball indicators use visibility bits, distinguishing the selected two-ball mode from a surviving single ball. Both counters come from the same frame snapshots as the sprites.

Segmented charge gauges, moving rail lights, shaded flippers, sparse circuit patterns and illuminated object rims reuse existing animation, hit and geometry fields. The native particle shader fades sparks with age. The eight-slot effect pool alternates between two four-spark bursts, retaining both quick impact origins. Pause freezes particle motion and preserves accepted late bursts; a survivor handoff clears only trail history.

The visual direction adapts the luminous circuit atmosphere of [Stern TRON](https://www.sternpinball.com/game/tron/) and the clear feature lighting shown in [Zen Studios' Tesla table guide](https://www.pinballfx.com/press/table_guides/Tesla_Table_Guide_By_ShoryukenToTheChin.pdf). The RTL uses original procedural graphics, with no copied game assets. Native VGA remains 800×600 with 480,000 individual pixels per frame, versus 6,144 OLED pixels; it uses independent fine text, shading and Q8 motion instead of enlarging the OLED bitmap. `VALIDATION.md` and actual RTL previews provide demonstration evidence for the high-resolution and smart-UI features.

The circuit cat is original procedural pixel art and is now persistent in all states. The experience-tuning section above describes its idle/context moods, state placement, event expiry and gameplay layering. Both compact OLED and native VGA render it from constant masks and existing animation/state fields, without importing bitmap assets or adding a framebuffer.

## References used

- [Stern Jurassic Park pinball flyer](https://sternpinball.com/wp-content/uploads/2021/10/Jurassic-Park-PIN-Flyer.pdf) describes spinner shots, target banks and playfield objectives. It informed the added object types and repeatable missions.
- [Zen Studios pinball essentials](https://zenstudios.freshdesk.com/support/solutions/articles/43000638115-pinball-essentials) describes basic pinball controls and features. It informed the emphasis on timed flipper action, clear rewards and finite ball saves.
- [Glenn Fiedler, Fix Your Timestep](https://gafferongames.com/post/fix_your_timestep/) explains why physics needs a consistent time step. The design keeps a fixed physics enable and separates display sampling from simulation.
- [Project F video timings](https://projectf.io/posts/video-timings-vga-720p-1080p/) documents standard 800×600 timing. The pixel clock, porches, sync widths and polarity follow that mode.
- [Stern Godzilla playfield features](https://www.sternpinball.com/game/godzilla/) describe motorized targets, a moving skyscraper and ball diversion. They informed the idea of physical moving obstacles rather than animation alone.
- [Box2D simulation documentation](https://box2d.org/documentation/md_simulation.html#autotoc_md61) explains velocity-driven kinematic bodies and cautions against teleporting geometry. The RTL uses its own fixed-point collision model and atomic updates; no Box2D software runs on the FPGA.

## Further features to consider

The following costs are engineering estimates, not measured LUT percentages. A new implementation and routed build would establish their actual fit.

| Feature | Fit with this game | Estimated cost and source |
| --- | --- | --- |
| Launch skill shot | Light one existing top lane and reward reaching it shortly after launch; makes the charge control more purposeful | Low: target ID, armed flag and timeout. [Stern Metallica skill shots, page 2](https://sternpinball.com/wp-content/uploads/2025/04/Metallica-Remastered-Rulesheet.pdf#page=2) |
| Timed target hunt | Hit three named objects in 20 seconds for a fixed bonus, using the current lamps and contact bits | Low to medium: timer, progress mask and compact HUD. [Stern Metallica timed modes, pages 11–12](https://sternpinball.com/wp-content/uploads/2025/04/Metallica-Remastered-Rulesheet.pdf#page=11) |
| Nudge/tilt meter | Display warnings and let repeated nudges accumulate toward a short tilt penalty | Low: small meter and decay counter; requires careful play-feel tuning. [Zen Studios nudging and tilt](https://zenstudios.freshdesk.com/support/solutions/articles/43000638115-pinball-essentials) |

Skill shots and a timed target hunt remain possible next steps because they reuse the existing field and rules. Selectable two-ball play is now implemented; its measured hardware cost and verification are recorded in `VALIDATION.md`.
