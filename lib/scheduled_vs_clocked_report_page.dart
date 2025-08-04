// lib/scheduled_vs_clocked_report_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class TimeEntry {
  final DateTime clockIn;
  final DateTime? clockOut;
  final String clockInAddress;
  double get duration => (clockOut?.difference(clockIn).inMinutes ?? 0) / 60.0;

  TimeEntry({required this.clockIn, this.clockOut, this.clockInAddress = 'N/A'});
}

class AttendanceReportRow {
  final String userName;
  double scheduledHours;
  final List<TimeEntry> clockedEntries;

  double get clockedHours => clockedEntries.fold(0, (sum, entry) => sum + entry.duration);
  double get variance => clockedHours - scheduledHours;

  AttendanceReportRow({required this.userName, this.scheduledHours = 0, List<TimeEntry>? entries})
      : clockedEntries = entries ?? [];
}

class ScheduledVsClockedReportPage extends StatefulWidget {
  const ScheduledVsClockedReportPage({super.key});

  @override
  State<ScheduledVsClockedReportPage> createState() => _ScheduledVsClockedReportPageState();
}

class _ScheduledVsClockedReportPageState extends State<ScheduledVsClockedReportPage> {
  DateTimeRange? _selectedDateRange;
  bool _isGenerating = false;

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  Future<void> _generateReport() async {
    if (_selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date range first.')));
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final data = await _fetchReportData(_selectedDateRange!);
      if (data.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data found for this period.')));
      } else {
        await _generatePdf(data);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<Map<String, AttendanceReportRow>> _fetchReportData(DateTimeRange range) async {
    Map<String, AttendanceReportRow> reportMap = {};

    final usersSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
    for (var doc in usersSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = '${data['firstName']} ${data['lastName']}'.trim();
      reportMap[doc.id] = AttendanceReportRow(userName: name.isEmpty ? data['email'] : name);
    }

    final schedulesSnapshot = await FirebaseFirestore.instance.collection('schedules')
        .where('weekStartDate', isGreaterThanOrEqualTo: range.start.subtract(const Duration(days: 7)))
        .where('weekStartDate', isLessThanOrEqualTo: range.end)
        .get();

    for (var scheduleDoc in schedulesSnapshot.docs) {
      final data = scheduleDoc.data() as Map<String, dynamic>;
      if (data['shifts'] != null) {
        final shifts = data['shifts'] as List<dynamic>;
        for (var shiftData in shifts) {
          final userId = shiftData['userId'];
          final startTime = (shiftData['startTime'] as Timestamp).toDate();
          if (startTime.isAfter(range.start) && startTime.isBefore(range.end.add(const Duration(days: 1)))) {
            final endTime = (shiftData['endTime'] as Timestamp).toDate();
            final duration = endTime.difference(startTime).inMinutes / 60.0;
            if (reportMap.containsKey(userId)) {
              reportMap[userId]!.scheduledHours += duration;
            }
          }
        }
      }
    }

    final timeEntriesSnapshot = await FirebaseFirestore.instance.collection('timeEntries')
        .where('clockInTime', isGreaterThanOrEqualTo: range.start)
        .where('clockInTime', isLessThanOrEqualTo: range.end.add(const Duration(days: 1)))
        .get();

    for (var entryDoc in timeEntriesSnapshot.docs) {
      final data = entryDoc.data() as Map<String, dynamic>;
      final userId = data['userId'];
      if (reportMap.containsKey(userId)) {
        final clockIn = (data['clockInTime'] as Timestamp).toDate();
        final clockOut = (data['clockOutTime'] as Timestamp?)?.toDate();
        final clockInLocation = data['clockInLocation'] as Map<String, dynamic>?;

        reportMap[userId]!.clockedEntries.add(TimeEntry(
            clockIn: clockIn,
            clockOut: clockOut,
            clockInAddress: clockInLocation?['address'] ?? 'N/A'
        ));
      }
    }

    reportMap.removeWhere((key, value) => value.scheduledHours == 0 && value.clockedEntries.isEmpty);
    return reportMap;
  }

  Future<void> _generatePdf(Map<String, AttendanceReportRow> data) async {
    final pdf = pw.Document();
    pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            List<pw.Widget> widgets = [];
            widgets.add(pw.Header(level: 0, text: 'Scheduled vs. Clocked Hours Report'));
            widgets.add(pw.Text('Date Range: ${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}'));

            for (final row in data.values) {
              widgets.add(pw.Wrap(
                  children: [
                    pw.SizedBox(height: 30),
                    pw.Header(level: 1, text: row.userName),
                    pw.RichText(
                        text: pw.TextSpan(
                            children: [
                              pw.TextSpan(text: 'Total Scheduled: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                              pw.TextSpan(text: '${row.scheduledHours.toStringAsFixed(2)} hrs, '),
                              pw.TextSpan(text: 'Total Clocked: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                              pw.TextSpan(text: '${row.clockedHours.toStringAsFixed(2)} hrs, '),
                              pw.TextSpan(text: 'Variance: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                              pw.TextSpan(text: '${row.variance.toStringAsFixed(2)} hrs', style: pw.TextStyle(color: row.variance >= 0 ? PdfColors.green : PdfColors.red)),
                            ]
                        )
                    ),
                    pw.SizedBox(height: 10),
                    if (row.clockedEntries.isNotEmpty)
                      pw.Table.fromTextArray(
                          headers: ['Date', 'Clock In', 'Clock Out', 'Duration (hrs)', 'Clock In Location'],
                          data: row.clockedEntries.map((entry) => [
                            DateFormat('yyyy-MM-dd').format(entry.clockIn),
                            DateFormat('HH:mm:ss').format(entry.clockIn),
                            entry.clockOut != null ? DateFormat('HH:mm:ss').format(entry.clockOut!) : 'Still Clocked In',
                            entry.duration.toStringAsFixed(2),
                            entry.clockInAddress,
                          ]).toList(),
                          border: pw.TableBorder.all(),
                          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          cellAlignment: pw.Alignment.centerLeft,
                          columnWidths: { 4: const pw.FlexColumnWidth(2) }
                      )
                  ]
              ));
            }
            return widgets;
          },
        )
    );
    final fileName = 'attendance_report_detailed_${DateTime.now().toIso8601String()}.pdf';
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    await _uploadFileToStorage(file, fileName);
    await OpenFile.open(path);
  }

  Future<void> _uploadFileToStorage(File file, String fileName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final storageRef = FirebaseStorage.instance.ref();
      final reportRef = storageRef.child('reports/${user.uid}/$fileName');
      await reportRef.putFile(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report uploaded to cloud storage.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cloud upload failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled vs. Clocked Report')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              title: const Text('Date Range'),
              subtitle: Text(_selectedDateRange == null ? 'Not Set' : '${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDateRange,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: _isGenerating
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Generate PDF Report'),
                onPressed: _generateReport,
              ),
            ),
          ],
        ),
      ),
    );
  }
}