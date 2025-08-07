// lib/edit_user_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'models/user_profile.dart';
import 'models/site_model.dart';

class EditUserPage extends StatefulWidget {
  final UserProfile userProfile;
  const EditUserPage({super.key, required this.userProfile});

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedRole;
  final List<String> _roles = ['staff', 'supervisor', 'admin'];

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _quotaController;
  late final TextEditingController _dailyHoursController;
  late final TextEditingController _payrollIdController;
  late final TextEditingController _siteClockInNumberController;
  late final TextEditingController _hourlyRateController;
  late final TextEditingController _deductionController;
  late final TextEditingController _loanController;
  late final TextEditingController _pensionController;
  late final TextEditingController _niNumberController;
  late final TextEditingController _niCategoryController;
  late final TextEditingController _taxCodeController;
  late final TextEditingController _paymentPeriodController;

  List<Site> _siteList = [];
  List<UserProfile> _supervisorList = [];
  List<UserProfile> _adminList = [];

  List<String> _selectedSiteIds = [];
  String? _selectedSupervisorId;
  String? _selectedAdminId;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.userProfile.role;
    _firstNameController = TextEditingController(text: widget.userProfile.firstName);
    _lastNameController = TextEditingController(text: widget.userProfile.lastName);
    _phoneController = TextEditingController(text: widget.userProfile.phoneNumber);
    _quotaController = TextEditingController(text: widget.userProfile.timeOffQuota.toString());
    _dailyHoursController = TextEditingController(text: widget.userProfile.defaultDailyHours.toString());
    _payrollIdController = TextEditingController(text: widget.userProfile.payrollId ?? '');
    _siteClockInNumberController = TextEditingController(text: widget.userProfile.siteClockInNumber ?? '');
    _hourlyRateController = TextEditingController(text: widget.userProfile.hourlyRate.toString());
    _deductionController = TextEditingController(text: widget.userProfile.standardDeduction.toString());
    _loanController = TextEditingController(text: widget.userProfile.loanRepayment.toString());
    _pensionController = TextEditingController(text: widget.userProfile.pensionPercentage.toString());
    _niNumberController = TextEditingController(text: widget.userProfile.niNumber ?? '');
    _niCategoryController = TextEditingController(text: widget.userProfile.niCategory ?? '');
    _taxCodeController = TextEditingController(text: widget.userProfile.taxCode ?? '');
    _paymentPeriodController = TextEditingController(text: widget.userProfile.paymentPeriod ?? '');

    _selectedSiteIds = List<String>.from(widget.userProfile.assignedSiteIds);
    _selectedSupervisorId = widget.userProfile.directSupervisorId;
    _selectedAdminId = widget.userProfile.directAdminId;

