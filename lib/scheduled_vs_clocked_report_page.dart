// lib/scheduled_vs_clocked_report_page.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'models/shift_model.dart';
import 'models/user_profile.dart';
import 'models/site_model.dart';

// --- UPDATED DATA MODELS FOR THIS REPORT ---

class TimeEntry {
  final DateTime clockIn;
  final DateTime? clockOut;
  TimeEntry({required this.clockIn, this.clockOut});
}

class ComparisonRow {
  final String siteId;
  final String siteName;
  final String userId;
  final String userName;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;

  ComparisonRow({
    required this.siteId,
    required this.siteName,
    required this.userId,
    required this.userName,
    required this.scheduledStart,
    required this.scheduledEnd,
    this.actualStart,
    this.actualEnd,
  });

  double get scheduledHours => scheduledEnd.difference(scheduledStart).inSeconds / 3600.0;
  double get actualHours => actualEnd != null && actualStart != null ? actualEnd!.difference(actualStart!).inSeconds / 3600.0 : 0;
  double get variance => actualHours - scheduledHours;
}

class UserTotals {
  double totalScheduled = 0;
  double totalActual = 0;
  double get totalVariance => totalActual - totalScheduled;
}

class ScheduledVsClockedReportPage extends StatefulWidget {
  const ScheduledVsClockedReportPage({super.key});

  @override
  State<ScheduledVsClockedReportPage> createState() => _ScheduledVsClockedReportPageState();
}

class _ScheduledVsClockedReportPageState extends State<ScheduledVsClockedReportPage> {
  DateTimeRange? _selectedDateRange;
  bool _isGenerating = false;
  bool _isLoadingFilters = true;

  // --- NEW: State for dropdown filters ---
  List<Site> _siteList = [];
  List<UserProfile> _staffList = [];
  Site? _selectedSite;
  UserProfile? _selectedStaff;

  @override
  void initState() {
    super.initState();
    _fetchFilterData();
  }

