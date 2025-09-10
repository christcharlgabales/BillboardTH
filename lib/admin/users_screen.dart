// lib/admin/users_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../models/user.dart';

class UsersScreen extends StatefulWidget {
  @override
  _UsersScreenState createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final response = await supabaseService.client
          .from('users')
          .select('*')
          .order('created_at', ascending: false);

      setState(() {
        _users = (response as List<dynamic>)
            .map((data) => AppUser.fromJson(data))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading users: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<AppUser> get _filteredUsers {
    List<AppUser> filtered = _users;

    // Apply status filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((user) => user.status == _selectedFilter.toLowerCase()).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((user) =>
          user.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          user.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          user.evRegistrationNo.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    return filtered;
  }

  Future<void> _updateUserStatus(AppUser user, String newStatus) async {
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      await supabaseService.client
          .from('users')
          .update({'status': newStatus})
          .eq('userid', user.userId);

      // Update local list
      setState(() {
        final index = _users.indexWhere((u) => u.userId == user.userId);
        if (index != -1) {
          _users[index] = user.copyWith(status: newStatus);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User status updated to $newStatus'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error updating user status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating user status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showUserDetails(AppUser user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('User Details'),
          content: Container(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Name', user.name),
                _buildDetailRow('Email', user.email),
                _buildDetailRow('Role', user.role),
                _buildDetailRow('EV Registration', user.evRegistrationNo),
                _buildDetailRow('Status', user.status),
                _buildDetailRow('Created At', DateFormat('MMM dd, yyyy - HH:mm').format(user.createdAt)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Users Management',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Spacer(),
              IconButton(
                onPressed: _loadUsers,
                icon: Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          
          SizedBox(height: 20),
          
          // Search and Filter Row
          Row(
            children: [
              // Search Bar
              Container(
                width: 300,
                height: 40,
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              
              SizedBox(width: 20),
              
              // Filter Dropdown
              Container(
                height: 40,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFilter,
                    items: ['All', 'Active', 'Inactive', 'Suspended']
                        .map((filter) => DropdownMenuItem(
                              value: filter,
                              child: Text(filter),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedFilter = value!;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 30),
          
          // Users Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text(
                                'No users found',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 30,
                            headingRowColor: MaterialStateColor.resolveWith((states) => Colors.grey[50]!),
                            columns: [
                              DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('EV Registration', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Created', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _filteredUsers.map((user) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.grey[300],
                                          backgroundImage: user.avatarUrl != null 
                                              ? NetworkImage(user.avatarUrl!) 
                                              : null,
                                          child: user.avatarUrl == null 
                                              ? Icon(Icons.person, size: 16, color: Colors.grey[600])
                                              : null,
                                        ),
                                        SizedBox(width: 8),
                                        Text(user.name),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(user.email)),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: user.role == 'admin' ? Colors.purple[100] : Colors.blue[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        user.role.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: user.role == 'admin' ? Colors.purple[700] : Colors.blue[700],
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(user.evRegistrationNo)),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: user.status == 'active' 
                                            ? Colors.green[100] 
                                            : user.status == 'suspended'
                                                ? Colors.red[100]
                                                : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        user.status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: user.status == 'active' 
                                              ? Colors.green[700] 
                                              : user.status == 'suspended'
                                                  ? Colors.red[700]
                                                  : Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(DateFormat('MMM dd, yyyy').format(user.createdAt))),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: () => _showUserDetails(user),
                                          icon: Icon(Icons.visibility, size: 16),
                                          tooltip: 'View Details',
                                        ),
                                        PopupMenuButton<String>(
                                          icon: Icon(Icons.more_vert, size: 16),
                                          onSelected: (value) {
                                            _updateUserStatus(user, value);
                                          },
                                          itemBuilder: (context) => [
                                            if (user.status != 'active')
                                              PopupMenuItem(value: 'active', child: Text('Activate')),
                                            if (user.status != 'inactive')
                                              PopupMenuItem(value: 'inactive', child: Text('Deactivate')),
                                            if (user.status != 'suspended')
                                              PopupMenuItem(value: 'suspended', child: Text('Suspend')),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}