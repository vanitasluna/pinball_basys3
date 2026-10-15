# Basys 3 Pinball

Target: **xc7a35tcpg236-1**, Vivado 2025.2, top module `My_Top_Module`.

Open `FDP2026.xpr` to edit/rebuild. Program `build/pinball_basys3.bit` in Vivado Hardware Manager to play.

- OLED: color Pmod OLEDrgb on **JC**.
- Bigger screen: Basys 3 VGA -> active VGA-to-HDMI converter -> display; supports 800x600 at approximately 60 Hz. Both screens work together.
- Mouse: board USB-A host port; enable **SW0**.
- **C:** start/restart, hold/release to launch, nudge during play.
- **L/R:** flippers; choose difficulty in the menu.
- **U:** choose one/two balls in the menu; pause/resume during a game.
- **D:** return to menu. **SW15:** full reset. SW1 is unused.
- Mouse left/right operate flippers; middle charges/releases or nudges. Left-click menu buttons to select options/start.

Rebuild from this directory with Vivado on PATH:

```text
vivado -mode batch -source scripts/build.tcl
```

Keep both constraint files. `Pinball_Physics_Timing.xdc` is implementation-only and is essential for the shared collision engine.

Current programming file: 91.46% LUT utilization; routed setup/hold slack +0.101/+0.046 ns. Game sources and bitstream are unchanged by folder cleanup.
