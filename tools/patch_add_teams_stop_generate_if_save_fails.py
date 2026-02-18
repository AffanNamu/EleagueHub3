import re
from pathlib import Path

p = Path("lib/features/leagues/presentation/add_teams_screen.dart")
s = p.read_text(encoding="utf-8")

# Change _saveTeamsOnly return type to Future<bool>
s, n1 = re.subn(r"Future<void>\s+_saveTeamsOnly\(", "Future<bool> _saveTeamsOnly(", s, count=1)
if n1 != 1:
    raise SystemExit("Couldn't patch _saveTeamsOnly signature")

# Ensure it returns true on success and false on failure.
# Insert 'return true;' just before the catch of _saveTeamsOnly
s = re.sub(
    r"(Future<bool>\s+_saveTeamsOnly\(\{bool silent = false\}\)\s+async\s*\{.*?\n)(\s*\}\s*catch\s*\(e\)\s*\{)",
    r"\1\n      return true;\n\2",
    s,
    count=1,
    flags=re.S,
)

# Insert 'return false;' at end of catch block before finally
s = re.sub(
    r"(\}\s*catch\s*\(e\)\s*\{.*?\n\s*if\s*\(mounted\)\s*_snackErr\(msg\);\n\s*\})(\s*finally\s*\{)",
    r"\1\n      return false;\n    }\n\n    \2",
    s,
    count=1,
    flags=re.S,
)

# In _generateFixturesOnly: await save -> check result
s, n2 = re.subn(
    r"\n\s*await\s+_saveTeamsOnly\(silent:\s*true\);\s*\n",
    "\n      final saved = await _saveTeamsOnly(silent: true);\n      if (!saved) return;\n\n",
    s,
    count=1,
)
if n2 != 1:
    raise SystemExit("Couldn't patch _generateFixturesOnly save call")

p.write_text(s, encoding="utf-8")
print("Patched: AddTeamsScreen now stops fixture generation if saving teams failed.")
