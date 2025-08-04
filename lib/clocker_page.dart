// lib/clocker_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'models/user_profile.dart';
import 'models/site_model.dart';

// --- NEW WIDGET: This widget's only job is to display the time and update itself. ---
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
// --- END OF NEW WIDGET ---


class ClockerPage extends StatefulWidget {
  const ClockerPage({super.key});

  @override
  State<ClockerPage> createState() => _ClockerPageState();
}

class _ClockerPageState extends State<ClockerPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Timer logic has been moved to the LiveClockWidget, so it's removed from here.

  Future<void> _updateLocationForEntry(String entryId, String locationField) async {
    // ... (This function remains unchanged)
    Map<String, dynamic>? locationData;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      String address = "No address found";
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        address = "${pm.street}, ${pm.locality}, ${pm.postalCode}, ${pm.country}";
      }

      locationData = {
        'coordinates': GeoPoint(position.latitude, position.longitude),
        'address': address,
      };

      await _firestore.collection('timeEntries').doc(entryId).update({
        locationField: locationData,
      });

    } catch (e) {
      print("Background location update failed: $e");
    }
  }

  Future<Site?> _showSiteSelectionDialog(List<Site> sites) async {
    // ... (This function remains unchanged)
    Site? selectedSite = sites.isNotEmpty ? sites.first : null;
    final formKey = GlobalKey<FormState>();

    return showDialog<Site>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Work Site'),
          content: Form(
            key: formKey,
            child: DropdownButtonFormField<Site>(
              value: selectedSite,
              items: sites.map((site) {
                return DropdownMenuItem<Site>(
                  value: site,
                  child: Text(site.siteName),
                );
              }).toList(),
              onChanged: (value) {
                selectedSite = value;
              },
              validator: (value) => value == null ? 'Please select a site' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(selectedSite);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clockIn() async {
    // ... (This function remains unchanged)
    if (_currentUser == null) return;
    try {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (!userDoc.exists) { throw Exception("User profile not found."); }
      final userProfile = UserProfile.fromFirestore(userDoc);
      final siteIds = userProfile.assignedSiteIds;

      if (siteIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are not assigned to any sites. Cannot clock in.'), backgroundColor: Colors.red));
        return;
      }

      final sitesSnapshot = await _firestore.collection('sites').where(FieldPath.documentId, whereIn: siteIds).get();
      final assignedSites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();

      if (assignedSites.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assigned site data could not be found. Cannot clock in.'), backgroundColor: Colors.red));
        return;
      }

      final Site? selectedSite = await _showSiteSelectionDialog(assignedSites);

      if (selectedSite != null) {
        final newEntry = await _firestore.collection('timeEntries').add({
          'userId': _currentUser!.uid,
          'siteId': selectedSite.id,
          'clockInTime': Timestamp.now(),
          'clockOutTime': null,
          'status': 'clocked-in',
          'clockInLocation': null,
        });
        _updateLocationForEntry(newEntry.id, 'clockInLocation');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Clock-in failed: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _clockOut(String entryId) async {
    // ... (This function remains unchanged)
    if (_currentUser == null) return;
    await _firestore.collection('timeEntries').doc(entryId).update({
      'clockOutTime': Timestamp.now(),
      'status': 'clocked-out',
      'clockOutLocation': null,
    });
    _updateLocationForEntry(entryId, 'clockOutLocation');
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(body: Center(child: Text("User not logged in.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clocker'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('timeEntries')
            .where('userId', isEqualTo: _currentUser!.uid)
            .where('status', isEqualTo: 'clocked-in')
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final bool isClockedIn = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
          final String? entryId = isClockedIn ? snapshot.data!.docs.first.id : null;

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // The old date/time Text widgets are replaced by our new, efficient widget
                  const LiveClockWidget(),
                  const SizedBox(height: 48),

                  Text(
                    isClockedIn ? 'You are CLOCKED IN' : 'You are CLOCKED OUT',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isClockedIn ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        if (isClockedIn) {
                          _clockOut(entryId!);
                        } else {
                          _clockIn();
                        }
                      },
                      child: Text(
                        isClockedIn ? 'Clock Out' : 'Clock In',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}