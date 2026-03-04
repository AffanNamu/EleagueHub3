import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore document stored at:
/// matches/{matchId}/highlights/{highlightId}
///
/// IMPORTANT:
/// - Firestore stores metadata only (Cloudinary stores the video).
/// - Keep fields aligned with security rules and UI requirements.
///
/// Status values:
/// - UPLOADING: client created doc optimistically and is uploading bytes
/// - PROCESSING: Cloudinary upload finished; awaiting moderation/approval
/// - APPROVED: moderator/organizer approved for public viewing
class MatchHighlight {
  final String id;

  final String matchId;
  final String leagueId;
  final String teamId;
  final String uploadedBy;

  final String cloudinaryPublicId;
  final String secureUrl;
  final String thumbnailUrl;

  /// Duration in seconds (from Cloudinary response).
  final double duration;

  /// Bytes (from Cloudinary response).
  final int size;

  final String format;

  final String status;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MatchHighlight({
    required this.id,
    required this.matchId,
    required this.leagueId,
    required this.teamId,
    required this.uploadedBy,
    required this.cloudinaryPublicId,
    required this.secureUrl,
    required this.thumbnailUrl,
    required this.duration,
    required this.size,
    required this.format,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  static const statusUploading = 'UPLOADING';
  static const statusProcessing = 'PROCESSING';
  static const statusApproved = 'APPROVED';

  bool get isUploading => status == statusUploading;
  bool get isApproved => status == statusApproved;

  Map<String, dynamic> toFirestoreMap() => <String, dynamic>{
        'matchId': matchId,
        'leagueId': leagueId,
        'teamId': teamId,
        'uploadedBy': uploadedBy,
        'cloudinaryPublicId': cloudinaryPublicId,
        'secureUrl': secureUrl,
        'thumbnailUrl': thumbnailUrl,
        'duration': duration,
        'size': size,
        'format': format,
        'status': status,
        'createdAt': createdAt == null ? FieldValue.serverTimestamp() : createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static MatchHighlight fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    DateTime? toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    double toDouble(dynamic v) {
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? 0;
      return 0;
    }

    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
      return 0;
    }

    return MatchHighlight(
      id: doc.id,
      matchId: (data['matchId'] as String?) ?? '',
      leagueId: (data['leagueId'] as String?) ?? '',
      teamId: (data['teamId'] as String?) ?? '',
      uploadedBy: (data['uploadedBy'] as String?) ?? '',
      cloudinaryPublicId: (data['cloudinaryPublicId'] as String?) ?? '',
      secureUrl: (data['secureUrl'] as String?) ?? '',
      thumbnailUrl: (data['thumbnailUrl'] as String?) ?? '',
      duration: toDouble(data['duration']),
      size: toInt(data['size']),
      format: (data['format'] as String?) ?? '',
      status: (data['status'] as String?) ?? statusUploading,
      createdAt: toDate(data['createdAt']),
      updatedAt: toDate(data['updatedAt']),
    );
  }
}

/// SECURITY RULES EXAMPLE (place into firestore.rules; adapt to your existing rules):
///
/// match /matches/{matchId} {
///   allow read: if true; // or league-member only, your choice
///
///   match /highlights/{highlightId} {
///     allow read: if true; // or league-member only
///
///     // CREATE: only authenticated users who are league members
///     // and their membership.teamId matches the highlight.teamId
///     allow create: if request.auth != null
///       && request.resource.data.uploadedBy == request.auth.uid
///       && request.resource.data.matchId == matchId
///       && request.resource.data.status in ['UPLOADING','PROCESSING']
///       && exists(/databases/$(database)/documents/leagues/$(request.resource.data.leagueId)/memberships/$(request.auth.uid))
///       && get(/databases/$(database)/documents/leagues/$(request.resource.data.leagueId)/memberships/$(request.auth.uid)).data.teamId == request.resource.data.teamId;
///
///     // UPDATE: only uploader can update their own doc while not approved
///     allow update: if request.auth != null
///       && resource.data.uploadedBy == request.auth.uid
///       && resource.data.status != 'APPROVED';
///
///     // DELETE: optionally uploader can delete before approval
///     allow delete: if request.auth != null
///       && resource.data.uploadedBy == request.auth.uid
///       && resource.data.status != 'APPROVED';
///   }
/// }
