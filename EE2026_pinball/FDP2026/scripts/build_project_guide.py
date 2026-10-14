"""Assemble the teaching guide, draw its diagrams and export a printable PDF.

Documentation only: this script never edits RTL, tests or build evidence.
Requires Pillow, ReportLab and pypdf from the bundled Python runtime.
"""
from pathlib import Path
import html
import json
import re

from PIL import Image, ImageDraw, ImageFont
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, Image as PDFImage, KeepTogether, PageBreak, PageTemplate,
    Paragraph, Preformatted, Spacer, Table, TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
ASSETS = DOCS / "guide_assets"
OUTPUT = ROOT / "output" / "pdf"
PARTS = DOCS / "guide_source"
for directory in (ASSETS, OUTPUT):
    directory.mkdir(parents=True, exist_ok=True)
FONT_DIR = Path("C:/Windows/Fonts")
FONT_FILES = {
    "GuideSans": "arial.ttf", "GuideSansBold": "arialbd.ttf",
    "GuideSansItalic": "ariali.ttf", "GuideMono": "consola.ttf",
}
for name, filename in FONT_FILES.items():
    pdfmetrics.registerFont(TTFont(name, str(FONT_DIR / filename)))
pdfmetrics.registerFontFamily("GuideSans", normal="GuideSans", bold="GuideSansBold",
                              italic="GuideSansItalic", boldItalic="GuideSansBold")

INK = "#132238"
BLUE = "#166187"
TEAL = "#087E8B"
PALE = "#EAF3F8"


def font(size, bold=False):
    return ImageFont.truetype(str(FONT_DIR / ("arialbd.ttf" if bold else "arial.ttf")), size)


def diagram_base(width, height, title, subtitle):
    im = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(im)
    draw.text((40, 25), title, font=font(40, True), fill=INK)
    draw.text((40, 80), subtitle, font=font(24), fill=BLUE)
    return im, draw


def box(draw, xy, title, lines, fill=PALE):
    draw.rounded_rectangle(xy, radius=18, fill=fill, outline=BLUE, width=3)
    left, top, right, bottom = xy
    draw.text((left + 18, top + 16), title, font=font(26, True), fill=INK)
    for i, line in enumerate(lines):
        draw.text((left + 18, top + 56 + i * 29), line, font=font(22), fill=INK)


def arrow(draw, points, color=TEAL, width=4):
    draw.line(points, fill=color, width=width)
    (x0, y0), (x1, y1) = points[-2:]
    dx, dy = x1 - x0, y1 - y0
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / length, dy / length
    size = 14
    draw.polygon([(x1, y1), (x1 - size * ux + size * uy / 2, y1 - size * uy - size * ux / 2),
                  (x1 - size * ux - size * uy / 2, y1 - size * uy + size * ux / 2)], fill=color)


