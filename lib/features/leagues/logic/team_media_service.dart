import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Uploads and manages Team images using Cloudinary (unsigned upload preset).
///
/// Storage:
/// - Upload to Cloudinary -> returns secure_url
/// - Persist to Firestore: leagues/{leagueId}/teams/{teamId}.teamImageUrl
///
/// NOTE:
/// Firestore rules must allow write to /leagues/{leagueId}/teams/{teamId} for league owner.
class TeamMediaService {
  TeamMediaService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? cloudName,
    String? unsignedUploadPreset,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _cloudName = (cloudName ?? const String.fromEnvironment('CLOUDINARY_CLOUD_NAME')).trim(),
        _unsignedUploadPreset =
            (unsignedUploadPreset ?? const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET')).trim();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  final String _cloudName;
  final String _unsignedUploadPreset;

  static const int _maxBytes = 5 * 1024 * 1024;

  Future<PlatformFile?> pickImage() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required.');
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      withReadStream: true,
      lockParentWindow: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;
    if (picked.size > _maxBytes) {
      throw StateError('Image too large. Max allowed is 5 MB.');
    }

    return picked;
  }

  /// Uploads the provided picked image to Cloudinary and returns `secure_url`.
  Future<String> uploadPickedToCloudinary({
    required String leagueId,
    required String teamId,
    required PlatformFile picked,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required.');
    }

    if (_cloudName.isEmpty || _unsignedUploadPreset.isEmpty) {
      throw StateError(
        'Cloudinary is not configured. Provide CLOUDINARY_CLOUD_NAME and CLOUDINARY_UNSIGNED_UPLOAD_PRESET.',
      );
    }

    final uploadUrl = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

    final ts = DateTime.now().millisecondsSinceEpoch;

    http.MultipartFile filePart;
    final path = (picked.path ?? '').trim();

    if (path.isNotEmpty) {
      filePart = await http.MultipartFile.fromPath(
        'file',
        path,
        filename: picked.name,
      );
    } else if (picked.readStream != null) {
      filePart = http.MultipartFile(
        'file',
        picked.readStream!,
        picked.size,
        filename: picked.name,
      );
    } else {
      throw StateError('Selected image file is not accessible.');
    }

    final safeLeagueId = leagueId.trim();
    final safeTeamId = teamId.trim();

    final folder = 'eleaguehub/leagues/$safeLeagueId/teams/$safeTeamId';
    final publicId = 'team_${safeTeamId}_$ts';

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = _unsignedUploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = folder
      ..fields['public_id'] = publicId
      ..fields['tags'] = 'eleaguehub,league_$safeLeagueId,team_$safeTeamId'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed = await client.send(req).timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 40));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message = 'Upload failed (HTTP ${resp.statusCode}).';
        try {
          final decoded = jsonDecode(resp.body);
          final err = (decoded is Map<String, dynamic>) ? decoded['error'] : null;
          final msg = (err is Map<String, dynamic>) ? (err['message']?.toString() ?? '') : '';
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

  /// Pick -> upload -> persist to Firestore. Returns secure_url, or null if user canceled.
  Future<String?> pickUploadAndSaveTeamImage({
    required String leagueId,
    required String teamId,
    String? teamName,
  }) async {
    final picked = await pickImage();
    if (picked == null) return null;

    final url = await uploadPickedToCloudinary(
      leagueId: leagueId,
      teamId: teamId,
      picked: picked,
    );

    await saveTeamImageUrl(
      leagueId: leagueId,
      teamId: teamId,
      teamName: teamName,
      teamImageUrl: url,
    );

    return url;
  }

  /// Pick -> upload ONLY (no Firestore write). Returns secure_url, or null if user canceled.
  Future<String?> pickAndUploadOnly({
    required String leagueId,
    required String teamId,
  }) async {
    final picked = await pickImage();
    if (picked == null) return null;

    return uploadPickedToCloudinary(
      leagueId: leagueId,
      teamId: teamId,
      picked: picked,
    );
  }

  Future<void> saveTeamImageUrl({
    required String leagueId,
    required String teamId,
    required String teamImageUrl,
    String? teamName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await _firestore
        .collection('leagues')
        .doc(leagueId.trim())
        .collection('teams')
        .doc(teamId.trim())
        .set(
          <String, dynamic>{
            'id': teamId.trim(),
            'leagueId': leagueId.trim(),
            if (teamName != null && teamName.trim().isNotEmpty) 'name': teamName.trim(),
            'teamImageUrl': teamImageUrl.trim(),
            'updatedAtMs': now,
            'version': FieldValue.increment(1),
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<void> clearTeamImage({
    required String leagueId,
    required String teamId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign-in required.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await _firestore
        .collection('leagues')
        .doc(leagueId.trim())
        .collection('teams')
        .doc(teamId.trim())
        .set(
          <String, dynamic>{
            'teamImageUrl': '',
            'updatedAtMs': now,
            'version': FieldValue.increment(1),
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));
  }
}
