import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EVInfoScreen extends StatefulWidget {
  const EVInfoScreen({super.key});

  @override
  State<EVInfoScreen> createState() => _EVInfoScreenState();
}

class _EVInfoScreenState extends State<EVInfoScreen> {
  Map<String, dynamic>? _evData;

  @override
  void initState() {
    super.initState();
    _loadEVInfo();
  }

  Future<void> _loadEVInfo() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final userData = await Supabase.instance.client
          .from('users')
          .select('ev_registration_no')
          .eq('email', user.email!)
          .maybeSingle();

      final evNo = userData?['ev_registration_no'];
      if (evNo == null) return;

      final data = await Supabase.instance.client
          .from('emergencyvehicle')
          .select()
          .eq('ev_registration_no', evNo)
          .maybeSingle();

      setState(() => _evData = data);
    } catch (e) {
      debugPrint("Error loading EV info: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("EV Info")),
      body: _evData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("EV Registration: ${_evData!['ev_registration_no']}",
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 10),
                  Text("Type: ${_evData!['ev_type'] ?? ''}",
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text("Agency: ${_evData!['agency'] ?? ''}",
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text("Plate Number: ${_evData!['plate_number'] ?? ''}",
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
    );
  }
}
