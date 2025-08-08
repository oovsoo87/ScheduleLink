// lib/auth_gate.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main_page.dart';
import 'login_page.dart';
import 'verify_email_page.dart'; // Import the new page

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // User is not logged in, show login page
        if (!snapshot.hasData) {
          return const LoginPage();
        }

        final user = snapshot.data!;

        // User is logged in but has NOT verified their email, show verification page
        if (!user.emailVerified) {
          return const VerifyEmailPage();
        }

        // User is logged in AND verified, show the main app
        return const MainPage();
      },
    );
  }
}