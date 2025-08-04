// lib/manage_staff_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/user_profile.dart';
import 'edit_user_page.dart';

class ManageStaffPage extends StatelessWidget {
  const ManageStaffPage({super.key});

  Future<void> _deactivateUser(BuildContext context, UserProfile user) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isActive': false,
      });
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${user.email} deactivated')));
      }
    } catch (e) {
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Staff'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No active users found.'));
          }

          var users = snapshot.data!.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();

          final roleOrder = {'admin': 1, 'supervisor': 2, 'staff': 3};
          users.sort((a, b) {
            final aOrder = roleOrder[a.role] ?? 4;
            final bOrder = roleOrder[b.role] ?? 4;
            return aOrder.compareTo(bOrder);
          });

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final displayName = '${user.firstName} ${user.lastName}'.trim();

              return ListTile(
                // --- NEW: Added alternating row color ---
                tileColor: index.isEven ? Theme.of(context).colorScheme.surface.withOpacity(0.5) : null,
                title: Text(displayName.isEmpty ? user.email : displayName),
                subtitle: Text('Role: ${user.role}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => EditUserPage(userProfile: user)));
                },
                onLongPress: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Please Confirm'),
                      content: Text('Are you sure you want to deactivate ${displayName.isEmpty ? user.email : displayName}?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            _deactivateUser(context, user);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Deactivate', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}