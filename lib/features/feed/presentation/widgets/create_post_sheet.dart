// lib/features/feed/presentation/widgets/create_post_sheet.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/safe_image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/public_feed_repository.dart';

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

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final brightness = Theme.of(ctx).brightness;
      bool busy = false;
      String? error;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickImage() async {
            final result = await SafeImagePicker.pickImage();
            if (result.wasCancelled) return;
            if (!result.isSuccess) {
              setSheetState(() => error = result.errorMessage ?? 'Could not pick image.');
              return;
            }
            setSheetState(() {
              pickedImage = result.file;
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
                // Ensure file size is reasonable for audio (e.g., max 10MB)
                final file = result.files.first;
                if (file.size > 10 * 1024 * 1024) {
                   setSheetState(() => error = 'Audio file is too large. Max 10MB.');
                   return;
                }
                setSheetState(() {
                  pickedAudio = file;
                  error = null;
                });
              }
            } catch (e) {
              setSheetState(() => error = 'Could not pick audio file.');
            }
          }

          Future<void> submit() async {
            final text = textController.text.trim();
            if (text.isEmpty && pickedImage == null && pickedAudio == null) {
              setSheetState(() => error = 'Please add some text, an image, or sound.');
              return;
            }

            setSheetState(() {
              busy = true;
              error = null;
            });

            try {
              await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));

              String mediaUrl = '';
              String audioUrl = '';

              if (pickedImage != null) {
                mediaUrl = await _uploadPostMediaToCloudinary(pickedImage!, isAudio: false);
              }
              if (pickedAudio != null) {
                audioUrl = await _uploadPostMediaToCloudinary(pickedAudio!, isAudio: true);
              }

              await PublicFeedRepository().createPost(
                authorDisplayName: authorDisplayName,
                authorPhotoUrl: authorPhotoUrl,
                text: text,
                mediaUrl: mediaUrl,
                audioUrl: audioUrl,
              );

              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(true);
            } catch (e) {
              setSheetState(() {
                busy = false;
                error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
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
                      'Create Post',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visible to the whole eSportlyic community.',
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
                        hintText: "What's happening in your competitive scene?",
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

                    // Media Picker Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Image'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : pickAudio,
                            icon: const Icon(Icons.audiotrack_outlined),
                            label: const Text('Sound'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),

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
                            : const Text('Post to Feed', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
