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
        SnackBar(
          content: Text('Error loading logs: $e'),
          backgroundColor: Color(0xFF8B4B3B),
        ),
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            'Select Avatar Source',
            style: TextStyle(
              color: Color(0xFF8B4B3B),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSourceOption(
                icon: Icons.camera_alt,
                title: 'Camera',
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              SizedBox(height: 8),
              _buildSourceOption(
                icon: Icons.photo_library,
                title: 'Gallery',
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
            backgroundColor: Color(0xFFD32F2F),
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
            backgroundColor: Color(0xFF388E3C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Color(0xFFD32F2F),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color(0xFF8B4B3B).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Color(0xFF8B4B3B).withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Color(0xFF8B4B3B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: Color(0xFF8B4B3B),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLogsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(0xFF8B4B3B).withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFF8B4B3B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.history,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'EMERGENCY LOGS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                if (_isLoadingLogs)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(8),
            child: Column(
              children: [
                // Compact Table Header
                Container(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Color(0xFF8B4B3B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Date & Time',
                          style: TextStyle(
                            color: Color(0xFF8B4B3B),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Billboard',
                          style: TextStyle(
                            color: Color(0xFF8B4B3B),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Result',
                          style: TextStyle(
                            color: Color(0xFF8B4B3B),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4),
                
                // Compact Table Data
                if (_paginatedLogs.isEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No emergency logs available',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._paginatedLogs.map((log) => Container(
                    margin: EdgeInsets.only(bottom: 2),
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log['date'] ?? '',
                                style: TextStyle(
                                  color: Color(0xFF2E2E2E),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                log['time']?.substring(0, 8) ?? '',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 7,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'BB-${log['billboardid']?.toString().padLeft(3, '0') ?? ''}',
                            style: TextStyle(
                              color: Color(0xFF2E2E2E),
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getResultColor(log['result']).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              log['result'] ?? '',
                              style: TextStyle(
                                color: _getResultColor(log['result']),
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                
                // Compact Pagination
                if (_alertLogs.isNotEmpty && _totalPages > 1)
                  Container(
                    margin: EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          padding: EdgeInsets.all(4),
                          constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                          icon: Icon(Icons.chevron_left, color: Color(0xFF8B4B3B), size: 16),
                          onPressed: _currentPage > 0
                              ? () => setState(() => _currentPage--)
                              : null,
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(0xFF8B4B3B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_currentPage + 1}/$_totalPages',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.all(4),
                          constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                          icon: Icon(Icons.chevron_right, color: Color(0xFF8B4B3B), size: 16),
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

  Color _getResultColor(String? result) {
    switch (result?.toLowerCase()) {
      case 'success':
      case 'completed':
        return Color(0xFF388E3C);
      case 'failed':
      case 'error':
        return Color(0xFFD32F2F);
      case 'pending':
      case 'in progress':
        return Color(0xFFFF9800);
      default:
        return Color(0xFF8B4B3B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SupabaseService>(
      builder: (context, supabaseService, child) {
        final user = supabaseService.currentUser;
        
        return Scaffold(
          backgroundColor: Color(0xFFF5F5F5),
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildCompactProfileHeader(user),
                  SizedBox(height: 16),
                  Expanded(child: _buildCompactLogsSection()),
                  SizedBox(height: 16),
                  _buildCompactActionButtons(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactProfileHeader(dynamic user) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B4B3B), Color(0xFF6D3829)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF8B4B3B).withOpacity(0.3),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: user?.avatarUrl != null 
                    ? NetworkImage(user!.avatarUrl!) 
                    : null,
                child: user?.avatarUrl == null 
                    ? Icon(
                        Icons.person,
                        size: 30,
                        color: Color(0xFF8B4B3B),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _isUploadingAvatar ? null : _changeAvatar,
                  child: Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: _isUploadingAvatar
                        ? SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B4B3B)),
                            ),
                          )
                        : Icon(
                            Icons.camera_alt,
                            color: Color(0xFF8B4B3B),
                            size: 12,
                          ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.name ?? 'Loading...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    user?.role ?? 'Emergency Personnel',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Future<void> _showChangePasswordDialog() async {
    final _currentPasswordController = TextEditingController();
    final _newPasswordController = TextEditingController();
    final _confirmPasswordController = TextEditingController();
    final _formKey = GlobalKey<FormState>();
    bool _isLoading = false;
    bool _obscureCurrentPassword = true;
    bool _obscureNewPassword = true;
    bool _obscureConfirmPassword = true;

    // Color theme constants
    const Color primaryBrown = Color(0xFF8B4B3B);
    const Color lightBrown = Color(0xFFB8806B);
    const Color darkBrown = Color(0xFF6B3A2E);
    const Color accentBrown = Color(0xFFA67C5A);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 380,
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Section
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: primaryBrown,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.security,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Change Password',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          onPressed: _isLoading ? null : () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: Colors.white, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            padding: EdgeInsets.all(4),
                            minimumSize: Size(28, 28),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Form Section - Scrollable
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Security Info Card
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primaryBrown.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: primaryBrown.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: primaryBrown,
                                    size: 14,
                                  ),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Password Requirements',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: darkBrown,
                                            fontSize: 10,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          '• At least 6 characters\n• Mix of letters and numbers\n• Choose something unique',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 9,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            SizedBox(height: 12),

                            // Current Password Field
                            _buildPasswordField(
                              controller: _currentPasswordController,
                              label: 'Current Password',
                              hint: 'Enter current password',
                              obscureText: _obscureCurrentPassword,
                              onToggleVisibility: () => setState(() => 
                                _obscureCurrentPassword = !_obscureCurrentPassword),
                              validator: (value) => 
                                value?.isEmpty ?? true ? 'Please enter your current password' : null,
                              prefixIcon: Icons.lock_outline,
                            ),

                            SizedBox(height: 10),

                            // New Password Field
                            _buildPasswordField(
                              controller: _newPasswordController,
                              label: 'New Password',
                              hint: 'Enter new password',
                              obscureText: _obscureNewPassword,
                              onToggleVisibility: () => setState(() => 
                                _obscureNewPassword = !_obscureNewPassword),
                              validator: (value) {
                                if (value?.isEmpty ?? true) {
                                  return 'Please enter a new password';
                                }
                                if (value!.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                if (value == _currentPasswordController.text) {
                                  return 'New password must be different from current';
                                }
                                return null;
                              },
                              prefixIcon: Icons.lock,
                            ),

                            SizedBox(height: 10),

                            // Confirm Password Field
                            _buildPasswordField(
                              controller: _confirmPasswordController,
                              label: 'Confirm New Password',
                              hint: 'Re-enter new password',
                              obscureText: _obscureConfirmPassword,
                              onToggleVisibility: () => setState(() => 
                                _obscureConfirmPassword = !_obscureConfirmPassword),
                              validator: (value) {
                                if (value?.isEmpty ?? true) {
                                  return 'Please confirm your new password';
                                }
                                if (value != _newPasswordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                              prefixIcon: Icons.lock_reset,
                            ),

                            SizedBox(height: 16),

                            // Actions Section
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isLoading ? null : () {
                                      Navigator.pop(context);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey[600],
                                      side: BorderSide(color: Colors.grey[300]!),
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                
                                SizedBox(width: 10),
                                
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : () async {
                                      if (_formKey.currentState!.validate()) {
                                        setState(() => _isLoading = true);
                                        
                                        try {
                                          // Simulate API call delay
                                          await Future.delayed(Duration(seconds: 2));
                                          
                                          // Add your password change logic here
                                          
                                          Navigator.pop(context);
                                          
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.check_circle, color: Colors.white),
                                                  SizedBox(width: 12),
                                                  Text('Password changed!'),
                                                ],
                                              ),
                                              backgroundColor: Colors.green[600],
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              margin: EdgeInsets.all(16),
                                            ),
                                          );
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.error_outline, color: Colors.white),
                                                  SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text('Failed to change password: ${e.toString()}'),
                                                  ),
                                                ],
                                              ),
                                              backgroundColor: Colors.red[600],
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              margin: EdgeInsets.all(16),
                                              duration: Duration(seconds: 4),
                                            ),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isLoading = false);
                                          }
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryBrown,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: _isLoading
                                        ? Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                'Changing...',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            'Change',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?)? validator,
    required IconData prefixIcon,
  }) {
    const Color primaryBrown = Color(0xFF8B4B3B);
    const Color accentBrown = Color(0xFFA67C5A);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B3A2E),
          ),
        ),
        SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 11),
            prefixIcon: Icon(prefixIcon, color: accentBrown, size: 16),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[500],
                size: 16,
              ),
              onPressed: onToggleVisibility,
              splashRadius: 14,
              padding: EdgeInsets.all(4),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: primaryBrown, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: Colors.grey[50],
            errorStyle: TextStyle(fontSize: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }

Future<void> _showLogoutDialog() async {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFFD32F2F).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.logout,
              color: Color(0xFFD32F2F),
              size: 32,
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Logout',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E2E2E),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Are you sure you want to logout?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
                      await supabaseService.signOut();
                      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error logging out: $e'),
                          backgroundColor: Color(0xFFD32F2F),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFD32F2F),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildCompactActionButtons() {
  return Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: Container(
      color: Theme.of(context).scaffoldBackgroundColor, // Match your background
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16, // Safe area + padding
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _showChangePasswordDialog,
              icon: Icon(Icons.lock_outline, size: 16),
              label: Text(
                'Password',
                style: TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF8B4B3B),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _showLogoutDialog,
              icon: Icon(Icons.exit_to_app, size: 16),
              label: Text(
                'Log Out',
                style: TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}
