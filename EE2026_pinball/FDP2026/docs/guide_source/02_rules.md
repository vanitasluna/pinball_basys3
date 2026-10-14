## From controls to game rules

The module `pinball_game` answers questions such as “is the game running?”, “does this drain cost a life?”, and “what score should this contact earn?”. It does not calculate ball trajectories or produce display pixels. That separation is the first design idea to keep when rebuilding the project: the rules consume events from the physics datapath and publish state for the displays. `My_Top_Module` connects these modules and translates physical inputs into commands.

Every game register uses the 100 MHz `clk`. The slower `tick` is a one-clock enable, not a separate game clock. `PHYSICS_TICK_LAST=416665` makes one tick every 416,666 system clocks, approximately 240.000384 Hz. Calling it 240 Hz is appropriate for human-scale timing. The rules change state on any 100 MHz edge, but most timers change only when `tick` is true. A 480-tick countdown therefore takes approximately two seconds, rather than 4.8 microseconds.

There are two input meanings. A held level remains true throughout a press; a pulse requests one action. Debounced `buttons` are held levels and `button_press` contains rising-edge pulses. Confusing them would make a held menu button cycle difficulty thousands of times or would charge the spring for only 10 ns.

| Command in the RTL | Source and meaning |
|---|---|
| `start_press` | C rising edge or a mouse click in the displayed start/restart/resume region |
| `launch_down` | Held C or held mouse middle button |
| `pause_press` | U rising edge; its meaning in MENU is handled separately |
| `menu_press` | D rising edge |
| `level_left`, `level_right` | L/R rising edge or a click on the appropriate half of the menu difficulty row |
| `left_pressed`, `right_pressed` | Held L/R or mouse left/right button; routed directly to physics |
| `nudge_request` | C rising edge or middle-button rising edge during PLAY, outside the lane, with the cooldown expired |

SW0 enables mouse commands; SW15 resets the system. SW1 has no mode-selection role. The mouse held controls use `mouse_prev`, the last complete packet, so partially received button bytes cannot release a spring or move a flipper prematurely. A click additionally uses `mouse_event_d`, ensuring its cursor coordinates belong to that completed packet.

In MENU, U or the mouse ball-mode row toggles `menu_two_ball_mode`. Starting a game copies the selection into `two_ball_mode`. The connection `menu_two_ball_mode ^ mode_change` deliberately handles U and C arriving together: the new game uses the selection the player just requested. The chosen mode remains fixed for that game. `nudge_cooldown` loads 480 ticks and counts down only during active play; the top level also prevents a nudge while all surviving balls are in the shooter lane.

## The five-state controller and event priorities

A finite-state machine stores the current operating mode and selects which transitions are legal. Here `state` is a three-bit register with five named values. The names are useful because readers can reason about READY without memorising the binary encoding.

| State | Value | Main behaviour and exits |
|---|---:|---|
| `MENU` | 0 | Choose difficulty and ball mode; start prepares a new game |
| `READY` | 1 | Hold/release the launcher; pause can suspend preparation |
| `PLAY` | 2 | Physics active, scores accepted, play timers advance |
| `PAUSE` | 3 | Freeze ongoing play; U or a start/resume command restores `resume_state` |
| `OVER` | 4 | No lives remain; start prepares a fresh game |

`active` is the combinational expression `state == PLAY`. Physics uses this enable to decide whether it may begin another update. `prepare` and `launch` are one-clock command pulses: the clocked block clears them by default, then asserts the appropriate one when a transition needs it. Preparing resets ball placement; launching consumes the current `charge`. An illegal state falls back to MENU, while OVER stays OVER until a higher-priority command changes it.

The explicit transition order is reset first, then `menu_press`, then `new_game`, then an accepted `drained` event, then ordinary state-specific commands. This order is part of the specification. If D, U and drain arrive together, returning to MENU wins. If the last unprotected life drains on the same edge as U, OVER wins. For a non-final or saved drain, `next_life_paused` preserves the simultaneous pause/resume request and records READY as the state to resume into.

Pause needs special care because physics takes several clocks to finish an update. Setting `active=0` prevents another update but cannot erase one already calculating. `accepts_play_event` therefore remains true in PAUSE when `resume_state==PLAY`. That final hit or drain is still processed, including its save entitlement and award. A pause from READY does not accept gameplay results. The score pipeline also finishes already accepted transactions during pause or drain. This distinction between stopping new work and finishing outstanding work is useful in any FSM controlling a multicycle datapath.

