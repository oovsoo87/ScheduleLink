// lib/clocker_report_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:csv/csv.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'models/site_model.dart';
import 'models/user_profile.dart';

class ReportRow {
  final String name;
  final String site;
  final DateTime clockIn;
  final DateTime? clockOut;
  final double totalHours;
  final String clockInAddress;
  final String clockOutAddress;
  final GeoPoint? clockInCoordinates;
  final GeoPoint? clockOutCoordinates;

  ReportRow({
    required this.name,
    required this.site,
    required this.clockIn,
    this.clockOut,
    required this.totalHours,
    required this.clockInAddress,
    required this.clockOutAddress,
    this.clockInCoordinates,
    this.clockOutCoordinates,
  });
}

class ClockerReportPage extends StatefulWidget {
  const ClockerReportPage({super.key});

  @override
  State<ClockerReportPage> createState() => _ClockerReportPageState();
}

class _ClockerReportPageState extends State<ClockerReportPage> {
  DateTimeRange? _selectedDateRange;
  bool _isGenerating = false;
  bool _isLoadingFilters = true;

  List<Site> _siteList = [];
  List<UserProfile> _staffList = [];
  Site? _selectedSite;
  UserProfile? _selectedStaff;

  @override
  void initState() {
    super.initState();
    _fetchFilterData();
  }

