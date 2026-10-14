"""Convert exact RTL RGB565 dumps into OLED and native VGA previews."""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--dumps-dir", type=Path, default=root / "tests")
args = parser.parse_args()
dumps = args.dumps_dir
out = root / "docs"
out.mkdir(exist_ok=True)
labels = ["MENU", "READY", "PLAY", "PAUSE", "GAME OVER", "TABLE BONUS"]
canvas = Image.new("RGB", (1152, 580), (18, 24, 36))
draw = ImageDraw.Draw(canvas)
for i, label in enumerate(labels):
    values = [int(t, 16) for t in (dumps / f"render_{i}.hex").read_text(encoding="utf-8").split()]
    assert len(values) == 96 * 64
    im = Image.new("RGB", (96, 64))
    im.putdata([((v >> 11) * 255 // 31, ((v >> 5) & 63) * 255 // 63,
                 (v & 31) * 255 // 31) for v in values])
    im.save(out / (("jackpot" if i==5 else label.lower().replace(" ", "_")) + ".png"))
    x, y = (i % 3) * 384, (i // 3) * 290
    canvas.paste(im.resize((384, 256), Image.Resampling.NEAREST), (x, y + 24))
    draw.text((x + 12, y + 6), label, fill="white")
canvas.save(out / "display_preview.png")
native_canvas = Image.new("RGB", (1600, 1896), (18, 24, 36))
native_draw = ImageDraw.Draw(native_canvas)
for i, label in enumerate(labels):
    native_file = dumps / f"vga_render_{i}.hex"
    if not native_file.exists():
        continue
    values = [int(t,16) for t in native_file.read_text().split()]
    assert len(values)==800*600
    im=Image.new("RGB",(800,600))
    im.putdata([((v>>11)*255//31,((v>>5)&63)*255//63,(v&31)*255//31) for v in values])
    im.save(out / ("vga_"+("jackpot" if i==5 else label.lower().replace(" ","_"))+".png"))
    x,y=(i%2)*800,(i//2)*632
    native_canvas.paste(im,(x,y+24))
    native_draw.text((x+12,y+6),label,fill="white")
native_canvas.save(out / "vga_preview.png")
comparison=Image.new("RGB",(1240,656),(18,24,36))
comparison_draw=ImageDraw.Draw(comparison)
small=Image.open(out/"play.png").resize((384,256),Image.Resampling.NEAREST)
large=Image.open(out/"vga_play.png")
comparison.paste(small,(16,190))
comparison.paste(large,(424,32))
comparison_draw.text((16,166),"96 x 64 OLED (shown 4x)",fill="white")
comparison_draw.text((424,8),"Native 800 x 600 VGA",fill="white")
comparison.save(out/"dual_display_preview.png")
print(out/"display_preview.png")
print(out/"vga_preview.png")
print(out/"dual_display_preview.png")

# Supplementary motion poses are exact RTL pixels. Their sequence illustrates
# positions; it is not a recording of the complete real-time physics simulation.
motion_frames=[]
motion_sheet=Image.new("RGB",(1240,1968),(18,24,36))
for pose,label in enumerate(("START", "FRACTIONAL MIDPOINT", "TRAVEL ENDPOINTS")):
    native_dump=dumps/f"vga_render_motion_{pose}.hex"
    oled_dump=dumps/f"render_motion_{pose}.hex"
    if not native_dump.exists() or not oled_dump.exists():
        continue
    pose_canvas=Image.new("RGB",(1240,656),(18,24,36))
    pose_draw=ImageDraw.Draw(pose_canvas)
    for source,size,where,scale in ((oled_dump,(96,64),(16,190),4),
                                   (native_dump,(800,600),(424,32),1)):
        values=[int(t,16) for t in source.read_text().split()]
        assert len(values)==size[0]*size[1]
        pixels=Image.new("RGB",size)
        pixels.putdata([((v>>11)*255//31,((v>>5)&63)*255//63,(v&31)*255//31) for v in values])
        pixels=pixels.resize((size[0]*scale,size[1]*scale),Image.Resampling.NEAREST)
        pose_canvas.paste(pixels,where)
    pose_draw.text((16,12),"RTL position sample: "+label,fill="white")
    pose_draw.text((16,166),"96 x 64 OLED (shown 4x)",fill="white")
    pose_draw.text((424,8),"Native 800 x 600 VGA",fill="white")
    motion_sheet.paste(pose_canvas,(0,pose*656))
    motion_frames.append(pose_canvas)
if len(motion_frames)==3:
    motion_sheet.save(out/"moving_bumpers_preview.png")
    sequence=[motion_frames[i] for i in (0,1,2,1)]
    sequence[0].save(out/"moving_bumpers_preview.gif",save_all=True,
                     append_images=sequence[1:],duration=900,loop=0)
    print(out/"moving_bumpers_preview.gif")

# These static state samples come directly from the two renderer testbenches.
multiball_labels=("U / CLICK TWO-BALL MENU", "BOTH BALLS QUEUED",
                  "WHITE AND GOLD BALLS PLAY", "GOLD BALL CONTINUES AFTER WHITE DRAINS")
multiball_sheet=Image.new("RGB",(1240,2624),(18,24,36))
multiball_count=0
for sample,label in enumerate(multiball_labels):
    native_dump=dumps/f"vga_render_multiball_{sample}.hex"
    oled_dump=dumps/f"render_multiball_{sample}.hex"
    if not native_dump.exists() or not oled_dump.exists():
        continue
    sample_canvas=Image.new("RGB",(1240,656),(18,24,36))
    sample_draw=ImageDraw.Draw(sample_canvas)
    for source,size,where,scale in ((oled_dump,(96,64),(16,190),4),
                                   (native_dump,(800,600),(424,32),1)):
        values=[int(t,16) for t in source.read_text(encoding="utf-8").split()]
        assert len(values)==size[0]*size[1]
        pixels=Image.new("RGB",size)
        pixels.putdata([((v>>11)*255//31,((v>>5)&63)*255//63,(v&31)*255//31) for v in values])
        pixels=pixels.resize((size[0]*scale,size[1]*scale),Image.Resampling.NEAREST)
        sample_canvas.paste(pixels,where)
    sample_draw.text((16,12),"RTL state sample: "+label,fill="white")
    sample_draw.text((16,166),"96 x 64 OLED (shown 4x)",fill="white")
    sample_draw.text((424,8),"Native 800 x 600 VGA",fill="white")
    sample_canvas.save(out/f"multiball_{sample}.png")
    multiball_sheet.paste(sample_canvas,(0,sample*656))
    multiball_count+=1
if multiball_count==4:
    multiball_sheet.save(out/"multiball_preview.png")
    print(out/"multiball_preview.png")

# Event poses are exact renderer captures, not imported cartoon artwork.
funny_labels=("REWARD: CIRCUIT CAT CHEERS", "NUDGE: NANI!",
              "SAVED BALL: PHEW!")
funny_sheet=Image.new("RGB",(1240,1968),(18,24,36))
funny_frames=[]
for sample,label in enumerate(funny_labels):
    native_dump=dumps/f"vga_render_funny_{sample}.hex"
    oled_dump=dumps/f"render_funny_{sample}.hex"
    if not native_dump.exists() or not oled_dump.exists():
        continue
    sample_canvas=Image.new("RGB",(1240,656),(18,24,36))
    sample_draw=ImageDraw.Draw(sample_canvas)
    for source,size,where,scale in ((oled_dump,(96,64),(16,190),4),
                                   (native_dump,(800,600),(424,32),1)):
        values=[int(t,16) for t in source.read_text(encoding="utf-8").split()]
        assert len(values)==size[0]*size[1]
        pixels=Image.new("RGB",size)
        pixels.putdata([((v>>11)*255//31,((v>>5)&63)*255//63,(v&31)*255//31) for v in values])
        pixels=pixels.resize((size[0]*scale,size[1]*scale),Image.Resampling.NEAREST)
        sample_canvas.paste(pixels,where)
    sample_draw.text((16,12),"RTL reaction sample: "+label,fill="white")
    sample_draw.text((16,166),"96 x 64 OLED (shown 4x)",fill="white")
    sample_draw.text((424,8),"Native 800 x 600 VGA",fill="white")
    sample_canvas.save(out/f"funny_{sample}.png")
    funny_sheet.paste(sample_canvas,(0,sample*656))
    funny_frames.append(sample_canvas)
if len(funny_frames)==3:
    funny_sheet.save(out/"funny_preview.png")
    print(out/"funny_preview.png")
