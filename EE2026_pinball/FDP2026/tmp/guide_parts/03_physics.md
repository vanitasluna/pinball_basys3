## Motion is a sampled calculation, not a moving pixel

Read `pinball_physics.v` for the stored world state and scheduling, then `pinball_collision.v` for the combinational contact calculation. The physics module stores position, velocity, shooter-lane status and visibility separately for each ball. It also owns the moving bumper centres and flipper angles. The collision module receives a snapshot of these quantities and returns corrected position, corrected velocity and a 14-bit contact mask. Scoring belongs to `pinball_game.v`; collision detection does not directly add points.

The board clock is 100 MHz, but the world advances on a 240 Hz enable named `tick`. One world step therefore represents approximately 4.167 ms. Registers remain clocked at 100 MHz; the enable decides when a new physical step may begin. This distinction connects directly to synchronous digital design: a slowly changing game can use a fast clock without inventing another clock domain.

The logical table uses OLED-sized coordinates: x increases to the right and y increases downwards. Consequently positive vertical velocity means falling, negative vertical velocity means rising, and gravity is positive. A ball is more than its displayed integer coordinate. Between x=20 and x=21 there are 256 representable fractional positions.

### Signed fixed-point arithmetic and its units

The position and velocity registers are `signed [15:0]`, with eight fractional bits. The project calls this Q8: divide a stored integer by 256 to recover a logical pixel quantity. Be careful because other references use Q-format names differently; the actual bit width and scale define the representation here.

| Quantity | Stored value example | Meaning |
|---|---:|---|
| Position | 10240 | 40 logical pixels |
| Position | 10368 | 40.5 logical pixels |
| Velocity | 128 | 0.5 logical pixels per physics step |
| Velocity | -256 | -1 logical pixel per physics step |
| Gravity | 2 | 2/256 logical pixels per step squared |

A signed 16-bit register ranges from -32768 to 32767, corresponding to -128 through approximately 127.996 pixels. This covers the 96×64 table, the drain at y=64, and temporary negative values without needing floating-point hardware. Signed arithmetic is essential: interpreting -256 as unsigned gives 65280, an enormous and incorrect positive speed.

For a normal-difficulty free-flight example, suppose:

```text
position_y = 40*256 = 10240
velocity_y = 64       = 0.25 pixels/step
gravity    = 2        = 0.0078125 pixels/step^2

accelerated_vy = 64 + 2 = 66
proposed_y     = 10240 + 66 = 10306 = 40.2578125 pixels
```

If no collision occurs, these become the new registers. The next step adds gravity again: velocity becomes 68 and y becomes 10374, or 40.5234375 pixels. This is semi-implicit Euler integration: update velocity first, then position using the updated velocity. At 240 steps/s, stored velocity 64 means 60 pixels/s, while normal gravity means `2*240*240/256 = 450 pixels/s^2`. These are table coordinates, not physical metres.

The OLED receives the integer part after clipping to x=0..95 and y=0..63. The native VGA renderer also receives fractional positions. Its table mapping uses eight screen pixels per logical pixel, with offsets x=16 and y=32. Thus x=40.5 can appear at native x=340 instead of being rounded to the same position as x=40. The physics is shared by both outputs; display resolution does not change game speed.

### Limits and why the ball remains playable

`clamp_horizontal` and `clamp_vertical` deliberately cap velocity. These are experience decisions as well as numerical bounds:

| Limit | Q8 units per step | Logical pixels/s |
|---|---:|---:|
| Horizontal, either direction | 256 | 240 |
| Upwards | 320 | 300 |
| Downwards before the lower region, or in the shooter lane | 160 | 150 |
| Downwards outside the lane at y >= 38 | 76 | 71.25 |

Difficulty chooses gravity 1, 2 or 3, giving 225, 450 or 675 pixels/s². It does not replace these speed caps. From y=38 to the flipper pivot height y=53, the capped descent takes at least about `15/71.25 = 0.211 s` if unobstructed. This leaves a useful reaction interval on a small table. Extremely fast, physically realistic motion would often be less enjoyable here.

