// lib/approve_time_off_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// A simple data model to make handling request data cleaner
class TimeOffRequest {
  final String id;
  final String requesterName;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final List<dynamic> approverIds;
  final List<dynamic> approvedBy;

  TimeOffRequest({
    required this.id,
    required this.requesterName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.approverIds,
    required this.approvedBy,
  });

  factory TimeOffRequest.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TimeOffRequest(
      id: doc.id,
      requesterName: data['requesterName'] ?? 'Unknown User',
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      reason: data['reason'] ?? 'No reason provided.',
      approverIds: data['approverIds'] ?? [],
      approvedBy: data['approvedBy'] ?? [],
    );
  }
}

class ApproveTimeOffPage extends StatefulWidget {
  const ApproveTimeOffPage({super.key});

  @override
  State<ApproveTimeOffPage> createState() => _ApproveTimeOffPageState();
}

class _ApproveTimeOffPageState extends State<ApproveTimeOffPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(content),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: title == 'Confirm Denial' ? Colors.red : Colors.green),
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _denyRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance.collection('timeOffRequests').doc(requestId).update({
        'status': 'denied',
      });
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request has been denied.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error denying request: $e')),
        );
      }
    }
  }

  Future<void> _approveRequest(TimeOffRequest request) async {
    if (_currentUser == null) return;
    final docRef = FirebaseFirestore.instance.collection('timeOffRequests').doc(request.id);

    try {
      // Add the current user to the list of those who have approved
      await docRef.update({
        'approvedBy': FieldValue.arrayUnion([_currentUser!.uid])
      });

      // After updating, get the latest document state to check if all have approved
      final updatedDoc = await docRef.get();
      final updatedRequest = TimeOffRequest.fromFirestore(updatedDoc);

      if (updatedRequest.approvedBy.length >= updatedRequest.approverIds.length) {
        // All required approvers have approved, so update status
        await docRef.update({'status': 'approved'});
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Final approval given. Request is approved.'), backgroundColor: Colors.green),
          );
        }
      } else {
        // Still waiting on other approvers
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your approval has been recorded.')),
          );
        }
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving request: $e')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(body: Center(child: Text('You must be logged in to view this page.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Approve Time Off'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('timeOffRequests')
            .where('status', isEqualTo: 'pending')
            .where('approverIds', arrayContains: _currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No pending requests for you to approve.'));
          }

          final requests = snapshot.data!.docs.map((doc) => TimeOffRequest.fromFirestore(doc)).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              // Don't show requests that this user has already approved
              if (request.approvedBy.contains(_currentUser!.uid)) {
                return const SizedBox.shrink();
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.requesterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Divider(),
                      Text('Dates: ${DateFormat.yMd().format(request.startDate)} - ${DateFormat.yMd().format(request.endDate)}'),
                      const SizedBox(height: 8),
                      Text('Reason: ${request.reason}'),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                            onPressed: () {
                              _showConfirmationDialog(
                                context: context,
                                title: 'Confirm Denial',
                                content: 'Are you sure you want to deny this time-off request for ${request.requesterName}?',
                                onConfirm: () => _denyRequest(request.id),
                              );
                            },
                            child: const Text('Deny'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                            onPressed: () {
                              _showConfirmationDialog(
                                context: context,
                                title: 'Confirm Approval',
                                content: 'Are you sure you want to approve this time-off request for ${request.requesterName}?',
                                onConfirm: () => _approveRequest(request),
                              );
                            },
                            child: const Text('Approve'),
                          ),
                        ],
                      )
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