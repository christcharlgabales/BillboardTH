import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final evRegCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  String? role; // "Driver" | "Billboard Admin"
  // Optional EV fields (you can show extra inputs if you like)
  final evTypeCtrl = TextEditingController();
  final agencyCtrl = TextEditingController();
  final plateCtrl = TextEditingController();

  bool loading = false;

  Future<void> _signup() async {
    if (passCtrl.text != confirmCtrl.text) {
      _toast('Passwords do not match');
      return;
    }
    if (role == null || role!.isEmpty) {
      _toast('Please select a role');
      return;
    }
    if (role!.toLowerCase() == 'driver' && evRegCtrl.text.trim().isEmpty) {
      _toast('EV Registration No is required for Driver');
      return;
    }

    setState(() => loading = true);
    final err = await AuthService.signUp(
      email: emailCtrl.text.trim(),
      password: passCtrl.text.trim(),
      name: nameCtrl.text.trim(),
      role: role!,
      evRegistrationNo: role!.toLowerCase() == 'driver' ? evRegCtrl.text.trim() : null,
      evType: evTypeCtrl.text.trim().isEmpty ? null : evTypeCtrl.text.trim(),
      agency: agencyCtrl.text.trim().isEmpty ? null : agencyCtrl.text.trim(),
      plateNumber: plateCtrl.text.trim().isEmpty ? null : plateCtrl.text.trim(),
    );
    if (!mounted) return;

    if (err != null) {
      _toast('Sign up failed: $err');
    } else {
      _toast('Signup successful! Please log in.');
      Navigator.pop(context);
    }
    setState(() => loading = false);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = (role ?? '').toLowerCase() == 'driver';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Image.asset('assets/logo.png', height: 100, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              const SizedBox(height: 10),
              const Text('REGISTER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 22),
              _tf(nameCtrl, 'Name'),
              const SizedBox(height: 12),
              _tf(emailCtrl, 'Email', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 12),

              // Role
              DropdownButtonFormField<String>(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'Driver', child: Text('Driver')),
                  DropdownMenuItem(value: 'Billboard Admin', child: Text('Billboard Admin')),
                ],
                onChanged: (v) => setState(() => role = v),
                decoration: _dec('Role'),
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 12),

              // EV fields if Driver
              if (isDriver) ...[
                _tf(evRegCtrl, 'EV Registration No'),
                const SizedBox(height: 12),
                _tf(evTypeCtrl, 'EV Type (optional)'),
                const SizedBox(height: 12),
                _tf(agencyCtrl, 'Agency (optional)'),
                const SizedBox(height: 12),
                _tf(plateCtrl, 'Plate Number (optional)'),
                const SizedBox(height: 12),
              ],

              _tf(passCtrl, 'Password', obscure: true),
              const SizedBox(height: 12),
              _tf(confirmCtrl, 'Verify Password', obscure: true),
              const SizedBox(height: 16),

              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : _signup,
                  child: Text(loading ? 'REGISTERING...' : 'REGISTER'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Already have an Account? Log In')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tf(TextEditingController c, String hint,
      {bool obscure = false, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: _dec(hint),
      style: const TextStyle(color: Colors.black),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black54),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
