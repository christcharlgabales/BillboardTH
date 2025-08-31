import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _alertLogs = [];

  @override
  void initState() {
    super.initState();
    _loadAlertLogs();
  }

  void _loadAlertLogs() async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    if (supabaseService.currentUser != null) {
      final logs = await supabaseService.getAlertLogs(
        supabaseService.currentUser!.evRegistrationNo,
      );
      setState(() {
        _alertLogs = logs;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SupabaseService>(
      builder: (context, supabaseService, child) {
        final user = supabaseService.currentUser;
        
        return SingleChildScrollView(  // Add this to allow scrolling
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile Header
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey.shade300,
                  child: Icon(Icons.person, size: 50, color: Colors.grey.shade600),
                ),
                SizedBox(height: 16),
                Text(
                  user?.name ?? 'Loading...',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8B4B3B),
                  ),
                ),
                Text(
                  user?.role ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                SizedBox(height: 24),
                
                // Logs Section
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFF8B4B3B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOGS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text('Date & Time', style: TextStyle(color: Colors.white, fontSize: 12))),
                                Expanded(child: Text('Billboard No.', style: TextStyle(color: Colors.white, fontSize: 12))),
                                Expanded(child: Text('Result', style: TextStyle(color: Colors.white, fontSize: 12))),
                              ],
                            ),
                            Divider(color: Colors.grey),
                            ..._alertLogs.take(4).map((log) => Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(log['date'] ?? '', style: TextStyle(color: Colors.white, fontSize: 10)),
                                        Text(log['time']?.substring(0, 8) ?? '', style: TextStyle(color: Colors.white, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  Expanded(child: Text('BB - ${log['billboardid']?.toString().padLeft(3, '0') ?? ''}', style: TextStyle(color: Colors.white, fontSize: 10))),
                                  Expanded(child: Text(log['result'] ?? '', style: TextStyle(color: Colors.white, fontSize: 10))),
                                ],
                              ),
                            )).toList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Change Password'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Log Out'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
