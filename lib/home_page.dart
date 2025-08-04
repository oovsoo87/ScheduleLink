// lib/home_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'models/user_profile.dart';
import 'models/site_model.dart';
import 'manage_schedule_page.dart';
import 'models/shift_model.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final UserProfile userProfile;
  const HomePage({super.key, required this.userProfile});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ValueNotifier<List<Shift>> _selectedShifts;
  Map<DateTime, List<Shift>> _allShiftsByDay = {};
  Map<String, String> _siteNames = {};
  Map<String, Color> _siteColors = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedShifts = ValueNotifier(_getShiftsForDay(_selectedDay!));
    _fetchUserSchedule();
  }

  @override
  void dispose() {
    _selectedShifts.dispose();
    super.dispose();
  }

  Color _colorFromHex(String hexColor) {
    hexColor = hexColor.replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  List<Shift> _getShiftsForDay(DateTime day) {
    return _allShiftsByDay[DateTime.utc(day.year, day.month, day.day)] ?? [];
  }

  Future<void> _fetchUserSchedule() async {
    setState(() => _isLoading = true);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final sitesFuture = FirebaseFirestore.instance.collection('sites').get();
      final scheduleFuture = FirebaseFirestore.instance.collection('schedules').get();
      final results = await Future.wait([sitesFuture, scheduleFuture]);

      final sitesSnapshot = results[0] as QuerySnapshot;
      final scheduleSnapshot = results[1] as QuerySnapshot;

      final sites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
      final siteNameMap = {for (var site in sites) site.id: site.siteName};
      final siteColorMap = {for (var site in sites) site.id: _colorFromHex(site.siteColor)};

      Map<DateTime, List<Shift>> shiftsMap = {};
      for (var scheduleDoc in scheduleSnapshot.docs) {
        final data = scheduleDoc.data() as Map<String, dynamic>;
        final allShiftsData = data['shifts'] as List<dynamic>? ?? [];

        final userShiftsData = allShiftsData.where((shift) => shift['userId'] == currentUser.uid);
        for (var shiftData in userShiftsData) {
          final shift = Shift.fromMap(shiftData);
          final day = DateTime.utc(shift.startTime.year, shift.startTime.month, shift.startTime.day);
          if (shiftsMap[day] == null) {
            shiftsMap[day] = [];
          }
          shiftsMap[day]!.add(shift);
        }
      }
      if (mounted) {
        setState(() {
          _siteNames = siteNameMap;
          _siteColors = siteColorMap;
          _allShiftsByDay = shiftsMap;
          _selectedShifts.value = _getShiftsForDay(_selectedDay!);
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
      _selectedShifts.value = _getShiftsForDay(selectedDay);
    }
  }

  // --- NEW: Dialog to show shift details and notes ---
  void _showShiftDetailsDialog(Shift shift) {
    final siteName = _siteNames[shift.siteId] ?? 'Unknown Site';
    final siteColor = _siteColors[shift.siteId] ?? Colors.grey;
    final notes = shift.notes ?? 'No notes for this shift.';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(backgroundColor: siteColor, radius: 10),
            const SizedBox(width: 8),
            Text(siteName),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat.yMMMMd().format(shift.startTime)),
            const SizedBox(height: 8),
            Text(
              '${DateFormat('h:mm a').format(shift.startTime)} - ${DateFormat('h:mm a').format(shift.endTime)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 24),
            const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(notes),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  // --- END NEW ---

  @override
  Widget build(BuildContext context) {
    final bool canManage = widget.userProfile.role == 'supervisor' || widget.userProfile.role == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
        actions: [
          if (canManage)
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageSchedulePage())),
              icon: const Icon(Icons.edit_calendar),
            ),
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          TableCalendar<Shift>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: _onDaySelected,
            eventLoader: _getShiftsForDay,
            calendarFormat: _calendarFormat,
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, shifts) {
                if (shifts.isEmpty) return null;
                return Wrap(
                  alignment: WrapAlignment.center,
                  children: shifts.map((shift) => Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _siteColors[shift.siteId] ?? Colors.grey,
                    ),
                  )).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: ValueListenableBuilder<List<Shift>>(
              valueListenable: _selectedShifts,
              builder: (context, value, _) {
                if (value.isEmpty) {
                  return const Center(child: Text('No shifts on this day.'));
                }
                return ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final shift = value[index];
                    final String startTime = DateFormat('h:mm a').format(shift.startTime);
                    final String endTime = DateFormat('h:mm a').format(shift.endTime);
                    final siteName = _siteNames[shift.siteId] ?? 'Unknown Site';
                    final siteColor = _siteColors[shift.siteId] ?? Colors.grey;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: siteColor, radius: 10),
                        title: Text(siteName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$startTime - $endTime'),
                        // NEW: Add onTap to show the details dialog
                        onTap: () => _showShiftDetailsDialog(shift),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}