// lib/send_notification_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'models/user_profile.dart';

class SendNotificationPage extends StatefulWidget {
  const SendNotificationPage({super.key});

  @override
  State<SendNotificationPage> createState() => _SendNotificationPageState();
}

class _SendNotificationPageState extends State<SendNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  List<UserProfile> _userList = [];
  List<UserProfile> _selectedUsers = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
      if(mounted) {
        setState(() {
          _userList = usersSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching users: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  // --- NEW: Helper functions for Select All ---
  bool _isAllSelected() {
    return _userList.isNotEmpty && _selectedUsers.length == _userList.length;
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected()) {
        _selectedUsers.clear();
      } else {
        _selectedUsers = List.from(_userList);
      }
    });
  }
  // --- END NEW ---

  Future<void> _sendNotifications() async {
    if (!_formKey.currentState!.validate() || _selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields and select at least one user."), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSending = true);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You must be logged in to send notifications."), backgroundColor: Colors.red));
      return;
    }

    try {
      // Use a batch write for efficiency
      final batch = FirebaseFirestore.instance.batch();

      for (final user in _selectedUsers) {
        final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
        batch.set(notificationRef, {
          'userId': user.uid,
          'title': _titleController.text.trim(),
          'body': _bodyController.text.trim(),
          'timestamp': Timestamp.now(),
          'isRead': false,
          'createdBy': currentUser.uid,
        });
      }

      await batch.commit();

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Notification sent to ${_selectedUsers.length} user(s)."), backgroundColor: Colors.green));
        Navigator.of(context).pop();
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error sending notification: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Notification'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // --- NEW: Select All / Clear All Button ---
            if (_userList.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  child: Text(_isAllSelected() ? 'Clear All' : 'Select All'),
                  onPressed: _toggleSelectAll,
                ),
              ),
            // --- END NEW ---
            MultiSelectDialogField<UserProfile>(
              items: _userList.map((user) {
                final name = '${user.firstName} ${user.lastName}'.trim();
                return MultiSelectItem(user, name.isEmpty ? user.email : name);
              }).toList(),
              initialValue: _selectedUsers, // Important to show pre-selected users
              title: const Text("Select Users"),
              selectedColor: Theme.of(context).primaryColor,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              buttonIcon: const Icon(Icons.people),
              // --- NEW: Dynamic button text ---
              buttonText: Text(
                _selectedUsers.isEmpty
                    ? "Select user(s) to notify"
                    : "${_selectedUsers.length} user(s) selected",
                style: const TextStyle(fontSize: 16),
              ),
              onConfirm: (results) {
                setState(() {
                  _selectedUsers = results;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Notification Title', border: OutlineInputBorder()),
              validator: (value) => value == null || value.isEmpty ? 'Please enter a title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Notification Message', border: OutlineInputBorder()),
              maxLines: 5,
              validator: (value) => value == null || value.isEmpty ? 'Please enter a message' : null,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send Notification'),
              onPressed: _isSending ? null : _sendNotifications,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            if(_isSending)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}