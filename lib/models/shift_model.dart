// lib/models/shift_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;

class Shift {
  final String userId;
  final tz.TZDateTime startTime;
  final tz.TZDateTime endTime;
  final String shiftId;
  final String siteId;
  final String? notes;

  Shift({
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.shiftId,
    required this.siteId,
    this.notes,
  });

  double get durationInHours {
    if (endTime.isBefore(startTime)) {
      return 0;
    }
    return endTime.difference(startTime).inMinutes / 60.0;
  }

  factory Shift.fromMap(Map<String, dynamic> map) {
    final location = tz.getLocation('Europe/London');
    final utcStartTime = (map['startTime'] as Timestamp).toDate();
    final utcEndTime = (map['endTime'] as Timestamp).toDate();

    return Shift(
      userId: map['userId'] ?? 'Unknown',
      startTime: tz.TZDateTime.from(utcStartTime, location),
      endTime: tz.TZDateTime.from(utcEndTime, location),
      shiftId: map['shiftId'] ?? '',
      siteId: map['siteId'] ?? '',
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'shiftId': shiftId,
      'siteId': siteId,
      'notes': notes,
    };
  }
}