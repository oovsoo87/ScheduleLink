// lib/manage_schedule_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'models/shift_model.dart';
import 'models/user_profile.dart';
import 'models/site_model.dart';
import 'add_shift_page.dart';

class ManageSchedulePage extends StatefulWidget {
  const ManageSchedulePage({super.key});

  @override
  State<ManageSchedulePage> createState() => _ManageSchedulePageState();
}

// Helper function needed by this page
bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ManageSchedulePageState extends State<ManageSchedulePage> {
  late final ValueNotifier<List<Shift>> _selectedShifts;
  Map<DateTime, List<Shift>> _allShiftsByDay = {};
  Map<String, String> _userNames = {};
  Map<String, String> _siteNames = {};
  Map<String, Color> _siteColors = {};

  List<Shift> _copiedShifts = [];
  DateTime? _copiedWeekStartDate;
  bool _isSelectionMode = false;
  Set<Shift> _selectedShiftsForCopy = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.week;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedShifts = ValueNotifier(_getShiftsForDay(_selectedDay!));
    _fetchData();
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

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final usersFuture = FirebaseFirestore.instance.collection('users').get();
      final sitesFuture = FirebaseFirestore.instance.collection('sites').get();
      final scheduleFuture = FirebaseFirestore.instance.collection('schedules').get();

      final results = await Future.wait([usersFuture, sitesFuture, scheduleFuture]);

      final usersSnapshot = results[0] as QuerySnapshot;
      final sitesSnapshot = results[1] as QuerySnapshot;
      final scheduleSnapshot = results[2] as QuerySnapshot;

      final userMap = {for (var doc in usersSnapshot.docs) doc.id: '${doc['firstName']} ${doc['lastName']}'.trim()};

      final sites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
      final siteNameMap = {for (var site in sites) site.id: site.siteName};
      final siteColorMap = {for (var site in sites) site.id: _colorFromHex(site.siteColor)};

      Map<DateTime, List<Shift>> shiftsMap = {};

      for (var scheduleDoc in scheduleSnapshot.docs) {
        final data = scheduleDoc.data() as Map<String, dynamic>;
        final shiftsData = data['shifts'] as List<dynamic>? ?? [];

        for (var shiftData in shiftsData) {
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
          _userNames = userMap;
          _siteNames = siteNameMap;
          _siteColors = siteColorMap;
          _allShiftsByDay = shiftsMap;
          _selectedShifts.value = _getShiftsForDay(_selectedDay!);
          _isLoading = false;
        });
      }
    } catch(e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching schedule: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSingleShift(Shift shiftToDelete) async {
    final startOfWeek = _getStartOfWeek(shiftToDelete.startTime);
    final weekStartDate = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final scheduleQuery = await FirebaseFirestore.instance.collection('schedules').where('weekStartDate', isEqualTo: weekStartDate).limit(1).get();

    if (scheduleQuery.docs.isNotEmpty) {
      final scheduleDocRef = scheduleQuery.docs.first.reference;
      await scheduleDocRef.update({'shifts': FieldValue.arrayRemove([shiftToDelete.toMap()])});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift deleted.'), backgroundColor: Colors.green));
      _fetchData();
    }
  }

  Future<void> _deleteDayShifts(DateTime dayToDelete) async {
    final startOfWeek = _getStartOfWeek(dayToDelete);
    final weekStartDate = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final scheduleQuery = await FirebaseFirestore.instance.collection('schedules').where('weekStartDate', isEqualTo: weekStartDate).limit(1).get();

    if (scheduleQuery.docs.isNotEmpty) {
      final scheduleDocRef = scheduleQuery.docs.first.reference;
      final scheduleData = await scheduleDocRef.get();
      final data = scheduleData.data() as Map<String, dynamic>?;

      if (data != null) {
        final allShifts = (data['shifts'] as List<dynamic>? ?? []).map((s) => Shift.fromMap(s)).toList();
        final shiftsToKeep = allShifts.where((s) => !_isSameDay(s.startTime, dayToDelete)).map((s) => s.toMap()).toList();
        await scheduleDocRef.update({'shifts': shiftsToKeep});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('All shifts for ${DateFormat.yMd().format(dayToDelete)} deleted.'), backgroundColor: Colors.green));
        _fetchData();
      }
    }
  }

  Future<bool> _showDeleteConfirmationDialog({required BuildContext context, required String title, required String content}) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
  }

  DateTime _getStartOfWeek(DateTime date) {
    final utcDate = DateTime.utc(date.year, date.month, date.day);
    return utcDate.subtract(Duration(days: utcDate.weekday - 1));
  }

  void _copySelectedShifts() {
    if (_selectedShiftsForCopy.isEmpty) return;

    final startOfWeek = _getStartOfWeek(_focusedDay);

    setState(() {
      _copiedShifts = _selectedShiftsForCopy.toList();
      _copiedWeekStartDate = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      _cancelSelectionMode();
    });

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${_copiedShifts.length} shifts.'))
    );
  }

  Future<void> _pasteWeek() async {
    if (_copiedShifts.isEmpty || _copiedWeekStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to paste. Please copy shifts first.')));
      return;
    }

    final destStartOfWeek = _getStartOfWeek(_focusedDay);

    if(isSameDay(destStartOfWeek, _copiedWeekStartDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot paste into the same week.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);

    List<Map<String, dynamic>> newShiftsToSave = [];
    for (final copiedShift in _copiedShifts) {
      final sourceStartOfWeek = _getStartOfWeek(copiedShift.startTime);
      final dayOffset = copiedShift.startTime.difference(sourceStartOfWeek).inDays;

      final newDate = destStartOfWeek.add(Duration(days: dayOffset));

      final newStartTime = DateTime(newDate.year, newDate.month, newDate.day, copiedShift.startTime.hour, copiedShift.startTime.minute);
      final newEndTime = DateTime(newDate.year, newDate.month, newDate.day, copiedShift.endTime.hour, copiedShift.endTime.minute);

      final newShift = Shift(
        userId: copiedShift.userId,
        siteId: copiedShift.siteId,
        startTime: newStartTime,
        endTime: newEndTime,
        shiftId: FirebaseFirestore.instance.collection('schedules').doc().id,
        notes: copiedShift.notes,
      );
      newShiftsToSave.add(newShift.toMap());
    }

    final scheduleQuery = await FirebaseFirestore.instance.collection('schedules').where('weekStartDate', isEqualTo: destStartOfWeek).limit(1).get();

    if (scheduleQuery.docs.isNotEmpty) {
      final scheduleDocRef = scheduleQuery.docs.first.reference;
      await scheduleDocRef.update({'shifts': FieldValue.arrayUnion(newShiftsToSave)});
    } else {
      await FirebaseFirestore.instance.collection('schedules').add({
        'weekStartDate': destStartOfWeek,
        'shifts': newShiftsToSave,
        'published': true,
        'siteId': newShiftsToSave.first['siteId'],
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pasted ${newShiftsToSave.length} shifts to week of ${DateFormat.yMd().format(destStartOfWeek)}.'), backgroundColor: Colors.green)
    );

    setState(() {
      _copiedShifts.clear();
    });

    await _fetchData();
  }

  void _startSelectionMode(Shift shift) {
    setState(() {
      _isSelectionMode = true;
      _selectedShiftsForCopy.add(shift);
    });
  }

  void _toggleSelection(Shift shift) {
    setState(() {
      if (_selectedShiftsForCopy.contains(shift)) {
        _selectedShiftsForCopy.remove(shift);
      } else {
        _selectedShiftsForCopy.add(shift);
      }
      if (_selectedShiftsForCopy.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _cancelSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedShiftsForCopy.clear();
    });
  }

  List<Shift> _getShiftsForDay(DateTime day) {
    final utcDay = DateTime.utc(day.year, day.month, day.day);
    return _allShiftsByDay[utcDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _isSelectionMode = false;
        _selectedShiftsForCopy.clear();
      });
      _selectedShifts.value = _getShiftsForDay(selectedDay);
    }
  }

  void _navigateAndRefresh(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page))
        .then((_) => _fetchData());
  }

  AppBar _buildDefaultAppBar() {
    return AppBar(
      title: const Text('Manage Team Schedule'),
      actions: [
        if (_selectedShifts.value.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final confirmed = await _showDeleteConfirmationDialog(
                context: context,
                title: 'Delete All Shifts?',
                content: 'Are you sure you want to delete all ${_selectedShifts.value.length} shifts for ${DateFormat.yMd().format(_selectedDay!)}?',
              );
              if (confirmed) {
                _deleteDayShifts(_selectedDay!);
              }
            },
            tooltip: 'Delete all shifts for selected day',
          ),
        if (_copiedShifts.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.paste),
            onPressed: _pasteWeek,
            tooltip: 'Paste Copied Shifts',
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _fetchData,
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _cancelSelectionMode,
      ),
      title: Text('${_selectedShiftsForCopy.length} Selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.copy),
          onPressed: _copySelectedShifts,
          tooltip: 'Copy Selected Shifts',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          TableCalendar<Shift>(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: _onDaySelected,
            eventLoader: _getShiftsForDay,
            calendarFormat: _calendarFormat,
            onFormatChanged: (format) { if (_calendarFormat != format) setState(() => _calendarFormat = format); },
            onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
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
                  return const Center(child: Text('No shifts scheduled for this day.'));
                }
                return ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final shift = value[index];
                    final employeeName = _userNames[shift.userId] ?? shift.userId;
                    final siteName = _siteNames[shift.siteId] ?? 'Unknown Site';
                    final siteColor = _siteColors[shift.siteId] ?? Colors.grey;
                    final isSelected = _selectedShiftsForCopy.contains(shift);

                    final bool isPastShift = shift.startTime.isBefore(DateTime.now());

                    return Opacity(
                      opacity: isPastShift ? 0.6 : 1.0,
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withOpacity(0.2),
                          leading: _isSelectionMode
                              ? Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank)
                              : CircleAvatar(backgroundColor: siteColor, radius: 10),
                          title: Text(employeeName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('$siteName\n${DateFormat('h:mm a').format(shift.startTime)} - ${DateFormat('h:mm a').format(shift.endTime)}'),
                          isThreeLine: true,
                          trailing: isPastShift || _isSelectionMode
                              ? null
                              : IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final confirmed = await _showDeleteConfirmationDialog(
                                context: context,
                                title: 'Delete Shift?',
                                content: 'Are you sure you want to delete this shift for $employeeName?',
                              );
                              if (confirmed) {
                                _deleteSingleShift(shift);
                              }
                            },
                          ),
                          onLongPress: isPastShift || _isSelectionMode ? null : () => _startSelectionMode(shift),
                          onTap: isPastShift ? null : () {
                            if (_isSelectionMode) {
                              _toggleSelection(shift);
                            } else {
                              _navigateAndRefresh(AddShiftPage(shiftToEdit: shift));
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode ? null : FloatingActionButton(
        onPressed: () { if (_selectedDay != null) _navigateAndRefresh(AddShiftPage(initialDate: _selectedDay)); },
        child: const Icon(Icons.add),
        tooltip: 'Add Shift on Selected Day',
      ),
    );
  }
}