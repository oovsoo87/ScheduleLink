// lib/weekly_grid_report_page.dart

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
import 'models/user_profile.dart';
import 'models/shift_model.dart';

class WeeklyGridReportPage extends StatefulWidget {
  const WeeklyGridReportPage({super.key});

  @override
  State<WeeklyGridReportPage> createState() => _WeeklyGridReportPageState();
}

class _WeeklyGridReportPageState extends State<WeeklyGridReportPage> {
  bool _isLoadingFilters = true;
  bool _isGenerating = false;
  DateTime _displayDate = DateTime.now();

  // --- NEW: Controller for the custom name field ---
  final _customNameController = TextEditingController();

  List<UserProfile> _staffList = [];
  Map<String, String> _siteNames = {};
  Map<String, String> _siteColorsHex = {};
  Set<String> _selectedStaffIds = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    // --- NEW: Dispose the controller ---
    _customNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoadingFilters = true);
    try {
      final staffFuture = FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
      final sitesFuture = FirebaseFirestore.instance.collection('sites').get();

      final results = await Future.wait([staffFuture, sitesFuture]);

      final staffSnapshot = results[0] as QuerySnapshot;
      final sitesSnapshot = results[1] as QuerySnapshot;

      final sites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();

      if (mounted) {
        setState(() {
          _staffList = staffSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
          _siteNames = {for (var site in sites) site.id: site.siteName};
          _siteColorsHex = {for (var site in sites) site.id: site.siteColor};
          _selectedStaffIds = _staffList.map((user) => user.uid).toSet();
          _isLoadingFilters = false;
        });
      }
    } catch(e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
        setState(() => _isLoadingFilters = false);
      }
    }
  }

  Future<void> _showStaffFilterDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        final tempSelectedIds = _selectedStaffIds.toSet();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter Staff'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _staffList.length,
                  itemBuilder: (context, index) {
                    final user = _staffList[index];
                    final name = '${user.firstName} ${user.lastName}'.trim();
                    return CheckboxListTile(
                      title: Text(name.isEmpty ? user.email : name),
                      value: tempSelectedIds.contains(user.uid),
                      onChanged: (isSelected) {
                        setDialogState(() {
                          if (isSelected ?? false) {
                            tempSelectedIds.add(user.uid);
                          } else {
                            tempSelectedIds.remove(user.uid);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                TextButton(onPressed: () { setState(() => _selectedStaffIds = tempSelectedIds); Navigator.of(context).pop(); }, child: const Text('Apply')),
              ],
            );
          },
        );
      },
    );
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
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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

  PdfColor _getTextColorForBackground(String hexColor) {
    try {
      final color = PdfColor.fromHex(hexColor);
      double luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue);
      return luminance > 0.5 ? PdfColors.black : PdfColors.white;
    } catch (e) {
      return PdfColors.white;
    }
  }

  Future<void> _generatePdf(List<Shift> allShifts) async {
    final pdf = pw.Document();

    final filteredShifts = allShifts.where((shift) => _selectedStaffIds.contains(shift.userId)).toList();
    final staffInReport = _staffList.where((user) => _selectedStaffIds.contains(user.uid)).toList();

    final Map<String, Map<int, List<Shift>>> userShiftsByDay = {};
    for (var user in staffInReport) {
      userShiftsByDay[user.uid] = {};
    }
    for (var shift in filteredShifts) {
      final dayIndex = shift.startTime.weekday - 1;
      userShiftsByDay[shift.userId]!.putIfAbsent(dayIndex, () => []).add(shift);
    }

    DateTime startOfWeek = _displayDate.subtract(Duration(days: _displayDate.weekday - 1));
    final headers = ['Staff Member'];
    for (int i=0; i<7; i++) {
      final day = startOfWeek.add(Duration(days: i));
      headers.add('${DateFormat('E').format(day)}\n${DateFormat('d MMM').format(day)}');
    }

    final List<pw.TableRow> tableRows = [];
    tableRows.add(pw.TableRow(
        children: headers.map((header) => pw.Container(
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.center,
          child: pw.Text(header, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        )).toList()
    ));

    for (final user in staffInReport) {
      final name = '${user.firstName} ${user.lastName}'.trim();
      final cells = <pw.Widget>[];
      cells.add(pw.Container(
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(name.isEmpty ? user.email : name, style: const pw.TextStyle(fontSize: 9))
      ));

      for (int i = 0; i < 7; i++) {
        final dayShifts = userShiftsByDay[user.uid]![i] ?? [];
        cells.add(
            pw.Column(
                children: dayShifts.map((shift) {
                  final siteColorHex = _siteColorsHex[shift.siteId] ?? '9E9E9E';
                  final siteColor = PdfColor.fromHex(siteColorHex);
                  final textColor = _getTextColorForBackground(siteColorHex);
                  final siteName = _siteNames[shift.siteId] ?? 'N/A';
                  final shiftText = '${DateFormat('HH:mm').format(shift.startTime)}-${DateFormat('HH:mm').format(shift.endTime)}\n$siteName';

                  return pw.Container(
                    color: siteColor,
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(3),
                    margin: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Text(
                        shiftText,
                        style: pw.TextStyle(fontSize: 8, color: textColor),
                        textAlign: pw.TextAlign.center
                    ),
                  );
                }).toList()
            )
        );
      }
      tableRows.add(pw.TableRow(children: cells));
    }

    // --- NEW: Header logic ---
    final DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
    final String formattedSundayDate = DateFormat('d MMMM yyyy').format(endOfWeek);
    final String mainHeader = 'Team Weekly Schedule for Week Ending $formattedSundayDate';
    final String customName = _customNameController.text.trim();
    // --- END NEW ---

    pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) {
            return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Header(level: 0, text: mainHeader),
                  // --- NEW: Add custom name if provided ---
                  if (customName.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4, bottom: 20),
                      child: pw.Text(
                        customName,
                        style: pw.TextStyle(fontSize: 18, fontStyle: pw.FontStyle.italic),
                      ),
                    )
                  else
                    pw.SizedBox(height: 20),
                  // --- END NEW ---
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: { 0: const pw.FlexColumnWidth(2.5) },
                    children: tableRows,
                  )
                ]
            );
          },
        )
    );

    final fileName = 'team_schedule_${DateTime.now().toIso8601String()}.pdf';
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
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report uploaded to cloud storage')));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cloud upload failed: $e')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Team Schedule Grid')),
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
                Text(_formatWeekRange(_displayDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: _goToNextWeek),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.filter_list),
                label: Text('Filter Staff (${_selectedStaffIds.length}/${_staffList.length})'),
                onPressed: _showStaffFilterDialog,
              ),
            ),
            // --- NEW: Text field for custom name ---
            const SizedBox(height: 16),
            TextFormField(
              controller: _customNameController,
              decoration: const InputDecoration(
                labelText: 'Custom Report Name (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            // --- END NEW ---
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: _isGenerating
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Generate PDF Grid'),
                onPressed: _generateReport,
              ),
            ),
          ],
        ),
      ),
    );
  }
}