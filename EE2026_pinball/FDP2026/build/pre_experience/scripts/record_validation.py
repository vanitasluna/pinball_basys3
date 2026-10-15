"""Record a successful routed build and current self-checking simulations."""
from pathlib import Path
from datetime import datetime, timedelta, timezone
import argparse
import hashlib
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("--build-log", default="finalization.log")
args = parser.parse_args()
build = root / "build"
log_path = build / args.build_log
log = log_path.read_text()
assert "BUILD PASSED:" in log and "Bitgen Completed Successfully" in log
assert not re.search(r"^(?:ERROR|CRITICAL WARNING):", log, re.M)
assert "PROJECT VERIFIED:" in (build / "project_check.log").read_text()
timing = (build / "timing.rpt").read_text()
row = re.search(r"\n\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+"
                r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+"
                r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*\n", timing)
assert row, "Missing routed timing summary"
wns, tns, setup_fail, _, whs, ths, hold_fail, _, _, _, pulse_fail, _ = row.groups()
assert float(wns) >= 0 and float(whs) >= 0
assert int(setup_fail) == int(hold_fail) == int(pulse_fail) == 0
assert "All user specified timing constraints are met." in timing
assert "unconstrained_internal_endpoints (0)" in timing
util = (build / "utilization.rpt").read_text()
resources = {}
for name in ("Slice LUTs", "Slice Registers", "DSPs", "Block RAM Tile", "Bonded IOB", "BUFGCTRL"):
    row = re.search(r"\|\s*" + re.escape(name) +
                    r"\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*([0-9.]+)", util)
    assert row, name
    used, available, percent = row.groups()
    resources[name] = dict(used=int(used), available=int(available), percent=float(percent))
drc = (build / "drc.rpt").read_text()
assert not re.search(r"\|\s*(?:Error|Critical Warning)\s*\|", drc)
drc_warnings = sum(int(n) for n in re.findall(r"\|\s*Warning\s*\|[^\n]*\|\s*(\d+)\s*\|", drc))
hierarchy = (build / "utilization_hierarchical.rpt").read_text()
assert len(re.findall(r"\|\s*collisions\s*\|\s*pinball_collision\s*\|", hierarchy)) == 1, "Expected one shared collision engine"
tests = ["tb_input", "tb_game", "tb_physics", "tb_multiball", "tb_two_ball_game", "tb_collision", "tb_vga", "tb_vga_clock",
         "tb_renderer", "tb_effects", "tb_vga_renderer", "tb_top"]
source_dir = root / "FDP2026.srcs" / "sources_1" / "new"
dependencies = {
    "tb_input": ["pinball_input"],
    "tb_game": ["pinball_game"],
    "tb_physics": ["pinball_physics", "pinball_collision"],
    "tb_multiball": ["pinball_physics", "pinball_collision"],
    "tb_two_ball_game": ["pinball_game", "pinball_physics", "pinball_collision"],
    "tb_collision": ["pinball_collision"],
    "tb_vga": ["pinball_vga"],
    "tb_vga_clock": ["pinball_vga_clock"],
    "tb_renderer": ["pinball_renderer"],
    "tb_effects": ["pinball_effects"],
    "tb_vga_renderer": ["pinball_vga_renderer"],
}
for test in tests:
    test_log = root / "tests" / "work" / (test + ".log")
    content = test_log.read_text()
    assert "PASS " + test in content and not re.search(r"^(?:Fatal:|ERROR:)", content, re.M), test
    # Check the modules actually instantiated by each bench, including the
    # shared collision engine and every protected/top-level RTL dependency.
    rtl = list(source_dir.glob("*.v")) + list(source_dir.glob("*.vhd")) if test == "tb_top" else [
        source_dir / (name + ".v") for name in dependencies[test]]
    inputs = [root / "tests" / (test + ".sv")] + rtl
    assert test_log.stat().st_mtime >= max(p.stat().st_mtime for p in inputs), "Stale RTL/testbench regression: " + test
assert "half-point scoring/carry" in (root / "tests" / "work" / "tb_game.log").read_text(), "Missing reduced-score/mode regression"
subprocess.run([sys.executable, str(root / "scripts" / "verify_project.py")], check=True)
bit = build / "pinball_basys3.bit"
paths = sorted(p for p in (root / "FDP2026.srcs").rglob("*")
               if p.suffix.lower() in (".v", ".vhd", ".xdc")) + [root / "FDP2026.xpr"]
assert all(p.stat().st_mtime <= bit.stat().st_mtime for p in paths if p.suffix != ".xpr"), "Source newer than bitstream"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
previous = json.loads((build / "pre_finalization" / "manifest.json").read_text())
oracle_log = build / "final_physics_audit" / "tb_geometry_oracle.log"
assert "PASS tb_geometry_oracle (18231 exact segment checks)" in oracle_log.read_text()
# The independent oracle ran before declaration-only cleanup. Verify its
# collision implementation still matches, ignoring net types and line endings.
def collision_implementation(path):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"^`default_nettype[^\n]*\n", "", text, flags=re.M)
    return re.sub(r"\b(input|output|inout) wire\b", r"\1", text).strip()