  Future<void> _fetchFilterData() async {
    final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
    final staffSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();

    if (mounted) {
      setState(() {
        _siteList = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
        _staffList = staffSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
        _isLoadingFilters = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  Future<void> _generateReport(String format) async {
    if (_selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date range first.')));
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final data = await _fetchReportData(_selectedDateRange!);
      if (data.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No clocker data found for this period.')));
        setState(() => _isGenerating = false);
        return;
      }

      if (format == 'CSV') {
        await _generateAndUploadCsv(data);
      } else if (format == 'PDF') {
        await _generateAndUploadPdf(data);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating report: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<List<ReportRow>> _fetchReportData(DateTimeRange range) async {
    Query query = FirebaseFirestore.instance.collection('timeEntries')
        .where('clockInTime', isGreaterThanOrEqualTo: range.start)
        .where('clockInTime', isLessThanOrEqualTo: range.end.add(const Duration(days: 1)));

    if (_selectedSite != null) {
      query = query.where('siteId', isEqualTo: _selectedSite!.id);
    }
    if (_selectedStaff != null) {
      query = query.where('userId', isEqualTo: _selectedStaff!.uid);
    }

    final timeEntriesSnapshot = await query.orderBy('clockInTime').get();

    if (timeEntriesSnapshot.docs.isEmpty) return [];

    final userIds = timeEntriesSnapshot.docs.map((doc) => doc['userId'] as String).toSet().toList();
    final siteIds = timeEntriesSnapshot.docs.map((doc) => (doc.data() as Map<String, dynamic>)['siteId'] as String?).where((id) => id != null).toSet().toList();

    if (userIds.isEmpty) return [];

    final usersSnapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: userIds).get();
    final sitesSnapshot = siteIds.isNotEmpty ? await FirebaseFirestore.instance.collection('sites').where(FieldPath.documentId, whereIn: siteIds).get() : null;

    final userMap = {for (var doc in usersSnapshot.docs) doc.id: '${doc['firstName']} ${doc['lastName']}'};
    final siteMap = sitesSnapshot != null ? {for (var doc in sitesSnapshot.docs) doc.id: doc['siteName']} : <String, String>{};

    List<ReportRow> reportData = [];
    for (var doc in timeEntriesSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final clockIn = (data['clockInTime'] as Timestamp).toDate();
      final clockOut = (data['clockOutTime'] as Timestamp?)?.toDate();
      double totalHours = 0;
      if (clockOut != null) {
        totalHours = clockOut.difference(clockIn).inMinutes / 60.0;
      }

      final clockInLocation = data['clockInLocation'] as Map<String, dynamic>?;
      final clockOutLocation = data['clockOutLocation'] as Map<String, dynamic>?;

      reportData.add(
          ReportRow(
            name: userMap[data['userId']]?.trim() ?? 'Unknown User',
            site: siteMap[data['siteId']] ?? 'N/A',
            clockIn: clockIn,
            clockOut: clockOut,
            totalHours: totalHours,
            clockInAddress: clockInLocation?['address'] ?? 'N/A',
            clockOutAddress: clockOutLocation?['address'] ?? 'N/A',
            clockInCoordinates: clockInLocation?['coordinates'] as GeoPoint?,
            clockOutCoordinates: clockOutLocation?['coordinates'] as GeoPoint?,
          )
      );
    }
    return reportData;
  }

  String _formatCoordinates(GeoPoint? point) {
    if (point == null) return 'N/A';
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  Future<void> _generateAndUploadCsv(List<ReportRow> data) async {
    final List<List<dynamic>> rows = [];
    rows.add(['Name', 'Site', 'Clock In', 'Clock Out', 'Total Hours', 'Clock In Address', 'Clock In Coords', 'Clock Out Address', 'Clock Out Coords']);
    for (final row in data) {
      rows.add([
        row.name,
        row.site,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(row.clockIn),
        row.clockOut != null ? DateFormat('yyyy-MM-dd HH:mm:ss').format(row.clockOut!) : 'N/A',
        row.totalHours.toStringAsFixed(2),
        row.clockInAddress,
        _formatCoordinates(row.clockInCoordinates),
        row.clockOutAddress,
        _formatCoordinates(row.clockOutCoordinates),
      ]);
    }
    String csv = const ListToCsvConverter().convert(rows);
    final fileName = 'clocker_report_${DateTime.now().toIso8601String()}.csv';
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsString(csv);
    await _uploadFileToStorage(file, fileName);
    await OpenFile.open(path);
  }

  Future<void> _generateAndUploadPdf(List<ReportRow> data) async {
    final pdf = pw.Document();
    final Map<String, Map<String, List<ReportRow>>> groupedData = {};
    for (final row in data) {
      groupedData.putIfAbsent(row.site, () => {}).putIfAbsent(row.name, () => []).add(row);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          List<pw.Widget> widgets = [];
          widgets.add(pw.Header(level: 0, child: pw.Text('Detailed Clocker Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))));
          widgets.add(pw.Text('Date Range: ${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}'));
          widgets.add(pw.SizedBox(height: 20));

          for (final site in groupedData.keys) {
            widgets.add(pw.Header(level: 1, text: site));
            final usersInData = groupedData[site]!;
            for (final user in usersInData.keys) {
              final userEntries = usersInData[user]!;

              widgets.add(pw.Wrap(
                  children: [
                    pw.Header(level: 2, text: user, textStyle: const pw.TextStyle(fontSize: 14)),
                    pw.Table.fromTextArray(
                        headers: ['Date', 'Clock In', 'Clock Out', 'Hours', 'Clock In Location', 'Clock Out Location'],
                        data: userEntries.map((entry) => [
                          DateFormat('yyyy-MM-dd').format(entry.clockIn),
                          DateFormat('HH:mm:ss').format(entry.clockIn),
                          entry.clockOut != null ? DateFormat('HH:mm:ss').format(entry.clockOut!) : 'N/A',
                          entry.totalHours.toStringAsFixed(2),
                          '${entry.clockInAddress}\n${_formatCoordinates(entry.clockInCoordinates)}',
                          '${entry.clockOutAddress}\n${_formatCoordinates(entry.clockOutCoordinates)}',
                        ]).toList(),
                        cellAlignment: pw.Alignment.centerLeft,
                        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        cellStyle: const pw.TextStyle(fontSize: 9),
                        columnWidths: {
                          4: const pw.FlexColumnWidth(3),
                          5: const pw.FlexColumnWidth(3),
                        }
                    ),
                  ]
              ));
              widgets.add(pw.SizedBox(height: 15));
            }
          }
          return widgets;
        },
      ),
    );

    final fileName = 'clocker_report_${DateTime.now().toIso8601String()}.pdf';
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    await _uploadFileToStorage(file, fileName);
    await OpenFile.open(path);
  }

  Future<void> _uploadFileToStorage(File file, String fileName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
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
      appBar: AppBar(title: const Text('Clocker Report')),
      body: _isLoadingFilters
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select filters for the report:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            DropdownButtonFormField<Site>(
              value: _selectedSite,
              hint: const Text('All Sites'),
              items: [
                const DropdownMenuItem<Site>(value: null, child: Text('All Sites')),
                ..._siteList.map((site) => DropdownMenuItem(value: site, child: Text(site.siteName))),
              ],
              onChanged: (site) => setState(() => _selectedSite = site),
            ),
            const SizedBox(height: 16),
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
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Date Range'),
              subtitle: Text(
                _selectedDateRange == null
                    ? 'Not Set'
                    : '${_selectedDateRange!.start.toLocal().toString().split(' ')[0]} - ${_selectedDateRange!.end.toLocal().toString().split(' ')[0]}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDateRange,
            ),
            const SizedBox(height: 32),
            if (_isGenerating)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.description),
                      label: const Text('Generate CSV Report'),
                      onPressed: () => _generateReport('CSV'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Generate PDF Report'),
                      onPressed: () => _generateReport('PDF'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}