Preparation places ball 1 at (89,56) and optional ball 2 at (89,60). A single launch sets each available ball's initial vertical velocity to `-288-launch_power`, then subsequent physics steps apply gravity and the upward cap. Charge therefore influences a bounded launch; it does not allow unlimited speed. At the lane exit, when the proposed y reaches 15 or less, ball 1 receives horizontal velocity `-160-shot_power`, ball 2 `-128-shot_power`, and both receive vertical velocity -56. Different starting heights and exit velocities separate their paths after the shared shot.

The collision block confines an in-lane ball centre to x=85..93. Outside the lane, the left boundary is x=3; the right lane divider limits x to 83 at y>=18, with x=93 allowed in the upper opening. The top boundary is y=10. A round drain is possible after collision correction reaches y>=64 inside x=30..56, outside the lane. Display clipping at y=63 is presentation only: it does not stop the physical ball reaching the drain.

## Contacts: approximating useful geometry in hardware

`pinball_collision.v` is an `always @*` combinational block. It initializes every output and temporary, then applies contact tests in a stable priority order. A `solid_contact` flag allows one main solid-object response per step: bumpers, stand-up targets, slings, side targets, flippers and guides are considered in order. Outer boundary correction still follows. Sensor regions such as rollovers and the spinner report passage without stopping the ball.

This ordered approximation is intentional. The project is an arcade model, not a general rigid-body solver. It has no ball-to-ball collision, spin, continuous contact manifold or general search for the earliest collision among all objects. Two balls may pass through each other. This keeps the hardware cost and behavior predictable.

### Inflated objects and simple distance tests

Rather than calculate a circle intersecting another shape, enlarge the object by the ball radius and treat the ball centre as a point. The drawn bumper radius is three logical pixels and the ball radius is one. Its clearance envelope is an octagon described by:

```text
abs(dx) <= 1024              // 4 pixels
abs(dy) <= 1024              // 4 pixels
abs(dx) + abs(dy) <= 1472    // 5.75 pixels
```

Here `dx` and `dy` are ball position minus bumper centre in Q8 units. These comparisons use absolute values, adders and comparators instead of square roots. The response chooses an axis or 45-degree normal, providing eight useful rebound directions without trigonometric hardware.

The three permanent stand-ups at (34,20), (42,20) and (50,20) use a square clearance of ±2 pixels around their centres. Slings at (17,41) and (69,41) use a diamond: `abs(dx)+abs(dy)<=1024`, a Manhattan radius of four pixels. These shapes match the inexpensive drawn forms well enough for play.

### Why checking the final position is insufficient

A ball can graze a corner between two samples even though both endpoints are outside the clearance shape. This is called tunnelling. The code therefore also tests the segment from the previous ball position to its proposed position.

`swept_octagon` considers the four pairs of octagon faces. Each face has a projection coordinate perpendicular to it and a tangent coordinate along it. For a vertical face these are x and y; for a diagonal face they are x+y and x-y. Reflecting negative projection values lets one formula describe either sign of a face.

Suppose the old projection P0 is outside boundary B, and the new projection P1 crosses inward. The crossing fraction would be:

```text
D = P0 - P1        // positive denominator
N = P0 - B
t = N/D
crossing_tangent = T0 + (T1-T0)*N/D
```

Crossing the infinite line is insufficient: the crossing must fall on the finite face. If its tangent extent is ±L, division can be removed:

```text
I = T0*D + (T1-T0)*N
-L*D <= I <= L*D
```

This is what the signed wide `intercept` and `tangent_bound` calculations implement. For example, with B=1024, L=448, P0=1100, P1=900, T0=300 and T1=500, D=200, N=76 and I=75200. Because L*D=89600, the crossing lies on the face: its mathematical tangent is 376. With T0=500 and T1=700 instead, the crossing tangent becomes 576, beyond 448, and the segment is a near miss. A collision detector that only asks whether the line was crossed would falsely bounce the second trajectory.

