import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/config/config.dart';
import '../../../routes.dart';

const String baseUrl = AppConfig.baseUrl;

class TripDetailsPage extends StatefulWidget {
  const TripDetailsPage({super.key});

  @override
  State<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends State<TripDetailsPage> {
  final TextEditingController _destinationController = TextEditingController();
  DateTimeRange? _selectedDateRange;
  
  int _selectedVehicleIndex = -1;
  double _passengerCount = 1.0;

  final List<Map<String, dynamic>> _vehicles = [
    {"name": "Bike", "icon": Icons.two_wheeler, "min": 1.0, "max": 1.0},
    {"name": "Mini", "icon": Icons.directions_car, "min": 1.0, "max": 4.0},
    {"name": "SUV", "icon": Icons.airport_shuttle, "min": 1.0, "max": 7.0},
    {"name": "Bus", "icon": Icons.directions_bus, "min": 1.0, "max": 15.0},
  ];

  @override
  void initState() {
    super.initState();
    _destinationController.addListener(() { setState(() {}); });
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<int?> _saveTripToBackend(Map<String, dynamic> data) async {
    try {
      final String? token = await _getToken();
      if (token == null) {
        _showError("User not logged in");
        return null;
      }

      final Uri url = Uri.parse('$baseUrl/api/savetrip/trip/');
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Token $token",
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        return responseData['trip_id']; 
      } else {
        _showError("Server Error: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      _showError("Connection failed: $e");
      return null;
    }
  }

  Future<void> _pickDateRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              onSurface: Colors.black,
              secondary: Color(0xFFFFD54F),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDateRange = picked);
  }

  void _onVehicleSelected(int index) {
    setState(() {
      _selectedVehicleIndex = index;
      _passengerCount = _vehicles[index]['min'];
    });
  }

  bool _isFormValid() {
    return _destinationController.text.isNotEmpty &&
        _selectedDateRange != null &&
        _selectedVehicleIndex != -1;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleNext() async {
    if (_isFormValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Processing Trip Details...")),
      );

      final Map<String, dynamic> tripData = {
        "destination": _destinationController.text,
        "start_date": DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
        "end_date": DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
        "vehicle": _vehicles[_selectedVehicleIndex]['name'],
        "passengers": _passengerCount.toInt(),
      };

      int? tripId = await _saveTripToBackend(tripData);

      if (tripId != null && mounted) {
        // --- PASSING DATA TO NEXT PAGE ---
        Navigator.pushNamed(
          context, 
          AppRoutes.routeDetails, 
          arguments: {
            'tripId': tripId,
            'destination': _destinationController.text,
            'startDate': DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
            'endDate': DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
            // --- FIX IS HERE: Sending the passenger count ---
            'passengers': _passengerCount.toInt(), 
          }
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String startDateText = _selectedDateRange == null ? "Select Start" : DateFormat('MMM dd, yyyy').format(_selectedDateRange!.start);
    String endDateText = _selectedDateRange == null ? "Select End" : DateFormat('MMM dd, yyyy').format(_selectedDateRange!.end);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Plan Your Trip"),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Destination", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _destinationController,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: "Where are you going?",
                        prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      ),
                    ),
                    const SizedBox(height: 25),
                    const Text("Dates", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: GestureDetector(onTap: _pickDateRange, child: _buildDateBox("Start Date", startDateText))),
                        const SizedBox(width: 15),
                        Expanded(child: GestureDetector(onTap: _pickDateRange, child: _buildDateBox("End Date", endDateText))),
                      ],
                    ),
                    const SizedBox(height: 25),
                    const Text("Mode of Transport", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 15),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _vehicles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final vehicle = _vehicles[index];
                          final isSelected = _selectedVehicleIndex == index;
                          return GestureDetector(
                            onTap: () => _onVehicleSelected(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 80,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFFFD54F) : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(16),
                                border: isSelected ? Border.all(color: Colors.black, width: 1.5) : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(vehicle['icon'], size: 32, color: isSelected ? Colors.black : Colors.grey[600]),
                                  const SizedBox(height: 8),
                                  Text(vehicle['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.black : Colors.grey[600])),
                                  Text(vehicle['name'] == "Bike" ? "1 seat" : "max ${vehicle['max'].toInt()}", style: TextStyle(fontSize: 10, color: isSelected ? Colors.black54 : Colors.grey[400])),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (_selectedVehicleIndex != -1) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Passengers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                            child: Text("${_passengerCount.toInt()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _vehicles[_selectedVehicleIndex]['name'] == 'Bike'
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              width: double.infinity,
                              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
                              child: const Text("Bike is limited to 1 person.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                            )
                          : SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFFFFD54F),
                                inactiveTrackColor: Colors.grey[300],
                                thumbColor: Colors.black,
                                overlayColor: const Color(0xFFFFD54F).withOpacity(0.2),
                                trackHeight: 6.0,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10.0),
                              ),
                              child: Slider(
                                value: _passengerCount,
                                min: _vehicles[_selectedVehicleIndex]['min'],
                                max: _vehicles[_selectedVehicleIndex]['max'],
                                divisions: (_vehicles[_selectedVehicleIndex]['max'] - _vehicles[_selectedVehicleIndex]['min']).toInt(),
                                label: _passengerCount.round().toString(),
                                onChanged: (double value) => setState(() => _passengerCount = value),
                              ),
                            ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isFormValid() ? _handleNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    disabledBackgroundColor: Colors.grey[300],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: const Text("Next", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}