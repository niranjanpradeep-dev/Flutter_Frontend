import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/config/config.dart';
import '../../../routes.dart';
// ── NEW: import the map picker ──────────────────────────────────────────────
import 'map_picker_screen.dart';

const String baseUrl = AppConfig.baseUrl;

class RouteDetailsPage extends StatefulWidget {
  const RouteDetailsPage({super.key});

  @override
  State<RouteDetailsPage> createState() => _RouteDetailsPageState();
}

class _RouteDetailsPageState extends State<RouteDetailsPage> {
  final TextEditingController _startLocationController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _vehicleModelController = TextEditingController();

  int? _actualTripId;
  String _destinationName = "Loading...";
  int _passengerCount = 1;

  // ── NEW: hold the coordinates chosen from the map ───────────────────────
  double? _startLatitude;
  double? _startLongitude;

  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _tripMaxDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  final List<Map<String, dynamic>> _routeItems = [];
  bool _isLoading = false;
  bool _isInit = true;

  @override
  void initState() {
    super.initState();
    _routeItems.add({
      'id': 'destination_main',
      'type': 'destination',
      'value': _destinationName,
      'controller': null,
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _actualTripId = args['tripId'];
        _destinationName = args['destination'] ?? "Unknown";
        _passengerCount = args['passengers'] ?? 1;

        if (args['startDate'] != null) {
          _startDate = DateTime.parse(args['startDate']);
        }
        if (args['endDate'] != null) {
          _endDate = DateTime.parse(args['endDate']);
          _tripMaxDate = DateTime.parse(args['endDate']);
        }
      } else if (args is int) {
        _actualTripId = args;
      }

      final destIndex =
          _routeItems.indexWhere((item) => item['type'] == 'destination');
      if (destIndex != -1) {
        setState(() => _routeItems[destIndex]['value'] = _destinationName);
      }
      _isInit = false;
    }
  }

