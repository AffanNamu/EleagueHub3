from pathlib import Path
import re

p = Path("lib/features/leagues/presentation/add_teams_screen.dart")
s = p.read_text(encoding="utf-8")

# 1) Remove any "if (!saved) return;" lines (with flexible spacing)
s = re.sub(r"^\s*if\s*\(\s*!\s*saved\s*\)\s*return\s*;\s*\n", "", s, flags=re.M)

# 2) Remove any "final saved = await _saveTeamsOnly(silent: true);" lines
s = re.sub(
    r"^\s*final\s+saved\s*=\s*await\s+_saveTeamsOnly\s*\(\s*silent\s*:\s*true\s*\)\s*;\s*\n",
    "",
    s,
    flags=re.M,
)

# 3) Fix the known corrupted line if present
s = s.replace(
    "final saved = final saved = await _saveTeamsOnly(silent: true);",
    "await _saveTeamsOnly(silent: true);",
)

# 4) Ensure generate flow still calls saveTeams once.
# If generate function does not contain _saveTeamsOnly(silent: true), insert it right after "try {"
gen_start = s.find("Future<void> _generateFixturesOnly() async {")
if gen_start == -1:
    raise SystemExit("Could not find _generateFixturesOnly()")

gen_block = s[gen_start:]
if "_saveTeamsOnly(silent: true)" not in gen_block:
    # Insert after the first "try {"
    gen_block = gen_block.replace(
        "    try {\n",
        "    try {\n      await _saveTeamsOnly(silent: true);\n\n",
        1,
    )
    s = s[:gen_start] + gen_block

p.write_text(s, encoding="utf-8")
print("OK: Removed leftover 'saved' lines and ensured _saveTeamsOnly(silent:true) is called in _generateFixturesOnly().")
