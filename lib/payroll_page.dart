// lib/payroll_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'models/user_profile.dart';

class PayrollData {
  final UserProfile user;
  final double totalHours;
  PayrollData({required this.user, required this.totalHours});
}

class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key});

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  DateTimeRange? _selectedDateRange;
  bool _isGenerating = false;

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  Future<List<PayrollData>> _fetchPayrollData(DateTimeRange range) async {
    // 1. Fetch all active users
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
    final users = usersSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
    final userMap = {for (var user in users) user.uid: user};

    // 2. Fetch all relevant time entries in the date range
    final timeEntriesSnapshot = await FirebaseFirestore.instance.collection('timeEntries')
        .where('status', isEqualTo: 'clocked-out')
        .where('clockInTime', isGreaterThanOrEqualTo: range.start)
        .where('clockInTime', isLessThanOrEqualTo: range.end.add(const Duration(days: 1)))
        .get();

    // 3. Calculate total hours for each user
    Map<String, double> userHours = {};
    for (var entryDoc in timeEntriesSnapshot.docs) {
      final data = entryDoc.data() as Map<String, dynamic>;
      final userId = data['userId'];
      final clockIn = (data['clockInTime'] as Timestamp).toDate();
      final clockOut = (data['clockOutTime'] as Timestamp).toDate();
      final hoursWorked = clockOut.difference(clockIn).inMinutes / 60.0;

      userHours.update(userId, (value) => value + hoursWorked, ifAbsent: () => hoursWorked);
    }

    // 4. Combine data into a final list
    List<PayrollData> payrollList = [];
    userHours.forEach((userId, totalHours) {
      if (userMap.containsKey(userId)) {
        payrollList.add(PayrollData(user: userMap[userId]!, totalHours: totalHours));
      }
    });

    return payrollList;
  }

  Future<void> _generateCsv(String format) async {
    if (_selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date range first.')));
      return;
    }
    setState(() => _isGenerating = true);

    try {
      final payrollData = await _fetchPayrollData(_selectedDateRange!);
      if (payrollData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No clocked-in data found for this period.')));
        return;
      }

      List<List<dynamic>> csvData;
      if (format == 'xero') {
        // Xero Format: Employee, StartDate, EndDate, Timesheet Title, Total Units
        csvData = [ ['*Employee', '*StartDate', '*EndDate', 'Timesheet Title', '*Total Units'] ];
        final title = 'Hours for ${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}';
        for (var data in payrollData) {
          csvData.add([
            data.user.payrollId ?? data.user.email,
            DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
            DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
            title,
            data.totalHours.toStringAsFixed(2),
          ]);
        }
      } else { // Sage Format
        // Sage Format: Employee Reference, Pay Element Name, Hours
        csvData = [ ['Employee Reference', 'Pay Element Name', 'Hours'] ];
        for (var data in payrollData) {
          csvData.add([
            data.user.payrollId ?? data.user.email,
            'Standard Hours', // A common pay element name
            data.totalHours.toStringAsFixed(2),
          ]);
        }
      }

      String csv = const ListToCsvConverter().convert(csvData);
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${format}_payroll_${DateTime.now().toIso8601String()}.csv';
      final path = '${directory.path}/$fileName';
      final file = File(path);
      await file.writeAsString(csv);

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export successful! File saved to $path'), backgroundColor: Colors.green));
        await OpenFile.open(path);
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating export: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Export')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              title: const Text('Select Pay Period'),
              subtitle: Text(_selectedDateRange == null ? 'Not Set' : '${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDateRange,
            ),
            const SizedBox(height: 32),
            if (_isGenerating)
              const CircularProgressIndicator()
            else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download_for_offline),
                  label: const Text('Export for Sage Payroll'),
                  onPressed: () => _generateCsv('sage'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download_for_offline),
                  label: const Text('Export for Xero Payroll'),
                  onPressed: () => _generateCsv('xero'),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}