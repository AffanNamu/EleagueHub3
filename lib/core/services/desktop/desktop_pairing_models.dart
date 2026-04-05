class DesktopPairingSession {
  final String sessionId;
  final String sessionSecret;
  final String qrPayload;
  final String status;
  final int createdAtMs;
  final int expiresAtMs;

  const DesktopPairingSession({
    required this.sessionId,
    required this.sessionSecret,
    required this.qrPayload,
    required this.status,
    required this.createdAtMs,
    required this.expiresAtMs,
  });

  factory DesktopPairingSession.fromMap(Map<String, dynamic> map) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
      return 0;
    }

    String toStr(dynamic v) => (v ?? '').toString().trim();

    return DesktopPairingSession(
      sessionId: toStr(map['sessionId']).isNotEmpty
          ? toStr(map['sessionId'])
          : toStr(map['session_id']),
      sessionSecret: toStr(map['sessionSecret']).isNotEmpty
          ? toStr(map['sessionSecret'])
          : toStr(map['session_secret']),
      qrPayload: toStr(map['qrPayload']).isNotEmpty
          ? toStr(map['qrPayload'])
          : toStr(map['qr_payload']),
      status: toStr(map['status']).isNotEmpty ? toStr(map['status']) : 'pending',
      createdAtMs: toInt(map['createdAtMs'] ?? map['created_at_ms']),
      expiresAtMs: toInt(map['expiresAtMs'] ?? map['expires_at_ms']),
    );
  }
}

class DesktopPairingApprovalResult {
  final bool success;
  final String message;
  final String status;
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;

  const DesktopPairingApprovalResult({
    required this.success,
    required this.message,
    required this.status,
    this.pairedUserUid = '',
    this.pairedUserName = '',
    this.pairedUserEmail = '',
  });

  factory DesktopPairingApprovalResult.fromMap(Map<String, dynamic> map) {
    String toStr(dynamic v) => (v ?? '').toString().trim();

    return DesktopPairingApprovalResult(
      success: map['success'] == true,
      message: toStr(map['message']).isNotEmpty
          ? toStr(map['message'])
          : toStr(map['error']),
      status: toStr(map['status']),
      pairedUserUid: toStr(map['pairedUserUid']).isNotEmpty
          ? toStr(map['pairedUserUid'])
          : toStr(map['paired_user_uid']),
      pairedUserName: toStr(map['pairedUserName']).isNotEmpty
          ? toStr(map['pairedUserName'])
          : toStr(map['paired_user_name']),
      pairedUserEmail: toStr(map['pairedUserEmail']).isNotEmpty
          ? toStr(map['pairedUserEmail'])
          : toStr(map['paired_user_email']),
    );
  }
}

class DesktopPairingStatus {
  final bool success;
  final bool approved;
  final String status;
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;
  final String firebaseCustomToken;

  const DesktopPairingStatus({
    required this.success,
    required this.approved,
    required this.status,
    this.pairedUserUid = '',
    this.pairedUserName = '',
    this.pairedUserEmail = '',
    this.firebaseCustomToken = '',
  });

  factory DesktopPairingStatus.fromMap(Map<String, dynamic> map) {
    String toStr(dynamic v) => (v ?? '').toString().trim();

    return DesktopPairingStatus(
      success: map['success'] == true,
      approved: map['approved'] == true,
      status: toStr(map['status']),
      pairedUserUid: toStr(map['pairedUserUid']).isNotEmpty
          ? toStr(map['pairedUserUid'])
          : toStr(map['paired_user_uid']),
      pairedUserName: toStr(map['pairedUserName']).isNotEmpty
          ? toStr(map['pairedUserName'])
          : toStr(map['paired_user_name']),
      pairedUserEmail: toStr(map['pairedUserEmail']).isNotEmpty
          ? toStr(map['pairedUserEmail'])
          : toStr(map['paired_user_email']),
      firebaseCustomToken: toStr(map['firebaseCustomToken']).isNotEmpty
          ? toStr(map['firebaseCustomToken'])
          : toStr(map['firebase_custom_token']),
    );
  }
}
