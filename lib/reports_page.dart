// lib/reports_page.dart

import 'package:flutter/material.dart';
import 'clocker_report_page.dart';
import 'scheduled_vs_clocked_report_page.dart';
import 'weekly_grid_report_page.dart';
import 'weekly_manager_report_page.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // A list to hold all the report options
    final List<Map<String, dynamic>> reportItems = [
      {
        'icon': Icons.timer,
        'title': 'Clocker Report',
        'subtitle': 'Detailed clock-in/out history.',
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClockerReportPage())),
      },
      {
        'icon': Icons.compare_arrows,
        'title': 'Scheduled vs. Clocked',
        'subtitle': 'Compare scheduled hours to actual clocked hours.',
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduledVsClockedReportPage())),
      },
      {
        'icon': Icons.grid_on,
        'title': 'Weekly Grid Report',
        'subtitle': 'View weekly hours in a grid format.',
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyGridReportPage())),
      },
      {
        'icon': Icons.person_outline,
        'title': 'Weekly Manager Report',
        'subtitle': 'A weekly summary for managers.',
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyManagerReportPage())),
      },
      {
        'icon': Icons.payment,
        'title': 'Export to Payroll CSV',
        'subtitle': 'Generate a CSV file for payroll processing.',
        'onTap': () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Coming Soon!'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      // Use ListView.separated to create a list with dividers
      body: ListView.separated(
        itemCount: reportItems.length,
        separatorBuilder: (context, index) => const Divider(), // Adds a line between items
        itemBuilder: (context, index) {
          final item = reportItems[index];
          return ListTile(
            leading: Icon(item['icon'], color: Theme.of(context).primaryColor),
            title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(item['subtitle']),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: item['onTap'],
          );
        },
      ),
    );
  }
}