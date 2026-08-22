// lib/features/status/presentation/widgets/create_status_sheet.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/safe_image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/status_repository.dart';

Future<String> _uploadStatusImageToCloudinary(PlatformFile picked) async {
  final cloudName = const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
  final uploadPreset =
      const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET').trim();
  if (cloudName.isEmpty || uploadPreset.isEmpty) {
    throw StateError('Cloudinary is not configured.');
  }

  final uploadUrl = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
  final ts = DateTime.now().millisecondsSinceEpoch;

  http.MultipartFile filePart;
  final bytes = picked.bytes;
  final path = (picked.path ?? '').trim();

  if (bytes != null && bytes.isNotEmpty) {
    filePart = http.MultipartFile.fromBytes('file', bytes, filename: picked.name);
  } else if (path.isNotEmpty) {
    filePart = await http.MultipartFile.fromPath('file', path, filename: picked.name);
  } else {
    throw StateError('Selected image is not accessible.');
  }

  final req = http.MultipartRequest('POST', uploadUrl)
    ..fields['upload_preset'] = uploadPreset
    ..fields['resource_type'] = 'image'
    ..fields['folder'] = 'eleaguehub/statuses'
    ..fields['public_id'] = 'status_$ts'
    ..files.add(filePart);

  final client = http.Client();
  try {
    final streamed = await client.send(req).timeout(const Duration(seconds: 45));
    final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 45));

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

/// Shows the "create status" bottom sheet. Handles image picking,
/// Cloudinary upload, and writing the status via [StatusRepository].
/// Returns true if a status was successfully posted.
///
/// The caller should only offer this to users it already believes are
/// eligible (Pro/Elite) — but the real enforcement is the Firestore
/// rule regardless of what the UI shows.
Future<bool?> showCreateStatusSheet(BuildContext context) {
  final captionController = TextEditingController();
  PlatformFile? picked;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
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
              picked = result.file;
              error = null;
            });
          }

          Future<void> submit() async {
            if (picked == null) {
              setSheetState(() => error = 'Please select an image first.');
              return;
            }
            setSheetState(() {
              busy = true;
              error = null;
            });
            try {
              await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));
              final url = await _uploadStatusImageToCloudinary(picked!);
              await StatusRepository().createStatus(
                imageUrl: url,
                caption: captionController.text,
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Status',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visible to everyone for 24 hours.',
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: busy ? null : pickImage,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: AppTheme.searchBackground(brightness),
                          border: Border.all(color: AppTheme.searchOutline(brightness)),
                        ),
                        child: picked == null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined,
                                        color: AppTheme.secondaryText(brightness), size: 30),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Tap to select image',
                                      style: TextStyle(
                                        color: AppTheme.secondaryText(brightness),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: (picked!.bytes != null)
                                    ? Image.memory(picked!.bytes!, fit: BoxFit.cover, width: double.infinity)
                                    : Center(
                                        child: Text(
                                          picked!.name,
                                          style: TextStyle(color: AppTheme.primaryText(brightness)),
                                        ),
                                      ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: captionController,
                      maxLength: 200,
                      maxLines: 2,
                      enabled: !busy,
                      decoration: const InputDecoration(hintText: 'Add a caption (optional)'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkText),
                              )
                            : const Text('Post Status', style: TextStyle(fontWeight: FontWeight.w900)),
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
  ).whenComplete(() => captionController.dispose());
}