Stand-ups reuse `swept_clearance` for rectangular clearance. The bounded step sizes allow it to select the old outside face instead of building every face calculation separately. The sling diamond becomes a rectangle in transformed coordinates `u=x+y`, `v=x-y`, so the same function handles its swept corners. The 17-, 18- and 36-bit intermediates matter: products can overflow even when each coordinate fits in 16 bits. Width selection is a direct application of finite-width arithmetic taught in digital design.

### Correct penetration, reflect only inward motion

Detection is followed by two separate actions: move an overlapping ball outside the object, and change velocity only if it approaches the surface. Otherwise an already departing ball can be reflected back into the object every step and appear stuck.

For a right-facing bumper surface, positive x is outward. A relative x velocity below zero approaches the surface, so it reflects; positive x is already leaving. For a diagonal, the approach expression adds the signed components along the selected normal. The `approach<0` test also gates the hit event. Axis bumper rebounds retain roughly 7/8 of incoming speed, add a small impulse of 24 Q8 units, and enforce a useful minimum of 160. Diagonal rebounds swap/sign-change the two components, then add a 32-unit outward impulse. These impulses deliberately make a pinball bumper energized rather than a passive wall.

Moving bumpers require relative velocity. If the bumper itself has velocity c, reflect `ball_velocity-c`, then add c back. Old and new relative positions also subtract the matching old and new bumper centres. Mixing an old ball position with a new bumper centre would distort the swept segment and create false hits.

The left bumper moves vertically at x=26, y=22..28; the right moves horizontally at y=22, x=58..66. Each accepted world step moves a centre by four Q8 units, or `4*240/256 = 3.75 pixels/s`. End comparisons reverse direction. Both ball calculations see one shared old/next pair, and the centres commit once after the complete world step. Do not advance the world once per ball: that would make two-ball mode move bumpers twice as fast.

### Flippers are controlled surfaces with different responses

Each flipper has angle states 0..4. Holding the button advances one angle per accepted physics tick; releasing retreats one. Four transitions take about 16.7 ms. The left pivot is (21,53), the right (65,53), and each reaches 18 pixels toward the middle. A lookup function gives inner-tip offsets +5,+3,+1,-2,-4, approximating rotation without sine/cosine.

The surface height is `53*256 + local_x*tip_offset/18`. The previous ball height is checked as well as the proposed height. A ball travelling below a flipper should continue below it, rather than being teleported onto its top. A rising flipper may sweep into a nearby ball within its clearance band.

A rising flipper gives a strong upward and inward impulse that grows toward the tip. A held raised flipper gives a weaker return. A released flipper halves sufficiently fast downward speed, while a low-energy ball rolls toward its tip instead of receiving an endless upward impulse. Post-collision speed limits still apply. Side guides join the visible pivots; matching rendered geometry and collision endpoints prevents invisible rails.

## Sharing one collision engine between two balls

The expensive combinational collision block exists once. Physics chooses a ball's operands, snapshots them into `collision_*` registers, waits for the calculation, and stores its result. This is resource sharing controlled by a small sequential scheduler, not two concurrent software function calls.

At 100 MHz one clock is 10 ns. A collision transaction gets 16 clocks, or 160 ns. One-ball mode commits after that window. With both balls launched, the first result goes into `stage_*` registers while the displayed/live ball positions remain unchanged. A separate handover clock selects and captures ball 2's operands, followed by its 16-clock window:

```text
edge 0     capture ball 1 and the world's old/next bumper centres
edge 16    stage ball 1 result; select second-ball work
edge 17    capture ball 2 operands
edge 33    commit both ball results and the moving centres together
```

