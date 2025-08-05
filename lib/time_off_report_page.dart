// lib/time_off_report_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'models/user_profile.dart';
import 'models/time_off_request_model.dart';

class TimeOffReportRow {
  final TimeOffRequest request;
  final UserProfile user;
  final double remainingQuota;

  TimeOffReportRow({required this.request, required this.user, required this.remainingQuota});

  double get durationInHours => daysRequested * user.defaultDailyHours;
  int get daysRequested => request.endDate.difference(request.startDate).inDays + 1;
}

class TimeOffReportPage extends StatefulWidget {
  const TimeOffReportPage({super.key});

  @override
  State<TimeOffReportPage> createState() => _TimeOffReportPageState();
}

class _TimeOffReportPageState extends State<TimeOffReportPage> {
  DateTimeRange? _selectedDateRange;
  bool _isGenerating = false;
  bool _isLoadingFilters = true;
  List<UserProfile> _staffList = [];
  UserProfile? _selectedStaff;

  @override
  void initState() {
    super.initState();
    _fetchFilterData();
  }

  Future<void> _fetchFilterData() async {
    final staffSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
    if (mounted) {
      setState(() {
        _staffList = staffSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
        _isLoadingFilters = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  // --- THIS FUNCTION CONTAINS THE EFFICIENCY IMPROVEMENT ---
  Future<List<TimeOffReportRow>> _fetchReportData() async {
    if (_selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date range.')));
      return [];
    }
    // Get requests within the selected date range for the report
    Query query = FirebaseFirestore.instance.collection('timeOffRequests')
        .where('startDate', isGreaterThanOrEqualTo: _selectedDateRange!.start)
        .where('startDate', isLessThanOrEqualTo: _selectedDateRange!.end.add(const Duration(days: 1)));
    if (_selectedStaff != null) {
      query = query.where('userId', isEqualTo: _selectedStaff!.uid);
    }

    final snapshot = await query.orderBy('startDate').get();
    final requestsInDateRange = snapshot.docs.map((doc) => TimeOffRequest.fromFirestore(doc)).toList();
    if (requestsInDateRange.isEmpty) return [];

    final userIds = requestsInDateRange.map((req) => req.userId).toSet().toList();
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: userIds).get();
    final userMap = {for (var doc in usersSnapshot.docs) doc.id: UserProfile.fromFirestore(doc)};

    // Fetch only the approved requests needed to calculate the quota, up to the end of the report period.
    final allApprovedRequestsSnapshot = await FirebaseFirestore.instance.collection('timeOffRequests')
        .where('userId', whereIn: userIds)
        .where('status', isEqualTo: 'approved')
        .where('startDate', isLessThanOrEqualTo: _selectedDateRange!.end) // This is the efficient change
        .get();
    final allApprovedRequests = allApprovedRequestsSnapshot.docs.map((doc) => TimeOffRequest.fromFirestore(doc)).toList();

    List<TimeOffReportRow> reportData = [];
    for (var request in requestsInDateRange) {
      if (userMap.containsKey(request.userId)) {
        final user = userMap[request.userId]!;
        double totalUsedHours = 0;
        // Calculate used hours based on the efficiently fetched requests
        allApprovedRequests.where((r) => r.userId == user.uid).forEach((approvedReq) {
          final days = approvedReq.endDate.difference(approvedReq.startDate).inDays + 1;
          totalUsedHours += days * user.defaultDailyHours;
        });
        final remainingQuota = user.timeOffQuota - totalUsedHours;
        reportData.add(TimeOffReportRow(request: request, user: user, remainingQuota: remainingQuota));
      }
    }
    return reportData;
  }

  Future<void> _generateReport(String format) async {
    setState(() => _isGenerating = true);
    try {
      final data = await _fetchReportData();
      if (data.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No time off records found for this period.')));
        return;
      }
      if (format == 'CSV') await _generateCsv(data);
      else if (format == 'PDF') await _generatePdf(data);
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating report: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateCsv(List<TimeOffReportRow> data) async {
    final List<List<dynamic>> rows = [];
    rows.add(['Employee', 'Start Date', 'End Date', 'Days', 'Hours', 'Total Quota', 'Remaining Quota', 'Reason', 'Status']);
    for (final row in data) {
      rows.add([
        row.request.requesterName,
        DateFormat('yyyy-MM-dd').format(row.request.startDate),
        DateFormat('yyyy-MM-dd').format(row.request.endDate),
        row.daysRequested,
        row.durationInHours.toStringAsFixed(2),
        row.user.timeOffQuota.toStringAsFixed(1),
        row.remainingQuota.toStringAsFixed(1),
        row.request.reason,
        row.request.status,
      ]);
    }
    String csv = const ListToCsvConverter().convert(rows);
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'time_off_report_${DateTime.now().toIso8601String()}.csv';
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsString(csv);
    await OpenFile.open(path);
  }

  Future<void> _generatePdf(List<TimeOffReportRow> data) async {
    final pdf = pw.Document();
    final themeColor = PdfColor.fromHex('4DB6AC');
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      header: (context) => pw.Header(text: 'Time Off Records Report'),
      footer: (context) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(color: PdfColors.grey))),
      build: (context) => [
        pw.Text('Date Range: ${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}'),
        pw.Text('Staff Member: ${_selectedStaff?.email ?? 'All Staff'}'),
        pw.SizedBox(height: 20),
        pw.Table.fromTextArray(
          headers: ['Employee', 'Start Date', 'End Date', 'Days', 'Hours', 'Total Quota', 'Remaining', 'Reason', 'Status'],
          data: data.map((row) => [
            row.request.requesterName,
            DateFormat('yyyy-MM-dd').format(row.request.startDate),
            DateFormat('yyyy-MM-dd').format(row.request.endDate),
            row.daysRequested.toString(),
            row.durationInHours.toStringAsFixed(1),
            '${row.user.timeOffQuota.toStringAsFixed(1)} hrs',
            '${row.remainingQuota.toStringAsFixed(1)} hrs',
            row.request.reason,
            row.request.status.toUpperCase(),
          ]).toList(),
          border: pw.TableBorder.all(color: PdfColors.grey),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: themeColor),
          cellStyle: const pw.TextStyle(fontSize: 9),
          columnWidths: { 7: const pw.FlexColumnWidth(2) },
        ),
      ],
    ));
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'time_off_report_${DateTime.now().toIso8601String()}.pdf';
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Time Off Records Report')),
      body: _isLoadingFilters
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<UserProfile>(
              value: _selectedStaff,
              hint: const Text('All Staff'),
              items: [
                const DropdownMenuItem<UserProfile>(value: null, child: Text('All Staff')),
                ..._staffList.map((user) {
                  final name = '${user.firstName} ${user.lastName}'.trim();
                  return DropdownMenuItem(value: user, child: Text(name.isEmpty ? user.email : name));
                }),
              ],
              onChanged: (user) => setState(() => _selectedStaff = user),
              decoration: const InputDecoration(labelText: 'Filter by Staff Member'),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Select Date Range'),
              subtitle: Text(_selectedDateRange == null ? 'Not Set' : '${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDateRange,
            ),
            const SizedBox(height: 32),
            if (_isGenerating) const CircularProgressIndicator()
            else Column(
              children: [
                SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.description), label: const Text('Generate CSV'), onPressed: () => _generateReport('CSV'))),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.picture_as_pdf), label: const Text('Generate PDF'), onPressed: () => _generateReport('PDF'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}