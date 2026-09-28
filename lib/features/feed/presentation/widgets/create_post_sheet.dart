// lib/features/feed/presentation/widgets/create_post_sheet.dart
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/locale/app_localizations.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/safe_image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../highlights/data/video_compression_service.dart';
import '../../data/public_feed_repository.dart';

/// Raw video picks larger than this are rejected before we spend time
/// compressing them -- avoids the UI hanging on a multi-minute local
/// transcode for a clip nobody meant to post to the feed.
const int _maxRawPickedVideoBytes = 300 * 1024 * 1024;

Future<String> _uploadPostVideoToCloudinary(String filePath) async {
  final cloudName = const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
  final uploadPreset =
      const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET').trim();
  if (cloudName.isEmpty || uploadPreset.isEmpty) {
    throw StateError('Cloudinary is not configured.');
  }

  final uploadUrl = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/video/upload');
  final ts = DateTime.now().millisecondsSinceEpoch;

  final req = http.MultipartRequest('POST', uploadUrl)
    ..fields['upload_preset'] = uploadPreset
    ..fields['resource_type'] = 'video'
    ..fields['folder'] = 'eleaguehub/public_posts'
    ..fields['public_id'] = 'post_video_$ts'
    ..files.add(await http.MultipartFile.fromPath('file', filePath));

  final client = http.Client();
  try {
    final streamed = await client.send(req).timeout(const Duration(seconds: 90));
    final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 90));

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
    if (secureUrl.isEmpty) throw StateError('Upload failed: secure_url missing.');
    return secureUrl;
  } finally {
    client.close();
  }
}

