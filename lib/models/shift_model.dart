// lib/models/shift_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Shift {
  final String userId;
  final DateTime startTime;
  final DateTime endTime;
  final String shiftId;
  final String siteId;
  final String? notes; // <-- NEW: Optional field for notes

  Shift({
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.shiftId,
    required this.siteId,
    this.notes, // <-- NEW
  });

  factory Shift.fromMap(Map<String, dynamic> map) {
    return Shift(
      userId: map['userId'] ?? 'Unknown',
      startTime: (map['startTime'] as Timestamp).toDate(),
      endTime: (map['endTime'] as Timestamp).toDate(),
      shiftId: map['shiftId'] ?? '',
      siteId: map['siteId'] ?? '',
      notes: map['notes'], // <-- NEW
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'shiftId': shiftId,
      'siteId': siteId,
      'notes': notes, // <-- NEW
    };
  }
}