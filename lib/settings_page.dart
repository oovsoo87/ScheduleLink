// lib/settings_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'services/theme_provider.dart';
import 'my_account_page.dart';
import 'about_page.dart'; // <-- NEW

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _signOut(BuildContext context) async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('My Account'),
            subtitle: const Text('View your personal details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const MyAccountPage()));
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: themeProvider.themeMode == ThemeMode.dark,
            onChanged: (value) {
              themeProvider.toggleTheme(value);
            },
            secondary: const Icon(Icons.dark_mode_outlined),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline), // <-- NEW
            title: const Text('About'), // <-- NEW
            trailing: const Icon(Icons.chevron_right), // <-- NEW
            onTap: () { // <-- NEW
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutPage()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}