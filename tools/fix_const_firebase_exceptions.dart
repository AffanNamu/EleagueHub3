import 'dart:io';

/// Fixes build breaks caused by invalid `const FirebaseAuthException(...)`
/// and `const FirebaseException(...)` usages.
///
/// FirebaseAuthException/FirebaseException constructors are NOT const.
/// Any `throw const ...` or `= const ...` will fail to compile.
///
/// Usage:
///   dart run tools/fix_const_firebase_exceptions.dart
///
/// Optional:
///   dart run tools/fix_const_firebase_exceptions.dart --dry-run
void main(List<String> args) {
  final dryRun = args.contains('--dry-run');

  final root = Directory.current;
  final libDir = Directory('${root.path}${Platform.pathSeparator}lib');

  if (!libDir.existsSync()) {
    stderr.writeln('Could not find ./lib directory. Run this from the project root.');
    exitCode = 2;
    return;
  }

  final dartFiles = <File>[];
  for (final ent in libDir.listSync(recursive: true, followLinks: false)) {
    if (ent is File && ent.path.endsWith('.dart')) {
      dartFiles.add(ent);
    }
  }

  final patterns = <RegExp, String>{
    // `throw const FirebaseAuthException(`, `= const FirebaseAuthException(`, etc.
    RegExp(r'\bconst\s+FirebaseAuthException\s*\('): 'FirebaseAuthException(',
    RegExp(r'\bconst\s+FirebaseException\s*\('): 'FirebaseException(',
  };

  int changed = 0;

  for (final f in dartFiles) {
    final original = f.readAsStringSync();
    var updated = original;

    for (final entry in patterns.entries) {
      updated = updated.replaceAll(entry.key, entry.value);
    }

    if (updated != original) {
      changed++;
      stdout.writeln('${dryRun ? "[dry-run] " : ""}patched: ${f.path}');
      if (!dryRun) {
        f.writeAsStringSync(updated);
      }
    }
  }

  stdout.writeln('Done. ${dryRun ? "Would patch" : "Patched"} $changed file(s).');
}