    _fetchDropdownData();
  }

  Future<void> _fetchDropdownData() async {
    try {
      final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
      final supervisorSnapshot = await FirebaseFirestore.instance.collection('users').where('role', whereIn: ['supervisor', 'admin']).get();
      final adminSnapshot = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'admin').get();

      if (mounted) {
        setState(() {
          _siteList = sitesSnapshot.docs.map((doc) => Site.fromFirestore(doc)).toList();
          _supervisorList = supervisorSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
          _adminList = adminSnapshot.docs.map((doc) => UserProfile.fromFirestore(doc)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load data: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _quotaController.dispose();
    _dailyHoursController.dispose();
    _payrollIdController.dispose();
    _siteClockInNumberController.dispose();
    _hourlyRateController.dispose();
    _deductionController.dispose();
    _loanController.dispose();
    _pensionController.dispose();
    _niNumberController.dispose();
    _niCategoryController.dispose();
    _taxCodeController.dispose();
    _paymentPeriodController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance.collection('users').doc(widget.userProfile.uid).update({
          'role': _selectedRole,
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'phoneNumber': _phoneController.text.trim(),
          'timeOffQuota': double.tryParse(_quotaController.text) ?? 0.0,
          'defaultDailyHours': double.tryParse(_dailyHoursController.text) ?? 8.0,
          'payrollId': _payrollIdController.text.trim(),
          'siteClockInNumber': _siteClockInNumberController.text.trim(),
          'assignedSiteIds': _selectedSiteIds,
          'directSupervisorId': _selectedSupervisorId,
          'directAdminId': _selectedAdminId,
          'hourlyRate': double.tryParse(_hourlyRateController.text) ?? 0.0,
          'standardDeduction': double.tryParse(_deductionController.text) ?? 0.0,
          'loanRepayment': double.tryParse(_loanController.text) ?? 0.0,
          'pensionPercentage': double.tryParse(_pensionController.text) ?? 0.0,
          'niNumber': _niNumberController.text.trim(),
          'niCategory': _niCategoryController.text.trim(),
          'taxCode': _taxCodeController.text.trim(),
          'paymentPeriod': _paymentPeriodController.text.trim(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User updated successfully!')));
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save user: $e'), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit User')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // --- Section 1: General Information ---
            Text('General Information', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(initialValue: widget.userProfile.email, decoration: const InputDecoration(labelText: 'Email (read-only)'), readOnly: true),
            const SizedBox(height: 16),
            TextFormField(controller: _firstNameController, decoration: const InputDecoration(labelText: 'First Name')),
            const SizedBox(height: 16),
            TextFormField(controller: _lastNameController, decoration: const InputDecoration(labelText: 'Last Name')),
            const SizedBox(height: 16),
            TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            TextFormField(controller: _siteClockInNumberController, decoration: const InputDecoration(labelText: 'Site Clock-in Number (Optional)'), keyboardType: TextInputType.number),

            // --- Section 2: Roles & Assignments ---
            const Divider(height: 32),
            Text('Roles & Assignments', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            MultiSelectDialogField<String>(
              items: _siteList.map((site) => MultiSelectItem<String>(site.id, site.siteName)).toList(),
              initialValue: _selectedSiteIds,
              title: const Text("Select Sites"),
              buttonText: const Text("Assigned Work Sites"),
              onConfirm: (values) => setState(() => _selectedSiteIds = values),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey, width: 1), borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedSupervisorId,
              hint: const Text('Select Direct Supervisor'),
              items: [ const DropdownMenuItem<String>(value: null, child: Text('None')), ..._supervisorList.map((user) => DropdownMenuItem(value: user.uid, child: Text(user.fullName))) ],
              onChanged: (value) => setState(() => _selectedSupervisorId = value),
              decoration: const InputDecoration(labelText: 'Direct Supervisor'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedAdminId,
              hint: const Text('Select Direct Admin'),
              items: [ const DropdownMenuItem<String>(value: null, child: Text('None')), ..._adminList.map((user) => DropdownMenuItem(value: user.uid, child: Text(user.fullName))) ],
              onChanged: (value) => setState(() => _selectedAdminId = value),
              decoration: const InputDecoration(labelText: 'Direct Admin'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(labelText: 'Role'),
              items: _roles.map((String role) => DropdownMenuItem<String>(value: role, child: Text(role))).toList(),
              onChanged: (String? newValue) => setState(() => _selectedRole = newValue!),
            ),

            // --- Section 3: Payroll Information ---
            const Divider(height: 32),
            Text('Payroll Information', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(controller: _payrollIdController, decoration: const InputDecoration(labelText: 'Payroll ID (Optional)')),
            const SizedBox(height: 16),
            TextFormField(controller: _taxCodeController, decoration: const InputDecoration(labelText: 'Tax Code')),
            const SizedBox(height: 16),
            TextFormField(controller: _niNumberController, decoration: const InputDecoration(labelText: 'NI Number')),
            const SizedBox(height: 16),
            TextFormField(controller: _niCategoryController, decoration: const InputDecoration(labelText: 'NI Category')),
            const SizedBox(height: 16),
            TextFormField(controller: _paymentPeriodController, decoration: const InputDecoration(labelText: 'Payment Period (e.g., Weekly)')),
            const SizedBox(height: 16),
            TextFormField(controller: _hourlyRateController, decoration: const InputDecoration(labelText: 'Hourly Rate (£)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 16),
            TextFormField(controller: _pensionController, decoration: const InputDecoration(labelText: 'Pension Contribution (%)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 16),
            TextFormField(controller: _deductionController, decoration: const InputDecoration(labelText: 'Standard Deduction (£)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 16),
            TextFormField(controller: _loanController, decoration: const InputDecoration(labelText: 'Loan Repayment (£)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 16),
            TextFormField(controller: _quotaController, decoration: const InputDecoration(labelText: 'Time Off Quota (in hours)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 16),
            TextFormField(controller: _dailyHoursController, decoration: const InputDecoration(labelText: 'Default Hours Per Day'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

            const SizedBox(height: 32),
            if (_isLoading) const Center(child: CircularProgressIndicator()) else ElevatedButton(onPressed: _saveUser, child: const Text('Save Changes')),
          ],
        ),
      ),
    );
  }
}