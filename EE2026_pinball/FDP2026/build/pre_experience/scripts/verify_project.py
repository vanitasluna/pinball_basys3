"""Verify FPGA part, registered sources, and byte-preserved supplied drivers."""
from pathlib import Path
import hashlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
sources = root / "FDP2026.srcs" / "sources_1" / "new"
expected = {
    "Oled_Display.v": "f0f7b4a7a5b65a40598ccbb8f985ac826e788ce381c613409e92cea52528ffe5",
    "Mouse_Control.vhd": "f57b58c4c35b21e569b0d279a2014c41f19a57bf10990338463e0480944d9ca7",
    "Ps2Interface.vhd": "7c2af6f51bd408549435bbb bafcb9d33053a98a1a63bdc1046c9872f52c499eb".replace(" ", ""),
}
for name, digest in expected.items():
    actual = hashlib.sha256((sources / name).read_bytes()).hexdigest()
    assert actual == digest, f"Protected module changed: {name}"
    print(f"UNCHANGED {name}: {actual}")
project = ET.parse(root / "FDP2026.xpr").getroot()
assert project.find('./Configuration/Option[@Name="Part"]').get("Val") == "xc7a35tcpg236-1"
registered = set()
for entry in project.findall("./FileSets/FileSet/File"):
    path = entry.get("Path").replace("$PSRCDIR", str(root / "FDP2026.srcs")).replace("$PPRDIR", str(root))
    assert Path(path).is_file(), f"Missing project source: {path}"
    registered.add(Path(path).name)
for source in sources.iterdir():
    if source.suffix.lower() in (".v", ".vhd"):
        assert source.name in registered, f"Unregistered source: {source}"
    if source.suffix == ".v" and source.name not in expected:
        text = source.read_text(encoding="utf-8")
        first_module = re.search(r"^\s*module\s+", text, re.M)
        assert first_module and text.index("`default_nettype none") < first_module.start(), f"Implicit nets enabled: {source}"
        assert text.rstrip().endswith("`default_nettype wire"), f"Nettype guard leaks into supplied modules: {source}"
xdc = (root / "FDP2026.srcs" / "constrs_1" / "new" / "Basys3_Master.xdc").read_text()
active_assignments = re.findall(r'^set_property[^\n]*PACKAGE_PIN\s+(\w+)[^\n]*get_ports\s+\{JC\[(\d)\]\}', xdc, re.M)
assert dict((int(bit), pin) for pin, bit in active_assignments) == dict(enumerate(
    ["K17", "M18", "N17", "P18", "L17", "M19", "P17", "R18"])), "Incorrect JC pin mapping"
assert not re.search(r'^set_property[^\n]*get_ports\s+\{JA\[', xdc, re.M), "JA still has active pin assignments"
print("PASS project sources, FPGA part, JC pin mapping, explicit-net guards, and protected module integrity")
