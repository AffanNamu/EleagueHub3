class DesktopPairingSession {
  final String sessionId;
  final String sessionSecret;
  final String qrPayload;
  final String status;
  final int expiresAtMs;

  const DesktopPairingSession({
    required this.sessionId,
    required this.sessionSecret,
    required this.qrPayload,
    required this.status,
    required this.expiresAtMs,
  });

  factory DesktopPairingSession.fromMap(Map<String, dynamic> map) {
    return DesktopPairingSession(
      sessionId: (map['session_id'] ?? '').toString(),
      sessionSecret: (map['session_secret'] ?? '').toString(),
      qrPayload: (map['qr_payload'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      expiresAtMs: ((map['expires_at_ms'] ?? 0) as num).toInt(),
    );
  }
}

class DesktopPairingApprovalResult {
  final bool success;
  final String message;
  final String status;

  const DesktopPairingApprovalResult({
    required this.success,
    required this.message,
    required this.status,
  });

  factory DesktopPairingApprovalResult.fromMap(Map<String, dynamic> map) {
    return DesktopPairingApprovalResult(
      success: map['success'] == true,
      message: (map['message'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
    );
  }
}

class DesktopPairingStatus {
  final String sessionId;
  final String status;
  final bool approved;
  final bool consumed;
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;

  const DesktopPairingStatus({
    required this.sessionId,
    required this.status,
    required this.approved,
    required this.consumed,
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
  });

  factory DesktopPairingStatus.fromMap(Map<String, dynamic> map) {
    final status = (map['status'] ?? 'pending').toString();
    return DesktopPairingStatus(
      sessionId: (map['session_id'] ?? '').toString(),
      status: status,
      approved: map['approved'] == true || status == 'approved',
      consumed: map['consumed'] == true || status == 'consumed',
      pairedUserUid: (map['paired_user_uid'] ?? '').toString(),
      pairedUserName: (map['paired_user_name'] ?? '').toString(),
      pairedUserEmail: (map['paired_user_email'] ?? '').toString(),
    );
  }
}