assert collision_implementation(source_dir / "pinball_collision.v") == collision_implementation(
    build / "pre_finalization" / "rtl" / "pinball_collision.v"), "Geometry oracle implementation changed"
completed = datetime.fromtimestamp(bit.stat().st_mtime, timezone(timedelta(hours=8))).isoformat(timespec="seconds")
manifest = dict(part="xc7a35tcpg236-1", tool="Vivado 2025.2", date=completed[:10],
                timezone="Asia/Singapore", build_completed_local=completed, build_log=log_path.relative_to(root).as_posix(),
                setup_slack_ns=float(wns), hold_slack_ns=float(whs), setup_failing_endpoints=0,
                hold_failing_endpoints=0, drc_errors=0, drc_advisory_warnings=drc_warnings,
                unconstrained_internal_endpoints=0, resources=resources, vga_resolution=[800, 600],
                vga_pixel_clock_mhz=40, oled_resolution=[96, 64], oled_connector="JC", score_unit_points=0.5, physics_hz=240, moving_bumper_speed_pixels_per_second=3.75,
                play_modes=[1,2], mode_selector="Menu U press or ball-mode-row mouse click; captured at game start", collision_instances=1,
                bug_fixes=["parameter-sized debounce counter prevents long-interval overflow", "right guide ends at visible flipper pivot", "newest trail sample wins overlaps on OLED and VGA", "swept target/sling corners", "drain pause/resume race", "complete mouse packets and bounded widgets", "atomic survivor trail handoff", "paused impact retention", "cursor/ball priority and clipped/state-aware prompts"],
                code_review=dict(custom_rtl_files=11, custom_rtl_modules=13, protected_driver_files=3,
                                 coding_safeguards=["scoped implicit-net rejection", "explicit port types", "sized state/timing constants", "parameter-derived debounce width"],
                                 geometry_oracle_cases=18231, geometry_oracle_log_sha256=sha(oracle_log)),
                protection_feedback=dict(ball_color="bright blue", trail_color="fading blue", applies_to="both live balls and shared trail", signal="frame-snapshotted save_timer != 0"),
                visual_enhancements=["persistent score/lives HUD", "save countdown and live-ball status", "mouse-hover action buttons", "neon panels and animated table accents", "segmented charge meter", "two retained impact bursts"],
                anime_reactions=dict(mascot="original circuit cat", events=[1,3,4,5,6,7], window="feature_timer > 120 (first half-second)", states="PLAY; READY only for saved event4", combo_event_excluded=True),
                impact_bursts=dict(capacity=2, sparks_per_burst=4),
                physics_commit_clocks={"one_ball":16,"two_balls":33}, two_ball_hit_separation_clocks=4, final_pair_drain_delay_clocks=6,
                launch_power={"meter_min":0, "meter_max":63, "minimum_shot":16, "steps_per_second":60, "cycle_seconds":2.1, "mode":"continuous triangular sweep"},
                moving_bumper_paths={"left": {"x":26,"y_min":22,"y_max":28}, "right": {"y":22,"x_min":58,"x_max":66}},
                previous_lut_percent=previous["resources"]["Slice LUTs"]["percent"],
                bitstream_bytes=bit.stat().st_size, bitstream_sha256=sha(bit),
                source_sha256={p.relative_to(root).as_posix(): sha(p) for p in paths}, simulations_passed=tests,
                simulations_rerun_this_revision=tests,
                testbench_sha256={"tests/" + t + ".sv": sha(root / "tests" / (t + ".sv")) for t in tests},
                simulation_log_sha256={"tests/work/" + t + ".log": sha(root / "tests" / "work" / (t + ".log")) for t in tests})
