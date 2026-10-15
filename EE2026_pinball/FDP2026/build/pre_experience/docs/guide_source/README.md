# Code guide sources

The five numbered Markdown files are the editable chapter sources for `../PROJECT_CODE_GUIDE.md`. Edit these files when updating the teaching guide, then run the following from the project directory:

```powershell
python .\scripts\build_project_guide.py
```

The builder requires Python with Pillow, ReportLab and pypdf, plus Arial and Consolas in `C:/Windows/Fonts`. It regenerates the architecture, state and two-ball timing diagrams in `../guide_assets/`, assembles the guide with chapter numbers and a contents list, and writes `../../output/pdf/EE2026_Pinball_Code_Guide.pdf`. It also records document statistics under `../../tmp/guide_sources/`.

Image paths in the chapter sources are resolved for the assembled guide, which lives in `docs/`. The game preview comes from the existing RTL preview image. The builder does not edit hardware sources or run a Vivado build.

When changing factual explanations, compare them with the RTL and the latest build manifest. Render and inspect the regenerated PDF to check pagination, tables, code blocks and diagrams.
