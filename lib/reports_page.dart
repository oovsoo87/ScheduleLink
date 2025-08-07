// lib/reports_page.dart

import 'package:flutter/material.dart';
import 'clocker_report_page.dart';
import 'weekly_manager_report_page.dart'; // UPDATED import
import 'scheduled_vs_clocked_report_page.dart';
import 'weekly_grid_report_page.dart';
import 'payroll_page.dart';
import 'time_off_report_page.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Reports'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Payroll Export'),
              subtitle: const Text('Generate CSV files for Sage and Xero.'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const PayrollPage()));
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.beach_access_outlined),
              title: const Text('Time Off Records'),
              subtitle: const Text('CSV/PDF of all approved/denied time off.'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const TimeOffReportPage()));
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_view_week),
              title: const Text('Weekly Schedule PDF'),
              subtitle: const Text('Printable grid view of the team\'s schedule.'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const WeeklyGridReportPage()));
              },
            ),
          ),
          // --- THIS LIST TILE IS UPDATED ---
          Card(
            child: ListTile(
              leading: const Icon(Icons.assessment_outlined),
              title: const Text('Weekly Manager Report'),
              subtitle: const Text('PDF of projections & scheduled staff by site.'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const WeeklyManagerReportPage()));
              },
            ),
          ),
          // --- END UPDATE ---
          Card(
            child: ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: const Text('Scheduled vs. Clocked-In'),
              subtitle: const Text('PDF comparing scheduled vs. actual hours.'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ScheduledVsClockedReportPage()));
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Detailed Clocker Report'),
              subtitle: const Text('CSV/PDF of all clock-in/out entries.'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ClockerReportPage()));
              },
            ),
          ),
        ],
      ),
    );
  }
}