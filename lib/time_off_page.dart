// lib/time_off_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'models/user_profile.dart';
import 'models/time_off_request_model.dart';
import 'models/shift_model.dart';
import 'time_off_history_page.dart';

class TimeOffPage extends StatefulWidget {
  const TimeOffPage({super.key});

  @override
  State<TimeOffPage> createState() => _TimeOffPageState();
}

class _TimeOffPageState extends State<TimeOffPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  late final Future<Map<String, dynamic>> _initialDataFuture;

  @override
  void initState() {
    super.initState();
    _initialDataFuture = _fetchInitialData();
  }

  double _calculateUsedQuota(List<TimeOffRequest> requests, UserProfile userProfile) {
    double hoursUsed = 0;
    for (final request in requests) {
      if (request.status == 'approved') {
        final days = request.endDate.difference(request.startDate).inDays + 1;
        hoursUsed += days * userProfile.defaultDailyHours;
      }
    }
    return hoursUsed;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(body: Center(child: Text('User not logged in.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Off'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const TimeOffHistoryPage()));
            },
            tooltip: 'View Request History',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _initialDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text("Error loading data: ${snapshot.error}"));
          }

          final UserProfile userProfile = snapshot.data!['profile'];
          final List<TimeOffRequest> approvedRequests = snapshot.data!['requests'];
          final double usedQuota = _calculateUsedQuota(approvedRequests, userProfile);
          final double remainingQuota = userProfile.timeOffQuota - usedQuota;

          final bool hasEntitlement = userProfile.timeOffQuota > 0 &&
              userProfile.defaultDailyHours > 0 &&
              remainingQuota > 0;

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              _buildQuotaCard(userProfile.timeOffQuota, usedQuota, remainingQuota),
              const SizedBox(height: 8),
              if (hasEntitlement)
                NewRequestForm(userProfile: userProfile, onRequestSubmitted: () {
                  setState(() {
                    _initialDataFuture = _fetchInitialData();
                  });
                })
              else
                Card(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  elevation: 0,
                  child: const ListTile(
                    leading: Icon(Icons.info_outline, color: Colors.grey),
                    title: Text('No Time Off Entitlement'),
                    subtitle: Text('Your quota is not set or has been used.'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchInitialData() async {
    final profileDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).get();
    final requestsSnapshot = await FirebaseFirestore.instance
        .collection('timeOffRequests')
        .where('userId', isEqualTo: _currentUser!.uid)
        .where('status', isEqualTo: 'approved')
        .get();

    return {
      'profile': UserProfile.fromFirestore(profileDoc),
      'requests': requestsSnapshot.docs.map((doc) => TimeOffRequest.fromFirestore(doc)).toList(),
    };
  }

  Widget _buildQuotaCard(double total, double used, double remaining) {
    return Card(
      margin: const EdgeInsets.all(0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _QuotaColumn(title: 'Total', hours: total),
            _QuotaColumn(title: 'Used', hours: used, color: Colors.orange),
            _QuotaColumn(title: 'Remaining', hours: remaining, color: Colors.green),
          ],
        ),
      ),
    );
  }
}

class _QuotaColumn extends StatelessWidget {
  final String title;
  final double hours;
  final Color color;
  const _QuotaColumn({required this.title, required this.hours, this.color = Colors.black});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = color == Colors.black ? (isDark ? Colors.white : Colors.black) : color;

    return Column(
      children: [
        Text(title.toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(hours.toStringAsFixed(1), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: textColor)),
        Text('hours', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey)),
      ],
    );
  }
}

class NewRequestForm extends StatefulWidget {
  final UserProfile userProfile;
  final VoidCallback onRequestSubmitted;
  const NewRequestForm({super.key, required this.userProfile, required this.onRequestSubmitted});

  @override
  State<NewRequestForm> createState() => _NewRequestFormState();
}

