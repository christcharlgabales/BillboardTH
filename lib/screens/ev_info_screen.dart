import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';

class EVInfoScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SupabaseService>(builder: (context, supabaseService, child) {
      final vehicle = supabaseService.currentVehicle;  // Ensure this is correctly fetched
      
      return SingleChildScrollView(  // Added scroll support to avoid overflow
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emergency Vehicle\nInformation',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B4B3B),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              
              _buildInfoCard('TYPE', vehicle?.evType ?? 'Loading...'),
              SizedBox(height: 16),
              _buildInfoCard('AGENCY', vehicle?.agency ?? 'Loading...'),
              SizedBox(height: 16),
              _buildInfoCard('PLATE NUMBER', vehicle?.plateNumber ?? 'Loading...'),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildInfoCard(String title, String value) {
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
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
