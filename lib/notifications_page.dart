// lib/notifications_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Simple model for type safety
class NotificationModel {
  final String id;
  final String title;
  final String body;
  final Timestamp timestamp;
  final bool isRead;

  NotificationModel.fromFirestore(DocumentSnapshot doc)
      : id = doc.id,
        title = (doc.data() as Map<String, dynamic>)['title'] ?? '',
        body = (doc.data() as Map<String, dynamic>)['body'] ?? '',
        timestamp = (doc.data() as Map<String, dynamic>)['timestamp'] ?? Timestamp.now(),
        isRead = (doc.data() as Map<String, dynamic>)['isRead'] ?? false;
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  Future<void> _markAsRead(String notificationId) async {
    await FirebaseFirestore.instance.collection('notifications').doc(notificationId).update({'isRead': true});
  }

  // --- NEW: Function to delete a notification ---
  Future<void> _deleteNotification(String notificationId, BuildContext context) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').doc(notificationId).delete();
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification deleted.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting notification: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showNotificationDialog(BuildContext context, NotificationModel notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notification.title),
        content: Text(notification.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    // Mark as read when the user opens the dialog
    if (!notification.isRead) {
      _markAsRead(notification.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('You must be logged in to view notifications.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: currentUser.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('You have no notifications.'));
          }

          final notifications = snapshot.data!.docs.map((doc) => NotificationModel.fromFirestore(doc)).toList();

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];

              // --- NEW: Wrap the Card in a Dismissible widget ---
              return Dismissible(
                key: ValueKey(notification.id), // Unique key for each item
                direction: DismissDirection.endToStart, // Allow swiping from right to left
                onDismissed: (direction) {
                  // This is called when the item is fully swiped
                  _deleteNotification(notification.id, context);
                },
                background: Container(
                  color: Colors.red.shade700,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  elevation: notification.isRead ? 1 : 4,
                  child: ListTile(
                    leading: notification.isRead
                        ? const Icon(Icons.mark_email_read_outlined, color: Colors.grey)
                        : Icon(Icons.mark_email_unread_outlined, color: Theme.of(context).primaryColor),
                    title: Text(
                      notification.title,
                      style: TextStyle(fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Received: ${DateFormat.yMd().add_jm().format(notification.timestamp.toDate())}',
                    ),
                    onTap: () => _showNotificationDialog(context, notification),
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