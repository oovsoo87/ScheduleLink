// lib/manage_schedule_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models/shift_model.dart';
import 'models/user_profile.dart';
import 'models/site_model.dart';
import 'add_shift_page.dart';

class ManageSchedulePage extends StatefulWidget {
  final UserProfile userProfile;
  const ManageSchedulePage({super.key, required this.userProfile});

  @override
  State<ManageSchedulePage> createState() => _ManageSchedulePageState();
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ManageSchedulePageState extends State<ManageSchedulePage> {
  late final ValueNotifier<List<Shift>> _selectedShifts;

  Map<DateTime, List<Shift>> _allShiftsByDay = {};
  List<UserProfile> _allStaff = [];
  List<UserProfile> _allManagers = [];

  Map<DateTime, List<Shift>> _filteredShiftsByDay = {};

  Map<String, String> _userNames = {};
  Map<String, String> _siteNames = {};
  Map<String, Color> _siteColors = {};

  List<Shift> _copiedShifts = [];
  bool _isSelectionMode = false;
  Set<Shift> _selectedShiftsForCopy = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.week;
  bool _isLoading = true;

  dynamic _selectedFilter;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedShifts = ValueNotifier([]);
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

      final userProfiles = usersSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
      _userNames = {for (var user in userProfiles) user.uid: user.fullName};

      final sites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
      _siteNames = {for (var site in sites) site.id: site.siteName};
      _siteColors = {for (var site in sites) site.id: _colorFromHex(site.siteColor)};

      Map<DateTime, List<Shift>> shiftsMap = {};
      for (var scheduleDoc in scheduleSnapshot.docs) {
        final data = scheduleDoc.data() as Map<String, dynamic>;
        final shiftsData = data['shifts'] as List<dynamic>? ?? [];

        for (var shiftData in shiftsData) {
          final shift = Shift.fromMap(shiftData);
          final day = DateTime.utc(shift.startTime.year, shift.startTime.month, shift.startTime.day);
          shiftsMap.putIfAbsent(day, () => []).add(shift);
        }
      }

      if (mounted) {
        setState(() {
          _allStaff = userProfiles;
          _allManagers = userProfiles.where((u) => u.role == 'supervisor' || u.role == 'admin').toList();
          _allShiftsByDay = shiftsMap;
          _initializeFilter();
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

  void _initializeFilter() {
    if (widget.userProfile.role == 'supervisor') {
      _selectedFilter = _allManagers.firstWhere((m) => m.uid == widget.userProfile.uid, orElse: () => widget.userProfile);
    }
    _applyFilter();
  }

  void _applyFilter() {
    Map<DateTime, List<Shift>> newFilteredMap = {};

    if (_selectedFilter == null) {
      newFilteredMap = Map.from(_allShiftsByDay);
    } else if (_selectedFilter is UserProfile) {
      final manager = _selectedFilter as UserProfile;
      final staffIdsToShow = _allStaff
          .where((user) => user.directSupervisorId == manager.uid || user.uid == manager.uid)
          .map((user) => user.uid)
          .toSet();

      _allShiftsByDay.forEach((day, shifts) {
        final filteredShifts = shifts.where((shift) => staffIdsToShow.contains(shift.userId)).toList();
        if(filteredShifts.isNotEmpty) {
          newFilteredMap[day] = filteredShifts;
        }
      });
    }

    setState(() {
      _filteredShiftsByDay = newFilteredMap;
      if(_selectedDay != null) {
        _selectedShifts.value = _getShiftsForDay(_selectedDay!);
      }
    });
  }

  List<Shift> _getShiftsForDay(DateTime day) {
    final utcDay = DateTime.utc(day.year, day.month, day.day);
    return _filteredShiftsByDay[utcDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _isSelectionMode = false;
        _selectedShiftsForCopy.clear();
      });
    }
    _selectedShifts.value = _getShiftsForDay(selectedDay);
  }

  Future<void> _deleteSingleShift(Shift shiftToDelete) async {
    final startOfWeek = _getStartOfWeek(shiftToDelete.startTime);
    final weekStartDate = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final scheduleQuery = await FirebaseFirestore.instance.collection('schedules').where('weekStartDate', isEqualTo: weekStartDate).limit(1).get();

    if (scheduleQuery.docs.isNotEmpty) {
      final scheduleDocRef = scheduleQuery.docs.first.reference;
      await scheduleDocRef.update({'shifts': FieldValue.arrayRemove([shiftToDelete.toMap()])});
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift deleted.'), backgroundColor: Colors.green));
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
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('All shifts for ${DateFormat.yMd().format(dayToDelete)} deleted.'), backgroundColor: Colors.green));
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
    setState(() {
      _copiedShifts = _selectedShiftsForCopy.toList();
      _cancelSelectionMode();
    });

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${_copiedShifts.length} shifts.'))
    );
  }

