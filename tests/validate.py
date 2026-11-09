"""Static checks for the Leonidas - Neon Light terminal files (Python 3.11+, stdlib only).

    python tests/validate.py
"""
import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
errors: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


# 1. Windows Terminal color scheme: valid JSON, all 20 keys, hex colors
SCHEME_KEYS = {
    "background", "foreground", "cursorColor", "selectionBackground",
    "black", "red", "green", "yellow", "blue", "purple", "cyan", "white",
    "brightBlack", "brightRed", "brightGreen", "brightYellow",
    "brightBlue", "brightPurple", "brightCyan", "brightWhite",
}
scheme = json.loads((ROOT / "windows-terminal/leonidas-neon-light.scheme.json").read_text(encoding="utf-8"))
check(scheme.get("name") == "Leonidas - Neon Light", "scheme: name must be 'Leonidas - Neon Light'")
missing = SCHEME_KEYS - scheme.keys()
check(not missing, f"scheme: missing keys {sorted(missing)}")
for key in SCHEME_KEYS & scheme.keys():
    check(bool(HEX.match(scheme[key])), f"scheme: {key}={scheme[key]!r} is not #RRGGBB")

# 2. Starship: valid TOML, palette exists, every color_* reference is defined
toml_text = (ROOT / "starship/starship.toml").read_text(encoding="utf-8")
config = tomllib.loads(toml_text)
palette_name = config.get("palette")
palette = config.get("palettes", {}).get(palette_name, {})
check(palette_name == "leonidas_neon", f"starship: palette is {palette_name!r}, expected 'leonidas_neon'")
check(bool(palette), "starship: palette section [palettes.leonidas_neon] is missing or empty")
for name, value in palette.items():
    check(bool(HEX.match(value)), f"starship: palette {name}={value!r} is not #RRGGBB")
for ref in sorted(set(re.findall(r"\bcolor_[a-z0-9]+\b", toml_text))):
    check(ref in palette, f"starship: {ref} is used but not defined in the palette")

# 3. Shader: entry point and Windows Terminal constant buffer
hlsl = (ROOT / "windows-terminal/leonidas-neon.hlsl").read_text(encoding="utf-8")
check("float4 main(" in hlsl, "shader: missing 'float4 main(' entry point")
for field in ("float  Time;", "float  Scale;", "float2 Resolution;", "float4 Background;"):
    check(field in hlsl, f"shader: constant buffer field {field!r} missing")

# 4. PowerShell scripts: UTF-8 with BOM (required by Windows PowerShell 5.1 for non-ASCII text)
for script in ("install.ps1", "claude-code/statusline.ps1"):
    raw = (ROOT / script).read_bytes()
    check(raw.startswith(b"\xef\xbb\xbf"), f"{script}: must be saved as UTF-8 with BOM")

# 5. Shell scripts: LF line endings
for script in ("bash/leonidas-neon.bash", "starship/build-target.sh"):
    check(b"\r\n" not in (ROOT / script).read_bytes(), f"{script}: must use LF line endings")

# 6. No leftover placeholders or personal data in published files
PATTERNS = re.compile(r"TODO_|@noelse\.com|bhrakotondratompo", re.I)
for path in ROOT.rglob("*"):
    if path.is_file() and ".git" not in path.parts and path.suffix not in {".png"} and path.name != "validate.py":
        text = path.read_text(encoding="utf-8", errors="ignore")
        for match in PATTERNS.finditer(text):
            errors.append(f"{path.relative_to(ROOT)}: forbidden text {match.group(0)!r}")

if errors:
    print("FAILED")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("All static checks passed.")
