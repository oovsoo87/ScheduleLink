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
  final double defaultDailyHours; // <-- NEW

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
    this.defaultDailyHours = 8.0, // <-- NEW (default to 8)
  });

  // Factory constructor to create a UserProfile from a Firestore document
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
      defaultDailyHours: (data['defaultDailyHours'] ?? 8.0).toDouble(), // <-- NEW
    );
  }

  // Method to convert UserProfile instance to a map for Firestore
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
      'defaultDailyHours': defaultDailyHours, // <-- NEW
    };
  }
}