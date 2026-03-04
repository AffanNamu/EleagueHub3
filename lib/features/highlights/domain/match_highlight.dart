import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore highlight document model.
///
/// Collection path (required):
/// matches/{matchId}/highlights/{highlightId}
///
/// Firestore fields (required by spec):
/// - matchId
/// - leagueId
/// - teamId
/// - uploadedBy
/// - cloudinaryPublicId
/// - secureUrl
/// - thumbnailUrl
/// - duration
/// - size
/// - format
/// - status (UPLOADING | PROCESSING | APPROVED)
/// - createdAt (timestamp)
/// - updatedAt (timestamp)
class MatchHighlight {
  static const String statusUploading = 'UPLOADING';
  static const String statusProcessing = 'PROCESSING';
  static const String statusApproved = 'APPROVED';

  final String id;

  final String matchId;
  final String leagueId;
  final String teamId;

  final String uploadedBy;

  /// Must follow your folder policy:
  /// match_highlights/{leagueId}/{matchId}/{teamId}/{highlightId}
  final String cloudinaryPublicId;

  final String secureUrl;
  final String thumbnailUrl;

  final double duration;
  final int size;
  final String format;

  final String status;

  final Timestamp? createdAt;
  final Timestamp? updatedAt;

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

  bool get isUploading => status == statusUploading;
  bool get isProcessing => status == statusProcessing;
  bool get isApproved => status == statusApproved;

  static double _doubleFrom(dynamic v, {double fallback = 0}) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static int _intFrom(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static String _stringFrom(dynamic v) {
    if (v is String) return v.trim();
    return (v ?? '').toString().trim();
  }

  static Timestamp? _timestampFrom(dynamic v) {
    if (v is Timestamp) return v;
    return null;
  }

  factory MatchHighlight.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return MatchHighlight(
      id: doc.id,
      matchId: _stringFrom(data['matchId']),
      leagueId: _stringFrom(data['leagueId']),
      teamId: _stringFrom(data['teamId']),
      uploadedBy: _stringFrom(data['uploadedBy']),
      cloudinaryPublicId: _stringFrom(data['cloudinaryPublicId']),
      secureUrl: _stringFrom(data['secureUrl']),
      thumbnailUrl: _stringFrom(data['thumbnailUrl']),
      duration: _doubleFrom(data['duration'], fallback: 0),
      size: _intFrom(data['size'], fallback: 0),
      format: _stringFrom(data['format']),
      status: _stringFrom(data['status']).isEmpty ? statusUploading : _stringFrom(data['status']),
      createdAt: _timestampFrom(data['createdAt']),
      updatedAt: _timestampFrom(data['updatedAt']),
    );
  }

  /// Firestore map writer.
  ///
  /// IMPORTANT:
  /// - This intentionally omits null timestamp fields to work cleanly with:
  ///   - `FieldValue.serverTimestamp()` writes from repositories, OR
  ///   - absent fields on create (rules allow optional timestamps).
  /// - If you include null timestamps, ordering by createdAt is still possible but less reliable.
  Map<String, dynamic> toFirestoreMap() {
    final map = <String, dynamic>{
      // Optional but allowed by rules (keeps some tooling simpler).
      'id': id,

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
    };

    if (createdAt != null) map['createdAt'] = createdAt;
    if (updatedAt != null) map['updatedAt'] = updatedAt;

    return map;
  }
}
