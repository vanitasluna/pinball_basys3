## How one game produces two different pictures

The display system answers a very specific question: **given the current scene and the coordinate of the pixel being scanned, what colour should that pixel be?** It does not advance physics or award points. That separation lets one authoritative game feed a small OLED and a larger VGA screen without duplicating the game rules.

The main files divide this work as follows:

| File or module | Responsibility |
|---|---|
| `pinball_renderer.v` | Compact 96×64 picture, 3×5 characters, OLED-sized shapes and trail dots |
| `pinball_vga_renderer.v` | Native 800×600 picture, 5×7 characters, fine movement, larger HUD and effects |
| `pinball_effects.v` | Clocked storage and movement of trail samples and impact sparks |
| `pinball_vga.v` | Raster counters, blanking, horizontal/vertical synchronization and registered VGA colour outputs |
| `pinball_vga_clock.v` | MMCM and clock buffers producing the 40 MHz pixel clock |
| `pinball_scene`, `pinball_vga_scene` in `My_Top_Module.v` | Unpack a frame's scene bundle and connect the appropriate renderer |
| Protected `Oled_Display.v` | OLED initialization, frame scheduling and SPI transmission |

The OLED and VGA renderers are **combinational circuits**. An `always @*` block describes comparisons, arithmetic and multiplexers that settle to a colour. It is not a CPU painting the screen by executing a loop over every pixel. The display controller supplies successive coordinates; the hardware answers each coordinate separately.

## Procedural drawing and layer priority

This project mostly draws mathematically rather than reading a full-screen bitmap. A rectangle needs bounds comparisons. A diamond can use `abs(x-cx)+abs(y-cy)<=radius`. A circle uses squared distance, with carefully limited operand widths. Rails use constant coordinates or line equations; flippers use signed distance from a short line segment. Lighting and outlines are extra tests near each shape's edge.

The following is a **simplified teaching example, not a replacement module**:

```verilog
always @* begin
    pixel = BACKGROUND;                   // Every path has a default.
    if (inside_table) pixel = TABLE_COLOR;
    if (inside_trail) pixel = TRAIL_COLOR;
    if (inside_bumper) pixel = BUMPER_COLOR;
    if (inside_ball) pixel = BALL_COLOR;   // Latest assignment wins.
end
```

Blocking assignments express an ordered selection of the final colour. Several conditions may hold for the same pixel; the last applicable assignment wins. This is the painter's-order rule. Synthesis builds priority logic from it, so layers affect both visual correctness and timing.

The actual renderers draw subdued backgrounds and comic reactions before trails and table objects. Trails remain beneath obstacles. Text, panels and pointers come later; **live PLAY balls are drawn last**, above notifications, sparks and the pointer. READY, PAUSE and OVER have their own overlay treatment, so do not generalize the PLAY rule to every state.

Trail samples are painted from index **7 down to 0**. Index 0 is the newest. An older dim square must not overwrite a brighter fresh square where they overlap. This is a useful example of a visual bug that can exist even when every coordinate and colour individually looks correct.

Keep collision geometry and visible landmarks consistent. The bright ring around a bumper is an animation, not an enlarged collision boundary. The circuit cat is decoration, not an obstacle. When adding a wall, change and verify its intended collision representation as well as its picture; a drawn wall without a collision feels hollow, while a hidden collision feels unfair.

## Coordinates: logical playfield versus native VGA

Physics uses the compact table's coordinate system, with eight fractional bits. For example, a raw X position of `10816` represents `10816/256=42.25` logical pixels. The OLED shows the integer part, `42`; VGA can show the fractional motion more finely.

The native table fits inside a 768×512 region with origin `(16,32)`. The conversion is:

```text
native_x = 16 + floor(x_fp / 32)
native_y = 32 + floor(y_fp / 32)
```

Dividing Q8 coordinates by 32 is equivalent to multiplying the logical position by eight and discarding only fractions smaller than one native pixel. In RTL, slices such as `ball_x_fp[14:5]` implement that conversion by wiring. For `(42.25,35.5)`, raw positions are `(10816,9088)`, OLED centre is `(42,35)`, and VGA centre is `(354,316)`. One VGA pixel represents one-eighth of a logical pixel. Five low Q8 bits are discarded; three fractional bits beyond the logical integer position remain useful.

The VGA renderer receives the **full native coordinate**, not the OLED colour expanded into an 8×8 square. Its first ball is a radius-eight circle with highlights, its second ball uses a chamfered silhouette to limit additional arithmetic, and its bumpers have circular faces and smooth rings. Native text and menus have their own placement and scale. Consequently the large screen gains detail and finer motion, while the OLED remains legible at its physical resolution.

The legacy logical `x`/`y` outputs of `pinball_vga` still exist, but Top leaves them unconnected. `pixel_x` and `pixel_y` drive `pinball_vga_scene`. Connecting the legacy outputs instead would throw away the native rendering advantage.

## Colours and small font memories

