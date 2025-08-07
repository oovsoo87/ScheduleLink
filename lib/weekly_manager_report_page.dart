// lib/weekly_manager_report_page.dart

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
import 'models/site_model.dart';
import 'models/shift_model.dart';
import 'models/user_profile.dart';

class WeeklyManagerReportPage extends StatefulWidget {
  const WeeklyManagerReportPage({super.key});

  @override
  State<WeeklyManagerReportPage> createState() => _WeeklyManagerReportPageState();
}

class _WeeklyManagerReportPageState extends State<WeeklyManagerReportPage> {
  bool _isLoadingFilters = true;
  bool _isGenerating = false;
  DateTime _displayDate = DateTime.now();

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

  Future<void> _generateReport() async {
    setState(() => _isGenerating = true);
    try {
      final weekShifts = await _fetchScheduleForWeek(_displayDate);
      if (weekShifts.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No shifts found for this week.')));
      } else {
        await _generatePdf(weekShifts);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isGenerating = false);
    }
  }

  Future<List<Shift>> _fetchScheduleForWeek(DateTime date) async {
    DateTime startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    DateTime startOfDay = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final scheduleQuery = await FirebaseFirestore.instance.collection('schedules').where('weekStartDate', isEqualTo: startOfDay).limit(1).get();

    if (scheduleQuery.docs.isEmpty) return [];

    final data = scheduleQuery.docs.first.data() as Map<String, dynamic>;
    final shiftsData = data['shifts'] as List<dynamic>? ?? [];
    return shiftsData.map((data) => Shift.fromMap(data)).toList();
  }

  Future<void> _generatePdf(List<Shift> allShiftsInWeek) async {
    final pdf = pw.Document();

    final font = pw.Font.ttf(await rootBundle.load("assets/fonts/Poppins-Regular.ttf"));
    final boldFont = pw.Font.ttf(await rootBundle.load("assets/fonts/Poppins-Bold.ttf"));
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
    final turquoiseColor = PdfColor.fromHex('4DB6AC');

    var sitesToReportOn = _siteList;
    if (_selectedSite != null) {
      sitesToReportOn = _siteList.where((site) => site.id == _selectedSite!.id).toList();
    }

    var shiftsToReportOn = allShiftsInWeek;
    if (_selectedStaff != null) {
      shiftsToReportOn = allShiftsInWeek.where((shift) => shift.userId == _selectedStaff!.uid).toList();
    }

    List<pw.Widget> pageWidgets = [];
    bool firstSite = true;

    for (final site in sitesToReportOn) {
      if (!firstSite) {
        pageWidgets.add(pw.Container(height: 8, color: turquoiseColor, margin: const pw.EdgeInsets.symmetric(vertical: 10)));
      }

      // Projections Table
      double totalScheduledHours = 0;
      final siteShifts = shiftsToReportOn.where((shift) => shift.siteId == site.id).toList();
      for (final shift in siteShifts) {
        totalScheduledHours += shift.endTime.difference(shift.startTime).inSeconds / 3600.0;
      }
      final variance = totalScheduledHours - site.projectedWeeklyHours;

      final projectionsTable = pw.Table.fromTextArray(
        headers: ['Metric', 'Hours'], data: [
        ['Projected Weekly Hours', site.projectedWeeklyHours.toStringAsFixed(2)],
        ['Total Scheduled Hours', totalScheduledHours.toStringAsFixed(2)],
        ['Variance', variance.toStringAsFixed(2)],
      ],
        border: pw.TableBorder.all(color: PdfColors.grey400),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellAlignments: { 1: pw.Alignment.centerRight },
      );

      // Scheduled Staff Table
      List<List<String>> staffData = [];
      if (siteShifts.isNotEmpty) {
        final Map<String, List<Shift>> shiftsByUser = {};
        for (final shift in siteShifts) {
          shiftsByUser.putIfAbsent(shift.userId, () => []).add(shift);
        }
        for (final userId in shiftsByUser.keys) {
          final user = _staffList.firstWhere((u) => u.uid == userId, orElse: () => UserProfile(uid: '', email: 'Unknown', role: '', firstName: '', lastName: '', phoneNumber: '', isActive: false, assignedSiteIds: []));
          final userShifts = shiftsByUser[userId]!;
          userShifts.sort((a,b) => a.startTime.compareTo(b.startTime));
          staffData.add([
            user.fullName,
            userShifts.map((s) => '${DateFormat('E d/M HH:mm').format(s.startTime)}-${DateFormat('HH:mm').format(s.endTime)}').join('\n')
          ]);
        }
      }

      final staffTable = pw.Table.fromTextArray(
          headers: ['Staff Member', 'Shifts'], data: staffData,
          border: pw.TableBorder.all(color: PdfColors.grey400),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellStyle: const pw.TextStyle(fontSize: 9),
          columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(2) }
      );

      pageWidgets.add(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(level: 1, text: site.siteName),
            pw.SizedBox(width: 300, child: projectionsTable),
            pw.SizedBox(height: 15),
            pw.Text('Scheduled Staff', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            staffTable,
          ]
      ));
      firstSite = false;
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Weekly Manager Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text(_formatWeekRange(_displayDate)),
          ]
      ),
      build: (context) => pageWidgets,
    ));

    final fileName = 'manager_report_${DateTime.now().toIso8601String()}.pdf';
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report uploaded to cloud storage')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cloud upload failed: $e')));
    }
  }

  void _goToPreviousWeek() { setState(() => _displayDate = _displayDate.subtract(const Duration(days: 7))); }
  void _goToNextWeek() { setState(() => _displayDate = _displayDate.add(const Duration(days: 7))); }
  String _formatWeekRange(DateTime date) {
    DateTime startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
    final DateFormat formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(startOfWeek)} - ${formatter.format(endOfWeek)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Manager Report')),
      body: _isLoadingFilters
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _goToPreviousWeek),
                Text(_formatWeekRange(_displayDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: _goToNextWeek),
              ],
            ),
            const SizedBox(height: 16),
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