def make_diagrams():
    im, draw = diagram_base(1500, 1170, "One authoritative game, two display pipelines",
                            "Top wires the modules, clocks, resets and whole-frame scene registers")
    box(draw, (45, 140, 445, 280), "Input adapters", ["Buttons: sync + debounce", "Mouse: complete packets"])
    box(draw, (550, 140, 950, 280), "Clock / reset", ["100 MHz + 240 Hz enable", "6.25 MHz OLED / 40 MHz VGA"])
    box(draw, (45, 380, 445, 545), "Rules own game state", ["FSM, charge, lives, save", "Score, missions, timers"])
    box(draw, (550, 380, 950, 545), "Physics owns world state", ["Q8 balls, flippers, bumpers", "Snapshot / schedule / commit"])
    box(draw, (1055, 380, 1455, 545), "Shared collision logic", ["Stable operands in", "Corrected state + contacts out"])
    arrow(draw, [(245, 280), (245, 380)])
    arrow(draw, [(750, 280), (750, 380)])
    arrow(draw, [(445, 425), (550, 425)])
    draw.text((460, 390), "commands", font=font(17), fill=TEAL)
    arrow(draw, [(550, 500), (445, 500)])
    draw.text((458, 515), "hit / drain", font=font(17), fill=TEAL)
    arrow(draw, [(950, 425), (1055, 425)])
    arrow(draw, [(1055, 500), (950, 500)])
    box(draw, (1055, 630, 1455, 770), "Effects", ["Trail history, 2 spark banks", "Actual scoring-ball position"])
    arrow(draw, [(950, 535), (1000, 535), (1000, 665), (1055, 665)])
    box(draw, (270, 665, 930, 805), "100 MHz producer bundles", ["Rules + world + effects + pointer", "Derived fields registered before display crossing"])
    arrow(draw, [(245, 545), (245, 695), (270, 695)])
    arrow(draw, [(750, 545), (750, 665)])
    arrow(draw, [(1055, 735), (930, 735)])
    box(draw, (80, 925, 690, 1080), "OLED frame snapshot / renderer / SPI", ["318-bit frozen scene, compact RGB565", "96 x 64 panel on JC"])
    box(draw, (810, 925, 1420, 1080), "VGA frame snapshot / renderer / raster", ["611-bit frozen scene, native detail", "800 x 600 -> active HDMI converter"])
    arrow(draw, [(470, 805), (470, 870), (385, 870), (385, 925)])
    arrow(draw, [(750, 805), (750, 870), (1115, 870), (1115, 925)])
    draw.text((80, 1120), "Renderers consume state. They never update the physical world or score.", font=font(23, True), fill=INK)
    im.save(ASSETS / "architecture.png")

    im, draw = diagram_base(1500, 640, "One world step: shared calculation, atomic results",
                            "Each numbered edge is a 100 MHz clock edge (10 ns). Tick period is about 4.167 ms.")
    left, right, y = 90, 1410, 220
    def xx(edge):
        return left + (right - left) * edge / 40
    draw.line((left, y, right, y), fill=INK, width=4)
    for edge in (0, 16, 17, 33, 37, 39):
        x = xx(edge)
        draw.line((x, y - 10, x, y + 12), fill=INK, width=3)
        draw.text((x - 15, y - 55), str(edge), font=font(26, True), fill=INK)
    draw.rectangle((xx(0), 280, xx(16), 325), fill="#D4EBF3", outline=BLUE, width=2)
    draw.text((xx(0) + 20, 288), "Ball 1 isolated calculation", font=font(23), fill=INK)
    draw.rectangle((xx(17), 280, xx(33), 325), fill="#DCF1EA", outline=TEAL, width=2)
    draw.text((xx(17) + 20, 288), "Ball 2 isolated calculation", font=font(23), fill=INK)
    box(draw, (80, 385, 465, 535), "Edge 0 / 16 / 17", ["Capture first operands", "Stage first; load second"])
    box(draw, (545, 385, 925, 535), "Edge 33", ["Commit both balls + world", "Publish first hit mask"])
    box(draw, (1000, 385, 1420, 535), "Edges 37 / 39", ["Publish second hit mask", "Final drain if both drained"])
    draw.text((80, 580), "Consumers see registered hit/drain pulses on the following system edge.", font=font(24), fill=INK)
    im.save(ASSETS / "two_ball_timeline.png")

    im, draw = diagram_base(1500, 650, "Five game states and their normal transitions",
                            "Reset -> MENU. D returns to MENU. Drain priority and finite saves refine this diagram.")
    for xy, title, lines in [
        ((80, 170, 460, 305), "MENU", ["Choose mode + difficulty"]),
        ((560, 170, 940, 305), "READY", ["Prepare and charge balls"]),
        ((1040, 170, 1420, 305), "PLAY", ["Advance world, score hits"]),
        ((560, 455, 940, 585), "PAUSE", ["Remember READY or PLAY"]),
        ((1040, 455, 1420, 585), "OVER", ["Final unprotected life lost"]),
    ]:
        box(draw, xy, title, lines)
    arrow(draw, [(460, 235), (560, 235)])
    draw.text((480, 195), "start", font=font(20), fill=TEAL)
    arrow(draw, [(940, 235), (1040, 235)])
    draw.text((960, 185), "release", font=font(20), fill=TEAL)
    arrow(draw, [(1230, 305), (1230, 455)])
    draw.text((1245, 355), "last life", font=font(20), fill=TEAL)
    arrow(draw, [(750, 305), (750, 455)])
    draw.text((770, 350), "pause / resume", font=font(20), fill=TEAL)
    arrow(draw, [(650, 455), (650, 305)])
    arrow(draw, [(1040, 275), (975, 275), (975, 415), (900, 415), (900, 455)])
    arrow(draw, [(940, 565), (1005, 565), (1005, 330), (1130, 330), (1130, 305)])
    arrow(draw, [(1100, 170), (1100, 125), (840, 125), (840, 170)])
    draw.text((910, 90), "saved / next-life drain", font=font(20), fill=TEAL)
    arrow(draw, [(1040, 525), (980, 525), (980, 345), (850, 345), (850, 305)])
    draw.text((1000, 575), "restart -> READY", font=font(20), fill=TEAL)
    im.save(ASSETS / "states.png")


