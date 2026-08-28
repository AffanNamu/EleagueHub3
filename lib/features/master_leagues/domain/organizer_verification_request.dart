import 'package:cloud_firestore/cloud_firestore.dart';

enum VerificationRequestStatus {
  pending,
  approved,
  rejected,
  infoRequested,
  unknown,
}

VerificationRequestStatus verificationRequestStatusFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'pending':
      return VerificationRequestStatus.pending;
    case 'approved':
      return VerificationRequestStatus.approved;
    case 'rejected':
      return VerificationRequestStatus.rejected;
    case 'info_requested':
      return VerificationRequestStatus.infoRequested;
    default:
      return VerificationRequestStatus.unknown;
  }
}

extension VerificationRequestStatusX on VerificationRequestStatus {
  String get id {
    switch (this) {
      case VerificationRequestStatus.pending:
        return 'pending';
      case VerificationRequestStatus.approved:
        return 'approved';
      case VerificationRequestStatus.rejected:
        return 'rejected';
      case VerificationRequestStatus.infoRequested:
        return 'info_requested';
      case VerificationRequestStatus.unknown:
        return 'unknown';
    }
  }

  String get displayName {
    switch (this) {
      case VerificationRequestStatus.pending:
        return 'Pending Review';
      case VerificationRequestStatus.approved:
        return 'Approved';
      case VerificationRequestStatus.rejected:
        return 'Rejected';
      case VerificationRequestStatus.infoRequested:
        return 'Additional Info Requested';
      case VerificationRequestStatus.unknown:
        return 'Unknown';
    }
  }
}

/// Data an applicant fills out on the Verified Organizer application
/// form. Kept separate from [OrganizerVerificationRequest] (the stored
/// document, which also carries payment/review bookkeeping) so the
/// form widget and repository can pass this bag around without
/// touching fields it has no business setting (status, payment ids,
/// review history).
class OrganizerVerificationApplicationData {
  const OrganizerVerificationApplicationData({
    required this.orgName,
    required this.orgType,
    required this.orgCountry,
    required this.orgRegion,
    required this.orgCity,
    required this.contactEmail,
    required this.contactPhone,
    required this.website,
    required this.socialLink,
    required this.applicantFullName,
    required this.applicantRole,
    required this.orgDescription,
    required this.competitionTypes,
    required this.verificationReason,
    required this.supportingLinks,
    required this.logoUrl,
  });

  final String orgName;
  final String orgType;
  final String orgCountry;
  final String orgRegion;
  final String orgCity;
  final String contactEmail;
  final String contactPhone;
  final String website;
  final String socialLink;
  final String applicantFullName;
  final String applicantRole;
  final String orgDescription;
  final String competitionTypes;
  final String verificationReason;
  final String supportingLinks;
  final String logoUrl;

  factory OrganizerVerificationApplicationData.empty() {
    return const OrganizerVerificationApplicationData(
      orgName: '',
      orgType: '',
      orgCountry: '',
      orgRegion: '',
      orgCity: '',
      contactEmail: '',
      contactPhone: '',
      website: '',
      socialLink: '',
      applicantFullName: '',
      applicantRole: '',
      orgDescription: '',
      competitionTypes: '',
      verificationReason: '',
      supportingLinks: '',
      logoUrl: '',
    );
  }

  factory OrganizerVerificationApplicationData.fromRequest(
    OrganizerVerificationRequest req,
  ) {
    return OrganizerVerificationApplicationData(
      orgName: req.orgName,
      orgType: req.orgType,
      orgCountry: req.orgCountry,
      orgRegion: req.orgRegion,
      orgCity: req.orgCity,
      contactEmail: req.contactEmail,
      contactPhone: req.contactPhone,
      website: req.website,
      socialLink: req.socialLink,
      applicantFullName: req.applicantFullName,
      applicantRole: req.applicantRole,
      orgDescription: req.orgDescription,
      competitionTypes: req.competitionTypes,
      verificationReason: req.verificationReason,
      supportingLinks: req.supportingLinks,
      logoUrl: req.logoUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'orgName': orgName.trim(),
      'orgType': orgType.trim(),
      'orgCountry': orgCountry.trim().toUpperCase(),
      'orgRegion': orgRegion.trim(),
      'orgCity': orgCity.trim(),
      'contactEmail': contactEmail.trim(),
      'contactPhone': contactPhone.trim(),
      'website': website.trim(),
      'socialLink': socialLink.trim(),
      'applicantFullName': applicantFullName.trim(),
      'applicantRole': applicantRole.trim(),
      'orgDescription': orgDescription.trim(),
      'competitionTypes': competitionTypes.trim(),
      'verificationReason': verificationReason.trim(),
      'supportingLinks': supportingLinks.trim(),
      'logoUrl': logoUrl.trim(),
    };
  }

  String? validate() {
    if (orgName.trim().isEmpty) return 'Organization name is required.';
    if (orgType.trim().isEmpty) return 'Organization type is required.';
    if (orgCountry.trim().length != 2) return 'Please select a country.';
    if (contactEmail.trim().isEmpty || !contactEmail.contains('@')) {
      return 'A valid contact email is required.';
    }
    if (applicantFullName.trim().isEmpty) {
      return "Applicant's full name is required.";
    }
    if (applicantRole.trim().isEmpty) {
      return "Applicant's role or position is required.";
    }
    if (orgDescription.trim().isEmpty) {
      return 'Please describe what your organization does.';
    }
    if (verificationReason.trim().isEmpty) {
      return 'Please explain why you want organizer verification.';
    }
    if (logoUrl.trim().isEmpty) {
      return 'Please upload your organization logo.';
    }
    return null;
  }

