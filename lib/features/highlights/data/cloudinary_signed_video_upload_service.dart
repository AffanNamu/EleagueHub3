import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Result of a Cloudinary video upload.
/// Fields chosen to populate Firestore highlight metadata.
class CloudinaryVideoUploadResult {
  final String publicId;
  final String secureUrl;
  final String format;
  final int bytes;
  final double duration;

  const CloudinaryVideoUploadResult({
    required this.publicId,
    required this.secureUrl,
    required this.format,
    required this.bytes,
    required this.duration,
  });
}

/// Signed Cloudinary video uploader with progress support.
///
/// WHY SIGNED UPLOAD (preferred):
/// - Prevents abuse: clients cannot upload arbitrary assets without a server signature.
/// - NEVER embed Cloudinary API secret in the app.
/// - Signature must be generated server-side (Cloudflare Worker / Firebase Function / tiny endpoint).
///
/// EXPECTED SIGN ENDPOINT CONTRACT (recommended):
/// POST {signEndpoint}
/// body: { "params": { "timestamp": 123, "folder": "...", "public_id": "...", "overwrite": true } }
/// response JSON:
/// {
///   "cloudName": "xxx",
///   "apiKey": "12345",
///   "timestamp": 1710000000,
///   "signature": "sha1sig"
/// }
///
/// SECURITY COMMENT:
/// - The signer must authenticate the user (Firebase ID token) and verify:
///   - user is a league member
///   - match is finished
///   - user team participated
///   - rate limits (per uid/team/match) to protect free tier
/// - Then it returns the signature for ONLY the allowed folder/public_id.
class CloudinarySignedVideoUploadService {
  CloudinarySignedVideoUploadService({
    Dio? dio,
    String? cloudName,
    String? apiKey,
    String? signEndpoint,
  })  : _dio = dio ?? Dio(),
        _cloudName = (cloudName ?? const String.fromEnvironment('CLOUDINARY_CLOUD_NAME')).trim(),
        _apiKey = (apiKey ?? const String.fromEnvironment('CLOUDINARY_API_KEY')).trim(),
        _signEndpoint = (signEndpoint ?? const String.fromEnvironment('CLOUDINARY_SIGN_ENDPOINT')).trim();

  final Dio _dio;
  final String _cloudName;
  final String _apiKey;
  final String _signEndpoint;

  void _requireConfigured() {
    if (_cloudName.isEmpty) {
      throw StateError('Cloudinary cloud name missing (CLOUDINARY_CLOUD_NAME).');
    }
    if (_apiKey.isEmpty) {
      throw StateError('Cloudinary api key missing (CLOUDINARY_API_KEY).');
    }
    if (_signEndpoint.isEmpty) {
      throw StateError('Cloudinary sign endpoint missing (CLOUDINARY_SIGN_ENDPOINT).');
    }
  }

  Future<Map<String, dynamic>> _signParams({
    required Map<String, dynamic> params,
  }) async {
    _requireConfigured();

    // Keep signer request small and explicit.
    final payload = <String, dynamic>{
      'params': params,
    };

    final res = await _dio
        .post<dynamic>(
          _signEndpoint,
          data: jsonEncode(payload),
          options: Options(
            headers: const <String, String>{
              'content-type': 'application/json',
            },
            responseType: ResponseType.json,
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 12),
          ),
        )
        .timeout(const Duration(seconds: 15));

    final data = res.data;
    if (data is! Map) throw StateError('Invalid sign response.');
    final map = data.cast<String, dynamic>();

    final signature = (map['signature'] as String? ?? '').trim();
    final timestamp = map['timestamp'];
    final ts = (timestamp is int)
        ? timestamp
        : (timestamp is num)
            ? timestamp.toInt()
            : int.tryParse((timestamp ?? '').toString().trim());

    if (signature.isEmpty || ts == null || ts <= 0) {
      throw StateError('Invalid sign response: missing signature/timestamp.');
    }