def normalize(text):
    substitutions = {"\u2010": "-", "\u2011": "-", "\u2012": "-", "\u2013": "-", "\u2014": "-",
                     "\u2212": "-", "\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"', "\u00a0": " "}
    for old, new in substitutions.items():
        text = text.replace(old, new)
    return text


def assemble():
    names = ["01_foundations.md", "02_rules.md", "03_physics.md", "04_displays.md", "05_rebuild_verify.md"]
    text = "\n\n".join((PARTS / name).read_text(encoding="utf-8").strip() for name in names) + "\n"
    text = normalize(text)
    text = text.replace("../../docs/dual_display_preview.png", "dual_display_preview.png")
    text = text.replace("A round drain is possible after collision correction reaches", "A ball drains when collision correction reaches")
    text = text.replace("Consider starting with score 0098, half remainder 0, and expired combo.",
                        "Consider starting with score and high score both 0098, half remainder 0, and expired combo.")
    text = text.replace("## The five-state controller and event priorities\n", "## The five-state controller and event priorities\n\n![Five game states](guide_assets/states.png)\n")
    text = text.replace("## Sharing one collision engine between two balls\n", "## Sharing one collision engine between two balls\n\n![Shared two-ball calculation timeline](guide_assets/two_ball_timeline.png)\n")
    titles = []
    def number_heading(match):
        title = f"{len(titles) + 1}. {match.group(1)}"
        titles.append(title)
        return "## " + title
    text = re.sub(r"^## (.+)$", number_heading, text, flags=re.M)
    def slug(title):
        return re.sub(r"[^a-z0-9 -]", "", title.lower()).replace(" ", "-")
    toc = "## Contents\n\n" + "\n".join(f"- [{title}](#{slug(title)})" for title in titles) + "\n\n"
    at = text.index("\n## ")
    text = text[:at] + "\n\n" + toc + text[at:]
    target = DOCS / "PROJECT_CODE_GUIDE.md"
    target.write_text(text, encoding="utf-8")
    return target, text, titles


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r'<font name="GuideMono" size="8.7" color="#14506E">\1</font>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    def link(match):
        label, url = match.group(1), html.unescape(match.group(2))
        if url.startswith("#"):
            return label
        return '<a href="' + html.escape(url, quote=True) + '" color="#166187">' + label + "</a>"
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)


STYLES = getSampleStyleSheet()
STYLES.add(ParagraphStyle("GuideBody", fontName="GuideSans", fontSize=9.5, leading=13.8,
                          textColor=colors.HexColor(INK), spaceAfter=7, allowWidows=0, allowOrphans=0))
STYLES.add(ParagraphStyle("GuideH2", parent=STYLES["GuideBody"], fontName="GuideSansBold", fontSize=15,
                          leading=19, textColor=colors.HexColor(BLUE), spaceBefore=17, spaceAfter=8, keepWithNext=True))
STYLES.add(ParagraphStyle("GuideH3", parent=STYLES["GuideBody"], fontName="GuideSansBold", fontSize=11.3,
                          leading=15, spaceBefore=10, spaceAfter=5, keepWithNext=True))
