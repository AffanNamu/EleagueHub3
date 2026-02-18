from pathlib import Path
import re

p = Path("lib/features/leagues/presentation/add_teams_screen.dart")
s = p.read_text(encoding="utf-8")

save_sig_void = "Future<void> _saveTeamsOnly({bool silent = false}) async {"
save_sig_bool = "Future<bool> _saveTeamsOnly({bool silent = false}) async {"

start = s.find(save_sig_void)
if start == -1:
    start = s.find(save_sig_bool)
    if start == -1:
        raise SystemExit("Could not find _saveTeamsOnly() signature in add_teams_screen.dart")

gen_marker = "Future<void> _generateFixturesOnly() async {"
gen_pos = s.find(gen_marker, start)
if gen_pos == -1:
    raise SystemExit("Could not find _generateFixturesOnly() after _saveTeamsOnly()")

block = s[start:gen_pos]

# 1) Restore signature to Future<void>
block = block.replace(save_sig_bool, save_sig_void)

# 2) Remove any injected return true/false lines inside this function block
block_lines = block.splitlines(True)
clean_lines = []
for ln in block_lines:
    stripped = ln.strip()
    if stripped in ("return true;", "return false;"):
        continue
    clean_lines.append(ln)
block = "".join(clean_lines)

# 3) Ensure catch rethrows when silent=true, and does not snack when silent=true
# Replace:
#   if (mounted) _snackErr(msg);
# with:
#   if (!silent && mounted) _snackErr(msg);
#   if (silent) rethrow;
block = block.replace(
    "      if (mounted) _snackErr(msg);\n",
    "      if (!silent && mounted) _snackErr(msg);\n      if (silent) rethrow;\n",
)

s = s[:start] + block + s[gen_pos:]

# 4) Fix any broken generate call lines
# Replace any "final saved = ..." variants with just await
s = re.sub(
    r"\n\s*final\s+saved\s*=\s*(?:final\s+saved\s*=\s*)?await\s+_saveTeamsOnly\(silent:\s*true\);\s*\n\s*if\s*\(!saved\)\s*return;\s*\n",
    "\n      await _saveTeamsOnly(silent: true);\n",
    s,
    flags=re.S,
)

# Also fix the specific duplicated line if it exists
s = s.replace(
    "      final saved = final saved = await _saveTeamsOnly(silent: true);\n",
    "      await _saveTeamsOnly(silent: true);\n",
)

# If a single-line "final saved = await ..." exists, reduce it
s = re.sub(
    r"\n\s*final\s+saved\s*=\s*await\s+_saveTeamsOnly\(silent:\s*true\);\s*\n\s*if\s*\(!saved\)\s*return;\s*\n",
    "\n      await _saveTeamsOnly(silent: true);\n",
    s,
    flags=re.S,
)

p.write_text(s, encoding="utf-8")
print("OK: add_teams_screen.dart fixed (save flow restored; generate stops if save fails).")
