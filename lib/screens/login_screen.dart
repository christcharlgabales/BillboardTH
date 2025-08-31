import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;

  Future<void> _login() async {
    setState(() => loading = true);
    try {
      final profile = await AuthService.login(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );

      if (!mounted) return;

      if (profile == null) {
        _toast('Profile not found.');
      } else {
        _toast('Welcome, ${profile['Name'] ?? 'User'}!');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) =>  HomeScreen()),
        );
      }
    } catch (e) {
      _toast('Login failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Image.asset('assets/logo.png', height: 120, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              const SizedBox(height: 16),
              const Text('ALERT TO DIVERT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 28),
              _textField(emailCtrl, 'Email', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 14),
              _textField(passCtrl, 'Password', obscure: true),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: loading ? null : _login,
                  child: Text(loading ? 'LOGGING IN...' : 'LOGIN'),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an Account?"),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                    child: const Text('Sign Up Now!'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField(TextEditingController c, String hint,
      {bool obscure = false, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black54),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      style: const TextStyle(color: Colors.black),
    );
  }
}
