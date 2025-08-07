// lib/about_page.dart

import 'package:flutter/material.dart';
import 'package:schedulelink/models/user_profile.dart';

class AboutPage extends StatelessWidget {
  final UserProfile userProfile;
  const AboutPage({super.key, required this.userProfile});

  @override
  Widget build(BuildContext context) {
    // Helper function to build a styled section header
    Widget buildHeader(String title) {
      return Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    // Helper function to build a content paragraph
    Widget buildParagraph(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    // Function to get the correct manual based on user role
    List<Widget> getManualWidgets() {
      switch (userProfile.role) {
        case 'staff':
          return [
            buildHeader('ScheduleLink Manual for Staff'),
            buildParagraph('Welcome to ScheduleLink! This guide will walk you through the core features of the app to help you view your schedule, track your time, and stay informed.'),
            buildHeader('Core Features'),
            buildParagraph('• Schedule: View your personal work calendar. The week starts on Monday, and days you work have colored dots.'),
            buildParagraph('• Clocker: Clock in and out for your shifts. Your location may be verified to ensure you are at the worksite.'),
            buildParagraph('• Time Off: Request time off and view your remaining balance. View your request history in dd/MM/yyyy format.'),
            buildParagraph('• Notifications: Tap the Bell Icon on the schedule page to see messages from managers.'),
            buildParagraph('• Settings: Change your password, view your account details, and toggle dark mode.'),
          ];
        case 'supervisor':
          return [
            buildHeader('ScheduleLink Manual for Supervisors'),
            buildParagraph('This guide covers your core features and the tools for managing your team.'),
            buildHeader('Core Features'),
            buildParagraph('You have access to all standard staff features: Schedule, Clocker, Time Off, Notifications, and Settings.'),
            buildHeader('Team Schedule Management'),
            buildParagraph('From your "My Schedule" page, tap the Edit Calendar Icon. The view is automatically filtered to your assigned team and you will not see a dropdown menu.'),
            buildParagraph('• Add/Edit/Delete Shifts: Tap the (+) button to add shifts, or tap an existing shift to edit or delete it.'),
            buildParagraph('• Copy & Paste: Long-press a shift to enter selection mode, copy multiple shifts, then navigate to a new day and paste them.'),
          ];
        case 'admin':
          return [
            buildHeader('ScheduleLink Manual for Admins'),
            buildParagraph('This is a comprehensive overview of all features in the application.'),
            buildHeader('Core & Supervisor Features'),
            buildParagraph('You have access to all Staff and Supervisor features. In the "Manage Team Schedule" page, you will see a dropdown menu to filter between "All Staff" and specific teams.'),
            buildHeader('Administrator Panel'),
            buildParagraph('• Notification Centre: Send messages to individual users or all staff at once.'),
            buildParagraph('• Manage Sites: Add, edit, or delete worksites. Here you can also set up geofence boundaries for clock-in verification and define preset shifts.'),
            buildParagraph('• Manage Staff: Edit user profiles, change roles, assign supervisors, and deactivate accounts.'),
            buildParagraph('• View Reports: Generate detailed PDF/CSV reports for payroll, time off, and scheduling. The Weekly Schedule PDF includes a custom name field.'),
            buildParagraph('• Approve Time Off: Review and approve or deny all time off requests from across the company.'),
            buildHeader('Advanced Features & Concepts'),
            buildParagraph('• Geofencing: An optional feature per-site that verifies an employee\'s location when they clock in, improving accuracy.'),
            buildParagraph('• Shift Presets: Time-saving templates you can create for each site (e.g., "Morning Shift") that pre-fill shift times.'),
            buildParagraph('• User Roles & Security: The app has three roles (Staff, Supervisor, Admin) which are enforced by secure rules in the app\'s cloud database to protect data and control access.'),
          ];
        default:
          return [buildParagraph('Could not load user manual.')];
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('About ScheduleLink'.toUpperCase()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...getManualWidgets(), // Display the role-specific manual
            const Divider(height: 48),
            const Center(
              child: Text(
                'by OvshO™',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}