  OrganizerVerificationApplicationData copyWith({
    String? orgName,
    String? orgType,
    String? orgCountry,
    String? orgRegion,
    String? orgCity,
    String? contactEmail,
    String? contactPhone,
    String? website,
    String? socialLink,
    String? applicantFullName,
    String? applicantRole,
    String? orgDescription,
    String? competitionTypes,
    String? verificationReason,
    String? supportingLinks,
    String? logoUrl,
  }) {
    return OrganizerVerificationApplicationData(
      orgName: orgName ?? this.orgName,
      orgType: orgType ?? this.orgType,
      orgCountry: orgCountry ?? this.orgCountry,
      orgRegion: orgRegion ?? this.orgRegion,
      orgCity: orgCity ?? this.orgCity,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      website: website ?? this.website,
      socialLink: socialLink ?? this.socialLink,
      applicantFullName: applicantFullName ?? this.applicantFullName,
      applicantRole: applicantRole ?? this.applicantRole,
      orgDescription: orgDescription ?? this.orgDescription,
      competitionTypes: competitionTypes ?? this.competitionTypes,
      verificationReason: verificationReason ?? this.verificationReason,
      supportingLinks: supportingLinks ?? this.supportingLinks,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }
}

/// The stored `master_league_verification_requests/{id}` document.
/// Backward compatible: requests created before the application form
/// existed only ever had payment/note fields — every new field here
/// parses to '' / 0 for those old docs instead of throwing.
class OrganizerVerificationRequest {
  const OrganizerVerificationRequest({
    required this.requestId,
    required this.masterLeagueId,
    required this.ownerId,
    required this.status,
    required this.requestType,
    required this.provider,
    required this.receiptId,
    required this.paymentId,
    required this.attemptId,
    required this.submittedAtMs,
    required this.reviewedAtMs,
    required this.reviewedBy,
    required this.note,
    required this.resubmittedAtMs,
    required this.orgName,
    required this.orgType,
    required this.orgCountry,
    required this.orgRegion,
    required this.orgCity,
    required this.contactEmail,
    required this.contactPhone,
    required this.website,
    required this.socialLink,
    required this.applicantFullName,
    required this.applicantRole,
    required this.orgDescription,
    required this.competitionTypes,
    required this.verificationReason,
    required this.supportingLinks,
    required this.logoUrl,
  });

  final String requestId;
  final String masterLeagueId;
  final String ownerId;
  final String status;
  final String requestType;
  final String provider;
  final String receiptId;
  final String paymentId;
  final String attemptId;
  final int submittedAtMs;
  final int reviewedAtMs;
  final String reviewedBy;
  final String note;
  final int resubmittedAtMs;

  final String orgName;
  final String orgType;
  final String orgCountry;
  final String orgRegion;
  final String orgCity;
  final String contactEmail;
  final String contactPhone;
  final String website;
  final String socialLink;
  final String applicantFullName;
  final String applicantRole;
  final String orgDescription;
  final String competitionTypes;
  final String verificationReason;
  final String supportingLinks;
  final String logoUrl;

  VerificationRequestStatus get statusEnum =>
      verificationRequestStatusFromString(status);

  /// True for requests submitted before the application form existed —
  /// they only ever carried payment metadata and an optional free note.
  bool get isLegacyPaymentOnly =>
      orgName.trim().isEmpty && applicantFullName.trim().isEmpty;

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static String _asStr(dynamic v) => (v as String? ?? '').trim();

  factory OrganizerVerificationRequest.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return OrganizerVerificationRequest(
      requestId: _asStr(map['requestId']).isNotEmpty
          ? _asStr(map['requestId'])
          : id,
      masterLeagueId: _asStr(map['masterLeagueId']),
      ownerId: _asStr(map['ownerId']),
      status: _asStr(map['status']).isEmpty ? 'pending' : _asStr(map['status']),
      requestType: _asStr(map['requestType']).isEmpty
          ? 'initial'
          : _asStr(map['requestType']),
      provider: _asStr(map['provider']),
      receiptId: _asStr(map['receiptId']),
      paymentId: _asStr(map['paymentId']),
      attemptId: _asStr(map['attemptId']),
      submittedAtMs: _asInt(map['submittedAtMs']),
      reviewedAtMs: _asInt(map['reviewedAtMs']),
      reviewedBy: _asStr(map['reviewedBy']),
      note: _asStr(map['note']),
      resubmittedAtMs: _asInt(map['resubmittedAtMs']),
      orgName: _asStr(map['orgName']),
      orgType: _asStr(map['orgType']),
      orgCountry: _asStr(map['orgCountry']),
      orgRegion: _asStr(map['orgRegion']),
      orgCity: _asStr(map['orgCity']),
      contactEmail: _asStr(map['contactEmail']),
      contactPhone: _asStr(map['contactPhone']),
      website: _asStr(map['website']),
      socialLink: _asStr(map['socialLink']),
      applicantFullName: _asStr(map['applicantFullName']),
      applicantRole: _asStr(map['applicantRole']),
      orgDescription: _asStr(map['orgDescription']),
      competitionTypes: _asStr(map['competitionTypes']),
      verificationReason: _asStr(map['verificationReason']),
      supportingLinks: _asStr(map['supportingLinks']),
      logoUrl: _asStr(map['logoUrl']),
    );
  }

  factory OrganizerVerificationRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return OrganizerVerificationRequest.fromMap(
      doc.id,
      doc.data() ?? <String, dynamic>{},
    );
  }
}
