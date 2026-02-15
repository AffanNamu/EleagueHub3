import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Uploads league media (league image / sponsor image) to Cloudinary.
///
/// Previously used Firebase Storage — now fully migrated to Cloudinary
/// unsigned upload to avoid Storage rules issues and reduce dependencies.
///
/// Storage flow:
/// 1. Pick image via FilePicker (withData: true for Android 10+ safety)
/// 2. Upload to Cloudinary → returns secure_url
/// 3. Caller persists URL to Firestore as needed
class LeagueMediaService {
  LeagueMediaService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? cloudName,
    String? unsignedUploadPreset,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _cloudName =
            (cloudName ?? const String.fromEnvironment('CLOUDINARY_CLOUD_NAME'))
                .trim(),
        _unsignedUploadPreset = (unsignedUploadPreset ??
                const String.fromEnvironment(
                    'CLOUDINARY_UNSIGNED_UPLOAD_PRESET'))
            .trim();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  final String _cloudName;
  final String _unsignedUploadPreset;

  static const int _maxBytes = 5 * 1024 * 1024;

  /// Ensures a minimal draft league doc exists so Firestore rules pass
  /// when the league hasn't been fully created yet.
  Future<void> _ensureDraftLeagueDocExists({
    required String leagueId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required to upload league media.');
    }

    try {
      final ref = _firestore.collection('leagues').doc(leagueId);
      final snap = await ref.get().timeout(const Duration(seconds: 10));

      if (snap.exists) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      await ref.set(<String, dynamic>{
        'id': leagueId,
        'organizerUid': user.uid,
        'organizerUserId': user.uid,
        'isPrivate': 1,
        'memberIds': <String>[user.uid],
        'updatedAtMs': now,
        'version': 1,
      }).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Non-fatal: if draft creation fails, the upload can still proceed
      // and the real league creation will write the full doc later.
    }
  }

  /// Picks a single image and uploads it to Cloudinary.
  ///
  /// CRITICAL ANDROID SAFETY:
  /// - Uses `withData: true` to load bytes into memory (safe for images < 5 MB)
  /// - Does NOT use `withReadStream: true` which crashes on Android 10/11
  /// - Does NOT use `File()` path access which fails on SAF-only devices
  ///
  /// Returns the Cloudinary secure_url, or null if user cancelled.
  Future<String?> pickAndUploadImage({
    required String leagueId,
    required LeagueMediaKind kind,
    String storageBucketRoot = 'leagues',
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required to upload league media.');
    }

    if (_cloudName.isEmpty || _unsignedUploadPreset.isEmpty) {
      throw StateError(
        'Cloudinary is not configured. '
        'Provide CLOUDINARY_CLOUD_NAME and CLOUDINARY_UNSIGNED_UPLOAD_PRESET '
        'via --dart-define.',
      );
    }

    // Ensure draft doc exists for Firestore rule compliance
    await _ensureDraftLeagueDocExists(leagueId: leagueId);

    // ──────────────────────────────────────────────────────────
    // PICK IMAGE
    // withData: true  → loads bytes (safe for < 5 MB images)
    // withReadStream: false → avoids Android 10/11 SAF crash
    // ──────────────────────────────────────────────────────────
    final PlatformFile picked;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
        withReadStream: false,
        lockParentWindow: false,
      );

      if (result == null || result.files.isEmpty) return null;

      picked = result.files.first;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('cancel') ||
          msg.contains('user') ||
          msg.contains('abort')) {
        return null;
      }
      throw StateError(
        'Could not open image picker. '
        'Please check app permissions in Settings.',
      );
    }

    // ──────────────────────────────────────────────────────────
    // VALIDATE
    // ──────────────────────────────────────────────────────────
    if (picked.size > _maxBytes) {
      throw StateError('Image too large. Max allowed is 5 MB.');
    }

    if (picked.size == 0) {
      throw StateError('Selected file is empty.');
    }

    // ──────────────────────────────────────────────────────────
    // BUILD MULTIPART UPLOAD
    // ──────────────────────────────────────────────────────────
    final uploadUrl =
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeLeagueId = leagueId.trim();
    final folder = 'eleaguehub/leagues/$safeLeagueId/media';
    final publicId = '${kind.name}_$ts';

    http.MultipartFile filePart;

    final bytes = picked.bytes;
    final path = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      // Primary: use in-memory bytes (most reliable on all Android versions)
      filePart = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: picked.name,
      );
    } else if (path.isNotEmpty) {
      // Fallback: use file path if bytes were somehow not loaded
      filePart = await http.MultipartFile.fromPath(
        'file',
        path,
        filename: picked.name,
      );
    } else {
      throw StateError(
        'Selected image is not accessible. '
        'Please try again or choose a different image.',
      );
    }

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = _unsignedUploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = folder
      ..fields['public_id'] = publicId
      ..fields['tags'] = 'eleaguehub,league_$safeLeagueId,${kind.name}'
      ..files.add(filePart);

    // ──────────────────────────────────────────────────────────
    // UPLOAD TO CLOUDINARY
    // ──────────────────────────────────────────────────────────
    final client = http.Client();
    try {
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 45));

      final resp = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message = 'Upload failed (HTTP ${resp.statusCode}).';
        try {
          final decoded = jsonDecode(resp.body);
          final err =
              (decoded is Map<String, dynamic>) ? decoded['error'] : null;
          final msg = (err is Map<String, dynamic>)
              ? (err['message']?.toString() ?? '')
              : '';
          if (msg.trim().isNotEmpty) message = 'Upload failed: ${msg.trim()}';
        } catch (_) {}
        throw StateError(message);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Upload failed: invalid response from server.');
      }

      final secureUrl = (decoded['secure_url']?.toString() ?? '').trim();
      if (secureUrl.isEmpty) {
        throw StateError('Upload failed: secure_url missing in response.');
      }

      return secureUrl;
    } on TimeoutException {
      throw StateError('Upload timed out. Please check your connection and try again.');
    } finally {
      client.close();
    }
  }
}

enum LeagueMediaKind {
  leagueImage,
  sponsorImage,
}