    // Allow signer to override apiKey/cloudName (useful for multi-env),
    // but default to local env.
    return <String, dynamic>{
      'cloudName': (map['cloudName'] as String?)?.trim().isNotEmpty == true ? (map['cloudName'] as String).trim() : _cloudName,
      'apiKey': (map['apiKey'] as String?)?.trim().isNotEmpty == true ? (map['apiKey'] as String).trim() : _apiKey,
      'timestamp': ts,
      'signature': signature,
    };
  }

  /// Uploads a policy-compliant file (already compressed & validated).
  ///
  /// Inputs:
  /// - [filePath] must point to the compressed MP4 (<=15MB, <=720p, <=3min).
  /// - [folder] must follow: match_highlights/{leagueId}/{matchId}/{teamId}
  /// - [publicId] should be stable (e.g. highlightId) to prevent duplicates.
  ///
  /// Cost controls:
  /// - No eager transformations
  /// - No streaming_profile
  /// - No multi-format conversions
  Future<CloudinaryVideoUploadResult> uploadHighlightVideo({
    required String filePath,
    required String folder,
    required String publicId,
    void Function(int sentBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
  }) async {
    _requireConfigured();

    final p = filePath.trim();
    if (p.isEmpty) throw StateError('Video path is empty.');

    final f = File(p);
    if (!await f.exists()) throw StateError('Video file not found.');

    final folderSafe = folder.trim();
    if (folderSafe.isEmpty) throw StateError('Upload folder is required.');

    final pid = publicId.trim();
    if (pid.isEmpty) throw StateError('publicId is required.');

    final bytes = await f.length();
    if (bytes <= 0) throw StateError('Video file is empty.');

    // Parameters that MUST be included in signature if used.
    // Keep minimal to reduce risk of signer mismatch.
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor();

    final paramsToSign = <String, dynamic>{
      'timestamp': timestamp,
      'folder': folderSafe,
      'public_id': pid,
      'overwrite': true,
    };

    final signed = await _signParams(params: paramsToSign);
    final cloudName = signed['cloudName'] as String;
    final apiKey = signed['apiKey'] as String;
    final ts = signed['timestamp'] as int;
    final signature = signed['signature'] as String;

    final form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(
        p,
        filename: '${pid.isEmpty ? 'highlight' : pid}.mp4',
        // We intentionally omit contentType to avoid extra deps and because Cloudinary accepts it.
      ),

      // Required signed upload fields
      'api_key': apiKey,
      'timestamp': ts,
      'signature': signature,

      // Upload placement (folder structure requirement)
      'folder': folderSafe,
      'public_id': pid,

      // Abuse/dedup controls
      'overwrite': 'true',
      'unique_filename': 'false',
      'use_filename': 'false',

      // Cost controls: do NOT add eager/streaming_profile/transformations.
    });

    final uploadUrl = 'https://api.cloudinary.com/v1_1/$cloudName/video/upload';

    try {
      final res = await _dio.post<dynamic>(
        uploadUrl,
        data: form,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) onProgress(sent, total);
        },
      );

      final data = res.data;
      if (data is! Map) throw StateError('Invalid Cloudinary response.');
      final map = data.cast<String, dynamic>();

      final secureUrl = (map['secure_url'] as String? ?? '').trim();
      final publicIdOut = (map['public_id'] as String? ?? '').trim();
      final format = (map['format'] as String? ?? '').trim();
      final bytesOut = (map['bytes'] as num?)?.toInt() ?? 0;
      final durationOut = (map['duration'] as num?)?.toDouble() ?? 0.0;

      if (secureUrl.isEmpty || publicIdOut.isEmpty) {
        throw StateError('Upload failed: missing secure_url/public_id.');
      }

      return CloudinaryVideoUploadResult(
        publicId: publicIdOut,
        secureUrl: secureUrl,
        format: format,
        bytes: bytesOut > 0 ? bytesOut : bytes,
        duration: durationOut,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw StateError('Upload cancelled.');
      }

      final code = e.response?.statusCode;
      String hint = '';

      final data = e.response?.data;
      if (data is Map) {
        final err = data['error'];
        if (err is Map) {
          hint = (err['message'] ?? '').toString();
        } else {
          hint = err?.toString() ?? '';
        }
      }

      hint = hint.trim().isNotEmpty ? hint.trim() : (e.message ?? 'Upload failed');
      throw StateError(code != null ? 'Upload failed ($code): $hint' : 'Upload failed: $hint');
    } on TimeoutException {
      throw StateError('Upload timed out. Please try again.');
    }
  }

  /// Thumbnail URL builder that keeps transformations minimal.
  ///
  /// WARNING ABOUT COST:
  /// Cloudinary will typically create a derived asset the first time this URL is requested.
  /// Keep it small (w_480) and avoid preloading too many thumbnails to stay free-tier safe.
  static String buildLightweightThumbnailUrl({
    required String secureVideoUrl,
    int width = 480,
    int second = 0,
  }) {
    final u = secureVideoUrl.trim();
    if (u.isEmpty) return '';

    // Works only for Cloudinary URLs with /video/upload/
    const marker = '/video/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return '';

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final so = second < 0 ? 0 : second;
    final transforms = 'so_$so,f_jpg,q_auto,w_$width';

    // Replace extension with .jpg if present, otherwise append .jpg.
    final fixedSuffix = suffix.contains('.')
        ? suffix.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.jpg')
        : '$suffix.jpg';

    return '$prefix$transforms/$fixedSuffix';
  }
}