class _NewRequestFormState extends State<NewRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<bool> _checkForShiftConflicts(DateTime startDate, DateTime endDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final schedulesSnapshot = await FirebaseFirestore.instance.collection('schedules').get();
    for (var scheduleDoc in schedulesSnapshot.docs) {
      final data = scheduleDoc.data() as Map<String, dynamic>;
      final shifts = data['shifts'] as List<dynamic>? ?? [];
      for (var shiftData in shifts) {
        final shift = Shift.fromMap(shiftData);
        if (shift.userId == user.uid) {
          final shiftDate = DateTime(shift.startTime.year, shift.startTime.month, shift.startTime.day);
          final reqStartDate = DateTime(startDate.year, startDate.month, startDate.day);
          final reqEndDate = DateTime(endDate.year, endDate.month, endDate.day);
          if (!shiftDate.isBefore(reqStartDate) && !shiftDate.isAfter(reqEndDate)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  // --- NEW: Function to check for time off request conflicts ---
  Future<bool> _checkForTimeOffConflicts(DateTime startDate, DateTime endDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final requestsSnapshot = await FirebaseFirestore.instance
        .collection('timeOffRequests')
        .where('userId', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'approved'])
        .get();

    if (requestsSnapshot.docs.isEmpty) return false;

    for (var doc in requestsSnapshot.docs) {
      final existingRequest = TimeOffRequest.fromFirestore(doc);
      // The overlap logic: A conflict exists if the ranges are NOT completely separate.
      final bool overlaps = !(endDate.isBefore(existingRequest.startDate) ||
          startDate.isAfter(existingRequest.endDate));
      if (overlaps) {
        return true; // Conflict found
      }
    }
    return false; // No conflicts found
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() || _startDate == null || _endDate == null) return;

    setState(() => _isLoading = true);

    try {
      // Check for conflicts with work shifts
      final bool hasShiftConflict = await _checkForShiftConflicts(_startDate!, _endDate!);
      if (hasShiftConflict) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have shifts scheduled during this time.'), backgroundColor: Colors.red));
        }
        setState(() => _isLoading = false);
        return;
      }

      // --- NEW: Check for conflicts with other time off requests ---
      final bool hasTimeOffConflict = await _checkForTimeOffConflicts(_startDate!, _endDate!);
      if (hasTimeOffConflict) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This request overlaps with another time off request.'), backgroundColor: Colors.red));
        }
        setState(() => _isLoading = false);
        return;
      }
      // --- END NEW ---

      final requesterName = "${widget.userProfile.firstName} ${widget.userProfile.lastName}".trim();
      List<String> approverIds = [];
      if (widget.userProfile.directAdminId != null && widget.userProfile.directAdminId!.isNotEmpty) {
        approverIds.add(widget.userProfile.directAdminId!);
      }
      final shouldAutoApprove = approverIds.isEmpty;

      await FirebaseFirestore.instance.collection('timeOffRequests').add({
        'userId': widget.userProfile.uid,
        'requesterName': requesterName.isEmpty ? widget.userProfile.email : requesterName,
        'startDate': Timestamp.fromDate(_startDate!),
        'endDate': Timestamp.fromDate(_endDate!),
        'reason': _reasonController.text.trim(),
        'status': shouldAutoApprove ? 'approved' : 'pending',
        'approverIds': approverIds,
        'approvedBy': [],
        'dateRequested': Timestamp.now(),
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off request submitted!')));
        widget.onRequestSubmitted();
        setState(() {
          _startDate = null;
          _endDate = null;
          _reasonController.clear();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit request: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) _endDate = _startDate;
        } else {
          if (_startDate != null && picked.isBefore(_startDate!)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date cannot be before the start date.')));
          } else {
            _endDate = picked;
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(0),
      child: ExpansionTile(
        title: const Text("Create New Request", style: TextStyle(fontWeight: FontWeight.bold)),
        initiallyExpanded: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Start Date'),
                          TextButton(onPressed: () => _selectDate(context, true), child: Text(_startDate == null ? 'Select' : DateFormat.yMd().format(_startDate!))),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('End Date'),
                          TextButton(onPressed: () => _selectDate(context, false), child: Text(_endDate == null ? 'Select' : DateFormat.yMd().format(_endDate!))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(controller: _reasonController, decoration: const InputDecoration(labelText: 'Reason for request', border: OutlineInputBorder()), validator: (v) => (v == null || v.isEmpty) ? 'Please provide a reason.' : null, maxLines: 3),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: _isLoading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: _submitRequest, child: const Text('Submit Request')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}