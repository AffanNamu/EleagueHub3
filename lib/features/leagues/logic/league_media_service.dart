import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LeagueMediaService {
  const LeagueMediaService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  // Keep aligned with storage.rules under5Mb()
  static const int _maxBytes = 5 * 1024 * 1024;

  /// STRICT mode support:
  /// Storage rules require the Firestore league doc to exist and organizerUserId
  /// to match request.auth.uid before upload is allowed.
  ///
  /// This creates a minimal "draft" league doc if it doesn't exist yet.
  /// - Keeps it private by default (isPrivate: 1) so it won't appear in public discovery.
  /// - Final league creation/sync will overwrite/complete the doc later.
  Future<void> _ensureDraftLeagueDocExists({
    required String leagueId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required to upload league media.');
    }

    final ref = _firestore.collection('leagues').doc(leagueId);
    final snap = await ref.get();

    if (snap.exists) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Minimal doc that passes your Firestore rules:
    // allow create: if signedIn() && organizerUserId == auth.uid
    await ref.set(<String, dynamic>{
      'id': leagueId,
      'organizerUserId': user.uid,

      // Keep it private until the real league payload is written.
      'isPrivate': 1,

      // Optional but helpful to avoid missing-field edge cases elsewhere.
      'memberIds': <String>[user.uid],
      'updatedAtMs': now,
      'version': 1,
    });
  }

  /// Picks a single image from device storage and uploads it to Firebase Storage.
  ///
  /// IMPORTANT:
  /// We DO NOT request `bytes` from the picker because large photos can cause
  /// a native OutOfMemory crash and force-close the app on some devices.
  /// Instead, we upload via `putFile()` (streamed from disk).
  ///
  /// Returns the public download URL if upload succeeds, otherwise null.
  Future<String?> pickAndUploadImage({
    required String leagueId,
    required LeagueMediaKind kind,
    String storageBucketRoot = 'leagues',
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required to upload league media.');
    }

    // Strict requirement: the league doc must exist and be owned by this user.
    await _ensureDraftLeagueDocExists(leagueId: leagueId);

    // Do NOT use withData:true (can crash on large images).
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      withReadStream: true,
      lockParentWindow: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;

    // Enforce server-side rule limit client-side too (better UX, avoids upload failures).
    if (picked.size > _maxBytes) {
      throw StateError('Image too large. Max allowed is 5 MB.');
    }

    final ext = _safeAndAllowedExt(picked.extension);
    final contentType = _contentTypeForExt(ext);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final filename = '${kind.name}_$ts$ext'; // must match storage.rules regex

    File? uploadFile;
    bool isTempFile = false;

    try {
      // Best case: picker gives us a real path we can stream from.
      final path = (picked.path ?? '').trim();
      if (path.isNotEmpty) {
        uploadFile = File(path);
      } else if (picked.readStream != null) {
        // SAF providers may not expose a filesystem path. We copy stream -> temp file.
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = p.join(tmpDir.path, 'eh_${filename}');
        final f = File(tmpPath);

        final sink = f.openWrite();
        await picked.readStream!.pipe(sink);
        await sink.close();

        uploadFile = f;
        isTempFile = true;
      } else {
        // No path and no stream => cannot upload.
        return null;
      }

      if (!await uploadFile.exists()) {
        throw StateError('Selected image file is not accessible.');
      }

      // (Extra safety) check actual file size on disk where possible
      final actualLen = await uploadFile.length();
      if (actualLen > _maxBytes) {
        throw StateError('Image too large. Max allowed is 5 MB.');
      }

      final ref = _storage
          .ref()
          .child(storageBucketRoot)
          .child(leagueId)
          .child('media')
          .child(filename);

      final metadata = SettableMetadata(
        contentType: contentType,
        cacheControl: 'public, max-age=31536000',
      );

      final task = ref.putFile(uploadFile, metadata);
      final snap = await task.whenComplete(() {});
      final url = await snap.ref.getDownloadURL();

      final trimmed = url.trim();
      return trimmed.isEmpty ? null : trimmed;
    } finally {
      // Clean up temp file if we created one.
      if (isTempFile && uploadFile != null) {
        try {
          await uploadFile.delete();
        } catch (_) {
          // non-fatal
        }
      }
    }
  }

  String _safeAndAllowedExt(String? raw) {
    final e = (raw ?? '').trim().toLowerCase();
    final normalized = e.startsWith('.') ? e : (e.isEmpty ? '' : '.$e');

    // Keep in sync with storage.rules allowed extensions.
    const allowed = <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
    };

    if (allowed.contains(normalized)) return normalized;

    // Default to jpg if missing/unknown (also allowed by rules).
    return '.jpg';
  }

  String _contentTypeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.jpeg':
      case '.jpg':
      default:
        return 'image/jpeg';
    }
  }
}

enum LeagueMediaKind {
  leagueImage,
  sponsorImage,
}
