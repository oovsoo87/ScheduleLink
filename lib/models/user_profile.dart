// lib/models/user_profile.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String email;
  final String role;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final bool isActive;
  final List<String> assignedSiteIds;
  final String? directSupervisorId;
  final String? directAdminId;
  final double timeOffQuota;
  final double defaultDailyHours;
  final String? payrollId;
  final String? siteClockInNumber;

  final double hourlyRate;
  final double standardDeduction;
  final double loanRepayment;
  final double pensionPercentage;

  // --- NEW PAYROLL FIELDS ---
  final String? niNumber;
  final String? niCategory;
  final String? taxCode;
  final String? paymentPeriod; // e.g., 'Weekly', 'Monthly'

  UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.isActive,
    required this.assignedSiteIds,
    this.directSupervisorId,
    this.directAdminId,
    this.timeOffQuota = 0.0,
    this.defaultDailyHours = 8.0,
    this.payrollId,
    this.siteClockInNumber,
    this.hourlyRate = 0.0,
    this.standardDeduction = 0.0,
    this.loanRepayment = 0.0,
    this.pensionPercentage = 0.0,
    // --- NEW PAYROLL FIELDS ---
    this.niNumber,
    this.niCategory,
    this.taxCode,
    this.paymentPeriod,
  });

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? email : name;
  }

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: doc.id,
      email: data['email'] ?? '',
      role: data['role'] ?? 'staff',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      isActive: data['isActive'] ?? true,
      assignedSiteIds: List<String>.from(data['assignedSiteIds'] ?? []),
      directSupervisorId: data['directSupervisorId'],
      directAdminId: data['directAdminId'],
      timeOffQuota: (data['timeOffQuota'] ?? 0.0).toDouble(),
      defaultDailyHours: (data['defaultDailyHours'] ?? 8.0).toDouble(),
      payrollId: data['payrollId'],
      siteClockInNumber: data['siteClockInNumber'],
      hourlyRate: (data['hourlyRate'] ?? 0.0).toDouble(),
      standardDeduction: (data['standardDeduction'] ?? 0.0).toDouble(),
      loanRepayment: (data['loanRepayment'] ?? 0.0).toDouble(),
      pensionPercentage: (data['pensionPercentage'] ?? 0.0).toDouble(),
      // --- NEW PAYROLL FIELDS ---
      niNumber: data['niNumber'],
      niCategory: data['niCategory'],
      taxCode: data['taxCode'],
      paymentPeriod: data['paymentPeriod'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'role': role,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'isActive': isActive,
      'assignedSiteIds': assignedSiteIds,
      'directSupervisorId': directSupervisorId,
      'directAdminId': directAdminId,
      'timeOffQuota': timeOffQuota,
      'defaultDailyHours': defaultDailyHours,
      'payrollId': payrollId,
      'siteClockInNumber': siteClockInNumber,
      'hourlyRate': hourlyRate,
      'standardDeduction': standardDeduction,
      'loanRepayment': loanRepayment,
      'pensionPercentage': pensionPercentage,
      // --- NEW PAYROLL FIELDS ---
      'niNumber': niNumber,
      'niCategory': niCategory,
      'taxCode': taxCode,
      'paymentPeriod': paymentPeriod,
    };
  }
}