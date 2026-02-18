from pathlib import Path

path = Path("lib/features/leagues/presentation/add_teams_screen.dart")
s = path.read_text(encoding="utf-8")

start = s.find("Future<void> _saveTeamsOnly({bool silent = false}) async {")
if start == -1:
    start = s.find("Future<bool> _saveTeamsOnly({bool silent = false}) async {")
    if start == -1:
        raise SystemExit("Could not find _saveTeamsOnly() in add_teams_screen.dart")

gen_marker = "Future<void> _generateFixturesOnly() async {"
gen_pos = s.find(gen_marker, start)
if gen_pos == -1:
    raise SystemExit("Could not find _generateFixturesOnly() after _saveTeamsOnly()")

block = s[start:gen_pos]

# 1) Ensure return type is Future<bool>
block = block.replace(
    "Future<void> _saveTeamsOnly({bool silent = false}) async {",
    "Future<bool> _saveTeamsOnly({bool silent = false}) async {",
)

# 2) Insert return true before catch (only within this function block)
if "return true;" not in block:
    block = block.replace(
        "\n    } catch (e) {",
        "\n\n      return true;\n    } catch (e) {",
        1,
    )

# 3) Insert return false before finally (only within this function block)
if "return false;" not in block:
    block = block.replace(
        "\n    } finally {",
        "\n      return false;\n    } finally {",
        1,
    )

s = s[:start] + block + s[gen_pos:]

# 4) In generate flow: await save -> check result
needle = "      await _saveTeamsOnly(silent: true);\n"
if needle in s:
    s = s.replace(
        needle,
        "      final saved = await _saveTeamsOnly(silent: true);\n      if (!saved) return;\n\n",
        1,
    )
else:
    # Fallback (handles minor formatting differences)
    target = "await _saveTeamsOnly(silent: true);"
    if target in s:
        s = s.replace(
            target,
            "final saved = await _saveTeamsOnly(silent: true);\n      if (!saved) return;",
            1,
        )
    else:
        raise SystemExit("Could not find call: await _saveTeamsOnly(silent: true);")

path.write_text(s, encoding="utf-8")
print("OK: Patched add_teams_screen.dart (save returns bool; generate stops if save fails).")
