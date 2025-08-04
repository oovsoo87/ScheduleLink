// lib/my_account_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/user_profile.dart';

// A helper class to hold all the fetched details
class AccountDetails {
  final UserProfile profile;
  final String supervisorName;
  final String adminName;

  AccountDetails({
    required this.profile,
    required this.supervisorName,
    required this.adminName,
  });
}

class MyAccountPage extends StatefulWidget {
  const MyAccountPage({super.key});

  @override
  State<MyAccountPage> createState() => _MyAccountPageState();
}

class _MyAccountPageState extends State<MyAccountPage> {
  late final Future<AccountDetails> _detailsFuture;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _fetchAccountDetails();
  }

  Future<String> _getUserName(String? userId) async {
    if (userId == null || userId.isEmpty) {
      return 'Not Assigned';
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final firstName = data['firstName'] ?? '';
        final lastName = data['lastName'] ?? '';
        final name = '$firstName $lastName'.trim();
        return name.isEmpty ? (data['email'] ?? 'Unknown User') : name;
      }
    } catch (e) {
      print('Error fetching user name: $e');
    }
    return 'Unknown User';
  }

  Future<AccountDetails> _fetchAccountDetails() async {
    if (_currentUser == null) {
      throw Exception('No user logged in.');
    }

    final profileDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).get();
    if (!profileDoc.exists) {
      throw Exception('User profile not found.');
    }

    final userProfile = UserProfile.fromFirestore(profileDoc);

    // Fetch supervisor and admin names concurrently
    final names = await Future.wait([
      _getUserName(userProfile.directSupervisorId),
      _getUserName(userProfile.directAdminId),
    ]);

    return AccountDetails(
      profile: userProfile,
      supervisorName: names[0],
      adminName: names[1],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
      ),
      body: FutureBuilder<AccountDetails>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('No details found.'));
          }

          final details = snapshot.data!;
          final profile = details.profile;

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('First Name'),
                  subtitle: Text(profile.firstName.isEmpty ? 'Not Set' : profile.firstName),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Last Name'),
                  subtitle: Text(profile.lastName.isEmpty ? 'Not Set' : profile.lastName),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email'),
                  subtitle: Text(profile.email),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('Site Clock-in Number'),
                  subtitle: Text(profile.siteClockInNumber?.isEmpty ?? true ? 'Not Set' : profile.siteClockInNumber!),
                ),
              ),
              const Divider(),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.supervisor_account_outlined),
                  title: const Text('Direct Supervisor'),
                  subtitle: Text(details.supervisorName),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Direct Admin'),
                  subtitle: Text(details.adminName),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}