The pair costs 330 ns, negligible against the 4.167 ms physics period. Atomic final position commits prevent a renderer or effects module observing a newly moved ball 1 alongside an old ball 2. If only one survives, it returns to the 16-clock path; losing one ball does not immediately end the round.

Both balls can hit the same object in one step. OR-ing their contact masks would count that as only one contact. At the pair commit, the first mask appears with `hit_ball=0`; the second appears four system clocks later with `hit_ball=1`. If both balls drained, the final `drained` pulse appears six clocks after commit. Registered outputs are consumed by the game module on the following clock edge, so the relative sequence remains first contact, second contact, final drain. This preserves both awards before the game leaves PLAY. The four-clock spacing also leaves time for combo/progress changes from the first contact to influence the second transaction.

Each ball has separate `hit_armed` bits and 14 cooldown counters. A scored contact disarms its bit and starts a 16-step cooldown, about 66.7 ms. Time expiry alone does not rearm it: the ball must also leave a larger object-specific envelope. This hysteresis prevents repeated points while resting against a bumper or sitting inside a sensor. The other ball retains independent eligibility.

A one-clock nudge may arrive between physics ticks, so `nudge_pending` holds it. The accepted batch captures it once for both calculations; a late nudge waits for the next batch. Each eligible ball receives ±48 horizontally toward the middle, and -80 vertically, subject to limits. In-lane balls receive no nudge. This avoids the bug where a late control pulse affects only ball 2.

Pause prevents accepting another world step. An already accepted transaction finishes normally, including deferred contact/drain outputs; the rules module explicitly accepts that final event while paused. Reset or `prepare` instead cancels the calculation, staging and pending event timers. Preparation is used for a new round/menu, so stale contacts cannot arrive in the newly prepared game.

### The timing constraint is a promise made by the RTL

`Pinball_Physics_Timing.xdc` applies a 16-cycle setup exception and a matching 15-cycle hold exception from isolated collision snapshots to specified result-state registers. Ordinary control paths still have a 10 ns requirement. The calculation is not required to settle in one clock because its operands remain unchanged and its result is not captured until 16 clocks later.

This is legal only because the scheduler actually enforces that contract. Declaring a slow path multicycle does not make unsafe hardware correct. Changing snapshots midway, committing early, or broadly applying the exception to controls would invalidate it. The paired hold adjustment prevents the setup exception from also imposing an unintended later hold requirement. The build checks that the expected snapshot registers exist; timing reports must still be inspected after implementation.

## Recreate the physics incrementally

Begin with one signed Q8 position/velocity pair and a tick enable. Simulate free flight against the worked example before adding graphics. Add speed clamps and axis walls, separating penetration correction from inward-only reflection. Then implement one stationary bumper and test it from every side. Add flippers and a drain; ensure a released flipper cannot sustain the ball forever. Only after this works add sensors, scoring pulses, moving-object relative coordinates and swept corners. Finally share the engine with a second set of registers and add atomic commit/event scheduling. This order makes each failure attributable to a small new idea.

Useful exercises have measurable outcomes:

- Send a ball away from an overlapping wall: its position corrects, but velocity does not reverse inward.
- Compare one exact corner crossing with a near miss: only the crossing reports a contact.
- Keep a ball inside a sensor for many ticks: it scores once; exiting and re-entering after cooldown permits another score.
- Hit one bumper simultaneously with two balls: two masks appear four clocks apart, with independent arming bits.
- Pause after accepting a batch: that batch finishes once; later ticks cause no movement.
- Prepare during the second calculation: no staged position, contact or drain leaks into the next round.
- Drain one ball: the other continues. Drain the last: exactly one round-drain pulse follows the final contacts.

`tb_physics.sv`, `tb_collision.sv`, `tb_multiball.sv` and `tb_two_ball_game.sv` cover these kinds of contracts. The additional archived geometry oracle under `build/final_physics_audit/` compares swept cases against an independent mathematical model. This is more informative than checking that a simulation simply runs: state the numerical result, event count and latency that correct hardware must produce.