Counters are not all governed by the same condition. `anim`, hit flashes and `feature_timer` advance on `tick` in every state except PAUSE. Combo, gold-target and spinner timers advance only in PLAY. The pseudorandom `rng` continues on system clocks even while paused. Thus “paused” means frozen gameplay, not that every flip-flop in the device stops changing.

## Charge, lives and protected relaunches

`charge` is a six-bit value, 0 through 63. In READY, holding `launch_down` sets `charging`. A two-bit `charge_div` permits one power step per four ticks: approximately 60 steps per second. `charge_falling` selects whether the next step increases or decreases power. The sequence is `0,1,...,62,63,62,...,1,0,1,...`; direction reverses on arrival, with no extra endpoint hold. Each half-cycle takes approximately 1.05 seconds. Releasing after a charge asserts `launch`, changes the state to PLAY, and clamps a power below 16 up to 16 so a brief tap can leave the lane.

The first C press starts the game; continuing to hold C in READY begins charging. A READY pause freezes the current spring level, but resuming clears `charging`, `charge`, `charge_div` and direction. This prevents a release during pause from unexpectedly launching old stored power. The player can charge again after resuming.

`lives` counts remaining turns, including the current one. A new game sets it to three. An unprotected drain changes three to two, then two to one; draining with one remaining sets zero and OVER. A “turn” can contain a pair of balls. `pinball_physics` reports `drained` to the game only when the final surviving partner drains, so losing the first ball in two-ball mode does not deduct a life or prepare another shot. Both balls are prepared and launched together for the next turn.

Protection deliberately allows more than three shots. On a fresh-life launch, `launch_save_eligible` loads `save_timer=720`, approximately three seconds. The timer decreases only during PLAY and when `in_lane` is false. In two-ball mode, `in_lane` remains true only while every surviving ball is in its lane, so the countdown begins when either survivor enters the table. Completing both side targets grants `save_timer=1440`, approximately six seconds.

If the final drain occurs while `save_timer!=0`, or on the same edge as `target_complete`, the game prepares another shot without reducing lives. It consumes protection by clearing the timer and setting `launch_save_eligible=0`. That saved relaunch receives no automatic three-second save. A later unprotected life loss makes the next life eligible again. The protection is shared by the turn; it is not a separate timer for each ball. The renderers use the same published `save_timer` to make protected balls and their trail bright blue.

## Contact masks, combos and collection rewards

`hit_events` is a 14-bit event mask. Each bit identifies a scoring contact, not a persistent overlap. Physics filters raw collision contacts with per-ball arming masks, so one ball resting near a bumper cannot earn points every tick. In two-ball mode the two results are emitted as separate transactions, allowing both contacts to score.

| Bits | Contact group | Base units per contact | Collection memory |
|---|---|---:|---|
| 0–2 | Left moving, right moving, and central bumpers | 1 | `mission_progress[2:0]` |
| 3–4 | Left/right side targets | 2 | `target_progress[1:0]` |
| 5–7 | Three upper rollover lanes | 1 | `table_progress[2:0]` |
| 8 | Spinner | 1 | No collection bit |
| 9–10 | Left/right slings | 1 | No collection bit |
| 11–13 | Three upper stand-up targets | 2 | `table_progress[5:3]` |

One unit is half a displayed point. A transaction ORs its bits into the remembered collection, for example `mission_next = mission_progress | hit_events[2:0]`. AND-reduction `&mission_next` means all three bumper bits are set. Completion awards its bonus and resets just that collection, making it repeatable. The bumper mission, side pair, rollover trio and stand-up bank award respectively 10, 5, 6 and 8 half-point units: 5, 2.5, 3 and 4 points.

Combo is a multiplier for the base contact units. With `combo_timer==0`, the next transaction uses ×1. Each following transaction within 480 ticks increases it through ×2 and ×3 to a maximum ×4, and reloads the two-second window. Multiple bits in one transaction increase combo once; they all use that transaction's multiplier. Flat collection and gold bonuses are added afterwards, so they are not multiplied.

The gold target is one of bumper bits 0–2. `bonus_timer` starts at 720; the target is active for timer values 480 down to 1, giving about one second waiting followed by two seconds active. A gold hit grants 5 units and restarts the cycle. Expiry also restarts it. The LFSR `rng` chooses a target from its lowest two bits, mapping value 3 back to target 0. This is inexpensive variation with a slight selection bias, not a uniform random-number generator.

