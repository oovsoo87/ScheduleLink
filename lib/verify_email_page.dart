// lib/verify_email_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _isEmailVerified = false;
  Timer? _timer;
  bool _canResendEmail = false;

  @override
  void initState() {
    super.initState();
    // Check if email is already verified (e.g., if user comes back to the app)
    _isEmailVerified = FirebaseAuth.instance.currentUser!.emailVerified;

    if (!_isEmailVerified) {
      // Set a timer to allow resending after a delay
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted) setState(() => _canResendEmail = true);
      });

      // Start a timer to automatically check for verification
      _timer = Timer.periodic(
        const Duration(seconds: 3),
            (_) => _checkEmailVerified(),
      );
    }
  }

  Future<void> _checkEmailVerified() async {
    // Reload the user to get the latest verification status from Firebase
    await FirebaseAuth.instance.currentUser!.reload();
    setState(() {
      _isEmailVerified = FirebaseAuth.instance.currentUser!.emailVerified;
    });

    // If verified, the AuthGate will automatically navigate to the main app, so we can cancel the timer.
    if (_isEmailVerified) {
      _timer?.cancel();
    }
  }

  Future<void> _sendVerificationEmail() async {
    try {
      await FirebaseAuth.instance.currentUser!.sendEmailVerification();
      setState(() => _canResendEmail = false);
      // Prevent spamming by re-enabling the button after a delay
      await Future.delayed(const Duration(seconds: 15));
      if (mounted) setState(() => _canResendEmail = true);

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email resent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red,));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? 'your email';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Email'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'A verification link has been sent to:',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                userEmail,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Text(
                'Please click the link in the email to continue. This screen will update automatically once you are verified.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.email_outlined),
                label: const Text('Resend Email'),
                onPressed: _canResendEmail ? _sendVerificationEmail : null,
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Cancel & Sign Out'),
              )
            ],
          ),
        ),
      ),
    );
  }
}