  // ── NEW: open the map picker and fill the text field ─────────────────────
  Future<void> _openMapPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );

    if (result != null && mounted) {
      final latlng = result['latlng']; // LatLng object
      final address = result['address'] as String;

      setState(() {
        _startLocationController.text = address;
        _startLatitude = latlng.latitude as double;
        _startLongitude = latlng.longitude as double;
      });
    }
  }

  // ── Date / Time pickers ──────────────────────────────────────────────────
  Future<void> _pickStartTime() async {
    final TimeOfDay? picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndDate() async {
    if (_startDate == null || _tripMaxDate == null) return;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _tripMaxDate!,
      firstDate: _startDate!,
      lastDate: _tripMaxDate!,
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _pickEndTime() async {
    final TimeOfDay? picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _endTime = picked);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _handleSubmit() async {
    if (_startLocationController.text.isEmpty ||
        _vehicleNumberController.text.isEmpty ||
        _vehicleModelController.text.isEmpty ||
        _startTime == null ||
        _endTime == null ||
        _endDate == null) {
      _showError("Please fill in all details.");
      return;
    }

    if (_actualTripId == null) {
      _showError("Error: No Trip ID found.");
      return;
    }

    final fullStartDateTime = DateTime(
      _startDate!.year,
      _startDate!.month,
      _startDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final fullEndDateTime = DateTime(
      _endDate!.year,
      _endDate!.month,
      _endDate!.day,
      _endTime!.hour,
      _endTime!.minute,
    );

    if (fullEndDateTime.isBefore(fullStartDateTime)) {
      _showError("Arrival time cannot be before Start time.");
      return;
    }
    if (_tripMaxDate != null) {
      final maxWithTime = DateTime(
          _tripMaxDate!.year, _tripMaxDate!.month, _tripMaxDate!.day, 23, 59, 59);
      if (fullEndDateTime.isAfter(maxWithTime)) {
        _showError("Arrival cannot be after the trip's scheduled end date.");
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final String? token = await _getToken();
      if (token == null) {
        _showError("User not logged in");
        return;
      }

      List<String> stopsList = _routeItems
          .where((item) => item['type'] == 'stop')
          .map((item) => item['controller'].text.toString())
          .toList();

      final Map<String, dynamic> requestBody = {
        "trip_id": _actualTripId,
        "start_location": _startLocationController.text,
        "start_datetime": fullStartDateTime.toIso8601String(),
        "end_datetime": fullEndDateTime.toIso8601String(),
        "stops": stopsList,
        "vehicle_number": _vehicleNumberController.text,
        "vehicle_model": _vehicleModelController.text,
        // ── NEW: send coordinates if the user pinned them on the map ──────
        if (_startLatitude != null) "start_latitude": _startLatitude,
        if (_startLongitude != null) "start_longitude": _startLongitude,
      };

      final Uri url = Uri.parse('$baseUrl/api/savetrip/route/');
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Token $token"
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        Navigator.pushNamed(
          context,
          AppRoutes.paymentDetails,
          arguments: {
            'tripId': _actualTripId,
            'tripStartDate': fullStartDateTime.toIso8601String(),
            'passengers': _passengerCount,
          },
        );
      } else {
        _showError("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Connection failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _addStop() {
    if (_routeItems.where((item) => item['type'] == 'stop').length < 8) {
      setState(() {
        _routeItems.insert(0, {
          'id': UniqueKey().toString(),
          'type': 'stop',
          'value': '',
          'controller': TextEditingController(),
        });
      });
    } else {
      _showError("Maximum 8 stops allowed.");
    }
  }

  void _removeStop(int index) {
    setState(() {
      if (_routeItems[index]['controller'] != null) {
        _routeItems[index]['controller'].dispose();
      }
      _routeItems.removeAt(index);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _routeItems.removeAt(oldIndex);
      _routeItems.insert(newIndex, item);
    });
  }

  @override
  void dispose() {
    _startLocationController.dispose();
    _vehicleNumberController.dispose();
    _vehicleModelController.dispose();
    for (var item in _routeItems) {
      if (item['controller'] != null) item['controller'].dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int stopCount =
        _routeItems.where((item) => item['type'] == 'stop').length;
    String startDayStr = _startDate != null
        ? DateFormat('MMM dd').format(_startDate!)
        : "";
    String startTimeStr =
        _startTime != null ? _startTime!.format(context) : "Set Time";
    String endDayStr =
        _endDate != null ? DateFormat('MMM dd').format(_endDate!) : "Set Date";
    String endTimeStr =
        _endTime != null ? _endTime!.format(context) : "Set Time";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Route Details"),
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
                    const Text("Route Details",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 15),

                    // ── Start location card ────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // ── NEW: tappable map-pin icon ───────────────
                              GestureDetector(
                                onTap: _openMapPicker,
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: _startLatitude != null
                                        ? Colors.black
                                        : Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.grey[300]!, width: 1.5),
                                  ),
                                  child: Icon(
                                    Icons.my_location,
                                    size: 20,
                                    color: _startLatitude != null
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _startLocationController,
                                  decoration: InputDecoration(
                                    hintText: "Start Location",
                                    hintStyle:
                                        const TextStyle(color: Colors.grey),
                                    border: InputBorder.none,
                                    // small "pinned" badge when location is set
                                    suffixIcon: _startLatitude != null
                                        ? const Tooltip(
                                            message: "Location pinned on map",
                                            child: Icon(Icons.check_circle,
                                                color: Colors.green, size: 18),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: [
                                const Icon(Icons.calendar_today,
                                    size: 16, color: Colors.grey),
                                const SizedBox(width: 5),
                                Text(startDayStr,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey))
                              ]),
                              GestureDetector(
                                onTap: _pickStartTime,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.grey[300]!)),
                                  child: Row(children: [
                                    const Icon(Icons.access_time, size: 16),
                                    const SizedBox(width: 5),
                                    Text(startTimeStr,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold))
                                  ]),
                                ),
                              )
                            ],
                          )
                        ],
                      ),
                    ),

                    Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Container(
                            height: 15,
                            width: 2,
                            color: Colors.grey[300])),

                    if (stopCount < 8)
                      Center(
                        child: TextButton.icon(
                          onPressed: _addStop,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.add,
                              size: 18, color: Colors.black),
                          label: const Text("Add Stop",
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                      ),

                    if (stopCount < 8)
                      Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: Container(
                              height: 15,
                              width: 2,
                              color: Colors.grey[300])),

                    Theme(
                      data: Theme.of(context).copyWith(
                          canvasColor: Colors.transparent,
                          shadowColor: Colors.transparent),
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _routeItems.length,
                        onReorder: _onReorder,
                        itemBuilder: (context, index) {
                          final item = _routeItems[index];
                          if (item['type'] == 'destination') {
                            return Container(
                              key: ValueKey(item['id']),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFFF8E1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: const Color(0xFFFFD54F))),
                              child: Column(children: [
                                Row(children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.black),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        const Text("Destination",
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey)),
                                        Text(item['value'],
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16))
                                      ])),
                                  const Icon(Icons.drag_indicator,
                                      color: Colors.black54)
                                ]),
                                const Divider(height: 20),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      GestureDetector(
                                          onTap: _pickEndDate,
                                          child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: Row(children: [
                                                const Icon(
                                                    Icons.calendar_today,
                                                    size: 14),
                                                const SizedBox(width: 5),
                                                Text(endDayStr,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12))
                                              ]))),
                                      GestureDetector(
                                          onTap: _pickEndTime,
                                          child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: Row(children: [
                                                const Icon(
                                                    Icons.access_time,
                                                    size: 14),
                                                const SizedBox(width: 5),
                                                Text(endTimeStr,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12))
                                              ]))),
                                    ]),
                              ]),
                            );
                          }
                          return Container(
                            key: ValueKey(item['id']),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              IconButton(
                                  icon: const Icon(
                                      CupertinoIcons.xmark_circle_fill,
                                      color: Colors.grey),
                                  onPressed: () => _removeStop(index)),
                              Expanded(
                                  child: TextField(
                                      controller: item['controller'],
                                      decoration: InputDecoration(
                                          hintText: "Stop Name",
                                          filled: true,
                                          fillColor:
                                              const Color(0xFFF5F5F5),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 14),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide:
                                                  BorderSide.none)))),
                              const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Icon(Icons.drag_indicator,
                                      color: Colors.grey))
                            ]),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 30),
                    const Divider(thickness: 1),
                    const SizedBox(height: 20),

                    const Text("Vehicle Details",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 15),

                    TextField(
                      controller: _vehicleNumberController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp("[a-zA-Z0-9]")),
                        UpperCaseTextFormatter()
                      ],
                      decoration: InputDecoration(
                          labelText: "Vehicle Number",
                          prefixIcon: const Icon(CupertinoIcons.tag,
                              color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 18)),
                    ),
                    const SizedBox(height: 15),
                    _buildTextField(
                        _vehicleModelController,
                        "Company & Model",
                        Icons.directions_car_outlined),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30))),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text("Confirm & Create Trip",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon) {
    return TextField(
        controller: controller,
        decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 18)));
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
        text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}
