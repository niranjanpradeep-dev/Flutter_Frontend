import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/misc/position.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  // Default center: India
  LatLng _pickedLocation = const LatLng(20.5937, 78.9629);
  final MapController _mapController = MapController();
  Timer? _debounce;

  String _addressText = "Move the map to pin your location";
  bool _isResolving = false;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _goToCurrentLocation();
  }

  // ── 1. Get device GPS location ────────────────────────────────────────────
  Future<void> _goToCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception("Location services disabled");

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        throw Exception("Location permission denied");
      }

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final LatLng current = LatLng(pos.latitude, pos.longitude);
      setState(() => _pickedLocation = current);
      _mapController.move(current, 16.0);
      await _reverseGeocode(current);
    } catch (e) {
      // Fall back to default center quietly
      await _reverseGeocode(_pickedLocation);
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── 2. Nominatim reverse geocoding (free, no API key) ────────────────────
  Future<void> _reverseGeocode(LatLng position) async {
    setState(() => _isResolving = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=${position.latitude}'
        '&lon=${position.longitude}'
        '&zoom=18'
        '&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {'Accept-Language': 'en', 'User-Agent': 'FlutterTripApp/1.0'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String displayName = data['display_name'] ?? 'Unknown location';
        // Shorten: keep first 3 comma-separated segments
        final parts = displayName.split(',');
        final short = parts.take(3).join(',').trim();
        if (mounted) setState(() => _addressText = short);
      } else {
        if (mounted) setState(() => _addressText = 'Could not resolve address');
      }
    } catch (_) {
      if (mounted) setState(() => _addressText = 'Could not resolve address');
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  // Called every time the map moves (flutter_map 6.x uses MapPosition)
  void _onMapPositionChanged(MapPosition position, bool hasGesture) {
    if (position.center != null) {
      setState(() => _pickedLocation = position.center!);
      // Debounce: only geocode 600ms after the user stops dragging
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        _reverseGeocode(_pickedLocation);
      });
    }
  }


  void _confirmLocation() {
    Navigator.pop(context, {
      'latlng': _pickedLocation,
      'address': _addressText,
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Pin Your Start Location",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickedLocation,
              initialZoom: 14.0,
              onPositionChanged: _onMapPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_app',
              ),
            ],
          ),

          // ── Centre pin ───────────────────────────────────────────────────
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_pin, color: Colors.red, size: 48),
                // Shadow dot beneath pin
                SizedBox(
                  width: 12,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Current location FAB ─────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 160,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: _isLoadingLocation ? null : _goToCurrentLocation,
              child: _isLoadingLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.my_location, color: Colors.black),
            ),
          ),

          // ── Bottom address card + confirm button ─────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Text(
                    "Selected Location",
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _isResolving
                            ? const Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text("Resolving address...", style: TextStyle(color: Colors.grey)),
                                ],
                              )
                            : Text(
                                _addressText,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${_pickedLocation.latitude.toStringAsFixed(5)}, ${_pickedLocation.longitude.toStringAsFixed(5)}",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isResolving || _addressText == "Move the map to pin your location")
                          ? null
                          : _confirmLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text(
                        "Confirm Location",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
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
}
