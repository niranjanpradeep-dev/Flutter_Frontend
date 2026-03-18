import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_app/config/config.dart';

class OtpVerifyPage extends StatefulWidget {
  final int    tripId;
  final String tripName;

  const OtpVerifyPage({
    Key? key,
    required this.tripId,
    required this.tripName,
  }) : super(key: key);

  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage> {
  bool _isLoading     = true;
  bool _isStarting    = false;
  bool _tripCompleted = false;
  List _members       = [];

  // One OTP text controller per member, keyed by user_id
  final Map<int, TextEditingController> _otpControllers  = {};
  final Map<int, bool>                  _isVerifying     = {};
  final Map<int, String?>               _errorMessages   = {};

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  @override
  void dispose() {
    for (var c in _otpControllers.values) c.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // Safe int parser — handles int, double, or String from JSON
  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  Future<void> _initPage() async {
    setState(() => _isStarting = true);
    try {
      final token = await _getToken();
      // Start trip — generates OTPs for all members (idempotent)
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/trips/${widget.tripId}/start/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );
      await _loadBoardingData();
    } catch (e) {
      _showSnack('Error starting trip: $e');
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _loadBoardingData() async {
    setState(() => _isLoading = true);
    try {
      final token    = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/trips/${widget.tripId}/boarding/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body);
        final members = (data['members'] ?? []) as List;

        // Create a controller for each member not yet tracked
        for (var member in members) {
          // FIX: was `member['user_id'] as int` — crashes if API returns String
          final uid = _parseInt(member['user_id']);
          if (!_otpControllers.containsKey(uid)) {
            _otpControllers[uid] = TextEditingController();
          }
        }

        setState(() {
          _members       = members;
          _tripCompleted = data['all_verified'] == true ||
              data['status'] == 'completed';
        });
      } else {
        _showSnack('Failed to load boarding data');
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOtp(int userId, String memberName) async {
    final controller = _otpControllers[userId];
    final otp        = controller?.text.trim() ?? '';

    if (otp.length != 4) {
      setState(() => _errorMessages[userId] = 'Enter the 4-digit OTP');
      return;
    }

    setState(() {
      _isVerifying[userId]   = true;
      _errorMessages[userId] = null;
    });

    try {
      final token    = await _getToken();
      final response = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/api/trips/${widget.tripId}/verify/$userId/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode({'otp': otp}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['verified'] == true) {
        controller?.clear();
        _showSnack('$memberName verified ✓');

        if (data['trip_completed'] == true) {
          setState(() => _tripCompleted = true);
          _showCompletionDialog();
        } else {
          await _loadBoardingData();
        }
      } else {
        setState(() =>
            _errorMessages[userId] = data['error'] ?? 'Incorrect OTP');
      }
    } catch (e) {
      setState(() => _errorMessages[userId] = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isVerifying[userId] = false);
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Trip Completed!'),
          ],
        ),
        content: Text(
            'All members of "${widget.tripName}" have been verified.\n\nPayment status has been updated.'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // go back to previous screen
            },
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
                        const Text('Board Verification',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(widget.tripName,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey)),
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

            // ── Instructions banner ───────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ask each member for their OTP and enter it below to verify them.',
                      style: TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            if (_tripCompleted)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('All members verified — Trip Completed!',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

            // ── Members list ──────────────────────────────────────────
            Expanded(
              child: (_isLoading || _isStarting)
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black))
                  : _members.isEmpty
                      ? const Center(
                          child: Text('No members found',
                              style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _loadBoardingData,
                          color: Colors.black,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            itemCount: _members.length,
                            itemBuilder: (context, index) {
                              final member = _members[index];

                              // FIX: safe casts — API can return int or String
                              final memberId =
                                  _parseInt(member['user_id']);
                              final name =
                                  member['name']?.toString() ?? 'Unknown';
                              final verified  = member['verified'] == true;
                              final isAdminMember =
                                  member['is_admin'] == true;
                              final isVerifying =
                                  _isVerifying[memberId] == true;
                              final errorMsg = _errorMessages[memberId];

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 4),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                                color: verified
                                    ? Colors.green.withOpacity(0.05)
                                    : const Color(0xFFF9F9F9),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // ── Member info row ────────────
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: isAdminMember
                                                ? Colors.black
                                                : const Color(0xFFE0E0E0),
                                            child: Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                color: isAdminMember
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Text(name,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15)),
                                                if (isAdminMember) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black,
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(4),
                                                    ),
                                                    child: const Text('ADMIN',
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (verified)
                                            Container(
                                              padding:
                                                  const EdgeInsets.all(6),
                                              decoration: const BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.check,
                                                  color: Colors.white,
                                                  size: 16),
                                            ),
                                        ],
                                      ),

                                      // ── OTP input (only if not verified) ──
                                      if (!verified && !_tripCompleted) ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _otpControllers[
                                                    memberId],
                                                keyboardType:
                                                    TextInputType.number,
                                                textAlign: TextAlign.center,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly,
                                                  LengthLimitingTextInputFormatter(
                                                      4),
                                                ],
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 8,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText: '_ _ _ _',
                                                  hintStyle: TextStyle(
                                                      color: Colors.grey[400],
                                                      letterSpacing: 4,
                                                      fontSize: 20),
                                                  filled: true,
                                                  fillColor: const Color(
                                                      0xFFFFFDE7),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    borderSide: BorderSide(
                                                        color: const Color(
                                                                0xFFFFD54F)
                                                            .withOpacity(0.5)),
                                                  ),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    borderSide: BorderSide(
                                                        color: const Color(
                                                                0xFFFFD54F)
                                                            .withOpacity(0.5)),
                                                  ),
                                                  focusedBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    borderSide:
                                                        const BorderSide(
                                                            color: Color(
                                                                0xFFFFD54F),
                                                            width: 2),
                                                  ),
                                                  errorText: errorMsg,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                              vertical: 14),
                                                ),
                                                onSubmitted: (_) =>
                                                    _submitOtp(
                                                        memberId, name),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            isVerifying
                                                ? const SizedBox(
                                                    height: 24,
                                                    width: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                Colors.black))
                                                : ElevatedButton(
                                                    onPressed: () =>
                                                        _submitOtp(
                                                            memberId, name),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.black,
                                                      foregroundColor:
                                                          Colors.white,
                                                      elevation: 0,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                              horizontal: 18,
                                                              vertical: 14),
                                                      shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12)),
                                                    ),
                                                    child: const Text('Verify',
                                                        style: TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ),
                                          ],
                                        ),
                                      ],

                                      if (verified)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            'Boarded ✓',
                                            style: TextStyle(
                                                color: Colors.green[700],
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}