STYLES.add(ParagraphStyle("GuideTable", parent=STYLES["GuideBody"], fontSize=8.2, leading=11.3, spaceAfter=0))
STYLES.add(ParagraphStyle("GuideTableHead", parent=STYLES["GuideTable"], fontName="GuideSansBold", textColor=colors.white))
STYLES.add(ParagraphStyle("GuideCode", fontName="GuideMono", fontSize=7.8, leading=10.7,
                          leftIndent=10, rightIndent=8, spaceBefore=4, spaceAfter=9,
                          backColor=colors.HexColor("#F0F4F7"), borderPadding=8))
STYLES.add(ParagraphStyle("GuideBullet", parent=STYLES["GuideBody"], leftIndent=14, firstLineIndent=-10, spaceAfter=5))
STYLES.add(ParagraphStyle("GuideCaption", parent=STYLES["GuideBody"], fontName="GuideSansItalic", fontSize=8.4,
                          leading=11.5, textColor=colors.HexColor(BLUE), alignment=TA_CENTER, spaceAfter=10))


class GuideDoc(BaseDocTemplate):
    def __init__(self, filename):
        super().__init__(filename, pagesize=A4, leftMargin=45, rightMargin=45, topMargin=54, bottomMargin=49,
                         title="EE2026 FPGA Pinball - Code, Concepts and Rebuilding Guide",
                         author="Project teaching guide", pageCompression=1)
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="normal", leftPadding=0, rightPadding=0)
        self.addPageTemplates(PageTemplate(id="guide", frames=frame, onPage=self.page_art))
        self.section = ""

    def page_art(self, canvas, doc):
        canvas.saveState()
        if doc.page > 1:
            canvas.setFont("GuideSans", 8)
            canvas.setFillColor(colors.HexColor(BLUE))
            canvas.drawString(45, A4[1] - 30, "EE2026 FPGA Pinball | Code, Concepts and Rebuilding")
            canvas.setStrokeColor(colors.HexColor("#C8DCE8"))
            canvas.line(45, A4[1] - 36, A4[0] - 45, A4[1] - 36)
        canvas.setFont("GuideSans", 8)
        canvas.setFillColor(colors.HexColor("#53677C"))
        canvas.drawString(45, 28, "Design snapshot: 14 October 2026 | Source-based teaching guide")
        canvas.drawRightString(A4[0] - 45, 28, str(doc.page))
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph) and flowable.style.name == "GuideH2":
            title = flowable.getPlainText()
            key = "section-" + re.sub(r"[^a-z0-9]+", "-", title.lower())
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(title, key, level=0, closed=False)
            self.notify("TOCEntry", (0, title, self.page, key))


def table_flow(lines, width):
    rows = [[cell.strip() for cell in line.strip().strip("|").split("|")] for line in lines]
    rows = [row for row in rows if not all(re.fullmatch(r":?-+:?", cell) for cell in row)]
    count = max(map(len, rows))
    # Give explanations room, but retain usable identifier columns.
    if count == 2:
        shares = (0.35, 0.65)
    elif count == 3:
        shares = (0.24, 0.28, 0.48)
    else:
        shares = tuple(1 / count for _ in range(count))
    data = [[Paragraph(inline(cell), STYLES["GuideTableHead" if i == 0 else "GuideTable"])
             for cell in row] for i, row in enumerate(rows)]
    table = Table(data, colWidths=[width * share for share in shares], repeatRows=1, hAlign="LEFT")
    row_padding = 4 if rows[0][0] == "Term" else 6
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor(BLUE)),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#EFF5F8")]),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 7), ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), row_padding),
        ("BOTTOMPADDING", (0, 0), (-1, -1), row_padding),
        ("LINEBELOW", (0, 0), (-1, 0), 0.5, colors.HexColor(BLUE)),
        ("LINEBELOW", (0, 1), (-1, -1), 0.25, colors.HexColor("#CADAE3")),
    ]))
    return table


