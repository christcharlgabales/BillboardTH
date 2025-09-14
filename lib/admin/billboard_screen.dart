// lib/admin/billboard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/supabase_service.dart';
import '../models/billboard.dart';

class BillboardScreen extends StatefulWidget {
  @override
  _BillboardScreenState createState() => _BillboardScreenState();
}

class _BillboardScreenState extends State<BillboardScreen> {
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  int? _selectedBillboardId;
  Timer? _refreshTimer;
  StreamSubscription? _alertsSubscription;

  // Color theme
  static const Color primaryBrown = Color(0xFF8B4B3B);
  static const Color lightBrown = Color(0xFFB8806B);
  static const Color darkBrown = Color(0xFF6B3A2E);
  static const Color accentBrown = Color(0xFFA67C5A);

  @override
  void initState() {
    super.initState();
    _loadBillboards();
    _startRealTimeSync();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _alertsSubscription?.cancel();
    super.dispose();
  }

  void _startRealTimeSync() {
    // Set up periodic refresh every 30 seconds
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _refreshBillboardStatus();
    });

    // Set up real-time subscription to alerts table
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    
    try {
      _alertsSubscription = supabaseService.client
          .from('alerts')
          .stream(primaryKey: ['id'])
          .listen((data) {
        print('Real-time alert update received: ${data.length} active alerts');
        _refreshBillboardStatus();
      });
      print('Real-time subscription established for alerts table');
    } catch (e) {
      print('Failed to set up real-time subscription: $e');
      // Fall back to periodic refresh only
    }
  }

  Future<void> _loadBillboards() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      await supabaseService.loadBillboards();
      await _refreshBillboardStatus(); // Load real status from database
      _updateMarkers(supabaseService.billboards);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading billboards: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading billboards: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshBillboardStatus() async {
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      
      // Get all active alerts from database
      final activeAlerts = await supabaseService.client
          .from('alerts')
          .select('billboard_id');
      
      final activeBillboardIds = Set<int>.from(
        activeAlerts.map((alert) => alert['billboard_id'] as int)
      );
      
      print('Active billboard IDs from database: $activeBillboardIds');
      
      // Update local billboard status based on database
      bool hasChanges = false;
      for (var billboard in supabaseService.billboards) {
        bool shouldBeActive = activeBillboardIds.contains(billboard.billboardId);
        if (billboard.isActivated != shouldBeActive) {
          supabaseService.updateBillboardStatus(billboard.billboardId, shouldBeActive);
          hasChanges = true;
        }
      }
      
      if (hasChanges) {
        _updateMarkers(supabaseService.billboards);
        print('Billboard statuses updated from database');
      }
    } catch (e) {
      print('Error refreshing billboard status: $e');
    }
  }

  void _updateMarkers(List<Billboard> billboards) {
  // Debug print
  for (var billboard in billboards) {
    print('Billboard ${billboard.billboardNumber}: isActivated = ${billboard.isActivated}');
  }
  
  setState(() {
    _markers = billboards.map((billboard) {
      final color = _selectedBillboardId == billboard.billboardId 
          ? BitmapDescriptor.hueBlue
          : billboard.isActivated 
              ? BitmapDescriptor.hueGreen 
              : BitmapDescriptor.hueRed;
      
      print('Billboard ${billboard.billboardNumber} color: $color');
      
      return Marker(
        markerId: MarkerId(billboard.billboardId.toString()),
        position: LatLng(billboard.latitude, billboard.longitude),
        onTap: () => _selectBillboard(billboard.billboardId),
        icon: BitmapDescriptor.defaultMarkerWithHue(color),
        infoWindow: InfoWindow(
          title: 'Billboard ${billboard.billboardNumber}',
          snippet: '${billboard.location}\n${billboard.isActivated ? "ACTIVE" : "INACTIVE"}',
        ),
      );
    }).toSet();
  });
}



  void _selectBillboard(int billboardId) {
    setState(() {
      _selectedBillboardId = _selectedBillboardId == billboardId ? null : billboardId;
    });
    
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    _updateMarkers(supabaseService.billboards);
    
    // Center map on selected billboard
    if (_selectedBillboardId != null) {
      final billboard = supabaseService.billboards
          .firstWhere((b) => b.billboardId == _selectedBillboardId);
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(billboard.latitude, billboard.longitude),
            zoom: 16,
          ),
        ),
      );
    }
  }

  List<Billboard> get _filteredBillboards {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    List<Billboard> filtered = supabaseService.billboards;

    // Apply status filter
    if (_selectedFilter == 'Active') {
      filtered = filtered.where((billboard) => billboard.isActivated).toList();
    } else if (_selectedFilter == 'Inactive') {
      filtered = filtered.where((billboard) => !billboard.isActivated).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((billboard) =>
          billboard.billboardNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          billboard.location.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    return filtered;
  }

  void _showAddBillboardDialog() {
    final TextEditingController billboardNumberController = TextEditingController();
    final TextEditingController locationController = TextEditingController();
    final TextEditingController latitudeController = TextEditingController();
    final TextEditingController longitudeController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Container(
                padding: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryBrown.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.add_location_alt,
                        color: primaryBrown,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Add New Billboard',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: darkBrown,
                      ),
                    ),
                  ],
                ),
              ),
              content: Container(
                width: 450,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Billboard Number Field
                      _buildFormField(
                        controller: billboardNumberController,
                        label: 'Billboard Number',
                        hint: 'e.g., BB001',
                        icon: Icons.numbers,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Billboard number is required';
                          }
                          return null;
                        },
                      ),
                      
                      SizedBox(height: 20),
                      
                      // Location Field
                      _buildFormField(
                        controller: locationController,
                        label: 'Location',
                        hint: 'e.g., Main Street, Downtown',
                        icon: Icons.location_on,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Location is required';
                          }
                          return null;
                        },
                      ),
                      
                      SizedBox(height: 20),
                      
                      // Coordinates Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildFormField(
                              controller: latitudeController,
                              label: 'Latitude',
                              hint: '8.9475',
                              icon: Icons.my_location,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Latitude is required';
                                }
                                final latitude = double.tryParse(value);
                                if (latitude == null || latitude < -90 || latitude > 90) {
                                  return 'Invalid latitude';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: _buildFormField(
                              controller: longitudeController,
                              label: 'Longitude',
                              hint: '125.5406',
                              icon: Icons.place,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Longitude is required';
                                }
                                final longitude = double.tryParse(value);
                                if (longitude == null || longitude < -180 || longitude > 180) {
                                  return 'Invalid longitude';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 24),
                      
                      // Help Text
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryBrown.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: primaryBrown.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: primaryBrown,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Click on the map to get coordinates, or enter them manually.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: darkBrown,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                // Cancel Button
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('Cancel'),
                ),
                
                // Add Button
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    if (formKey.currentState!.validate()) {
                      setDialogState(() {
                        isLoading = true;
                      });
                      
                      try {
                        final supabaseService = Provider.of<SupabaseService>(context, listen: false);
                        
                        // Create new billboard data
                        final billboardData = {
                          'billboard_number': billboardNumberController.text.trim(),
                          'location': locationController.text.trim(),
                          'latitude': double.parse(latitudeController.text.trim()),
                          'longitude': double.parse(longitudeController.text.trim()),
                          'created_at': DateTime.now().toIso8601String(),
                        };
                        
                        // Insert to database
                        final response = await supabaseService.client
                            .from('billboard')
                            .insert(billboardData)
                            .select()
                            .single();
                        
                        // Reload billboards to reflect changes
                        await _loadBillboards();
                        
                        Navigator.of(context).pop();
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Billboard added successfully!'),
                            backgroundColor: primaryBrown,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                        });
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error adding billboard: $e'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBrown,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isLoading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Adding...'),
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 18),
                            SizedBox(width: 4),
                            Text('Add Billboard'),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: darkBrown,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: accentBrown, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: primaryBrown, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
      ],
    );
  }

  void _showBillboardDetails(Billboard billboard) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Container(
            padding: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryBrown.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.info_outline,
                    color: primaryBrown,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Billboard Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: darkBrown,
                  ),
                ),
              ],
            ),
          ),
          content: Container(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Billboard ID', billboard.billboardId.toString()),
                _buildDetailRow('Billboard Number', billboard.billboardNumber),
                _buildDetailRow('Location', billboard.location),
                _buildDetailRow('Latitude', billboard.latitude.toStringAsFixed(6)),
                _buildDetailRow('Longitude', billboard.longitude.toStringAsFixed(6)),
                _buildDetailRow('Status', billboard.isActivated ? 'Active' : 'Inactive'),
                _buildDetailRow('Created At', DateFormat('MMM dd, yyyy - HH:mm').format(billboard.createdAt)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: primaryBrown,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: darkBrown,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBillboardStatus(Billboard billboard) async {
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final newStatus = !billboard.isActivated;
      final evRegistration = supabaseService.getCurrentEvRegistration();
      
      // Use manual activation method from SupabaseService
      final success = await supabaseService.manualActivation(
        billboard.billboardId, 
        evRegistration, 
        newStatus
      );
      
      if (success) {
        // Update local state
        supabaseService.updateBillboardStatus(billboard.billboardId, newStatus);
        
        // Update markers
        _updateMarkers(supabaseService.billboards);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Billboard ${billboard.billboardNumber} ${newStatus ? 'activated' : 'deactivated'}'),
            backgroundColor: primaryBrown,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${newStatus ? 'activate' : 'deactivate'} billboard'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Error toggling billboard status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating billboard status: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                'Billboard Management',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: darkBrown,
                ),
              ),
              Spacer(),
              // Add Billboard Button
              ElevatedButton.icon(
                onPressed: _showAddBillboardDialog,
                icon: Icon(Icons.add, size: 18),
                label: Text('Add Billboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBrown,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              SizedBox(width: 16),
              // Real-time indicator
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Real-time',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16),
              IconButton(
                onPressed: () {
                  _loadBillboards();
                  _refreshBillboardStatus();
                },
                icon: Icon(Icons.refresh, color: primaryBrown),
                tooltip: 'Refresh',
                style: IconButton.styleFrom(
                  backgroundColor: primaryBrown.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
                    hintText: 'Search billboards...',
                    prefixIcon: Icon(Icons.search, size: 20, color: accentBrown),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryBrown, width: 2),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: Colors.grey[50],
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
                  color: Colors.grey[50],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFilter,
                    icon: Icon(Icons.arrow_drop_down, color: accentBrown),
                    style: TextStyle(color: darkBrown),
                    items: ['All', 'Active', 'Inactive']
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
          
          // Main Content - Split between Map and Table
          Expanded(
            child: Row(
              children: [
                // Map Section
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
                            onTap: (_) => _selectBillboard(-1), // Deselect on map tap
                          );
                        },
                      ),
                    ),
                  ),
                ),
                
                SizedBox(width: 30),
                
                // Table Section
                Expanded(
                  flex: 1,
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
                        ? Center(child: CircularProgressIndicator(color: primaryBrown))
                        : _filteredBillboards.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.display_settings, size: 64, color: Colors.grey[400]),
                                    SizedBox(height: 16),
                                    Text(
                                      'No billboards found',
                                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                children: [
                                  // Table Header
                                  Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: primaryBrown.withOpacity(0.05),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(12),
                                        topRight: Radius.circular(12),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Billboards (${_filteredBillboards.length})',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: darkBrown,
                                          ),
                                        ),
                                        Spacer(),
                                        Text(
                                          'Active: ${_filteredBillboards.where((b) => b.isActivated).length}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Table Content
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _filteredBillboards.length,
                                      itemBuilder: (context, index) {
                                        final billboard = _filteredBillboards[index];
                                        final isSelected = _selectedBillboardId == billboard.billboardId;
                                        
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: isSelected ? primaryBrown.withOpacity(0.1) : Colors.transparent,
                                            border: Border(
                                              bottom: BorderSide(color: Colors.grey[200]!),
                                            ),
                                          ),
                                          child: ListTile(
                                            onTap: () => _selectBillboard(billboard.billboardId),
                                            leading: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: billboard.isActivated ? Colors.green : Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            title: Text(
                                              'Billboard ${billboard.billboardNumber}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: isSelected ? primaryBrown : darkBrown,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  billboard.location,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                SizedBox(height: 2),
                                                Container(
                                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: billboard.isActivated 
                                                        ? Colors.green.withOpacity(0.1)
                                                        : Colors.red.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    billboard.isActivated ? 'ACTIVE' : 'INACTIVE',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: billboard.isActivated 
                                                          ? Colors.green[700] 
                                                          : Colors.red[700],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            trailing: PopupMenuButton<String>(
                                              icon: Icon(Icons.more_vert, size: 16, color: accentBrown),
                                              onSelected: (value) {
                                                switch (value) {
                                                  case 'details':
                                                    _showBillboardDetails(billboard);
                                                    break;
                                                  case 'toggle':
                                                    _toggleBillboardStatus(billboard);
                                                    break;
                                                  case 'delete':
                                                    _showDeleteConfirmation(billboard);
                                                    break;
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                PopupMenuItem(
                                                  value: 'details',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.info_outline, size: 16, color: primaryBrown),
                                                      SizedBox(width: 8),
                                                      Text('View Details'),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'toggle',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        billboard.isActivated ? Icons.toggle_off : Icons.toggle_on, 
                                                        size: 16, 
                                                        color: billboard.isActivated ? Colors.red : Colors.green,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(billboard.isActivated ? 'Deactivate' : 'Activate'),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                                      SizedBox(width: 8),
                                                      Text('Delete', style: TextStyle(color: Colors.red)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
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

  void _showDeleteConfirmation(Billboard billboard) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Container(
            padding: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.warning_outlined,
                    color: Colors.red,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Delete Billboard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: darkBrown,
                  ),
                ),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to delete this billboard?',
                style: TextStyle(fontSize: 16, color: Colors.grey[800]),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Billboard ${billboard.billboardNumber}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: darkBrown,
                      ),
                    ),
                    Text(
                      billboard.location,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                'This action cannot be undone.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final supabaseService = Provider.of<SupabaseService>(context, listen: false);
                  
                  await supabaseService.client
                      .from('billboard')
                      .delete()
                      .eq('billboard_id', billboard.billboardId);
                  
                  await _loadBillboards();
                  Navigator.of(context).pop();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Billboard deleted successfully!'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting billboard: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete, size: 18),
                  SizedBox(width: 4),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}