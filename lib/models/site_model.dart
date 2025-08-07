// lib/models/site_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Site {
  final String id;
  final String siteName;
  final String address;
  final String siteGroup;
  final double projectedWeeklyHours;
  final String siteColor;
  final List<Map<String, String>> presetShifts;

  // --- NEW GEO-FENCE FIELDS ---
  final double? geofenceLatitude;
  final double? geofenceLongitude;
  final double? geofenceRadius;

  Site({
    required this.id,
    required this.siteName,
    required this.address,
    required this.siteGroup,
    required this.projectedWeeklyHours,
    required this.siteColor,
    required this.presetShifts,
    this.geofenceLatitude,
    this.geofenceLongitude,
    this.geofenceRadius,
  });

  factory Site.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    List<Map<String, String>> presets = [];
    if (data['presetShifts'] is List) {
      for (var item in (data['presetShifts'] as List)) {
        if (item is Map) {
          presets.add({
            'name': item['name']?.toString() ?? '',
            'startTime': item['startTime']?.toString() ?? '',
            'endTime': item['endTime']?.toString() ?? '',
          });
        }
      }
    }

    return Site(
      id: doc.id,
      siteName: data['siteName'] ?? 'Unnamed Site',
      address: data['address'] ?? '',
      siteGroup: data['siteGroup'] ?? '',
      projectedWeeklyHours: (data['projectedWeeklyHours'] ?? 0).toDouble(),
      siteColor: data['siteColor'] ?? '9E9E9E',
      presetShifts: presets,
      geofenceLatitude: data['geofenceLatitude'],
      geofenceLongitude: data['geofenceLongitude'],
      geofenceRadius: data['geofenceRadius'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteName': siteName,
      'address': address,
      'siteGroup': siteGroup,
      'projectedWeeklyHours': projectedWeeklyHours,
      'siteColor': siteColor,
      'presetShifts': presetShifts,
      'geofenceLatitude': geofenceLatitude,
      'geofenceLongitude': geofenceLongitude,
      'geofenceRadius': geofenceRadius,
    };
  }
}