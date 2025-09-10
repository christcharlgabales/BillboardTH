// lib/admin/logs_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';

class LogsScreen extends StatefulWidget {
  @override
  _LogsScreenState createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final logs = await supabaseService.getAllAlertLogs();
      
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading logs: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading logs: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    List<Map<String, dynamic>> filtered = _logs;

    // Apply activation type filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((log) => 
          log['type_of_activation'].toString().contains(_selectedFilter.toUpperCase())).toList();
    }

    // Apply date filter
    if (_selectedDate != null) {
      final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      filtered = filtered.where((log) => log['date'] == selectedDateStr).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((log) =>
          log['ev_registration_no'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log['billboardid'].toString().contains(_searchQuery) ||
          log['type_of_activation'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    return filtered;
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
  }

  Widget _buildLogEntry(Map<String, dynamic> log) {
    final isSuccess = log['result'].toString().startsWith('SUCCESS');
    final activationType = log['type_of_activation'].toString();
    
    Color typeColor;
    IconData typeIcon;
    
    switch (activationType) {
      case 'PROXIMITY_AUTO':
        typeColor = Colors.blue;
        typeIcon = Icons.near_me;
        break;
      case 'MANUAL_ACTIVATE':
        typeColor = Colors.green;
        typeIcon = Icons.play_arrow;
        break;
      case 'MANUAL_DEACTIVATE':
        typeColor = Colors.orange;
        typeIcon = Icons.stop;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.info;
    }

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(typeIcon, color: typeColor, size: 20),
        ),
        title: Row(
          children: [
            Text(
              'Billboard ${log['billboardid']}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(width: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSuccess ? Colors.green[100] : Colors.red[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isSuccess ? 'SUCCESS' : 'FAILED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSuccess ? Colors.green[700] : Colors.red[700],
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EV: ${log['ev_registration_no']}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              activationType.replaceAll('_', ' '),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              log['date'] ?? 'N/A',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            Text(
              log['time'] ?? 'N/A',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        onTap: () => _showLogDetails(log),
      ),
    );
  }

  void _showLogDetails(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Log Details'),
          content: Container(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Alert ID', log['alertid']?.toString() ?? 'N/A'),
                _buildDetailRow('Billboard ID', log['billboardid']?.toString() ?? 'N/A'),
                _buildDetailRow('Emergency Vehicle', log['ev_registration_no']?.toString() ?? 'N/A'),
                _buildDetailRow('Activation Type', log['type_of_activation']?.toString().replaceAll('_', ' ') ?? 'N/A'),
                _buildDetailRow('Date', log['date']?.toString() ?? 'N/A'),
                _buildDetailRow('Time', log['time']?.toString() ?? 'N/A'),
                _buildDetailRow('Result', log['result']?.toString() ?? 'N/A'),
                _buildDetailRow('Created At', log['created_at'] != null 
                    ? DateFormat('MMM dd, yyyy - HH:mm:ss').format(DateTime.parse(log['created_at']))
                    : 'N/A'),
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
                'System Logs',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Spacer(),
              IconButton(
                onPressed: _loadLogs,
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
                    hintText: 'Search logs...',
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
                    items: ['All', 'Proximity', 'Manual']
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
              
              SizedBox(width: 20),
              
              // Date Filter
              Container(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _selectDate,
                  icon: Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _selectedDate != null 
                        ? DateFormat('MMM dd, yyyy').format(_selectedDate!)
                        : 'Select Date',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              
              if (_selectedDate != null) ...[
                SizedBox(width: 8),
                IconButton(
                  onPressed: _clearDateFilter,
                  icon: Icon(Icons.clear, size: 16),
                  tooltip: 'Clear Date Filter',
                ),
              ],
            ],
          ),
          
          SizedBox(height: 20),
          
          // Statistics Row
          Row(
            children: [
              _buildStatChip('Total Logs', _logs.length.toString(), Colors.blue),
              SizedBox(width: 12),
              _buildStatChip('Filtered', _filteredLogs.length.toString(), Colors.green),
              SizedBox(width: 12),
              _buildStatChip('Success Rate', 
                  _logs.isNotEmpty 
                      ? '${((_logs.where((log) => log['result'].toString().startsWith('SUCCESS')).length / _logs.length) * 100).toStringAsFixed(1)}%'
                      : '0%', 
                  Colors.orange),
            ],
          ),
          
          SizedBox(height: 20),
          
          // Logs List
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
                  : _filteredLogs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.list_alt, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text(
                                'No logs found',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                              ),
                              if (_searchQuery.isNotEmpty || _selectedDate != null || _selectedFilter != 'All')
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _searchQuery = '';
                                      _selectedDate = null;
                                      _selectedFilter = 'All';
                                    });
                                  },
                                  child: Text('Clear Filters'),
                                ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            // Header
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Alert Logs (${_filteredLogs.length})',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Logs List
                            Expanded(
                              child: ListView.builder(
                                itemCount: _filteredLogs.length,
                                itemBuilder: (context, index) {
                                  return _buildLogEntry(_filteredLogs[index]);
                                },
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}