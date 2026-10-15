"""Record the current routed build, fresh regressions and protected interfaces."""
from pathlib import Path
from datetime import datetime, timedelta, timezone
import argparse
import hashlib
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build-log", default="experience_final.log")
args = parser.parse_args()
build = root / "build"
source_dir = root / "FDP2026.srcs" / "sources_1" / "new"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


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
resources = {}
util = (build / "utilization.rpt").read_text()
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
assert len(re.findall(r"\|\s*collisions\s*\|\s*pinball_collision\s*\|", hierarchy)) == 1

tests = ["tb_input", "tb_game", "tb_physics", "tb_multiball", "tb_two_ball_game", "tb_collision", "tb_vga", "tb_vga_clock",
         "tb_renderer", "tb_effects", "tb_vga_renderer", "tb_top"]
dependencies = {
    "tb_input": ["pinball_input"], "tb_game": ["pinball_game"],
    "tb_physics": ["pinball_physics", "pinball_collision"],
    "tb_multiball": ["pinball_physics", "pinball_collision"],
    "tb_two_ball_game": ["pinball_game", "pinball_physics", "pinball_collision"],
    "tb_collision": ["pinball_collision"], "tb_vga": ["pinball_vga"],
    "tb_vga_clock": ["pinball_vga_clock"], "tb_renderer": ["pinball_renderer"],
    "tb_effects": ["pinball_effects"], "tb_vga_renderer": ["pinball_vga_renderer"],
}
summaries = {}
for test in tests:
    test_log = root / "tests" / "work" / (test + ".log")
    content = test_log.read_text()
    assert "PASS " + test in content and not re.search(r"^(?:Fatal:|ERROR:)", content, re.M), test
    rtl = list(source_dir.glob("*.v")) + list(source_dir.glob("*.vhd")) if test == "tb_top" else [
        source_dir / (name + ".v") for name in dependencies[test]]
    inputs = [root / "tests" / (test + ".sv")] + rtl
    assert test_log.stat().st_mtime >= max(p.stat().st_mtime for p in inputs), "Stale regression: " + test
    summaries[test] = next(line.strip() for line in content.splitlines() if line.startswith("PASS " + test))
assert "half-point scoring/carry" in (root / "tests/work/tb_game.log").read_text()
subprocess.run([sys.executable, str(root / "scripts/verify_project.py")], check=True)
bit = build / "pinball_basys3.bit"
paths = sorted(p for p in (root / "FDP2026.srcs").rglob("*") if p.suffix.lower() in (".v", ".vhd", ".xdc")) + [root / "FDP2026.xpr"]
assert all(p.stat().st_mtime <= bit.stat().st_mtime for p in paths if p.suffix != ".xpr"), "Source newer than bitstream"
previous = json.loads((build / "pre_experience/manifest.json").read_text())
oracle_log = build / "experience_geometry_audit/tb_geometry_oracle.log"
assert "PASS tb_geometry_oracle (18231 exact segment checks)" in oracle_log.read_text()
assert oracle_log.stat().st_mtime >= (source_dir / "pinball_collision.v").stat().st_mtime, "Stale geometry oracle"
completed = datetime.fromtimestamp(bit.stat().st_mtime, timezone(timedelta(hours=8))).isoformat(timespec="seconds")
profiles = {
    "Easy": dict(gravity_q8_per_step=0.5, gravity_pixels_per_second_squared=112.5, upper_descent_pixels_per_second=105, lower_descent_pixels_per_second=45),
    "Normal": dict(gravity_q8_per_step=1, gravity_pixels_per_second_squared=225, upper_descent_pixels_per_second=127.5, lower_descent_pixels_per_second=56.25),
    "Hard": dict(gravity_q8_per_step=2, gravity_pixels_per_second_squared=450, upper_descent_pixels_per_second=150, lower_descent_pixels_per_second=67.5),
}
manifest = dict(part="xc7a35tcpg236-1", tool="Vivado 2025.2", date=completed[:10], timezone="Asia/Singapore",
    build_completed_local=completed, build_log=log_path.relative_to(root).as_posix(),
    setup_slack_ns=float(wns), hold_slack_ns=float(whs), setup_failing_endpoints=0, hold_failing_endpoints=0,
    drc_errors=0, drc_advisory_warnings=drc_warnings, unconstrained_internal_endpoints=0,
    resources=resources, vga_resolution=[800,600], vga_pixel_clock_mhz=40,
    oled_resolution=[96,64], oled_connector="JC", score_unit_points=0.5, physics_hz=240,
    play_modes=[1,2], mode_selector="Menu U or mode-row click; SW1 ignored", collision_instances=1,
    mouse_pointer=dict(raw_counts_per_logical_pixel=4, raw_bounds=[383,255], raw_center=[192,128], complete_packet_publication=True),
    difficulty_profiles=profiles,
    moving_bumper_speed_pixels_per_second=3.75,
    moving_bumper_paths={"left":dict(x=26,y_min=22,y_max=28),"right":dict(y=22,x_min=58,x_max=66)},
    moving_side_targets=dict(centers_x=[6,78],center_y_min=29,center_y_max=37,initial_center_y=33,
                             speed_pixels_per_second=3.75,opposite_initial_directions=True),
    anime_reactions=dict(mascot="original circuit cat",persistent_states=["MENU","READY","PLAY","PAUSE","OVER"],
                         event_override="feature_timer > 120",idle_expressions=True),
    physics_commit_clocks={"one_ball":16,"two_balls":33},two_ball_hit_separation_clocks=4,final_pair_drain_delay_clocks=6,
    protection_feedback=dict(ball_color="bright blue",trail_color="fading blue",applies_to="both balls and shared trail"),
    impact_bursts=dict(capacity=2,sparks_per_burst=4),
    launch_power=dict(meter_min=0,meter_max=63,minimum_shot=16,steps_per_second=60,cycle_seconds=2.1,mode="continuous triangular sweep"),
    code_review=dict(custom_rtl_files=11,custom_rtl_modules=13,protected_driver_files=3,
                     geometry_oracle_cases=18231,geometry_oracle_log_sha256=sha(oracle_log)),
    baseline="build/pre_experience",previous_lut_percent=previous["resources"]["Slice LUTs"]["percent"],
    bitstream_bytes=bit.stat().st_size,bitstream_sha256=sha(bit),
    source_sha256={p.relative_to(root).as_posix():sha(p) for p in paths},simulations_passed=tests,
    simulations_rerun_this_revision=tests,
    testbench_sha256={"tests/"+t+".sv":sha(root/"tests"/(t+".sv")) for t in tests},
    simulation_log_sha256={"tests/work/"+t+".log":sha(root/"tests/work"/(t+".log")) for t in tests})
