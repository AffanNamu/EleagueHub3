import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.teamName,
    required this.authProvider,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.shareId,
    required this.quickMessagesCustom,
    required this.photoUrl,
    required this.profileImageUrl,
    required this.teamImageUrl,
    required this.isPremium,
    required this.premiumExpiresAtMs,
  });

  final String userId;
  final String teamName;
  final String authProvider;
  final int createdAtMs;
  final int updatedAtMs;
  final String shareId;
  final List<String> quickMessagesCustom;
  final String photoUrl;
  final String profileImageUrl;
  final String teamImageUrl;
  final bool isPremium;
  final int premiumExpiresAtMs;

  String get effectivePhotoUrl {
    if (profileImageUrl.trim().isNotEmpty) return profileImageUrl.trim();
    if (teamImageUrl.trim().isNotEmpty) return teamImageUrl.trim();
    return photoUrl.trim();
  }

  bool get hasShareId => shareId.trim().isNotEmpty;

  UserProfile copyWith({
    String? userId,
    String? teamName,
    String? authProvider,
    int? createdAtMs,
    int? updatedAtMs,
    String? shareId,
    List<String>? quickMessagesCustom,
    String? photoUrl,
    String? profileImageUrl,
    String? teamImageUrl,
    bool? isPremium,
    int? premiumExpiresAtMs,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      teamName: teamName ?? this.teamName,
      authProvider: authProvider ?? this.authProvider,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      shareId: shareId ?? this.shareId,
      quickMessagesCustom: quickMessagesCustom ?? this.quickMessagesCustom,
      photoUrl: photoUrl ?? this.photoUrl,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      teamImageUrl: teamImageUrl ?? this.teamImageUrl,
      isPremium: isPremium ?? this.isPremium,
      premiumExpiresAtMs: premiumExpiresAtMs ?? this.premiumExpiresAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'userId': userId,
      'teamName': teamName,
      'authProvider': authProvider,
      'createdAt': createdAtMs,
      'updatedAt': updatedAtMs,
      if (shareId.trim().isNotEmpty) 'shareId': shareId.trim(),
      if (quickMessagesCustom.isNotEmpty)
        'quickMessagesCustom': quickMessagesCustom,
      if (photoUrl.trim().isNotEmpty) 'photoUrl': photoUrl.trim(),
      if (profileImageUrl.trim().isNotEmpty)
        'profileImageUrl': profileImageUrl.trim(),
      if (teamImageUrl.trim().isNotEmpty) 'teamImageUrl': teamImageUrl.trim(),
      'isPremium': isPremium,
      'premiumExpiresAtMs': premiumExpiresAtMs,
    };
  }

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return UserProfile.fromMap(
      doc.id,
      doc.data() ?? <String, dynamic>{},
    );
  }

  factory UserProfile.fromMap(String fallbackUserId, Map<String, dynamic> map) {
    final userId = (map['userId'] as String? ?? fallbackUserId).trim();

    return UserProfile(
      userId: userId,
      teamName: (map['teamName'] as String? ?? '').trim(),
      authProvider: (map['authProvider'] as String? ?? '').trim(),
      createdAtMs: _readMs(map['createdAt']),
      updatedAtMs: _readMs(map['updatedAt']),
      shareId: (map['shareId'] as String? ?? '').trim(),
      quickMessagesCustom: _readStringList(map['quickMessagesCustom']),
      photoUrl: (map['photoUrl'] as String? ?? '').trim(),
      profileImageUrl: (map['profileImageUrl'] as String? ?? '').trim(),
      teamImageUrl: (map['teamImageUrl'] as String? ?? '').trim(),
      isPremium: map['isPremium'] == true,
      premiumExpiresAtMs: _readMs(map['premiumExpiresAtMs']),
    );
  }

  static int _readMs(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is Timestamp) return raw.toDate().millisecondsSinceEpoch;
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    return 0;
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final item in raw) {
      final value = item is String ? item.trim() : '';
      if (value.isNotEmpty) out.add(value);
    }
    return List<String>.unmodifiable(out);
  }

  static String deriveShareIdFromUid(String uid) {
    final clean = uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim();
    if (clean.isEmpty) return '';

    final base = clean.length >= 8
        ? clean.substring(0, 8)
        : clean.padRight(8, 'X');

    return 'eS$base';
  }
}
