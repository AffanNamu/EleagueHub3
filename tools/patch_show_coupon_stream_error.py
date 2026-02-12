from pathlib import Path

PATH = Path("lib/features/leagues/presentation/league_admin_screen.dart")
src = PATH.read_text(encoding="utf-8")

old = "Failed to load coupon configuration."
if old not in src:
    raise SystemExit("Could not find the coupon config error text to patch.")

# Replace ONLY the first occurrence (coupon config sheet)
src = src.replace(
    f"'{old}'",
    "'Failed to load coupon configuration.\\n' + (snap.error?.toString() ?? 'unknown')",
    1,
)

PATH.write_text(src, encoding="utf-8")
print("Patched:", PATH)