(build / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
rows = "\n".join(f"| {n} | {v['used']} / {v['available']} | {v['percent']:.2f}% |" for n,v in resources.items())
bench_rows = "\n".join(f"| {test} | {summary.replace('|','/')} |" for test,summary in summaries.items())
validation = f"""# Validation - {completed[:10]} (Asia/Singapore)

The mouse, mascot, moving-side-target and gentler-difficulty revision was routed for Basys 3 xc7a35tcpg236-1 using Vivado 2025.2. Bitstream generation completed at {completed}. Program `build/pinball_basys3.bit` ({bit.stat().st_size:,} bytes). Authoritative build log: `{log_path.relative_to(root).as_posix()}`. The preceding working design is preserved under `build/pre_experience/`.

## Routed implementation

- Setup worst slack **+{float(wns):.3f} ns**, hold worst slack **+{float(whs):.3f} ns**; zero failing endpoints and zero unconstrained internal endpoints.
- DRC: zero errors, {drc_warnings} advisory warnings. Batch build: zero errors or critical warnings.
- One shared collision engine. Setup-16/hold-15 exceptions cover stable collision snapshots and delayed result registers, including side-target world state. Controls retain normal timing. Producer-to-frame scene crossings remain timed.
- Saved Vivado project part, tops, compile order and implementation-only timing file verified. OLED remains on JC; native VGA stays 800x600 at 40 MHz (about 60.317 Hz).

| Resource | Used / available | Utilization |
| --- | --- | --- |
{rows}

Previous LUT utilization: {previous['resources']['Slice LUTs']['percent']:.2f}%. Current: **{resources['Slice LUTs']['percent']:.2f}%**. Registers, DSPs and LUTs are separate limits; routed timing determines whether the revision works at the configured clocks.

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
{bench_rows}

A fresh independent rational bumper-segment oracle passed 18,231 checks against the current collision module. Its inputs, bench and log are under `build/experience_geometry_audit/`. New moving rectangle contacts, swept near misses, rearm, bounds and two-ball consistency are exercised in the collision/physics suites. Source, bench, log and bitstream SHA256 hashes are recorded in `build/manifest.json`; the protected three-module hashes match the supplied versions.

Preview PNGs are generated from exact RGB565 renderer dumps. Inspect `docs/dual_display_preview.png`, `docs/display_preview.png`, `docs/vga_preview.png`, `docs/moving_bumpers_preview.png` and `docs/funny_preview.png`. These are deterministic rendered-state samples, not recordings of physical gameplay.

## Final review and physical follow-up

The completed change was reviewed again for signed arithmetic, reset/cancellation, event priority, shared-world timing, renderer clipping/layers, snapshot widths, mouse dispatch and source integrity. Fixes and tests are described in `docs/DESIGN_NOTES.md`.

The user confirmed the previous design works on hardware. This revision was verified in simulation and Vivado; no physical board was programmed during development. Confirm slower pointer feel and edge reachability, all-state cat placement, both moving target tracks, one/two-ball launches and returns on each difficulty, pause/resume and finite saves, OLED startup and VGA-to-HDMI compatibility on the board. SW15 resets high score; SW0 enables mouse; SW1 remains unused.

The 33-page teaching guide is explicitly a 14 October 2026 snapshot. This validation, the current README and RTL describe the revised mouse scaling, persistent cat, target tracks and difficulty profiles.
"""
(root / "docs/VALIDATION.md").write_text(validation, encoding="utf-8")
print(json.dumps({k:manifest[k] for k in ("resources","setup_slack_ns","hold_slack_ns","bitstream_bytes")}, indent=2))
print("PASS recorded current routed build, all twelve simulation logs, fresh geometry oracle and protected driver integrity")
