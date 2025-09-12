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
  static const int _logsPerPage = 3;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Select Avatar Source', style: TextStyle(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSourceOption(Icons.camera_alt, 'Camera', ImageSource.camera),
              SizedBox(height: 8),
              _buildSourceOption(Icons.photo_library, 'Gallery', ImageSource.gallery),
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

  Widget _buildSourceOption(IconData icon, String title, ImageSource source) {
    return InkWell(
      onTap: () => Navigator.pop(context, source),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Color(0xFF8B4B3B)),
            SizedBox(width: 12),
            Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Consumer<SupabaseService>(
      builder: (context, supabaseService, child) {
        final user = supabaseService.currentUser;
        
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: user?.avatarUrl != null 
                          ? NetworkImage(user!.avatarUrl!) 
                          : null,
                      child: user?.avatarUrl == null 
                          ? Icon(Icons.person, size: 45, color: Colors.grey.shade500)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: _isUploadingAvatar ? null : _changeAvatar,
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Color(0xFF8B4B3B),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _isUploadingAvatar
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 14,
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
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8B4B3B),
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Color(0xFF8B4B3B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  user?.role ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8B4B3B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogsSection() {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Color(0xFF8B4B3B),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Activity Logs',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (_isLoadingLogs)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Date & Time', 
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: 12, 
                                fontWeight: FontWeight.w600
                              )
                            )
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Billboard', 
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: 12, 
                                fontWeight: FontWeight.w600
                              )
                            )
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              'Status', 
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: 12, 
                                fontWeight: FontWeight.w600
                              ),
                              textAlign: TextAlign.center,
                            )
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Colors.grey.shade700, height: 1),
                    SizedBox(height: 8),
                    // Content
                    Expanded(
                      child: _paginatedLogs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox_outlined, color: Colors.grey.shade600, size: 40),
                                  SizedBox(height: 8),
                                  Text(
                                    'No logs available',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _paginatedLogs.length,
                              separatorBuilder: (context, index) => SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final log = _paginatedLogs[index];
                                return Container(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              log['date'] ?? '', 
                                              style: TextStyle(color: Colors.white, fontSize: 11)
                                            ),
                                            Text(
                                              log['time']?.substring(0, 8) ?? '', 
                                              style: TextStyle(color: Colors.grey.shade400, fontSize: 10)
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'BB-${log['billboardid']?.toString().padLeft(3, '0') ?? ''}', 
                                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)
                                        )
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(log['result']),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            log['result'] ?? '', 
                                            style: TextStyle(
                                              color: Colors.white, 
                                              fontSize: 9,
                                              fontWeight: FontWeight.w500
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    // Pagination
                    if (_alertLogs.isNotEmpty && _totalPages > 1)
                      Container(
                        padding: EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(Icons.chevron_left, color: Colors.white, size: 20),
                              onPressed: _currentPage > 0
                                  ? () => setState(() => _currentPage--)
                                  : null,
                              padding: EdgeInsets.all(4),
                              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '${_currentPage + 1} / $_totalPages',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.chevron_right, color: Colors.white, size: 20),
                              onPressed: _currentPage < _totalPages - 1
                                  ? () => setState(() => _currentPage++)
                                  : null,
                              padding: EdgeInsets.all(4),
                              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? result) {
    switch (result?.toLowerCase()) {
      case 'success':
      case 'completed':
        return Colors.green;
      case 'failed':
      case 'error':
        return Colors.red;
      case 'pending':
      case 'processing':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActionButtons() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // Implement change password functionality
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 18),
                  SizedBox(width: 8),
                  Text('Change Password', style: TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // Implement logout functionality
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 8),
                  Text('Log Out', style: TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildProfileHeader(),
            _buildLogsSection(),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }
}