(build / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
rows = "\n".join(f"| {n} | {v['used']} / {v['available']} | {v['percent']:.2f}% |" for n, v in resources.items())
validation = f"""# Validation — {completed[:10]} (Asia/Singapore)

The finalized selectable one/two-ball game for OLED and native VGA was built with Vivado 2025.2 for xc7a35tcpg236-1 after a complete RTL review, explicit declaration cleanup and a parameter-sizing bug fix in the input filter. Bitstream generation completed at {completed}. The programming file is `build/pinball_basys3.bit` ({bit.stat().st_size:,} bytes), and the authoritative batch log is `{log_path.relative_to(root).as_posix()}`.

## Routed implementation

- Setup worst slack: **+{float(wns):.3f} ns**; TNS {float(tns):.3f} ns; zero failing endpoints.
- Hold worst slack: **+{float(whs):.3f} ns**; THS {float(ths):.3f} ns; zero failing endpoints.
- DRC: zero errors and {drc_warnings} advisory warnings. Consult `build/drc.rpt` for the recommendations. Bitstream generation succeeded.
- Final batch build: zero errors and zero critical warnings. Ordinary warnings include trimmed bits, the supplied OLED driver's zero-width replication expression, and recommendations for graphics/physics DSP pipelining.
- No unconstrained internal endpoints. Scoped collision snapshot paths use setup-16/hold-15 constraints. Asynchronous physical outputs have the explicit 100 ns propagation bound; OLED SPI and VGA retain their clock-based requirements.
- The 100→40 MHz scene crossing is fully timed, including its 5 ns minimum setup window. Graphics fields are registered in the producer domain before each display takes its frame snapshot; no false path hides the scene transfer.
- Vivado opened the saved XPR and verified the FPGA part, design/simulation tops, source compile order, implementation-only timing file and simulation settings.

| Resource | Used / available | Utilization |
| --- | --- | --- |
{rows}

The preceding bug-audit revision used {previous["resources"]["Slice LUTs"]["percent"]:.2f}% LUTs; this finalized revision uses **{resources['Slice LUTs']['percent']:.2f}%**. The prior bitstream, checkpoint, reports, RTL and debounce reproduction log are under `build/pre_finalization/`. Earlier versions remain under `build/pre_bug_audit/`, `build/pre_anime_fx/`, `build/pre_visual_polish/`, `build/pre_protection_blue/`, `build/pre_polish/`, `build/pre_menu_mode/`, `build/pre_multiball/`, `build/pre_charge_bounce/`, `build/pre_motion/`, `build/ja_previous/`, `build/pre_layout_revision/` and `build/baseline/`.

The OLED uses **JC** and remains 96×64 at 6.25 MHz. Point awards retain their half-point units and carry, preserving small awards; whole-point scores still saturate at 9999. VGA is native **800×600**, using a real MMCM-generated **40 MHz** pixel clock, 1056×628 total frame, positive H/V sync, and approximately 60.317 Hz. Physics uses a fixed 240 Hz enable on the 100 MHz game clock. Native eightfold scaling retains Q8 fractional ball motion and uses no full-frame buffer.

## Simulation and source integrity

All twelve benches were rerun for finalization. A new public-input regression first failed against the preceding fixed-width debounce counter: a stable input configured for 1,048,577 clocks never settled because the counter wrapped. The parameter-derived width fixes it, while retaining the board's 5 ms behavior. The input, rules, two-ball integration, clock and top-level benches were refreshed after final declaration/line-ending normalization. The earlier guide/overlap regressions continue to pass. The validation script checks log freshness against each bench's dependencies. Renderer captures verify that queued white/gold positions match physics preparation coordinates.

All eleven custom RTL files and the three protected driver files were reviewed, along with timing constraints, build/validation scripts and regression benches. Custom RTL rejects implicit signal names and explicitly declares ports; each file restores the default net type before supplied sources. State/timing constants are sized, sequential/combinational assignment styles retain their documented contracts, and comments now match menu selection and half-point award bounds. An independent rational geometry oracle passed 18,231 bounded bumper segment checks, including grazing contacts and near misses. Its log is `build/final_physics_audit/tb_geometry_oracle.log`; the validation script confirms the collision implementation still matches the reviewed baseline after declaration-only cleanup.

| Bench | Result and coverage |
| --- | --- |
| tb_input | PASS: bounce rejection, independent simultaneous inputs, exact settling and single-cycle events; long-interval counter overflow reproduced and corrected using 1,048,577 actual stable samples |
| tb_game | PASS: latched one/two-ball mode; half-point carry across adjacent transactions, drains and pause, new-game fraction flush, maximum simultaneous 55 award; continuous charge sweeps/releases/resets, fourteen contacts, repeatable collections, spinner, x1–x4 combos, finite saves, saturation, high score and late pause/drain transactions and simultaneous drain/pause/resume priority |
| tb_physics | PASS: 42,337 checks; complete shared track period (four vertical/three horizontal cycles), endpoint/direction bounds, moving-surface contacts, moving-centre score hysteresis, atomic motion/ball commit; minimum/light/full launches and eventual idle drains in all three difficulties, speed bounds, revised swept target/sling rebounds, new sensor rearming, nudge, isolated 16-clock collision commit, prepare/reset cancellation, pause and fractional coordinates |
| tb_multiball | PASS: 13,847 checks; one-shot pair launch; both lane exits at minimum/light/full power in all difficulties; 33-clock atomic pair/world commit, world advancement once, independent rearm/cooldown, separate same-object hit pulses, either-ball-first drains, final drain after event flush, natural unattended pair drains on every power/difficulty combination, shared nudge, a nudge queued between snapshots, pause and reset/prepare cancellation |
| tb_two_ball_game | PASS: 74 checks of real physics→rules integration; paired release/power, separately credited same-bumper contacts and fractions, partial/final drains, finite pair saves, queued final awards, pause completion and menu/reset cancellation |
| tb_collision | PASS: 86 focused checks for mirrored below-flipper clearance at every angle, bounded visible guides, relative-velocity rebounds, stationary balls struck by moving surfaces, grazing swept contacts/near misses, swept stand-up/slingshot corner hits and near misses, smaller ball/bumpers, walls, targets and flippers |
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

The UI includes neon panels, cursor-hover feedback on the existing action regions, segmented launch power, a protection countdown and live-ball status. OLED score and lives remain visible during award feedback. Countdown seconds use fixed threshold comparisons rather than division. Native VGA remains a procedural 800×600 raster with fine text and Q8 motion, while OLED uses a compact version of the same visual language. The particle pool keeps the two most recent four-spark bursts, so quick contacts from both balls can remain visible together. This audit bounds the right guide at its visible x65 pivot, matching the left x21 pivot. Both renderers now paint trail samples oldest first, retaining fresh brightness at overlapping positions. Game rules and scoring are unchanged.

The original circuit cat cheers selected rewards, panics during nudge and shows relief after a saved turn. It appears only while the current selected feature has more than 120 ticks remaining, then disappears after its first half-second. Generic combo event2 is excluded because repeated contacts refresh it. PLAY uses the clear upper-left gap; READY saved reactions move below the OLED charge bar. MENU, PAUSE and OVER hide the cameo. Its poses use existing timer/animation fields, constant masks and the shared font. The mascot body stays behind trails and table objects; live balls remain above the mascot and captions. Both displays retain their normal score, lives, countdown and blue-protection cues. Existing feature data represents the latest notification rather than a queue of every closely spaced award. Three actual RTL reaction examples are in `docs/funny_preview.png`.

Holding C or mouse middle cycles the power meter 0→63→0 at 60 units/second (1.05 seconds each way). Release uses the selected value with a minimum launch strength of 16. Both display meters and charge LEDs consume the same charge signal. Pause freezes charge; resume, menu, new game, reset and the final ball's drain restart the rising sweep from zero.

The left bumper travels at x26/y22..28 and the right at y22/x58..66, both at 3.75 logical pixels/second. One collision engine processes the balls sequentially against the same world snapshot. One-ball motion commits after 16 clocks; paired motion/world commits after 33 clocks. Each snapshot has its own full 16-clock window; selector, event-queue and staging-to-final paths retain ordinary timing. First/second hit masks emit four clocks apart, and a final paired drain is delayed six clocks so neither award is lost. Reset/prepare cancel pending results/events; pause allows only an already accepted batch to finish. Each ball has independent cooldown and moving-center hysteresis.

The input filter's counter now derives its width from the configured interval; seven-segment scanning, VGA timing, MMCM lock/reset and RGB conversion required only declaration safeguards. Protected driver SHA-256 hashes match their supplied versions. `build/manifest.json` records final source, testbench, simulation-log and bitstream hashes. Preview PNGs contain pixels from the actual RTL renderers and were inspected visually. Internet references and design choices are in `DESIGN_NOTES.md`.

## Physical board checks

No board was programmed during this revision. Verify short circuit-cat reward/nudge/saved reactions on both displays, expiration and modal hiding, hover buttons and persistent score/lives, protection countdown and live-ball status, paired impact bursts, bright blue balls/trails during launch and target protection, normal colors after expiry/consumption, OLED orientation/startup, U/mouse menu and bounded action clicks, completed mouse packets, corner rebounds, both balls launching and remaining visible, game feel, controls, fractional scoring, finite pair saves, partial/final drains, high score, optional mouse and the active VGA-to-HDMI converter's 800×600 support. High score resets with SW15 or power cycling. Top-level simulation accelerates long OLED waits and board debounce without changing the protected driver; it verifies sequencing, not actual power-up delays. Mouse integration tests use complete controller packets rather than a physical USB mouse.
"""
(root / "docs" / "VALIDATION.md").write_text(validation, encoding="utf-8")
print(json.dumps({k: manifest[k] for k in ("resources", "setup_slack_ns", "hold_slack_ns", "bitstream_bytes")}, indent=2))
print("PASS recorded current routed build, all twelve simulation logs and protected driver integrity")
