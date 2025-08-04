// lib/admin_page.dart

import 'package:flutter/material.dart';
import 'manage_sites_page.dart';
import 'manage_staff_page.dart';
import 'reports_page.dart';
import 'approve_time_off_page.dart';
import 'temp_pdf_generator_page.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            title: const Text('Manage Sites'),
            subtitle: const Text('Add, edit, or remove work sites'),
            leading: const Icon(Icons.store),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageSitesPage()));
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Manage Staff'),
            subtitle: const Text('View users and change roles'),
            leading: const Icon(Icons.people),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageStaffPage()));
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('View Reports'),
            subtitle: const Text('Generate and download reports'),
            leading: const Icon(Icons.bar_chart),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ReportsPage()));
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Approve Time Off'),
            subtitle: const Text('Review pending time off requests'),
            leading: const Icon(Icons.check_circle_outline),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ApproveTimeOffPage()));
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Generate Pricing PDF'),
            subtitle: const Text('Temporary tool for one-off PDF generation'),
            leading: const Icon(Icons.picture_as_pdf_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const TempPdfGeneratorPage()));
            },
          ),
        ],
      ),
    );
  }
}