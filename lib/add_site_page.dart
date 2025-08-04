// lib/add_site_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'models/site_model.dart';

// Helper class to manage the controllers for each preset row
class _PresetControllers {
  final TextEditingController name;
  final TextEditingController startTime;
  final TextEditingController endTime;

  _PresetControllers({String name = '', String startTime = '', String endTime = ''})
      : name = TextEditingController(text: name),
        startTime = TextEditingController(text: startTime),
        endTime = TextEditingController(text: endTime);

  void dispose() {
    name.dispose();
    startTime.dispose();
    endTime.dispose();
  }
}


class AddSitePage extends StatefulWidget {
  final Site? siteToEdit;
  const AddSitePage({super.key, this.siteToEdit});

  @override
  State<AddSitePage> createState() => _AddSitePageState();
}

class _AddSitePageState extends State<AddSitePage> {
  final _formKey = GlobalKey<FormState>();
  final _siteNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _siteGroupController = TextEditingController();
  final _projectedHoursController = TextEditingController();
  bool _isLoading = false;

  Color _currentColor = Colors.grey;
  List<_PresetControllers> _presetControllers = [];

  List<String> _existingSiteGroups = [];

  bool get _isEditing => widget.siteToEdit != null;

  @override
  void initState() {
    super.initState();
    _fetchExistingSiteGroups();

    if (_isEditing) {
      final site = widget.siteToEdit!;
      _siteNameController.text = site.siteName;
      _addressController.text = site.address;
      _siteGroupController.text = site.siteGroup;
      _projectedHoursController.text = site.projectedWeeklyHours.toString();
      _currentColor = _colorFromHex(site.siteColor);

      for (var preset in site.presetShifts) {
        _presetControllers.add(_PresetControllers(
          name: preset['name']!,
          startTime: preset['startTime']!,
          endTime: preset['endTime']!,
        ));
      }
    }
  }

  Future<void> _fetchExistingSiteGroups() async {
    try {
      final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
      final groups = sitesSnapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['siteGroup'] as String?)
          .whereType<String>()
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList();
      if (mounted) {
        setState(() {
          _existingSiteGroups = groups;
        });
      }
    } catch (e) {
      print("Error fetching site groups: $e");
    }
  }

  @override
  void dispose() {
    _siteNameController.dispose();
    _addressController.dispose();
    _siteGroupController.dispose();
    _projectedHoursController.dispose();
    for (var controller in _presetControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addPreset() {
    setState(() {
      _presetControllers.add(_PresetControllers());
    });
  }

  void _removePreset(int index) {
    setState(() {
      _presetControllers[index].dispose();
      _presetControllers.removeAt(index);
    });
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      final formattedTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      controller.text = formattedTime;
    }
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _currentColor,
            onColorChanged: (color) => setState(() => _currentColor = color),
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: <Widget>[
          ElevatedButton(child: const Text('Done'), onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  Future<void> _saveSite() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final List<Map<String, String>> presetsToSave = _presetControllers
          .map((controllers) => {'name': controllers.name.text.trim(), 'startTime': controllers.startTime.text, 'endTime': controllers.endTime.text})
          .toList();

      final siteData = {
        'siteName': _siteNameController.text.trim(),
        'address': _addressController.text.trim(),
        'siteGroup': _siteGroupController.text.trim(),
        'projectedWeeklyHours': double.tryParse(_projectedHoursController.text) ?? 0,
        'siteColor': _colorToHex(_currentColor),
        'presetShifts': presetsToSave,
      };

      if (_isEditing) {
        await FirebaseFirestore.instance.collection('sites').doc(widget.siteToEdit!.id).update(siteData);
      } else {
        await FirebaseFirestore.instance.collection('sites').add(siteData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Site ${ _isEditing ? 'updated' : 'added' } successfully!')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save site: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Site' : 'Add New Site'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(controller: _siteNameController, decoration: const InputDecoration(labelText: 'Site Name'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
              const SizedBox(height: 16),

              // --- CORRECTED Autocomplete field for Site Group ---
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _siteGroupController.text),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  return _existingSiteGroups.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  // When user selects an item, update our controller
                  _siteGroupController.text = selection;
                },
                fieldViewBuilder: (context, fieldTextEditingController, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: fieldTextEditingController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Site Group (type to search or add new)'),
                    // This is the key fix: update our main controller whenever the user types
                    onChanged: (value) {
                      _siteGroupController.text = value;
                    },
                  );
                },
              ),
              // --- END CORRECTION ---

              const SizedBox(height: 16),
              TextFormField(controller: _projectedHoursController, decoration: const InputDecoration(labelText: 'Projected Weekly Hours'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Site Color'),
                trailing: Container(width: 40, height: 40, decoration: BoxDecoration(color: _currentColor, shape: BoxShape.circle, border: Border.all(color: Colors.grey))),
                onTap: _pickColor,
              ),
              const Divider(height: 32),
              Text('Preset Shifts', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_presetControllers.isEmpty) const Text('No presets defined.', style: TextStyle(color: Colors.grey)),
              ..._presetControllers.asMap().entries.map((entry) {
                int index = entry.key;
                _PresetControllers controllers = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        TextFormField(controller: controllers.name, decoration: const InputDecoration(labelText: 'Preset Name (e.g., Opening)')),
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: controllers.startTime, decoration: const InputDecoration(labelText: 'Start Time'), onTap: () => _pickTime(controllers.startTime), readOnly: true)),
                            const SizedBox(width: 8),
                            Expanded(child: TextFormField(controller: controllers.endTime, decoration: const InputDecoration(labelText: 'End Time'), onTap: () => _pickTime(controllers.endTime), readOnly: true)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removePreset(index)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add Preset Shift'), onPressed: _addPreset),
              const SizedBox(height: 32),
              if (_isLoading) const Center(child: CircularProgressIndicator()) else ElevatedButton(onPressed: _saveSite, child: const Text('Save Site')),
            ],
          ),
        ),
      ),
    );
  }

  String _colorToHex(Color color) => color.value.toRadixString(16).substring(2).toUpperCase();
  Color _colorFromHex(String hex) {
    hex = hex.replaceAll("#", "");
    if(hex.length == 6) {
      hex = "FF$hex";
    }
    return Color(int.parse(hex, radix: 16));
  }
}