  Future<void> _pasteWeek() async {
    if (_copiedShifts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to paste. Please copy shifts first.')));
      return;
    }
    if (_selectedDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a day to paste the shifts onto.')));
      return;
    }

    setState(() => _isLoading = true);

    final DateTime destDate = _selectedDay!;
    final destStartOfWeek = _getStartOfWeek(destDate);

    final location = tz.getLocation('Europe/London');
    List<Map<String, dynamic>> newShiftsToSave = [];
    for (final copiedShift in _copiedShifts) {
      final newStartTime = tz.TZDateTime(location, destDate.year, destDate.month, destDate.day, copiedShift.startTime.hour, copiedShift.startTime.minute);
      final newEndTime = tz.TZDateTime(location, destDate.year, destDate.month, destDate.day, copiedShift.endTime.hour, copiedShift.endTime.minute);

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

    if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pasted ${newShiftsToSave.length} shifts to ${DateFormat.yMd().format(destDate)}.'), backgroundColor: Colors.green)
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
    final bool canFilter = widget.userProfile.role == 'admin';
    return Scaffold(
      appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (canFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: DropdownButtonFormField<dynamic>(
                value: _selectedFilter,
                isExpanded: true,
                hint: const Text('Filter by Team...'),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<dynamic>(value: null, child: Text('All Staff', style: TextStyle(fontWeight: FontWeight.bold))),
                  ..._allManagers.map((manager) => DropdownMenuItem<dynamic>(value: manager, child: Text('Team: ${manager.fullName}'))),
                ],
                onChanged: (newValue) { setState(() { _selectedFilter = newValue; }); _applyFilter(); },
              ),
            ),

          TableCalendar<Shift>(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            startingDayOfWeek: StartingDayOfWeek.monday,
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
                    width: 7, height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _siteColors[shift.siteId] ?? Colors.grey),
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
                if (value.isEmpty) { return const Center(child: Text('No shifts scheduled for this day.')); }
                return ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final shift = value[index];
                    final employeeName = _userNames[shift.userId] ?? shift.userId;
                    final siteName = _siteNames[shift.siteId] ?? 'Unknown Site';
                    final siteColor = _siteColors[shift.siteId] ?? Colors.grey;
                    final isSelected = _selectedShiftsForCopy.contains(shift);
                    final bool isPastShift = shift.startTime.isBefore(DateTime.now());
                    final String startTime = DateFormat('h:mm a').format(shift.startTime);
                    final String endTime = DateFormat('h:mm a').format(shift.endTime);

                    return Opacity(
                      opacity: isPastShift ? 0.6 : 1.0,
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withOpacity(0.2),
                          leading: _isSelectionMode ? Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank) : CircleAvatar(backgroundColor: siteColor, radius: 10),
                          title: Text(employeeName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('$siteName\n$startTime - $endTime'),
                          isThreeLine: true,
                          trailing: isPastShift || _isSelectionMode ? null : IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final confirmed = await _showDeleteConfirmationDialog(context: context, title: 'Delete Shift?', content: 'Are you sure you want to delete this shift for $employeeName?');
                              if (confirmed) { _deleteSingleShift(shift); }
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