  // --- NEW: Function to load data for filters ---
  Future<void> _fetchFilterData() async {
    final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
    final staffSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
    if(mounted) {
      setState(() {
        _siteList = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
        _staffList = staffSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
        _isLoadingFilters = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (picked != null) {
      setState(() { _selectedDateRange = picked; });
    }
  }

  Future<void> _generateReport() async {
    if (_selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date range first.')));
      return;
    }
    setState(() => _isGenerating = true);
    try {
      // 1. Fetch all data
      var data = await _fetchReportData(_selectedDateRange!);

      // 2. Apply filters
      if (_selectedSite != null) {
        data = data.where((row) => row.siteId == _selectedSite!.id).toList();
      }
      if (_selectedStaff != null) {
        data = data.where((row) => row.userId == _selectedStaff!.uid).toList();
      }

      // 3. Sort the data to ensure correct order
      data.sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

      if (data.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data found for the selected filters.')));
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

  Future<List<ComparisonRow>> _fetchReportData(DateTimeRange range) async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
    final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
    final userMap = {for (var doc in usersSnapshot.docs) doc.id: UserProfile.fromFirestore(doc)};
    final siteMap = {for (var doc in sitesSnapshot.docs) doc.id: doc['siteName']};

    final timeEntriesSnapshot = await FirebaseFirestore.instance.collection('timeEntries')
        .where('clockInTime', isGreaterThanOrEqualTo: range.start)
        .where('clockInTime', isLessThanOrEqualTo: range.end.add(const Duration(days: 1)))
        .get();

    final Map<String, List<TimeEntry>> userTimeEntries = {};
    for (final doc in timeEntriesSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final userId = data['userId'];
      final key = '$userId-${DateFormat('yyyy-MM-dd').format((data['clockInTime'] as Timestamp).toDate())}';
      userTimeEntries.putIfAbsent(key, () => []).add(
          TimeEntry(clockIn: (data['clockInTime'] as Timestamp).toDate(), clockOut: (data['clockOutTime'] as Timestamp?)?.toDate())
      );
    }

    final schedulesSnapshot = await FirebaseFirestore.instance.collection('schedules')
        .where('weekStartDate', isGreaterThanOrEqualTo: range.start.subtract(const Duration(days: 7)))
        .where('weekStartDate', isLessThanOrEqualTo: range.end)
        .get();

    List<ComparisonRow> finalData = [];

    for (var scheduleDoc in schedulesSnapshot.docs) {
      final shifts = (scheduleDoc.data()['shifts'] as List<dynamic>? ?? []).map((s) => Shift.fromMap(s));
      for (final shift in shifts) {
        if (shift.startTime.isAfter(range.start) && shift.startTime.isBefore(range.end.add(const Duration(days: 1)))) {
          final user = userMap[shift.userId];
          if (user == null) continue;

          final key = '${shift.userId}-${DateFormat('yyyy-MM-dd').format(shift.startTime)}';
          final matchingEntries = userTimeEntries[key];

          TimeEntry? bestMatch;
          if (matchingEntries != null) {
            bestMatch = matchingEntries.firstWhere((e) => !e.clockIn.isBefore(shift.startTime), orElse: () => matchingEntries.first);
          }

          finalData.add(ComparisonRow(
            siteId: shift.siteId,
            siteName: siteMap[shift.siteId] ?? 'Unknown Site',
            userId: user.uid,
            userName: user.fullName,
            scheduledStart: shift.startTime,
            scheduledEnd: shift.endTime,
            actualStart: bestMatch?.clockIn,
            actualEnd: bestMatch?.clockOut,
          ));
        }
      }
    }
    return finalData;
  }

  Future<void> _generatePdf(List<ComparisonRow> data) async {
    final pdf = pw.Document();

    final font = pw.Font.ttf(await rootBundle.load("assets/fonts/Poppins-Regular.ttf"));
    final boldFont = pw.Font.ttf(await rootBundle.load("assets/fonts/Poppins-Bold.ttf"));
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
    final turquoiseColor = PdfColor.fromHex('4DB6AC');

    final Map<String, UserTotals> userTotals = {};
    for (final row in data) {
      userTotals.putIfAbsent(row.userName, () => UserTotals());
      userTotals[row.userName]!.totalScheduled += row.scheduledHours;
      userTotals[row.userName]!.totalActual += row.actualHours;
    }

    final Map<String, Map<String, List<ComparisonRow>>> groupedData = {};
    for (final row in data) {
      groupedData.putIfAbsent(row.siteName, () => {}).putIfAbsent(row.userName, () => []).add(row);
    }
    final sortedSites = groupedData.keys.toList()..sort();

    List<pw.Widget> pageWidgets = [];
    bool firstSite = true;
    for (final site in sortedSites) {
      if (!firstSite) {
        pageWidgets.add(pw.Container(height: 8, color: turquoiseColor, margin: const pw.EdgeInsets.symmetric(vertical: 10)));
      }
      pageWidgets.add(pw.Header(level: 1, text: site));
      final usersInData = groupedData[site]!;
      final sortedUsers = usersInData.keys.toList()..sort();

      for (final userName in sortedUsers) {
        final totals = userTotals[userName]!;
        final userRows = usersInData[userName]!;

        final summaryTable = pw.Table(
            columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1) },
            children: [
              pw.TableRow(children: [ pw.Text('Total Scheduled:'), pw.Text('${totals.totalScheduled.toStringAsFixed(2)} hrs', textAlign: pw.TextAlign.right) ]),
              pw.TableRow(children: [ pw.Text('Total Clocked:'), pw.Text('${totals.totalActual.toStringAsFixed(2)} hrs', textAlign: pw.TextAlign.right) ]),
              pw.TableRow(children: [ pw.Text('Total Variance:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('${totals.totalVariance.toStringAsFixed(2)} hrs', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: totals.totalVariance >= 0 ? PdfColors.green : PdfColors.red), textAlign: pw.TextAlign.right) ]),
            ]
        );

        final headers = ['Date', 'Scheduled (In-Out)', 'Actual (In-Out)', 'Variance (Hrs)'];
        final detailTable = pw.Table.fromTextArray(
          headers: headers,
          data: userRows.map((row) {
            final scheduledText = '${DateFormat('HH:mm').format(row.scheduledStart)}-${DateFormat('HH:mm').format(row.scheduledEnd)}';
            final actualText = row.actualStart != null && row.actualEnd != null
                ? '${DateFormat('HH:mm').format(row.actualStart!)}-${DateFormat('HH:mm').format(row.actualEnd!)}'
                : 'No Clock-in';
            return [
              DateFormat('dd/MM/yy').format(row.scheduledStart),
              scheduledText,
              actualText,
              row.variance.toStringAsFixed(2),
            ];
          }).toList(),
          border: pw.TableBorder.all(color: PdfColors.grey400),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: { 3: pw.Alignment.centerRight },
        );

        pageWidgets.add(pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 2, text: userName),
              pw.SizedBox(width: 250, child: summaryTable),
              pw.SizedBox(height: 8),
              detailTable,
              pw.SizedBox(height: 20),
            ]
        ));
      }
      firstSite = false;
    }

    final DateFormat formatter = DateFormat('dd/MM/yyyy');
    final String dateRangeText = '${formatter.format(_selectedDateRange!.start)} - ${formatter.format(_selectedDateRange!.end)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        header: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Scheduled vs. Clocked Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text(dateRangeText),
            ]
        ),
        build: (context) => pageWidgets,
      ),
    );

    final fileName = 'scheduled_vs_clocked_${DateTime.now().toIso8601String()}.pdf';
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
      body: _isLoadingFilters
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- NEW FILTERS ADDED ---
            DropdownButtonFormField<Site>(
              value: _selectedSite,
              hint: const Text('All Sites'),
              items: [
                const DropdownMenuItem<Site>(value: null, child: Text('All Sites')),
                ..._siteList.map((site) => DropdownMenuItem(value: site, child: Text(site.siteName))),
              ],
              onChanged: (site) => setState(() => _selectedSite = site),
              decoration: const InputDecoration(labelText: 'Filter by Site'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<UserProfile>(
              value: _selectedStaff,
              hint: const Text('All Staff'),
              items: [
                const DropdownMenuItem<UserProfile>(value: null, child: Text('All Staff')),
                ..._staffList.map((user) => DropdownMenuItem(value: user, child: Text(user.fullName))),
              ],
              onChanged: (user) => setState(() => _selectedStaff = user),
              decoration: const InputDecoration(labelText: 'Filter by Staff Member'),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date Range'),
              subtitle: Text(_selectedDateRange == null ? 'Not Set' : '${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end)}'),
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