Both renderers return **RGB565**: red in bits `[15:11]`, green in `[10:5]`, and blue in `[4:0]`. There are 5, 6 and 5 bits per component. Full red is `16'hF800`, full green is `16'h07E0`, and white is `16'hFFFF`. A protected ball's principal bright blue shade, `16'h05BF`, has red 0, green 45/63 and blue 31/31, giving a cyan-blue rather than a dark pure blue.

The OLED consumes all 16 bits. Basys 3 VGA has four output bits per channel, so `pinball_vga` selects:

```verilog
red   <= visible ? pixel[15:12] : 0;
green <= visible ? pixel[10:7]  : 0;
blue  <= visible ? pixel[4:1]   : 0;
```

These are the most significant four bits of each channel; they are not three adjacent four-bit slices of the 16-bit word. Misreading this packing causes wrong colours. In the blue example the VGA outputs are `(0,11,15)`.

The font functions are small constant lookup tables: a character code selects a 15-bit OLED glyph or a 35-bit VGA glyph. Calling them ROMs describes their behaviour, not a guarantee of block-RAM inference. With small constant tables, Vivado may implement them in LUT logic.

For the OLED, `A` is `010_101_111_101_101`: five rows, each three bits wide. After selecting a message's character and its local glyph coordinate `(gx,gy)`, bit `14-(gy*3)-gx` determines whether to draw ink. Native VGA similarly uses `34-(gy*5)-gx`. Blank glyph cells leave the previously drawn colour visible. Character spacing prevents adjacent glyphs from touching.

Scale comes from coordinate shifts. A doubled character divides local coordinates by two; a fourfold character divides by four. These operations repeat glyph pixels without storing additional fonts. Each renderer selects one text region and passes it through a shared decoder, avoiding a separate font circuit for every label. The code's signed arithmetic, explicit widths and range guards remain important: subtraction and glyph indexing must not wrap outside the selected region.

## OLED scan and the supplied SPI driver

The OLED driver's linear `pixel_index` runs through 6144 positions. Top computes `oled_x=pixel_index%96` and `oled_y=pixel_index/96`. Index 0 means `(0,0)`, 95 means `(95,0)`, 96 means `(0,1)`, and 6143 means `(95,63)`. These are constant division and remainder operations that synthesis must implement; they are not software library calls.

Top derives the OLED clock by buffering bit 3 of a four-bit divider, giving `100 MHz/16=6.25 MHz`. The protected controller initializes the display, sets its column/row address range and serializes each RGB565 word in **16 clock cycles**. Its frame divider targets approximately 60 frames per second. The pixel payload alone occupies `6144×16/6.25 MHz≈15.729 ms`; initialization and frame commands are separate from that payload.

Read the actual edges carefully: `Oled_Display` updates its state, counters and SPI shift register on the **falling edge** of its `clk`. While busy, `sclk` follows that clock; the falling-edge update prepares data for the next rising SPI edge. Top captures `oled_scene` on the **rising edge** when `oled_frame` is asserted. This gives the renderer time to settle before the driver takes the next pixel word on a falling edge. Describing both modules as rising-edge consumers would hide an important half-cycle timing relationship.

`frame_begin` identifies a frame boundary; `sample_pixel` identifies pixel sampling opportunities; `sending_pixels` indicates the streaming phase. Top uses `frame_begin` for scene capture and supplies combinational `pixel_data` continuously. It does not need a framebuffer or to alter the supplied controller. The JC wiring is defined by Top and the constraints; `JC[2]` is tied low because that OLEDrgb pin is unconnected.

## VGA raster timing and the pixel clock

VGA requires a continuously timed raster. The monitor receives colour values during active video and synchronization pulses during blanking. The 800×600 mode is:

| Interval | Horizontal clocks | Vertical lines |
|---|---:|---:|
| Visible | 800 | 600 |
| Front porch | 40 | 1 |
| Positive sync | 128 | 4 |
| Back porch | 88 | 23 |
| Total | 1056 | 628 |

Counters `h` and `v` cover `0..1055` and `0..627`. Horizontal sync is high for `840<=h<968`; vertical sync is high for `601<=v<605`. RGB is forced to zero outside `h<800 && v<600`. At 40 MHz, frame rate is `40,000,000/(1056×628)≈60.317 Hz`. Do not substitute 25 MHz and keep these counts: that changes the video mode.

The MMCM multiplies the 100 MHz input by ten to a 1 GHz internal oscillator, then divides by 25 to obtain 40 MHz. BUFG buffers distribute the output and feedback clocks. Top holds the VGA path in reset until lock is established, with reset release synchronized to the pixel clock.

Colour and sync outputs are registered together. At a rising edge they use the pre-edge `h`/`v`, while the counters advance for the next pixel. This consistent one-cycle registration is intentional; delaying only colour or only sync would misalign the picture. During blanking, native renderer coordinates are clamped to zero instead of allowing a shortened coordinate bus to wrap.

An external active VGA-to-HDMI converter translates the board's VGA output for an HDMI monitor. This project does not generate HDMI TMDS signals in FPGA logic.

## Stable pictures: producer registers and frame snapshots

Game values change at different instants. Physics takes several 100 MHz clocks to complete a transaction, scores update on accepted events, and effects have their own storage. Sending those live wires directly to a scanning display would let a ball appear at its old position on one row and its new position on another: **tearing**.

Top first registers complete display payloads at 100 MHz in `oled_transfer` and `vga_transfer`. Each display then copies its transfer register only at its own `frame_begin`:

| Bundle | Width | Contents and use |
|---|---:|---|
| OLED scene | 318 bits | State/HUD, integer ball coordinates, mode/visibility, moving centres, compact trail samples |
| VGA scene | 611 bits | Common state/HUD plus fractional positions, native sparks and native trail samples |

The scene unpackers mirror the concatenation order. The frozen `oled_scene` or `vga_scene` feeds every pixel of that frame. The two displays sample at independent boundaries, so they can show neighboring game instants; each individual picture remains coherent. A snapshot is coherent as a bundle, but it is not a promise that every producer has finished its latest game transaction at that exact instant.

The producer registers also remove coordinate-conversion logic from a tight 100-to-40 MHz crossing. Here the clocks derive from the same board oscillator, use clock buffers, and are checked as **related clocks** by timing constraints. Copying a many-bit bus at a frame edge is not a general solution for genuinely asynchronous clocks. For independent clocks, use a proper handshake, stable-data protocol or asynchronous FIFO; independently synchronizing each data bit can mix values from different updates.

## Effects that consume little state

`pinball_effects` stores eight trail samples and two alternating banks of four sparks. Its two-bit phase divides the approximately 240 Hz physics enable by four: trails are sampled at approximately 60 Hz. New positions enter index 0; older samples shift toward index 7. Valid bits prevent uninitialized history from appearing. Renderers assign three brightness bands by sample age; these are discrete fades, not alpha blending.

In two-ball play, the shared trail follows the white ball while it survives, then the gold survivor. `trail_reset` clears old white-ball history on that handoff, and Top masks stale validity in the first outgoing scene. Otherwise an apparent line could connect two unrelated ball paths. Two balls do not each have a separate eight-sample trail.

An accepted impact supplies the corrected hitting ball's position. Four sparks replace the oldest alternating bank, allowing two closely spaced impacts to retain separate origins. Spark positions and velocities use fixed-point storage; movement occurs at physics ticks. A four-bit lifetime decreases at the slower phase, starting at 15, for roughly a quarter-second maximum burst. Out-of-screen sparks expire. Active motion freezes when paused, although an already accepted impact may finish and create a frozen burst. The OLED uses compact rings and flashes; detailed spark particles are sent to VGA.

Protection colour comes from the snapshot's `save_timer!=0`, shared by both balls and the trail. The OLED shows ceiling seconds as `S1..S6`; VGA shows `SAFE` with seconds. On expiry, normal white/gold palettes return. Renderers describe protection; the game module decides whether a drain consumes a life.

Original circuit-cat masks react to events 1/3/5/7 (major rewards), 6 (nudge) and 4 (save). They appear only while `feature_timer>120`, the first approximately half-second of a 240-tick notification. PLAY permits these reactions; READY permits the saved reaction and moves it below the charge area. Repeated combo event 2 is excluded to prevent constant interruption. OLED expresses the reaction with tiny faces, sweat or stars; VGA adds “YATTA!”, “NANI!” or “PHEW!”. The latest notification can replace an earlier one. It is not an event queue.

The pointer uses the same logical mouse coordinates and hover rectangles as Top's click logic. VGA transforms the pointer to the native origin/scale; OLED draws a compact cross. A hidden or disabled pointer must not highlight a button. Visible boundaries and accepted clicks should be tested together.

## Build your own display system in manageable steps

Start with fixed colour bars and a grid. Verify RGB packing, corner coordinates, OLED order and VGA timing before connecting game state. Next draw one stationary shape, then drive it with a clocked coordinate. Add a frame snapshot and deliberately change the producer halfway through a frame to verify that the current picture stays stable. Add integer OLED motion first, then fractional native motion, HUD text, and finally effects.

For verification, check pixels at shape centres, edges and just outside bounds; inspect full-frame captures for every state. Test overlapping old/new trails, protected and unprotected balls, drained visibility, both balls over a notification, pointer corners and modal overlays. `tb_renderer`, `tb_vga_renderer`, `tb_vga`, `tb_vga_clock`, `tb_effects` and `tb_top` cover these different responsibilities. Test bundle packing with nondefault fractional values: all-zero values cannot reveal swapped fields.

Finally, rerun implementation timing. A small extra comparison late in a pixel selector can extend a priority chain enough to miss the 25 ns VGA period. Shared arithmetic, bounded widths, constant masks and late colour gates help control cost. Correct simulation proves behaviour; successful routed timing proves the implemented circuit can meet its specified clocks. Both are required for a dependable EE2026 display design.
