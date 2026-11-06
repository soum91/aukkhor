import json, sys
src, out = sys.argv[1], sys.argv[2]
d = json.load(open(src))
by = {g['slug']: g['emojis'] for g in d}
groups = [
    ("Smileys & People", "face.smiling", by['smileys_emotion'] + by['people_body']),
    ("Animals & Nature", "leaf", by['animals_nature']),
    ("Food & Drink", "fork.knife", by['food_drink']),
    ("Activity", "soccerball", by['activities']),
    ("Travel & Places", "car", by['travel_places']),
    ("Objects", "lightbulb", by['objects']),
    ("Symbols", "heart", by['symbols']),
    ("Flags", "flag", by['flags']),
]
def lit(s):
    return json.dumps(s, ensure_ascii=False)
SEP = "\u001f"
lines = []
lines.append("// Generated from unicode-emoji-json 0.9.0 (Unicode emoji data, emoji 17.0).")
lines.append("// Do not edit by hand; regenerate with scripts/gen_emoji.py.")
lines.append("// Each group is one string, split at runtime, so the compiler never")
lines.append("// type-checks a 1,900-element array literal.")
lines.append("enum EmojiData {")
lines.append("    struct RawGroup {")
lines.append("        let title: String")
lines.append("        let symbol: String")
lines.append("        let glyphs: String   // U+001F separated")
lines.append("        let names: String    // U+001F separated, same order")
lines.append("        let toned: String    // U+001F separated glyphs that take skin tones")
lines.append("    }")
lines.append("    static let separator: Character = \"\\u{1F}\"")
lines.append("    static let groups: [RawGroup] = [")
newer = {}
for title, symbol, emojis in groups:
    glyphs = SEP.join(e['emoji'] for e in emojis)
    names = SEP.join(e['name'] for e in emojis)
    toned = SEP.join(e['emoji'] for e in emojis if e['skin_tone_support'])
    for e in emojis:
        v = float(e['emoji_version'])
        if v >= 15.0: newer.setdefault(e['emoji_version'], []).append(e['emoji'])
    lines.append("        RawGroup(title: %s, symbol: %s,\n                 glyphs: %s,\n                 names: %s,\n                 toned: %s)," % (
        lit(title), lit(symbol), lit(glyphs).replace("\\u001f", "\\u{1F}"),
        lit(names).replace("\\u001f", "\\u{1F}"), lit(toned).replace("\\u001f", "\\u{1F}")))
lines.append("    ]")
lines.append("    // Emoji added in recent Unicode releases, by emoji version. Hidden on")
lines.append("    // iOS versions whose font cannot draw them (they would show as boxes).")
lines.append("    static let newer: [(version: Double, glyphs: String)] = [")
for v in sorted(newer, key=float):
    lines.append("        (%s, %s)," % (v, lit(SEP.join(newer[v])).replace("\\u001f", "\\u{1F}")))
lines.append("    ]")
lines.append("}")
open(out, "w").write("\n".join(lines) + "\n")
print(sum(len(g[2]) for g in groups), "emoji")
