// lib/main_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/user_profile.dart';
import 'home_page.dart';
import 'clocker_page.dart';
import 'time_off_page.dart';
import 'admin_page.dart'; // Import the new Admin page

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  UserProfile? _userProfile;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _userProfile = UserProfile.fromFirestore(doc);
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_userProfile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // --- Start of New Logic ---
    final bool isAdmin = _userProfile!.role == 'admin';

    // Conditionally build the list of pages based on the user's role
    final List<Widget> pages = [
      HomePage(userProfile: _userProfile!),
      const ClockerPage(),
      const TimeOffPage(),
      if (isAdmin) const AdminPage(), // Only add AdminPage if user is an admin
    ];

    // Conditionally build the list of navigation items
    final List<BottomNavigationBarItem> navItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Schedule'),
      const BottomNavigationBarItem(icon: Icon(Icons.timer_outlined), label: 'Clocker'),
      const BottomNavigationBarItem(icon: Icon(Icons.beach_access), label: 'Time Off'),
      if (isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
    ];
    // --- End of New Logic ---

    return Scaffold(
      body: Center(
        child: pages.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: navItems, // Use the dynamically created list of items
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        // This is important to ensure all tabs are visible and have consistent styling
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}