// lib/clocker_report_page.dart

import 'dart:io';
import 'package:flutter/services.dart';
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
  final String siteId;
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
    required this.siteId,
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

  Map<String, String> _siteColorsHex = {};

  @override
  void initState() {
    super.initState();
    _fetchFilterData();
  }

  Future<void> _fetchFilterData() async {
    final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
    final staffSnapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();

    if (mounted) {
      final sites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
      setState(() {
        _siteList = sites;
        _staffList = staffSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
        _siteColorsHex = {for (var site in sites) site.id: site.siteColor};
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
      } else {
        if (format == 'CSV') {
          await _generateAndUploadCsv(data);
        } else if (format == 'PDF') {
          await _generateAndUploadPdf(data);
        }
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
        totalHours = clockOut.difference(clockIn).inSeconds / 3600.0;
      }

      final clockInLocation = data['clockInLocation'] as Map<String, dynamic>?;
      final clockOutLocation = data['clockOutLocation'] as Map<String, dynamic>?;

      reportData.add(
          ReportRow(
            name: userMap[data['userId']]?.trim() ?? 'Unknown User',
            site: siteMap[data['siteId']] ?? 'N/A',
            siteId: data['siteId'] ?? '',
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
    // This function is unchanged
  }

  // --- THIS PDF FUNCTION IS REBUILT TO FIX THE ERRORS AND ADD STYLING ---
  Future<void> _generateAndUploadPdf(List<ReportRow> data) async {
    final pdf = pw.Document();

    final font = pw.Font.ttf(await rootBundle.load("assets/fonts/Poppins-Regular.ttf"));
    final boldFont = pw.Font.ttf(await rootBundle.load("assets/fonts/Poppins-Bold.ttf"));
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
    final turquoiseColor = PdfColor.fromHex('4DB6AC');

    // Group all data by site first
    final Map<String, List<ReportRow>> groupedBySite = {};
    for (final row in data) {
      groupedBySite.putIfAbsent(row.site, () => []).add(row);
    }

    final List<String> sortedSites = groupedBySite.keys.toList()..sort();

    List<pw.Widget> pageWidgets = [];
    bool firstSite = true;

    for (final site in sortedSites) {
      // Add a turquoise separator before each new site group (except the first one)
      if (!firstSite) {
        pageWidgets.add(pw.Container(
          height: 8,
          color: turquoiseColor,
          margin: const pw.EdgeInsets.symmetric(vertical: 10),
        ));
      }

      final siteEntries = groupedBySite[site]!;
      final siteId = siteEntries.first.siteId;
      final siteColorHex = _siteColorsHex[siteId] ?? '9E9E9E';

      // Site Header with colored dot
      pageWidgets.add(
          pw.Header(
              level: 1,
              child: pw.Row(
                  children: [
                    pw.Container(width: 12, height: 12, decoration: pw.BoxDecoration(color: PdfColor.fromHex(siteColorHex), shape: pw.BoxShape.circle)),
                    pw.SizedBox(width: 8),
                    pw.Text(site),
                  ]
              )
          )
      );

      final headers = ['Name', 'Date', 'Clock In', 'Clock Out', 'Hours'];

      final tableData = siteEntries.map((row) => [
        row.name,
        DateFormat('dd/MM/yy').format(row.clockIn),
        DateFormat('HH:mm:ss').format(row.clockIn),
        row.clockOut != null ? DateFormat('HH:mm:ss').format(row.clockOut!) : 'N/A',
        row.totalHours.toStringAsFixed(4),
      ]).toList();

      final table = pw.Table.fromTextArray(
        headers: headers,
        data: tableData,
        border: pw.TableBorder.all(color: PdfColors.grey400),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          4: pw.Alignment.centerRight,
        },
      );

      pageWidgets.add(table);
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
              pw.Text('Detailed Clocker Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text(dateRangeText),
            ]
        ),
        build: (pw.Context context) => pageWidgets,
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
                    : '${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end)}',
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