/// Compresses [picked] with the same engine/policy used for match
/// highlights (90s / 20MB cap -- plenty for a feed clip), uploads the
/// compressed output, then cleans up the local temp file either way.
Future<String> _compressAndUploadPostVideo(PlatformFile picked) async {
  final path = (picked.path ?? '').trim();
  if (path.isEmpty) throw StateError('Selected video is not accessible.');

  final compressed = await VideoCompressionService().compressHighlight(inputPath: path);
  try {
    return await _uploadPostVideoToCloudinary(compressed.outputPath);
  } finally {
    try {
      final f = File(compressed.outputPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

Future<String> _uploadPostMediaToCloudinary(PlatformFile picked, {required bool isAudio}) async {
  final cloudName = const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
  final uploadPreset =
      const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET').trim();
  if (cloudName.isEmpty || uploadPreset.isEmpty) {
    throw StateError('Cloudinary is not configured.');
  }

  final uploadUrl = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/${isAudio ? 'video' : 'image'}/upload');
  final ts = DateTime.now().millisecondsSinceEpoch;

  http.MultipartFile filePart;
  final bytes = picked.bytes;
  final path = (picked.path ?? '').trim();

  if (bytes != null && bytes.isNotEmpty) {
    filePart = http.MultipartFile.fromBytes('file', bytes, filename: picked.name);
  } else if (path.isNotEmpty) {
    filePart = await http.MultipartFile.fromPath('file', path, filename: picked.name);
  } else {
    throw StateError('Selected file is not accessible.');
  }

  final req = http.MultipartRequest('POST', uploadUrl)
    ..fields['upload_preset'] = uploadPreset
    ..fields['resource_type'] = isAudio ? 'video' : 'image' // Cloudinary uses 'video' for audio files
    ..fields['folder'] = 'eleaguehub/public_posts'
    ..fields['public_id'] = 'post_${isAudio ? 'audio' : 'image'}_$ts'
    ..files.add(filePart);

  final client = http.Client();
  try {
    final streamed = await client.send(req).timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 60));

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
    if (secureUrl.isEmpty) throw StateError('Upload failed: secure_url missing.');
    return secureUrl;
  } finally {
    client.close();
  }
}

/// Shows the "create post" bottom sheet used by the "+" button in the
/// Public Feed. Handles optional image and optional audio uploads.
Future<bool?> showCreatePostSheet(
  BuildContext context, {
  required String authorDisplayName,
  required String authorPhotoUrl,
}) {
  final textController = TextEditingController();
  PlatformFile? pickedImage;
  PlatformFile? pickedAudio;
  PlatformFile? pickedVideo;
  final l10n = context.l10n;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final brightness = Theme.of(ctx).brightness;
      bool busy = false;
      String? busyStatus;
      String? error;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickImage() async {
            final result = await SafeImagePicker.pickImage();
            if (result.wasCancelled) return;
            if (!result.isSuccess) {
              setSheetState(() => error = result.errorMessage ?? l10n.tr('create_post_pick_image_failed'));
              return;
            }
            setSheetState(() {
              pickedImage = result.file;
              pickedVideo = null;
              error = null;
            });
          }

          Future<void> pickAudio() async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.audio,
                withData: true,
              );
              if (result != null && result.files.isNotEmpty) {
                // Ensure file size is reasonable for audio (max 5MB)
                final file = result.files.first;
                if (file.size > 5 * 1024 * 1024) {
                   setSheetState(() => error = l10n.tr('create_post_audio_too_large'));
                   return;
                }
                setSheetState(() {
                  pickedAudio = file;
                  pickedVideo = null;
                  error = null;
                });
              }
            } catch (e) {
              setSheetState(() => error = l10n.tr('create_post_pick_audio_failed'));
            }
          }

          Future<void> pickVideo() async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.video,
                withData: false,
              );
              if (result == null || result.files.isEmpty) return;
              final file = result.files.first;
              if ((file.path ?? '').trim().isEmpty) {
                setSheetState(() => error = l10n.tr('create_post_pick_video_failed'));
                return;
              }
              if (file.size > _maxRawPickedVideoBytes) {
                setSheetState(() => error = l10n.tr('create_post_video_too_large'));
                return;
              }
              setSheetState(() {
                pickedVideo = file;
                pickedImage = null;
                pickedAudio = null;
                error = null;
              });
            } catch (e) {
              setSheetState(() => error = l10n.tr('create_post_pick_video_failed'));
            }
          }

          Future<void> submit() async {
            final text = textController.text.trim();
            if (text.isEmpty && pickedImage == null && pickedAudio == null && pickedVideo == null) {
              setSheetState(() => error = l10n.tr('create_post_empty_error'));
              return;
            }

            setSheetState(() {
              busy = true;
              busyStatus = null;
              error = null;
            });

            try {
              await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));

              String mediaUrl = '';
              String mediaType = '';
              String audioUrl = '';

              if (pickedVideo != null) {
                setSheetState(() => busyStatus = l10n.tr('create_post_video_processing'));
                mediaUrl = await _compressAndUploadPostVideo(pickedVideo!);
                mediaType = 'video';
              } else {
                if (pickedImage != null) {
                  mediaUrl = await _uploadPostMediaToCloudinary(pickedImage!, isAudio: false);
                  mediaType = 'image';
                }
                if (pickedAudio != null) {
                  audioUrl = await _uploadPostMediaToCloudinary(pickedAudio!, isAudio: true);
                }
              }

              await PublicFeedRepository().createPost(
                authorDisplayName: authorDisplayName,
                authorPhotoUrl: authorPhotoUrl,
                text: text,
                mediaUrl: mediaUrl,
                mediaType: mediaType,
                audioUrl: audioUrl,
              );

              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(true);
            } catch (e) {
              setSheetState(() {
                busy = false;
                busyStatus = null;
                error = e is StateError
                    ? e.message
                    : UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(brightness),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.cardBorder(brightness)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('create_post_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('create_post_subtitle'),
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: textController,
                      maxLength: 2000,
                      maxLines: 4,
                      enabled: !busy,
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.tr('create_post_hint'),
                        hintStyle: TextStyle(color: AppTheme.secondaryText(brightness)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppTheme.cardBorder(brightness)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppTheme.cardBorder(brightness)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Media Previews
                    if (pickedImage != null)
                      Container(
                        height: 120,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          image: DecorationImage(
                            image: MemoryImage(pickedImage!.bytes!),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.white),
                            onPressed: busy ? null : () => setSheetState(() => pickedImage = null),
                          ),
                        ),
                      ),

                    if (pickedAudio != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.limeAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.limeAccentDark.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note, color: AppTheme.limeAccentDark),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pickedAudio!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              color: AppTheme.secondaryText(brightness),
                              onPressed: busy ? null : () => setSheetState(() => pickedAudio = null),
                            )
                          ],
                        ),
                      ),

                    if (pickedVideo != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.limeAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.limeAccentDark.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.videocam_rounded, color: AppTheme.limeAccentDark),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pickedVideo!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              color: AppTheme.secondaryText(brightness),
                              onPressed: busy ? null : () => setSheetState(() => pickedVideo = null),
                            )
                          ],
                        ),
                      ),

                    // Media Picker Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(l10n.tr('create_post_image_button')),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : pickVideo,
                            icon: const Icon(Icons.videocam_outlined),
                            label: Text(l10n.tr('create_post_video_button')),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : pickAudio,
                            icon: const Icon(Icons.audiotrack_outlined),
                            label: Text(l10n.tr('create_post_sound_button')),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (busy && (busyStatus ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        busyStatus!.trim(),
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.darkText),
                              )
                            : Text(l10n.tr('create_post_submit_button'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() => textController.dispose());
}
