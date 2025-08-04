// lib/models/time_off_request_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class TimeOffRequest {
  final String id;
  final String userId;
  final String requesterName;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;

  TimeOffRequest({
    required this.id,
    required this.userId,
    required this.requesterName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
  });

  factory TimeOffRequest.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TimeOffRequest(
      id: doc.id,
      userId: data['userId'] ?? '',
      requesterName: data['requesterName'] ?? 'Unknown User',
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      reason: data['reason'] ?? 'No reason provided.',
      status: data['status'] ?? 'pending',
    );
  }
}