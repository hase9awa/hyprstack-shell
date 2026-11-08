#!/usr/bin/env python3
"""Build the picker's character set from the Unicode emoji data.

The emoji themselves come from emoji-test.txt (UTS #51), which carries the
official groups and names. Skin tone variants are left out: they multiply the
set several times over and the picker offers the base character instead.

The symbol section is built from the Unicode character database that Python
ships, so it needs no download, and the kaomoji are a hand-kept list.

Characters newer than the fonts in circulation are left out, or they show
up in the picker as empty boxes. Raise the cap once the emoji fonts catch up.

Usage:
    ./generate_emoji.py emoji-test.txt [max-emoji-version] > ../shell/assets/emoji.json
"""

import json
import re
import sys
import unicodedata

# Material Symbols shown beside each section in the picker.
GROUP_ICONS = {
    "Smileys & Emotion": ("smileys", "mood"),
    "People & Body": ("people", "waving_hand"),
    "Animals & Nature": ("nature", "pets"),
    "Food & Drink": ("food", "restaurant"),
    "Travel & Places": ("travel", "flight"),
    "Activities": ("activities", "sports_soccer"),
    "Objects": ("objects", "lightbulb"),
    "Symbols": ("symbols", "tag"),
    "Flags": ("flags", "flag"),
}

# Blocks worth offering as characters, the way a character map would group
# them. Each entry is a name, an icon and the ranges it covers.
SYMBOL_BLOCKS = [
    ("arrows", "arrow_outward", [(0x2190, 0x21FF), (0x27F0, 0x27FF), (0x2900, 0x297F)]),
    ("maths", "functions", [(0x2200, 0x22FF), (0x2A00, 0x2AFF), (0x00B1, 0x00B1), (0x00D7, 0x00D7),
                            (0x00F7, 0x00F7)]),
    ("currency", "payments", [(0x20A0, 0x20BF), (0x0024, 0x0024), (0x00A2, 0x00A5)]),
    ("punctuation", "format_quote", [(0x2010, 0x205E), (0x00A1, 0x00BF)]),
    ("letterlike", "superscript", [(0x2070, 0x209C), (0x2100, 0x214F), (0x2150, 0x218B)]),
    ("shapes", "shapes", [(0x25A0, 0x25FF), (0x2B00, 0x2BFF)]),
    ("greek", "language", [(0x0370, 0x03FF)]),
]

# Text faces have no character database to read them out of.
KAOMOJI = [
    ("¯\\_(ツ)_/¯", "shrug"), ("(╯°□°)╯︵ ┻━┻", "table flip"), ("┬─┬ ノ( ゜-゜ノ)", "table back"),
    ("(ノಠ益ಠ)ノ彡┻━┻", "angry flip"), ("ಠ_ಠ", "disapproval"), ("ಥ_ಥ", "crying"),
    ("(╥﹏╥)", "sobbing"), ("(づ｡◕‿‿◕｡)づ", "hug"), ("(✿◠‿◠)", "flower smile"),
    ("(◕‿◕)", "smile"), ("(｡◕‿◕｡)", "cute"), ("(✧ω✧)", "sparkle eyes"),
    ("(>‿◠)✌", "wink peace"), ("( ͡° ͜ʖ ͡°)", "lenny"), ("(¬‿¬)", "smirk"),
    ("(•_•)", "blank"), ("(⌐■_■)", "deal with it"), ("(ง'̀-'́)ง", "fight"),
    ("ᕕ( ᐛ )ᕗ", "running"), ("(•̀ᴗ•́)و", "determined"), ("\\(^o^)/", "cheer"),
    ("(^_^)", "happy"), ("(T_T)", "tears"), ("(-_-)", "unamused"),
    ("(°□°)", "shocked"), ("(¬_¬)", "annoyed"), ("(*_*)", "star struck"),
    ("(^_~)", "wink"), ("(=^･ω･^=)", "cat"), ("ʕ•ᴥ•ʔ", "bear"),
    ("(づ￣ ³￣)づ", "kiss"), ("(人･∀･)", "please"), ("(╬ Ò﹏Ó)", "furious"),
    ("(ಠ‿ಠ)", "mischief"), ("(￣▽￣)ノ", "wave"), ("(._.)", "quiet"),
    ("(〜￣▽￣)〜", "dancing"), ("ヽ(•‿•)ノ", "yay"), ("(•ω•)", "soft"),
    ("(=_=)", "tired"), ("(≖‿≖)", "sly"), ("(ʘ‿ʘ)", "wide eyes"),
    ("(•‿•)", "pleased"), ("o(≧▽≦)o", "delighted"), ("(╯︵╰,)", "sad"),
    ("( ˘▽˘)っ♨", "tea"), ("(~˘▾˘)~", "sway"), ("乁( ◔ ౪◔)ㄏ", "whatever"),
    ("(☞ﾟヮﾟ)☞", "pointing"), ("☜(ﾟヮﾟ☜)", "pointing back"),
]


DEFAULT_MAX_VERSION = 17.0


def read_emoji(path, max_version):
    groups, entries = [], []
    seen_groups, group, subgroup = set(), None, ""
    line_pattern = re.compile(r"^([0-9A-F ]+);\s*(\S+)\s*#\s*(\S+)\s+E([\d.]+)\s+(.+)$")

    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if line.startswith("# subgroup:"):
            subgroup = line.split(":", 1)[1].strip()
            continue
        match = line_pattern.match(line)
        if not match or match.group(2) != "fully-qualified" or group not in GROUP_ICONS:
            continue
        name = match.group(5)
        # A tone is a variant of a character the picker already offers, and a
        # character no font draws yet is only an empty box.
        if "skin tone" in name or float(match.group(4)) > max_version:
            continue

        slug, icon = GROUP_ICONS[group]
        if slug not in seen_groups:
            seen_groups.add(slug)
            groups.append({"id": slug, "name": group, "icon": icon})
        entries.append({"c": match.group(3), "n": name, "g": slug, "k": subgroup.replace("-", " ")})

    return groups, entries


def read_symbols():
    groups, entries = [], []
    for slug, icon, ranges in SYMBOL_BLOCKS:
        groups.append({"id": slug, "name": slug.capitalize(), "icon": icon})
        for start, end in ranges:
            for point in range(start, end + 1):
                char = chr(point)
                name = unicodedata.name(char, "")
                # Unnamed points are unassigned, and separators have nothing
                # to show in a grid.
                if not name or unicodedata.category(char) in ("Cc", "Cf", "Zs", "Zl", "Zp"):
                    continue
                entries.append({"c": char, "n": name.lower(), "g": slug, "k": ""})
    return groups, entries


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)

    max_version = float(sys.argv[2]) if len(sys.argv) == 3 else DEFAULT_MAX_VERSION
    groups, entries = read_emoji(sys.argv[1], max_version)

    groups.append({"id": "kaomoji", "name": "Kaomoji", "icon": "sentiment_satisfied"})
    entries.extend({"c": face, "n": name, "g": "kaomoji", "k": "kaomoji"} for face, name in KAOMOJI)

    symbol_groups, symbol_entries = read_symbols()
    groups.extend(symbol_groups)
    entries.extend(symbol_entries)

    json.dump({"groups": groups, "entries": entries}, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    print(file=sys.stderr)
    print(f"{len(entries)} characters in {len(groups)} groups", file=sys.stderr)


if __name__ == "__main__":
    main()
