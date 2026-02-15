import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/safe_image_picker.dart';

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

  Future<void> _ensureDraftLeagueDocExists({required String leagueId}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign-in required to upload league media.');

    try {
      final ref = _firestore.collection('leagues').doc(leagueId);
      final snap = await ref.get().timeout(const Duration(seconds: 10));
      if (snap.exists) return;

      await ref.set(<String, dynamic>{
        'id': leagueId,
        'organizerUid': user.uid,
        'organizerUserId': user.uid,
        'isPrivate': 1,
        'memberIds': <String>[user.uid],
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'version': 1,
      }).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<String?> pickAndUploadImage({
    required String leagueId,
    required LeagueMediaKind kind,
    String storageBucketRoot = 'leagues',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign-in required to upload league media.');

    if (_cloudName.isEmpty || _unsignedUploadPreset.isEmpty) {
      throw StateError(
        'Cloudinary is not configured. '
        'Provide CLOUDINARY_CLOUD_NAME and CLOUDINARY_UNSIGNED_UPLOAD_PRESET via --dart-define.',
      );
    }

    await _ensureDraftLeagueDocExists(leagueId: leagueId);

    final pickResult = await SafeImagePicker.pickImage();

    if (pickResult.wasCancelled) return null;

    if (!pickResult.isSuccess) {
      throw StateError(pickResult.errorMessage ?? 'Could not pick image.');
    }

    final picked = pickResult.file!;

    final uploadUrl =
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeLeagueId = leagueId.trim();

    http.MultipartFile filePart;

    final bytes = picked.bytes;
    final path = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      filePart = http.MultipartFile.fromBytes('file', bytes, filename: picked.name);
    } else if (path.isNotEmpty) {
      filePart = await http.MultipartFile.fromPath('file', path, filename: picked.name);
    } else {
      throw StateError('Selected image is not accessible. Please try a different image.');
    }

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = _unsignedUploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = 'eleaguehub/leagues/$safeLeagueId/media'
      ..fields['public_id'] = '${kind.name}_$ts'
      ..fields['tags'] = 'eleaguehub,league_$safeLeagueId,${kind.name}'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed =
          await client.send(req).timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message = 'Upload failed (HTTP ${resp.statusCode}).';
        try {
          final decoded = jsonDecode(resp.body);
          final err = (decoded is Map<String, dynamic>) ? decoded['error'] : null;
          final msg = (err is Map<String, dynamic>)
              ? (err['message']?.toString() ?? '')
              : '';
          if (msg.trim().isNotEmpty) message = 'Upload failed: ${msg.trim()}';
        } catch (_) {}
        throw StateError(message);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Upload failed: invalid response.');
      }

      final secureUrl = (decoded['secure_url']?.toString() ?? '').trim();
      if (secureUrl.isEmpty) {
        throw StateError('Upload failed: secure_url missing.');
      }

      return secureUrl;
    } on TimeoutException {
      throw StateError('Upload timed out. Please try again.');
    } finally {
      client.close();
    }
  }
}

enum LeagueMediaKind {
  leagueImage,
  sponsorImage,
}
