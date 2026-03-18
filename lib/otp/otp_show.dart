import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_app/config/config.dart';

class OtpShowPage extends StatefulWidget {
  final int    tripId;
  final String tripName;

  const OtpShowPage({
    Key? key,
    required this.tripId,
    required this.tripName,
  }) : super(key: key);

  @override
  State<OtpShowPage> createState() => _OtpShowPageState();
}

class _OtpShowPageState extends State<OtpShowPage> {
  bool   _isLoading   = true;
  String _otp         = '';
  bool   _verified    = false;
  bool   _tripStarted = false;
  String _destination = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadOtp();
    // Poll every 8 seconds — catches when admin starts the trip
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 8), (_) => _loadOtp(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> _loadOtp({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final token    = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/trips/${widget.tripId}/my-otp/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // FIX: 'otp' from API could be an int (e.g. 1234) or a String ("1234")
        // Always convert to String for display
        final rawOtp = data['otp'];
        final otpStr = rawOtp != null ? rawOtp.toString() : '';

        // FIX: 'verified' could arrive as bool true/false or int 1/0
        final verifiedRaw = data['verified'];
        final isVerified  = verifiedRaw == true || verifiedRaw == 1;

        setState(() {
          _otp         = otpStr;
          _verified    = isVerified;
          _destination = data['destination']?.toString() ?? widget.tripName;
          _tripStarted = true;
        });
      } else if (response.statusCode == 404) {
        // Trip hasn't started yet — show waiting screen
        if (mounted) setState(() => _tripStarted = false);
      } else if (response.statusCode == 400) {
        // Admin calling this — shouldn't happen but handle gracefully
        final data = jsonDecode(response.body);
        _showSnack(data['error']?.toString() ?? 'Error');
      }
    } catch (e) {
      debugPrint('OTP load error: $e');
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
      // For silent refresh, just trigger a rebuild to reflect any state changes
      if (mounted && silent) setState(() {});
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your Boarding OTP',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(
                          _destination.isNotEmpty
                              ? _destination
                              : widget.tripName,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _showSnack('Report submitted (coming soon)'),
                    icon: const Icon(Icons.flag_outlined,
                        color: Colors.red, size: 18),
                    label: const Text('Report',
                        style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black))
                  : !_tripStarted
                      ? _buildWaitingState()
                      : _buildOtpState(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Waiting state — trip not started yet ──────────────────────────────────

  Widget _buildWaitingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.hourglass_top_rounded,
              size: 64, color: Colors.orange[700]),
        ),
        const SizedBox(height: 28),
        const Text(
          'Waiting for trip to start',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          'Your OTP will appear here once\nthe admin starts the trip.',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.grey[400]),
            ),
            const SizedBox(width: 8),
            Text('Checking automatically...',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () => _loadOtp(),
          icon: const Icon(Icons.refresh, color: Colors.black),
          label: const Text('Refresh now',
              style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  // ── OTP display state ─────────────────────────────────────────────────────

  Widget _buildOtpState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Status banner ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _verified
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('You have been verified!',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                )
              : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pending_outlined, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Show this OTP to your admin',
                          style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
        ),

        const SizedBox(height: 40),

        // ── OTP Box ───────────────────────────────────────────────────
        Container(
          width: 260,
          padding:
              const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            color: _verified
                ? Colors.green.withOpacity(0.05)
                : const Color(0xFFFFFDE7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _verified ? Colors.green : const Color(0xFFFFD54F),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (_verified ? Colors.green : Colors.amber)
                    .withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                _verified
                    ? Icons.verified_rounded
                    : Icons.lock_open_rounded,
                size: 44,
                color: _verified ? Colors.green : Colors.amber[700],
              ),
              const SizedBox(height: 16),
              // OTP digits — display with spacing
              Text(
                _otp.isNotEmpty ? _otp : '----',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 12,
                  color: _verified ? Colors.green : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _verified ? 'Boarded ✓' : 'Your 4-digit code',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // ── Auto-refresh indicator (only when not yet verified) ───────
        if (!_verified) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.grey[400]),
              ),
              const SizedBox(width: 8),
              Text('Auto-refreshes every 8 seconds',
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _loadOtp(),
            icon: const Icon(Icons.refresh, color: Colors.black),
            label: const Text('Refresh now',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ],
    );
  }
}