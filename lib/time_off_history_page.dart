import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'models/time_off_request_model.dart';

class TimeOffHistoryPage extends StatefulWidget {
  const TimeOffHistoryPage({super.key});

  @override
  State<TimeOffHistoryPage> createState() => _TimeOffHistoryPageState();
}

class _TimeOffHistoryPageState extends State<TimeOffHistoryPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

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
      padding: const EdgeInsets.all(6),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(body: Center(child: Text('You must be logged in.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request History'),
      ),
      body: StreamBuilder<QuerySnapshot>(
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
            return const Center(child: Text('You have no past requests.'));
          }

          final requests = snapshot.data!.docs.map((doc) => TimeOffRequest.fromFirestore(doc)).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              // --- DATE FORMAT IS CHANGED HERE ---
              final DateFormat formatter = DateFormat('dd/MM/yyyy');
              final String startDate = formatter.format(request.startDate);
              final String endDate = formatter.format(request.endDate);
              // --- END CHANGE ---

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListTile(
                  title: Text('Dates: $startDate - $endDate'),
                  subtitle: Text(request.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: _buildStatusChip(request.status),
                ),
              );
            },
          );
        },
      ),
    );
  }
}