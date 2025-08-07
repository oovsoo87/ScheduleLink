// lib/clocker_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'models/site_model.dart';
import 'models/shift_model.dart';

class ClockInRulesResult {
  final bool canClockIn;
  final String reason;
  ClockInRulesResult({required this.canClockIn, this.reason = ''});
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class LiveClockWidget extends StatefulWidget {
  const LiveClockWidget({super.key});
  @override
  State<LiveClockWidget> createState() => _LiveClockWidgetState();
}

class _LiveClockWidgetState extends State<LiveClockWidget> {
  late String _timeString;
  late String _dateString;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
  }

  void _updateTime() {
    final DateTime now = DateTime.now();
    final String formattedTime = DateFormat('HH:mm:ss').format(now);
    final String formattedDate = DateFormat('EEEE, d MMMM yyyy').format(now);
    if(mounted) {
      setState(() {
        _timeString = formattedTime;
        _dateString = formattedDate;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(_dateString, style: Theme.of(context).textTheme.titleMedium),
        Text(_timeString, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class ClockerPage extends StatefulWidget {
  const ClockerPage({super.key});
  @override
  State<ClockerPage> createState() => _ClockerPageState();
}

class _ClockerPageState extends State<ClockerPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  late Future<ClockInRulesResult> _clockInRulesFuture;

  bool _isClockingIn = false;
  // --- NEW: State to hold the pre-fetched location ---
  Position? _prefetchedPosition;

  @override
  void initState() {
    super.initState();
    _clockInRulesFuture = _fetchClockInRules();
    // Start getting the location as soon as the page loads
    _prefetchLocation();
  }

  // --- NEW: Function to get location in the background ---
  Future<void> _prefetchLocation() async {
    try {
      // Check for service and permission without blocking the UI
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      _prefetchedPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
    } catch (e) {
      // It's okay if this fails silently, the user can try again by pressing the button
      print("Prefetch location failed: $e");
    }
  }


  Future<ClockInRulesResult> _fetchClockInRules() async {
    if (_currentUser == null) return ClockInRulesResult(canClockIn: false, reason: 'Not logged in.');

    final now = DateTime.now().toUtc();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final weekStartDate = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final scheduleQuery = await _firestore.collection('schedules').where('weekStartDate', isEqualTo: weekStartDate).limit(1).get();
    if (scheduleQuery.docs.isEmpty) return ClockInRulesResult(canClockIn: false, reason: 'You are not scheduled to work today.');

    final data = scheduleQuery.docs.first.data() as Map<String, dynamic>;
    final allShiftsInWeek = (data['shifts'] as List<dynamic>? ?? []).map((s) => Shift.fromMap(s)).toList();
    final todayShifts = allShiftsInWeek.where((s) => s.userId == _currentUser!.uid && _isSameDay(s.startTime, now)).toList();

    if (todayShifts.isEmpty) return ClockInRulesResult(canClockIn: false, reason: 'You are not scheduled to work today.');

    final bool allShiftsAreOver = todayShifts.every((shift) => shift.endTime.isBefore(now));
    if (allShiftsAreOver) return ClockInRulesResult(canClockIn: false, reason: 'Your shift for today is over.');

    return ClockInRulesResult(canClockIn: true);
  }

  Future<void> _updateLocationForEntry(String entryId, String locationField) async {
    Map<String, dynamic>? locationData;
    try {
      // Use the pre-fetched position if available, otherwise get it now.
      final Position position = _prefetchedPosition ?? await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      String address = "Address not available";
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final addressParts = [pm.street, pm.locality, pm.postalCode, pm.country];
        address = addressParts.where((part) => part != null && part.isNotEmpty).join(', ');
        if(address.isEmpty) address = "Address details not available.";
      }
      locationData = { 'coordinates': GeoPoint(position.latitude, position.longitude), 'address': address };
      await _firestore.collection('timeEntries').doc(entryId).update({ locationField: locationData });
    } catch (e) {
      print('GEOLOCATION ERROR: ${e.toString()}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not save location: ${e.toString()}")));
    }
  }

  Future<Site?> _showSiteSelectionDialog(List<Site> sites) async {
    Site? selectedSite = sites.isNotEmpty ? sites.first : null;
    final formKey = GlobalKey<FormState>();
    return showDialog<Site>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Work Site'),
          content: Form(key: formKey, child: DropdownButtonFormField<Site>(
            value: selectedSite,
            items: sites.map((site) => DropdownMenuItem<Site>(value: site, child: Text(site.siteName))).toList(),
            onChanged: (value) => selectedSite = value,
            validator: (value) => value == null ? 'Please select a site' : null,
          )),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
            ElevatedButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.of(context).pop(selectedSite); }, child: const Text('Confirm')),
          ],
        );
      },
    );
  }

  Future<void> _clockIn() async {
    if (_currentUser == null) return;
    setState(() => _isClockingIn = true);

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final weekStartDate = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      final scheduleQuery = await _firestore.collection('schedules').where('weekStartDate', isEqualTo: weekStartDate).limit(1).get();

      if (scheduleQuery.docs.isEmpty) throw Exception("No schedule found for this week.");

      final data = scheduleQuery.docs.first.data() as Map<String, dynamic>;
      final allShiftsInWeek = (data['shifts'] as List<dynamic>? ?? []).map((s) => Shift.fromMap(s)).toList();
      final todayShifts = allShiftsInWeek.where((s) => s.userId == _currentUser!.uid && _isSameDay(s.startTime, now)).toList();
      final uniqueSiteIds = todayShifts.map((s) => s.siteId).toSet().toList();

      Site? selectedSite;

      if (uniqueSiteIds.length == 1) {
        final siteDoc = await _firestore.collection('sites').doc(uniqueSiteIds.first).get();
        if(siteDoc.exists) selectedSite = Site.fromFirestore(siteDoc);
      } else if (uniqueSiteIds.length > 1) {
        final sitesSnapshot = await _firestore.collection('sites').where(FieldPath.documentId, whereIn: uniqueSiteIds).get();
        final scheduledSites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
        selectedSite = await _showSiteSelectionDialog(scheduledSites);
      }

      if (selectedSite == null) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not determine work site."), backgroundColor: Colors.orange));
        return;
      }

      final lat = selectedSite.geofenceLatitude;
      final lon = selectedSite.geofenceLongitude;
      final radius = selectedSite.geofenceRadius;

      if (lat != null && lon != null && radius != null && radius > 0) {
        // --- UPDATED: Use the pre-fetched position if available, otherwise get it now ---
        final Position position = _prefetchedPosition ?? await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);

        final distance = Geolocator.distanceBetween(
          lat, lon, position.latitude, position.longitude,
        );

        if (distance > radius) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Clock-In Failed'),
                content: Text('You are ${distance.toInt()} meters away from the worksite. You must be within ${radius.toInt()} meters to clock in.'),
                actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')) ],
              ),
            );
          }
          return;
        }
      }

      final newEntry = await _firestore.collection('timeEntries').add({
        'userId': _currentUser!.uid, 'siteId': selectedSite.id, 'clockInTime': Timestamp.now(),
        'clockOutTime': null, 'status': 'clocked-in', 'clockInLocation': null,
      });
      await _updateLocationForEntry(newEntry.id, 'clockInLocation');

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Clock-in failed: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isClockingIn = false);
    }
  }

  Future<void> _clockOut(String entryId) async {
    if (_currentUser == null) return;
    await _firestore.collection('timeEntries').doc(entryId).update({
      'clockOutTime': Timestamp.now(), 'status': 'clocked-out', 'clockOutLocation': null,
    });
    await _updateLocationForEntry(entryId, 'clockOutLocation');
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) return const Scaffold(body: Center(child: Text("User not logged in.")));

    return Scaffold(
      appBar: AppBar(title: const Text('Clocker')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('timeEntries').where('userId', isEqualTo: _currentUser!.uid).where('status', isEqualTo: 'clocked-in').limit(1).snapshots(),
        builder: (context, streamSnapshot) {
          if (streamSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final bool isClockedIn = streamSnapshot.hasData && streamSnapshot.data!.docs.isNotEmpty;
          final String? entryId = isClockedIn ? streamSnapshot.data!.docs.first.id : null;

          return FutureBuilder<ClockInRulesResult>(
            future: _clockInRulesFuture,
            builder: (context, futureSnapshot) {
              if (futureSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              final clockInRules = futureSnapshot.data ?? ClockInRulesResult(canClockIn: false, reason: 'Error loading schedule.');
              final bool canClockIn = clockInRules.canClockIn;

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      const LiveClockWidget(),
                      const SizedBox(height: 48),
                      Text(isClockedIn ? 'You are CLOCKED IN' : 'You are CLOCKED OUT', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity, height: 60,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: isClockedIn ? Colors.red : (canClockIn ? Colors.green : Colors.grey), foregroundColor: Colors.white),
                          onPressed: isClockedIn ? () => _clockOut(entryId!) : (canClockIn && !_isClockingIn ? _clockIn : null),
                          child: _isClockingIn
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(isClockedIn ? 'Clock Out' : 'Clock In', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                        ),
                      ),
                      if (!isClockedIn && !canClockIn) ...[
                        const SizedBox(height: 16),
                        Text(clockInRules.reason, style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center)
                      ],
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}