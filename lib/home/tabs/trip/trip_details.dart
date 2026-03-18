import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
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
  final FocusNode _destinationFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();

  DateTimeRange? _selectedDateRange;
  int _selectedVehicleIndex = -1;
  double _passengerCount = 1.0;

  // ── Autocomplete state ────────────────────────────────────────────────────
  List<Map<String, String>> _suggestions = [];
  bool _loadingSuggestions = false;
  Timer? _debounce;
  OverlayEntry? _overlayEntry;

  final List<Map<String, dynamic>> _vehicles = [
    {"name": "Bike",  "icon": Icons.two_wheeler,      "min": 1.0, "max": 1.0},
    {"name": "Mini",  "icon": Icons.directions_car,   "min": 1.0, "max": 4.0},
    {"name": "SUV",   "icon": Icons.airport_shuttle,  "min": 1.0, "max": 7.0},
    {"name": "Bus",   "icon": Icons.directions_bus,   "min": 1.0, "max": 15.0},
  ];

  @override
  void initState() {
    super.initState();
    _destinationController.addListener(_onDestinationChanged);
    _destinationFocusNode.addListener(() {
      if (!_destinationFocusNode.hasFocus) {
        _hideOverlay();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destinationController.removeListener(_onDestinationChanged);
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    _hideOverlay();
    super.dispose();
  }

  // ── Autocomplete logic ────────────────────────────────────────────────────

  void _onDestinationChanged() {
    setState(() {});
    final query = _destinationController.text.trim();
    if (query.isEmpty) {
      _hideOverlay();
      return;
    }
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.length < 1) return;

    setState(() => _loadingSuggestions = true);

    try {
      // Using OpenStreetMap Nominatim — free, no API key needed
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=5'
        '&featuretype=city,town,village,state',
      );

      final res = await http.get(uri, headers: {
        'Accept-Language': 'en',
        'User-Agent': 'TripShareApp/1.0',
      });

      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        final List<Map<String, String>> results = [];

        for (var item in data) {
          final addr = item['address'] as Map<String, dynamic>? ?? {};

          // Build place, state, country format
          final place = addr['city'] ??
              addr['town'] ??
              addr['village'] ??
              addr['county'] ??
              addr['state_district'] ??
              item['name'] ??
              '';

          final state   = addr['state']   ?? '';
          final country = addr['country'] ?? '';

          if (place.isEmpty) continue;

          final parts = [place, if (state.isNotEmpty) state, if (country.isNotEmpty) country];
          final display = parts.join(', ');

          // Deduplicate
          if (!results.any((r) => r['display'] == display)) {
            results.add({'display': display, 'place': place});
          }

          if (results.length >= 5) break;
        }

        if (mounted) {
          setState(() {
            _suggestions = results;
            _loadingSuggestions = false;
          });
          if (results.isNotEmpty && _destinationFocusNode.hasFocus) {
            _showOverlay();
          } else {
            _hideOverlay();
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  void _selectSuggestion(String display) {
    _destinationController.text = display;
    _destinationController.selection = TextSelection.fromPosition(
      TextPosition(offset: display.length),
    );
    _hideOverlay();
    _destinationFocusNode.unfocus();
  }

  void _showOverlay() {
    _hideOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: MediaQuery.of(context).size.width - 48,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.map((s) {
                  final display = s['display'] ?? '';
                  final parts   = display.split(', ');
                  final place   = parts.isNotEmpty ? parts[0] : display;
                  final rest    = parts.length > 1
                      ? parts.sublist(1).join(', ')
                      : '';

                  return InkWell(
                    onTap: () => _selectSuggestion(display),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.location_on,
                                size: 16, color: Colors.black),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(place,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                if (rest.isNotEmpty)
                                  Text(rest,
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Backend ───────────────────────────────────────────────────────────────

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<int?> _saveTripToBackend(Map<String, dynamic> data) async {
    try {
      final String? token = await _getToken();
      if (token == null) { _showError("User not logged in"); return null; }

      final response = await http.post(
        Uri.parse('$baseUrl/api/savetrip/trip/'),
        headers: {
          "Content-Type":  "application/json",
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleNext() async {
    if (_isFormValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Processing Trip Details...")),
      );

      final tripData = {
        "destination": _destinationController.text,
        "start_date":  DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
        "end_date":    DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
        "vehicle":     _vehicles[_selectedVehicleIndex]['name'],
        "passengers":  _passengerCount.toInt(),
      };

      int? tripId = await _saveTripToBackend(tripData);

      if (tripId != null && mounted) {
        Navigator.pushNamed(
          context,
          AppRoutes.routeDetails,
          arguments: {
            'tripId':      tripId,
            'destination': _destinationController.text,
            'startDate':   DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
            'endDate':     DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
            'passengers':  _passengerCount.toInt(),
          },
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final startDateText = _selectedDateRange == null
        ? "Select Start"
        : DateFormat('MMM dd, yyyy').format(_selectedDateRange!.start);
    final endDateText = _selectedDateRange == null
        ? "Select End"
        : DateFormat('MMM dd, yyyy').format(_selectedDateRange!.end);

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

                    // ── Destination with autocomplete ─────────────────────
                    const Text("Destination",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),

                    CompositedTransformTarget(
                      link: _layerLink,
                      child: TextField(
                        controller:  _destinationController,
                        focusNode:   _destinationFocusNode,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: "Where are you going?",
                          prefixIcon: const Icon(Icons.location_on_outlined,
                              color: Colors.grey),
                          suffixIcon: _loadingSuggestions
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.black),
                                  ),
                                )
                              : _destinationController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          color: Colors.grey, size: 18),
                                      onPressed: () {
                                        _destinationController.clear();
                                        _hideOverlay();
                                      },
                                    )
                                  : null,
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                                color: Colors.black, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 18),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // ── Dates ─────────────────────────────────────────────
                    const Text("Dates",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDateRange,
                            child: _buildDateBox("Start Date", startDateText),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDateRange,
                            child: _buildDateBox("End Date", endDateText),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    // ── Vehicle ───────────────────────────────────────────
                    const Text("Mode of Transport",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 15),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _vehicles.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final vehicle    = _vehicles[index];
                          final isSelected = _selectedVehicleIndex == index;
                          return GestureDetector(
                            onTap: () => _onVehicleSelected(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 80,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFFD54F)
                                    : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(16),
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.black, width: 1.5)
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(vehicle['icon'],
                                      size: 32,
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.grey[600]),
                                  const SizedBox(height: 8),
                                  Text(vehicle['name'],
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.black
                                              : Colors.grey[600])),
                                  Text(
                                    vehicle['name'] == "Bike"
                                        ? "1 seat"
                                        : "max ${vehicle['max'].toInt()}",
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isSelected
                                            ? Colors.black54
                                            : Colors.grey[400]),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 30),

                    // ── Passengers ────────────────────────────────────────
                    if (_selectedVehicleIndex != -1) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Passengers",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 4),
                              Text("Remaining available seats",
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(12)),
                            child: Text("${_passengerCount.toInt()}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _vehicles[_selectedVehicleIndex]['name'] == 'Bike'
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Text(
                                  "Bike is limited to 1 person.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey)),
                            )
                          : SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFFFFD54F),
                                inactiveTrackColor: Colors.grey[300],
                                thumbColor: Colors.black,
                                overlayColor:
                                    const Color(0xFFFFD54F).withOpacity(0.2),
                                trackHeight: 6.0,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 10.0),
                              ),
                              child: Slider(
                                value: _passengerCount,
                                min: _vehicles[_selectedVehicleIndex]['min'],
                                max: _vehicles[_selectedVehicleIndex]['max'],
                                divisions: (_vehicles[_selectedVehicleIndex]
                                            ['max'] -
                                        _vehicles[_selectedVehicleIndex]['min'])
                                    .toInt(),
                                label: _passengerCount.round().toString(),
                                onChanged: (double value) =>
                                    setState(() => _passengerCount = value),
                              ),
                            ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Next Button ───────────────────────────────────────────────
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: const Text("Next",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
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
      decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ),
    );
  }
}