All earned bonuses accumulate even if several complete together. Only the displayed `feature_event` has priority: bumper jackpot, side reward, table completion, gold, then combo. Event codes are 1 gold, 2 combo, 3 bumper jackpot, 4 saved ball, 5 side reward, 6 nudge and 7 table bonus. Notifications load `feature_timer=240`, about one second; a newer qualifying notification replaces the previous one. Each hit also loads its `flash_timer` to 24 ticks, about 100 ms. Spinner hits add three to `spinner_phase` and load 120 ticks; another phase step occurs every four active ticks while that timer runs.

## Half-point scoring and the three-edge pipeline

Four seven-segment digits can represent 0000–9999. `score_bcd` and `high_bcd` therefore hold four binary-coded decimal nibbles: `16'h0123` represents decimal 123. It is not the binary integer `16'd123`. The carry function `add_bcd` adds each digit and propagates a decimal carry; a carry beyond the thousands digit saturates the result at `16'h9999`. Valid BCD values also compare in numeric order, so the independent `score_bcd > high_bcd` comparison is safe.

Scoring is pipelined to avoid placing combo arithmetic, conversion and four-digit carry on one 100 MHz path. Stage 1 accepts the event and registers `award_units_1`. Stage 2 adds the stored `score_half`, converts the whole part to `award_bcd_2`, and preserves the low bit as the new fractional remainder. Stage 3 commits the BCD addition and updates `last_award_bcd`. Valid flags `award_valid_1` and `award_valid_2` distinguish a real zero-point fractional credit from no transaction.

Consider starting with score 0098, half remainder 0, and expired combo. Two consecutive bumper-contact transactions earn 1 unit at ×1 and 2 units at ×2. No collection or gold bonus applies:

| Rising edge | Newly completed action |
|---|---|
| E0 | Capture A = 1 half-point unit |
| E1 | Convert A: whole credit 0, remainder 1; capture B = 2 units |
| E2 | Commit A: score stays 0098; convert B + remainder: credit 1, remainder 1 |
| E3 | Commit B: score becomes 0099; `last_award_bcd=0001` |
| E4 | Independent high-score register catches up to 0099 |

The earned total is 1.5 points, with 0.5 retained for a future transaction. Conversion happens in transaction order, so adjacent awards cannot lose that remainder. The largest synthetic transaction, all 14 contacts at ×4 plus every applicable flat bonus, is 110 units or 55 points. That bound justifies seven-bit award registers and a small compare/subtract decimal converter instead of a general divider. At saturation, `last_award_bcd` still describes the transaction's whole credit rather than the smaller increase visible in the capped score.

Reset clears both scores. A new game clears the current score, fractional carry and pipeline valid bits but preserves the session high score. Returning to MENU also preserves the high score. A drain resets combo but preserves accumulated score and collection progress; those collections reset on completion or a new game.

## Sequential reasoning and a rebuilding exercise

In `always @(posedge clk)`, nonblocking assignments read the pre-edge values and schedule new register values. This explains why E1 uses A while also accepting B, and why high score trails a committed score by one clock. It also explains timer tests such as `if(combo_timer==1)`: the condition sees the old one while decrement schedules zero. Later assignments to the same register in this block win, intentionally allowing a fresh hit to reload a timer after the generic countdown would decrement it.

For a small rebuild, first implement MENU, READY, PLAY and OVER with one ball, a held spring control and one bumper event. Add PAUSE and a remembered resume state next. Only after those transitions work should you add a decimal score and staged awards. This progression exercises the EE2026 concepts of combinational next-value logic, sequential registers, FSM control, counter enables, bit masks, numeric encoding and controller/datapath interfaces.

An illustrative pattern, not a drop-in replacement, is:

```verilog
always @(posedge clk) begin
    launch <= 1'b0;
    if (reset) state <= MENU;
    else if (state == READY && released_after_charge) begin
        launch <= 1'b1;
        state <= PLAY;
    end
end
```

Common mistakes are treating a held button as an event; using a tick as an unconstrained clock; giving a 1440-tick timer only ten bits; adding BCD as binary; discarding in-flight scores on pause; or renewing launch protection after every saved shot. Specify simultaneous-command priorities before coding rather than relying on accidental source order.

Check your implementation by answering these questions: What happens when pause and final drain share an edge? Does a two-ball first drain deduct a life? Can three ×1 half-point contacts eventually show one point with a remainder? Does MENU/restart erase pending credits? Does a saved relaunch get protection again? Are counters frozen by the intended enable, and can each register represent its maximum load? The supplied `tb_game` and `tb_two_ball_game` demonstrate these boundary cases explicitly.