def make_pdf(markdown_path, text):
    target = OUTPUT / "EE2026_Pinball_Code_Guide.pdf"
    doc = GuideDoc(str(target))
    story = [Spacer(1, 72),
             Paragraph("EE2026 FPGA Pinball", ParagraphStyle("CoverTitle", fontName="GuideSansBold", fontSize=30,
                                                               leading=36, textColor=colors.HexColor(INK), spaceAfter=12)),
             Paragraph("Code, concepts and rebuilding guide", ParagraphStyle("CoverSubtitle", fontName="GuideSans", fontSize=18,
                                                                              leading=24, textColor=colors.HexColor(BLUE), spaceAfter=20)),
             Paragraph("Understand the current circuit. Learn the digital-design principles. Build a new interactive FPGA project.", STYLES["GuideBody"]),
             Spacer(1, 16)]
    cover = ROOT / "docs" / "dual_display_preview.png"
    story.extend([PDFImage(str(cover), width=doc.width, height=doc.width * 656 / 1240), Spacer(1, 16),
                  Paragraph("Basys 3 / Artix-7 | OLED 96 x 64 on JC | Native VGA 800 x 600", STYLES["GuideH3"]),
                  Paragraph("Verified implementation snapshot: 14 October 2026. Detailed explanations, worked examples, source map, exercises, timing and debugging workflow.", STYLES["GuideBody"]),
                  PageBreak(), Paragraph("Contents", STYLES["GuideH3"])])
    toc = TableOfContents()
    toc.levelStyles = [ParagraphStyle("GuideTOC", fontName="GuideSans", fontSize=9, leading=13.3,
                                      leftIndent=0, firstLineIndent=0, textColor=colors.HexColor(INK), spaceBefore=3)]
    story.extend([toc, PageBreak()])
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.startswith("# "):
            i += 1
            continue
        if line == "## Contents":
            i += 1
            while i < len(lines) and not lines[i].startswith("## "):
                i += 1
            continue
        if line.startswith("## "):
            story.append(Paragraph(inline(line[3:]), STYLES["GuideH2"]))
            i += 1
        elif line.startswith("### "):
            story.append(Paragraph(inline(line[4:]), STYLES["GuideH3"]))
            i += 1
        elif line.startswith("```"):
            code = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                code.append(lines[i])
                i += 1
            story.append(KeepTogether([
                Preformatted("\n".join(code), STYLES["GuideCode"], maxLineLength=101)
            ]))
            i += 1
        elif line.startswith("|"):
            table_lines = []
            while i < len(lines) and lines[i].startswith("|"):
                table_lines.append(lines[i])
                i += 1
            story.extend([table_flow(table_lines, doc.width), Spacer(1, 10)])
        elif line.startswith("!["):
            match = re.fullmatch(r"!\[([^\]]*)\]\(([^)]+)\)", line)
            if not match:
                raise ValueError("Unsupported image line: " + line)
            path = markdown_path.parent / match.group(2)
            with Image.open(path) as im:
                width, height = im.size
            scale = min(doc.width / width, 440 / height)
            story.extend([PDFImage(str(path), width=width * scale, height=height * scale),
                          Paragraph(inline(match.group(1)), STYLES["GuideCaption"])])
            i += 1
        elif line.startswith("- ") or re.match(r"^\d+\. ", line):
            prefix = "- " if line.startswith("- ") else re.match(r"^\d+\. ", line).group()
            story.append(Paragraph(inline(prefix + line[len(prefix):]), STYLES["GuideBullet"]))
            i += 1
        else:
            paragraph = [line.strip()]
            i += 1
            while i < len(lines) and lines[i].strip() and not re.match(r"^(?:#|\||```|!\[|- |\d+\. )", lines[i]):
                paragraph.append(lines[i].strip())
                i += 1
            story.append(Paragraph(inline(" ".join(paragraph)), STYLES["GuideBody"]))
    doc.multiBuild(story)
    reader = PdfReader(target)
    assert len(reader.pages) > 15
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)
    for required in ("1,048,577", "88.37", "611", "BCD", "16-cycle", "18,231", "240"):
        assert required in extracted, "Missing teaching content: " + required
    stats = {"markdown": str(markdown_path), "pdf": str(target), "pages": len(reader.pages),
             "words": len(text.split()), "chapters": len(re.findall(r"^## \d+\.", text, re.M))}
    stats_dir = ROOT / "tmp" / "guide_sources"
    stats_dir.mkdir(parents=True, exist_ok=True)
    (stats_dir / "guide_stats.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")
    print(json.dumps(stats, indent=2))
    return target


if __name__ == "__main__":
    make_diagrams()
    md, content, chapters = assemble()
    make_pdf(md, content)
