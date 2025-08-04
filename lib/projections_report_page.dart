// lib/projections_report_page.dart

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
import 'models/site_model.dart';
import 'models/shift_model.dart';

class SiteReportData {
  final String siteName;
  final double projectedHours;
  final double scheduledHours;
  SiteReportData({required this.siteName, required this.projectedHours, required this.scheduledHours});
}

class ProjectionsReportPage extends StatefulWidget {
  const ProjectionsReportPage({super.key});

  @override
  State<ProjectionsReportPage> createState() => _ProjectionsReportPageState();
}

class _ProjectionsReportPageState extends State<ProjectionsReportPage> {
  bool _isLoadingFilters = true;
  bool _isGenerating = false;
  List<Site> _siteList = [];
  dynamic _selectedTarget;
  DateTime _displayDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchSites();
  }

  Future<void> _fetchSites() async {
    final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
    if (mounted) {
      setState(() {
        _siteList = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
        _isLoadingFilters = false;
      });
    }
  }

  Future<void> _generateReport() async {
    if (_selectedTarget == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a report target.')));
      return;
    }
    setState(() => _isGenerating = true);

    List<Site> sitesToReportOn = [];
    String reportTitle = 'Projections Report';

    if (_selectedTarget == 'all') {
      sitesToReportOn = _siteList;
      reportTitle = 'Projections Report (All Sites)';
    } else if (_selectedTarget is String) {
      sitesToReportOn = _siteList.where((site) => site.siteGroup == _selectedTarget).toList();
      reportTitle = 'Projections Report (Group: $_selectedTarget)';
    } else if (_selectedTarget is Site) {
      sitesToReportOn = [_selectedTarget as Site];
      reportTitle = 'Projections Report (${(_selectedTarget as Site).siteName})';
    }

    List<SiteReportData> reportDataList = [];
    for (final site in sitesToReportOn) {
      final projected = site.projectedWeeklyHours;
      final scheduled = await _calculateScheduledHours(site.id, _displayDate);
      reportDataList.add(SiteReportData(siteName: site.siteName, projectedHours: projected, scheduledHours: scheduled));
    }

    await _generatePdf(reportDataList, reportTitle);

    if(mounted) setState(() => _isGenerating = false);
  }

  Future<double> _calculateScheduledHours(String siteId, DateTime date) async {
    DateTime startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    DateTime startOfDay = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    DateTime endOfDay = startOfDay.add(const Duration(days: 1));
    final scheduleQuery = await FirebaseFirestore.instance.collection('schedules')
        .where('siteId', isEqualTo: siteId)
        .where('weekStartDate', isGreaterThanOrEqualTo: startOfDay)
        .where('weekStartDate', isLessThan: endOfDay).limit(1).get();

    double totalMinutes = 0;
    if (scheduleQuery.docs.isNotEmpty) {
      final shiftsData = scheduleQuery.docs.first.data()['shifts'] as List<dynamic>;
      final shifts = shiftsData.map((data) => Shift.fromMap(data));
      for (final shift in shifts) {
        totalMinutes += shift.endTime.difference(shift.startTime).inMinutes;
      }
    }
    return totalMinutes / 60.0;
  }

  Future<void> _generatePdf(List<SiteReportData> data, String title) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) {
          List<pw.Widget> widgets = [];

          // THE FIX: Changed 'style' to 'textStyle'
          widgets.add(pw.Header(level: 0, text: title, textStyle: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)));

          widgets.add(pw.Text('For Week: ${_formatWeekRange(_displayDate)}'));
          widgets.add(pw.SizedBox(height: 30));

          for (final report in data) {
            final variance = report.scheduledHours - report.projectedHours;
            widgets.add(pw.Header(level: 1, text: report.siteName));
            widgets.add(
                pw.Table.fromTextArray(
                  cellPadding: const pw.EdgeInsets.all(8),
                  border: pw.TableBorder.all(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  data: [
                    ['Metric', 'Hours'],
                    ['Projected Weekly Hours', report.projectedHours.toStringAsFixed(2)],
                    ['Total Scheduled Hours', report.scheduledHours.toStringAsFixed(2)],
                    ['Variance', variance.toStringAsFixed(2)],
                  ],
                  cellStyle: const pw.TextStyle(color: PdfColors.black),
                  cellAlignments: {
                    1: pw.Alignment.centerRight,
                  },
                )
            );
            widgets.add(pw.SizedBox(height: 20));
          }
          return widgets;
        },
      ),
    );

    final fileName = 'projections_report_${DateTime.now().toIso8601String()}.pdf';
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

  void _goToPreviousWeek() { setState(() => _displayDate = _displayDate.subtract(const Duration(days: 7))); }
  void _goToNextWeek() { setState(() => _displayDate = _displayDate.add(const Duration(days: 7))); }
  String _formatWeekRange(DateTime date) {
    DateTime startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
    return '${DateFormat.yMd().format(startOfWeek)} - ${DateFormat.yMd().format(endOfWeek)}';
  }

  @override
  Widget build(BuildContext context) {
    final siteGroups = _siteList.map((s) => s.siteGroup).where((g) => g.isNotEmpty).toSet().toList();
    List<DropdownMenuItem<dynamic>> dropdownItems = [];
    dropdownItems.add(const DropdownMenuItem(value: 'all', child: Text('All Sites', style: TextStyle(fontWeight: FontWeight.bold))));
    for (final group in siteGroups) {
      dropdownItems.add(DropdownMenuItem(value: group, child: Text('Group: $group', style: const TextStyle(fontWeight: FontWeight.bold))));
    }
    for (final site in _siteList) {
      dropdownItems.add(DropdownMenuItem(value: site, child: Padding(padding: const EdgeInsets.only(left: 16.0), child: Text(site.siteName))));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Projections Report')),
      body: _isLoadingFilters
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<dynamic>(
              value: _selectedTarget,
              isExpanded: true,
              hint: const Text('Select a Site or Group'),
              items: dropdownItems,
              onChanged: (target) => setState(() => _selectedTarget = target),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _goToPreviousWeek),
                Text(_formatWeekRange(_displayDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: _goToNextWeek),
              ],
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