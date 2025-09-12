import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _alertLogs = [];
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingAvatar = false;
  int _currentPage = 0;
  static const int _logsPerPage = 5;
  bool _isLoadingLogs = false;

  // Pagination helpers
  int get _totalPages => (_alertLogs.length / _logsPerPage).ceil();
  List<Map<String, dynamic>> get _paginatedLogs {
    final startIndex = _currentPage * _logsPerPage;
    final endIndex = startIndex + _logsPerPage;
    if (startIndex >= _alertLogs.length) return [];
    return _alertLogs.sublist(startIndex, endIndex > _alertLogs.length ? _alertLogs.length : endIndex);
  }

  @override
  void initState() {
    super.initState();
    _loadAlertLogs();
  }

  void _loadAlertLogs() async {
    setState(() => _isLoadingLogs = true);
    
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      if (supabaseService.currentUser != null) {
        final logs = await supabaseService.getAlertLogs(
          supabaseService.currentUser!.evRegistrationNo,
        );
        setState(() {
          _alertLogs = logs;
          _currentPage = 0;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading logs: $e')),
      );
    } finally {
      setState(() => _isLoadingLogs = false);
    }
  }

  Future<void> _changeAvatar() async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select Avatar Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) return;

      setState(() => _isUploadingAvatar = true);

      final file = File(image.path);
      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image not available. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final success = await supabaseService.uploadUserAvatar(file);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Avatar updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Widget _buildLogsSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF8B4B3B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LOGS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isLoadingLogs)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
            ],
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
                if (_paginatedLogs.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No logs available',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._paginatedLogs.map((log) => Padding(
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
                        Expanded(child: Text('BB - ${log['billboardid']?.toString().padLeft(3, '0') ?? ''}', 
                            style: TextStyle(color: Colors.white, fontSize: 10))),
                        Expanded(child: Text(log['result'] ?? '', 
                            style: TextStyle(color: Colors.white, fontSize: 10))),
                      ],
                    ),
                  )).toList(),
                if (_alertLogs.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left, color: Colors.white),
                          onPressed: _currentPage > 0
                              ? () => setState(() => _currentPage--)
                              : null,
                        ),
                        Text(
                          'Page ${_currentPage + 1} of $_totalPages',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right, color: Colors.white),
                          onPressed: _currentPage < _totalPages - 1
                              ? () => setState(() => _currentPage++)
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SupabaseService>(
      builder: (context, supabaseService, child) {
        final user = supabaseService.currentUser;
        
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: user?.avatarUrl != null 
                          ? NetworkImage(user!.avatarUrl!) 
                          : null,
                      child: user?.avatarUrl == null 
                          ? Icon(Icons.person, size: 50, color: Colors.grey.shade600)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _isUploadingAvatar ? null : _changeAvatar,
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Color(0xFF8B4B3B),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _isUploadingAvatar
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 16,
                                ),
                        ),
                      ),
                    ),
                  ],
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
                _buildLogsSection(),
                SizedBox(height: 24),
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