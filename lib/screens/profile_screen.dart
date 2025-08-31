import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', user.email!)
          .maybeSingle();

      setState(() => _userData = data);
    } catch (e) {
      debugPrint("Error loading profile: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: _userData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Name: ${_userData!['name'] ?? ''}",
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 10),
                  Text("Email: ${_userData!['email'] ?? ''}",
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text("Role: ${_userData!['role'] ?? ''}",
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text("EV Registration: ${_userData!['ev_registration_no'] ?? ''}",
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text("Status: ${_userData!['status'] ?? ''}",
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
    );
  }
}
