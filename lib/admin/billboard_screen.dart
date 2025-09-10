// lib/admin/billboard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
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

  @override
  void initState() {
    super.initState();
    _loadBillboards();
  }

  Future<void> _loadBillboards() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      await supabaseService.loadBillboards();
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

  void _updateMarkers(List<Billboard> billboards) {
    setState(() {
      _markers = billboards.map((billboard) {
        return Marker(
          markerId: MarkerId(billboard.billboardId.toString()),
          position: LatLng(billboard.latitude, billboard.longitude),
          onTap: () => _selectBillboard(billboard.billboardId),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _selectedBillboardId == billboard.billboardId 
                ? BitmapDescriptor.hueBlue
                : billboard.isActivated 
                    ? BitmapDescriptor.hueGreen 
                    : BitmapDescriptor.hueRed,
          ),
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

  void _showBillboardDetails(Billboard billboard) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Billboard Details'),
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

  Future<void> _toggleBillboardStatus(Billboard billboard) async {
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final newStatus = !billboard.isActivated;
      
      // Update local state
      supabaseService.updateBillboardStatus(billboard.billboardId, newStatus);
      
      // Update markers
      _updateMarkers(supabaseService.billboards);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Billboard ${billboard.billboardNumber} ${newStatus ? 'activated' : 'deactivated'}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error toggling billboard status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating billboard status: $e'),
          backgroundColor: Colors.red,
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
                  color: Colors.black87,
                ),
              ),
              Spacer(),
              IconButton(
                onPressed: _loadBillboards,
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
                    hintText: 'Search billboards...',
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
                        ? Center(child: CircularProgressIndicator())
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
                                      color: Colors.grey[50],
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
                                            color: isSelected ? Colors.blue[50] : Colors.transparent,
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
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  billboard.location,
                                                  style: TextStyle(fontSize: 12),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  billboard.isActivated ? 'ACTIVE' : 'INACTIVE',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: billboard.isActivated ? Colors.green[700] : Colors.red[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            trailing: PopupMenuButton<String>(
                                              icon: Icon(Icons.more_vert, size: 16),
                                              onSelected: (value) {
                                                switch (value) {
                                                  case 'details':
                                                    _showBillboardDetails(billboard);
                                                    break;
                                                  case 'toggle':
                                                    _toggleBillboardStatus(billboard);
                                                    break;
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                PopupMenuItem(
                                                  value: 'details',
                                                  child: Text('View Details'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'toggle',
                                                  child: Text(billboard.isActivated ? 'Deactivate' : 'Activate'),
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
}