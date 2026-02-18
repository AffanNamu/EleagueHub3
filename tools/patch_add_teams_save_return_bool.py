import re
from pathlib import Path

path = Path("lib/features/leagues/presentation/add_teams_screen.dart")
s = path.read_text(encoding="utf-8")

# 1) Change return type of _saveTeamsOnly to Future<bool>
s2 = s.replace(
    "Future<void> _saveTeamsOnly({bool silent = false}) async {",
    "Future<bool> _saveTeamsOnly({bool silent = false}) async {",
    1
)
if s2 == s:
    raise SystemExit("Could not find _saveTeamsOnly signature to patch.")
s = s2

# 2) Insert `return true;` at end of try-block of _saveTeamsOnly
pattern_true = r"(Future<bool> _saveTeamsOnly\(\{bool silent = false\}\) async \{.*?)(\n\s*\} catch \(e\) \{)"
m = re.search(pattern_true, s, flags=re.S)
if not m:
    raise SystemExit("Could not locate _saveTeamsOnly try/catch block for return true insertion.")
before = m.group(1)
after = m.group(2)
if "return true;" not in before:
    before = before + "\n\n      return true;"
s = s[:m.start()] + before + after + s[m.end():]

# 3) Insert `return false;` at end of catch-block of _saveTeamsOnly (before finally)
pattern_false = r"(Future<bool> _saveTeamsOnly\(\{bool silent = false\}\) async \{.*?\} catch \(e\) \{.*?)(\n\s*\} finally \{)"
m = re.search(pattern_false, s, flags=re.S)
if not m:
    raise SystemExit("Could not locate _saveTeamsOnly catch/finally block for return false insertion.")
before = m.group(1)
after = m.group(2)
if "return false;" not in before:
    before = before + "\n      return false;"
s = s[:m.start()] + before + after + s[m.end():]

# 4) In _generateFixturesOnly(), abort if save failed
needle = "      await _saveTeamsOnly(silent: true);\n"
if needle not in s:
    # If spacing differs, try a looser replacement
    s = re.sub(r"\n\s*await _saveTeamsOnly\(silent:\s*true\);\s*\n",
               "\n      final saved = await _saveTeamsOnly(silent: true);\n      if (!saved) return;\n\n",
               s, count=1)
else:
    s = s.replace(
        needle,
        "      final saved = await _saveTeamsOnly(silent: true);\n      if (!saved) return;\n\n",
        1
    )

path.write_text(s, encoding="utf-8")
print("Patched AddTeamsScreen: _saveTeamsOnly now returns bool; generate fixtures stops if save fails.")
