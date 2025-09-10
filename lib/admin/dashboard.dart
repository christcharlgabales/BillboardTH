// lib/admin/dashboard.dart

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../models/billboard.dart';
import 'users_screen.dart';
import 'billboard_screen.dart';
import 'logs_screen.dart';

class AdminDashboard extends StatefulWidget {
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  
  // Dashboard statistics
  int _activeUsers = 0;
  int _totalBillboards = 0;
  int _alertsTriggeredToday = 0;
  
  // Current user info
  String _currentUserName = "Admin User";
  
  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    
    try {
      // Load billboards
      await supabaseService.loadBillboards();
      
      // Get statistics
      await _loadStatistics();
      
      // Load current user info
      final currentUser = supabaseService.currentUser;
      if (currentUser != null) {
        _currentUserName = currentUser.name;
      }
      
      // Update markers
      _updateMarkers(supabaseService.billboards);
      
    } catch (e) {
      print('Error loading dashboard data: $e');
    }
  }

  Future<void> _loadStatistics() async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    
    try {
      // Get active users count
      final usersResponse = await supabaseService.client
    .from('users')
    .select('count')
    .eq('status', 'active')
    .count();
      
      // Get total billboards count
      final billboardsResponse = await supabaseService.client
          .from('billboard')
          .select('count')
          .count();
      
      // Get alerts triggered today
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final alertsResponse = await supabaseService.client
          .from('alertlog')
          .select('count')
          .eq('date', today)
          .count();
      
      setState(() {
        _activeUsers = usersResponse.count;
        _totalBillboards = billboardsResponse.count;
        _alertsTriggeredToday = alertsResponse.count;
      });
      
    } catch (e) {
      print('Error loading statistics: $e');
      setState(() {
        _activeUsers = 0;
        _totalBillboards = 0;
        _alertsTriggeredToday = 0;
      });
    }
  }

  void _updateMarkers(List<Billboard> billboards) {
    setState(() {
      _markers = billboards.map((billboard) {
        return Marker(
          markerId: MarkerId(billboard.billboardId.toString()),
          position: LatLng(billboard.latitude, billboard.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            billboard.isActivated ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: 'Billboard ${billboard.billboardNumber}',
            snippet: '${billboard.location}\n${billboard.isActivated ? "ACTIVE" : "INACTIVE"}',
          ),
        );
      }).toSet();
    });
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildSideNavigation() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Color(0xFF8B4B3B),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.navigation, color: Colors.white, size: 32),
                SizedBox(height: 8),
                Text(
                  'ALERT TO DIVERT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Navigation Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 20),
              children: [
                _buildNavItem(Icons.dashboard, 'Dashboard', 0),
                _buildNavItem(Icons.people, 'Users', 1),
                _buildNavItem(Icons.display_settings, 'Billboard', 2),
                _buildNavItem(Icons.list_alt, 'Logs', 3),
              ],
            ),
          ),
          
          // User Profile Section
          Container(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey[300],
                  child: Icon(Icons.person, color: Colors.grey[600]),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentUserName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Admin',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
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

  Widget _buildNavItem(IconData icon, String title, int index) {
    bool isSelected = _selectedIndex == index;
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Color(0xFF8B4B3B) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.grey[600],
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[800],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: () => _onNavItemTapped(index),
        dense: true,
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardContent();
      case 1:
        return UsersScreen();
      case 2:
        return BillboardScreen();
      case 3:
        return LogsScreen();
      default:
        return _buildDashboardContent();
    }
  }

  Widget _buildDashboardContent() {
    return Column(
      children: [
        // Header
        Container(
          height: 80,
          padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.05),

                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                'Welcome Back Christ!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Spacer(),
              Text(
                DateFormat('EEEE, MMMM d y').format(DateTime.now()),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        
        // Content
        Expanded(
          child: Container(
            color: Colors.grey[50],
            padding: EdgeInsets.all(30),
            child: Column(
              children: [
                // Map
                Expanded(
                  flex: 2,
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Consumer<SupabaseService>(
                        builder: (context, supabaseService, child) {
                          return GoogleMap(
                            onMapCreated: (GoogleMapController controller) {
                              _mapController = controller;
                              _updateMarkers(supabaseService.billboards);
                            },
                            initialCameraPosition: CameraPosition(
                              target: LatLng(8.9475, 125.5406), // Butuan City coordinates
                              zoom: 13,
                            ),
                            markers: _markers,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: true,
                            mapToolbarEnabled: false,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                
                SizedBox(height: 30),
                
                // Statistics Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total Active Billboards',
                        _totalBillboards.toString(),
                        Color(0xFF8B4B3B),
                        Icons.display_settings,
                      ),
                    ),
                    SizedBox(width: 20),
                    Expanded(
                      child: _buildStatCard(
                        'Active Users',
                        _activeUsers.toString(),
                        Colors.black87,
                        Icons.people,
                      ),
                    ),
                    SizedBox(width: 20),
                    Expanded(
                      child: _buildStatCard(
                        'Alerts Triggered Today',
                        _alertsTriggeredToday.toString(),
                        Color(0xFF8B4B3B),
                        Icons.warning,
                        showAlert: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, {bool showAlert = false}) {
    return Container(
      height: 120,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 1,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              if (showAlert) ...[
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.info, color: Colors.white, size: 16),
                ),
              ],
            ],
          ),
          Spacer(),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Row(
        children: [
          _buildSideNavigation(),
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }
}