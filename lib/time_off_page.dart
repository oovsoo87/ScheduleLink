// lib/time_off_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'models/user_profile.dart';
import 'models/time_off_request_model.dart';

class TimeOffPage extends StatefulWidget {
  const TimeOffPage({super.key});

  @override
  State<TimeOffPage> createState() => _TimeOffPageState();
}

class _TimeOffPageState extends State<TimeOffPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

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
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchInitialData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text("Error loading data: ${snapshot.error}"));
          }

          final UserProfile userProfile = snapshot.data!['profile'];
          final List<TimeOffRequest> initialRequests = snapshot.data!['requests'];
          final double usedQuota = _calculateUsedQuota(initialRequests, userProfile);
          final double remainingQuota = userProfile.timeOffQuota - usedQuota;

          // --- NEW LOGIC HERE ---
          // Determine if the user has any time off entitlement.
          final bool hasEntitlement = userProfile.timeOffQuota > 0 &&
              userProfile.defaultDailyHours > 0 &&
              remainingQuota > 0;

          return Column(
            children: [
              _buildQuotaCard(userProfile.timeOffQuota, usedQuota, remainingQuota),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8.0),
                  children: [
                    // Conditionally show either the form or the "No Entitlement" message.
                    if (hasEntitlement)
                      NewRequestForm(userProfile: userProfile)
                    else
                      Card(
                        color: Colors.grey[200],
                        elevation: 0,
                        child: const ListTile(
                          leading: Icon(Icons.info_outline, color: Colors.grey),
                          title: Text('No Time Off Entitlement'),
                          subtitle: Text('Your quota is not set or has been used.'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text('Request History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    _buildRequestHistoryList(),
                  ],
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
        .get();

    return {
      'profile': UserProfile.fromFirestore(profileDoc),
      'requests': requestsSnapshot.docs.map((doc) => TimeOffRequest.fromFirestore(doc)).toList(),
    };
  }

  Widget _buildQuotaCard(double total, double used, double remaining) {
    return Card(
      margin: const EdgeInsets.all(8.0),
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

  Widget _buildRequestHistoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('timeOffRequests')
          .where('userId', isEqualTo: _currentUser!.uid)
          .orderBy('dateRequested', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('You have no past requests.'),
          ));
        }

        final requests = snapshot.data!.docs.map((doc) => TimeOffRequest.fromFirestore(doc)).toList();

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              child: ListTile(
                title: Text('Dates: ${DateFormat.yMd().format(request.startDate)} - ${DateFormat.yMd().format(request.endDate)}'),
                subtitle: Text(request.reason),
                trailing: _buildStatusChip(request.status),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    IconData icon;
    Color color;
    switch (status) {
      case 'approved':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'denied':
        icon = Icons.cancel;
        color = Colors.red;
        break;
      default: // pending
        icon = Icons.hourglass_empty;
        color = Colors.orange;
    }
    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: color,
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
    return Column(
      children: [
        Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(hours.toStringAsFixed(1), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const Text('hours', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class NewRequestForm extends StatefulWidget {
  final UserProfile userProfile;
  const NewRequestForm({super.key, required this.userProfile});

  @override
  State<NewRequestForm> createState() => _NewRequestFormState();
}

class _NewRequestFormState extends State<NewRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false;

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() || _startDate == null || _endDate == null) return;
    setState(() => _isLoading = true);
    try {
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
        'reason': _reasonController.text,
        'status': shouldAutoApprove ? 'approved' : 'pending',
        'approverIds': approverIds,
        'approvedBy': [],
        'dateRequested': Timestamp.now(),
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off request submitted!')));
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
    return ExpansionTile(
      title: const Text("Create New Request", style: TextStyle(fontWeight: FontWeight.bold)),
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
    );
  }
}