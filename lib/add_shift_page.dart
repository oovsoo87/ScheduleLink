// lib/add_shift_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz; // NEW IMPORT
import 'models/shift_model.dart';
import 'models/user_profile.dart';
import 'models/site_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddShiftPage extends StatefulWidget {
  final Shift? shiftToEdit;
  final DateTime? initialDate;

  const AddShiftPage({super.key, this.shiftToEdit, this.initialDate});

  @override
  State<AddShiftPage> createState() => _AddShiftPageState();
}

class _AddShiftPageState extends State<AddShiftPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _notesController;

  List<UserProfile> _staffList = [];
  List<Site> _siteList = [];
  List<UserProfile> _filteredStaffList = [];
  UserProfile? _selectedStaff;
  Site? _selectedSite;
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = true;
  bool _isLocked = false;
  int? _selectedPresetIndex;

  bool get _isEditing => widget.shiftToEdit != null;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _notesController = TextEditingController();
    _fetchDataAndPopulateForm();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _filterStaffForSite(Site? site) {
    if (site == null) {
      setState(() {
        _filteredStaffList = [];
        _selectedStaff = null;
      });
      return;
    }
    final filteredList = _staffList.where((staff) => staff.assignedSiteIds.contains(site.id)).toList();
    setState(() {
      _filteredStaffList = filteredList;
      if (_selectedStaff != null && !filteredList.any((staff) => staff.uid == _selectedStaff!.uid)) {
        _selectedStaff = null;
      }
    });
  }

  Future<void> _fetchDataAndPopulateForm() async {
    try {
      final staffFuture = FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();
      final sitesFuture = FirebaseFirestore.instance.collection('sites').get();
      final results = await Future.wait([staffFuture, sitesFuture]);
      final staffSnapshot = results[0] as QuerySnapshot;
      final sitesSnapshot = results[1] as QuerySnapshot;
      final staff = staffSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
      final sites = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();

      if (mounted) {
        setState(() {
          _staffList = staff;
          _siteList = sites;
          if (_isEditing) {
            final shift = widget.shiftToEdit!;
            _selectedDate = shift.startTime;
            _startTime = TimeOfDay.fromDateTime(shift.startTime);
            _endTime = TimeOfDay.fromDateTime(shift.endTime);
            _notesController.text = shift.notes ?? '';

            if (_siteList.isNotEmpty && shift.siteId.isNotEmpty) {
              try { _selectedSite = _siteList.firstWhere((site) => site.id == shift.siteId); } catch (e) { _selectedSite = null; }
            }
            _filterStaffForSite(_selectedSite);
            if (_filteredStaffList.isNotEmpty) {
              try { _selectedStaff = _filteredStaffList.firstWhere((staffMember) => staffMember.uid == shift.userId); } catch (e) { _selectedStaff = null; }
            }
            if (widget.shiftToEdit!.startTime.isBefore(DateTime.now())) {
              _isLocked = true;
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveShift() async {
    if (!_formKey.currentState!.validate() || _selectedStaff == null || _selectedSite == null || _selectedDate == null || _startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    // --- THIS IS THE FIX ---
    // Create timezone-aware TZDateTime objects instead of standard DateTime objects.
    final location = tz.getLocation('Europe/London');
    final startDateTime = tz.TZDateTime(location, _selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _startTime!.hour, _startTime!.minute);
    final endDateTime = tz.TZDateTime(location, _selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _endTime!.hour, _endTime!.minute);

    if (!_isEditing && startDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Cannot create a shift that starts in the past.'), backgroundColor: Colors.red));
      return;
    }
    if (endDateTime.isBefore(startDateTime) || endDateTime.isAtSameMomentAs(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: End time must be after start time.'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    final shiftToSave = Shift(
      userId: _selectedStaff!.uid,
      startTime: startDateTime, // Pass the TZDateTime
      endTime: endDateTime,   // Pass the TZDateTime
      shiftId: _isEditing ? widget.shiftToEdit!.shiftId : FirebaseFirestore.instance.collection('schedules').doc().id,
      siteId: _selectedSite!.id,
      notes: _notesController.text.trim(),
    );
    // --- END OF FIX ---

    final startOfWeek = _selectedDate!.subtract(Duration(days: _selectedDate!.weekday - 1));
    final weekStartDate = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final scheduleQuery = await FirebaseFirestore.instance.collection('schedules').where('weekStartDate', isEqualTo: weekStartDate).limit(1).get();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (scheduleQuery.docs.isNotEmpty) {
      final scheduleDocRef = scheduleQuery.docs.first.reference;
      if (_isEditing) {
        final originalShiftMap = widget.shiftToEdit!.toMap();
        await scheduleDocRef.update({'shifts': FieldValue.arrayRemove([originalShiftMap])});
      }
      await scheduleDocRef.update({'shifts': FieldValue.arrayUnion([shiftToSave.toMap()])});
    } else {
      await FirebaseFirestore.instance.collection('schedules').add({
        'weekStartDate': weekStartDate, 'shifts': [shiftToSave.toMap()], 'published': true, 'siteId': _selectedSite!.id,
      });
    }

    FirebaseFirestore.instance.collection('notifications').add({
      'userId': _selectedStaff!.uid, 'title': _isEditing ? 'Shift Updated' : 'New Shift Assigned',
      'body': 'Your shift at ${_selectedSite!.siteName} on ${DateFormat.yMd().format(startDateTime)} has been updated.',
      'timestamp': Timestamp.now(), 'isRead': false, 'createdBy': currentUser.uid,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Shift ${ _isEditing ? 'updated' : 'added' } successfully!')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? (_isLocked ? 'View Shift' : 'Edit Shift') : 'Add New Shift')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (_isLocked)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [ Icon(Icons.lock_outline, color: Colors.grey), SizedBox(width: 8), Expanded(child: Text('This shift is in the past and cannot be edited.'))]),
              ),
            DropdownButtonFormField<Site>(
              value: _selectedSite,
              hint: const Text('Select Site'),
              onChanged: _isLocked ? null : (Site? newValue) {
                setState(() {
                  _selectedSite = newValue;
                  _selectedPresetIndex = null;
                  _filterStaffForSite(newValue);
                });
              },
              items: _siteList.map((site) => DropdownMenuItem<Site>(value: site, child: Text(site.siteName))).toList(),
              validator: (value) => value == null ? 'Please select a site' : null,
              decoration: const InputDecoration(labelText: 'Work Site'),
            ),
            if (_selectedSite != null && _selectedSite!.presetShifts.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedPresetIndex,
                hint: const Text('Select a Preset Shift (Optional)'),
                onChanged: _isLocked ? null : (int? selectedIndex) {
                  if (selectedIndex == null) return;
                  final preset = _selectedSite!.presetShifts[selectedIndex];
                  final startTimeString = preset['startTime'];
                  final endTimeString = preset['endTime'];
                  if (startTimeString != null && endTimeString != null) {
                    try {
                      final startParts = startTimeString.split(':').map(int.parse).toList();
                      final endParts = endTimeString.split(':').map(int.parse).toList();
                      setState(() {
                        _selectedPresetIndex = selectedIndex;
                        _startTime = TimeOfDay(hour: startParts[0], minute: startParts[1]);
                        _endTime = TimeOfDay(hour: endParts[0], minute: endParts[1]);
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not parse preset time.'), backgroundColor: Colors.red));
                    }
                  }
                },
                items: _selectedSite!.presetShifts.asMap().entries.map((entry) {
                  int index = entry.key;
                  Map<String, String> preset = entry.value;
                  return DropdownMenuItem<int>(value: index, child: Text(preset['name']!));
                }).toList(),
                decoration: const InputDecoration(labelText: 'Preset Shift'),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<UserProfile>(
              value: _selectedStaff,
              hint: Text(_selectedSite == null ? 'Please select a site first' : 'Select Staff Member'),
              onChanged: _isLocked || _selectedSite == null ? null : (UserProfile? newValue) => setState(() => _selectedStaff = newValue),
              items: _filteredStaffList.map((user) => DropdownMenuItem<UserProfile>(value: user, child: Text(user.fullName))).toList(),
              validator: (value) => value == null ? 'Please select a staff member' : null,
              decoration: InputDecoration(
                labelText: 'Staff Member',
                filled: _selectedSite == null,
                fillColor: _selectedSite == null ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : null,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Shift Date'),
              subtitle: Text(_selectedDate == null ? 'Not set' : DateFormat.yMMMMd().format(_selectedDate!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _isLocked ? null : () async {
                final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day);
                var selectableFirstDate = today;
                if (_isEditing && widget.shiftToEdit!.startTime.isBefore(today)) {
                  selectableFirstDate = DateTime(widget.shiftToEdit!.startTime.year, widget.shiftToEdit!.startTime.month, widget.shiftToEdit!.startTime.day);
                }
                final date = await showDatePicker(context: context, initialDate: _selectedDate ?? today, firstDate: selectableFirstDate, lastDate: today.add(const Duration(days: 365)));
                if (date != null) setState(() => _selectedDate = date);
              },
            ),
            ListTile(
              title: const Text('Start Time'),
              subtitle: Text(_startTime == null ? 'Not set' : _startTime!.format(context)),
              trailing: const Icon(Icons.access_time),
              onTap: _isLocked ? null : () async { final time = await showTimePicker(context: context, initialTime: _startTime ?? TimeOfDay.now()); if (time != null) setState(() => _startTime = time); },
            ),
            ListTile(
              title: const Text('End Time'),
              subtitle: Text(_endTime == null ? 'Not set' : _endTime!.format(context)),
              trailing: const Icon(Icons.access_time),
              onTap: _isLocked ? null : () async { final time = await showTimePicker(context: context, initialTime: _endTime ?? TimeOfDay.now()); if (time != null) setState(() => _endTime = time); },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Shift Notes (Optional)', border: OutlineInputBorder(), hintText: 'Add any important details...'),
              maxLines: 3,
              readOnly: _isLocked,
            ),
            const SizedBox(height: 32),
            if (!_isLocked) ElevatedButton(onPressed: _isLoading ? null : _saveShift, child: const Text('Save Shift')),
          ],
        ),
      ),
    );
  }
}