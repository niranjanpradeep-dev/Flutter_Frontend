import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/config/config.dart';
import '../../../routes.dart';

const String baseUrl = AppConfig.baseUrl;

class ContactDetailsPage extends StatefulWidget {
  const ContactDetailsPage({super.key});

  @override
  State<ContactDetailsPage> createState() => _ContactDetailsPageState();
}

class _ContactDetailsPageState extends State<ContactDetailsPage> {
  // --- State ---
  int? _tripId;
  
  // Controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _phoneOtpController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _emailOtpController = TextEditingController();

  // Verification Flags
  bool _isPhoneSent = false;
  bool _isPhoneVerified = false;
  bool _isEmailSent = false;
  bool _isEmailVerified = false;
  
  // Loading State for final submission
  bool _isSubmitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _tripId = args['tripId'];
    }
  }

  // --- Logic: Phone ---
  void _sendPhoneOtp() {
    if (_phoneController.text.length != 10) {
      _showError("Please enter a valid 10-digit number.");
      return;
    }
    setState(() => _isPhoneSent = true);
    _showSuccess("OTP sent to +91 ${_phoneController.text}");
  }

  void _verifyPhoneOtp() {
    if (_phoneOtpController.text.length != 4) {
      _showError("Enter valid 4-digit OTP");
      return;
    }
    setState(() => _isPhoneVerified = true);
  }

  // --- Logic: Email ---
  void _sendEmailOtp() {
    if (!_emailController.text.contains('@')) {
      _showError("Please enter a valid email.");
      return;
    }
    setState(() => _isEmailSent = true);
    _showSuccess("OTP sent to ${_emailController.text}");
  }

  void _verifyEmailOtp() {
    if (_emailOtpController.text.length != 4) {
      _showError("Enter valid 4-digit OTP");
      return;
    }
    setState(() => _isEmailVerified = true);
  }

  // --- Final Action: Save to Server ---
  Future<void> _onSlideComplete() async {
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (_tripId == null) {
        _showError("Error: Trip ID missing.");
        return;
      }

      final body = {
        "trip_id": _tripId,
        "phone": _phoneController.text,
        "email": _emailController.text,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/savetrip/contact/'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Token $token",
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Success! Show Dialog and Navigate
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Trip Published!"),
            content: const Text("Your trip has been successfully verified and published."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
                },
                child: const Text("Go to Dashboard"),
              )
            ],
          ),
        );
      } else {
        _showError("Server Error: ${response.body}");
        // Reset slide if failed so user can try again
        setState(() => _isSubmitting = false); 
      }
    } catch (e) {
      _showError("Connection failed: $e");
      setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }
  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    // Both must be verified to enable the slider
    bool canFinalize = _isPhoneVerified && _isEmailVerified && !_isSubmitting;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Contact Details"),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Verify Contact Info", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 5),
              const Text("We need to verify your details to publish the trip.", style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 30),

              // --- 1. PHONE SECTION ---
              _buildSectionHeader(Icons.phone_android, "Phone Number"),
              const SizedBox(height: 15),
              _buildPhoneInput(),
              
              if (_isPhoneSent && !_isPhoneVerified) ...[
                const SizedBox(height: 15),
                _buildOtpInput(_phoneOtpController, _verifyPhoneOtp),
              ],

              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 20),

              // --- 2. EMAIL SECTION ---
              _buildSectionHeader(Icons.email_outlined, "Email Address"),
              const SizedBox(height: 15),
              _buildEmailInput(),

              if (_isEmailSent && !_isEmailVerified) ...[
                const SizedBox(height: 15),
                _buildOtpInput(_emailOtpController, _verifyEmailOtp),
              ],

              const SizedBox(height: 50),

              // --- 3. SLIDE TO CONFIRM ---
              Center(
                child: SlideAction(
                  isActive: canFinalize,
                  onSubmit: _onSlideComplete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Widgets ---

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Text("+91", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_isPhoneVerified, // Lock if verified
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              hintText: "Enter 10 digit number",
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _isPhoneVerified 
          ? const Icon(Icons.check_circle, color: Colors.green, size: 32)
          : ElevatedButton(
              onPressed: _isPhoneSent ? null : _sendPhoneOtp, // Disable if OTP sent
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)
              ),
              child: const Text("Verify", style: TextStyle(color: Colors.white)),
            ),
      ],
    );
  }

  Widget _buildEmailInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !_isEmailVerified, // Lock if verified
            decoration: InputDecoration(
              hintText: "Enter email address",
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _isEmailVerified 
          ? const Icon(Icons.check_circle, color: Colors.green, size: 32)
          : ElevatedButton(
              onPressed: _isEmailSent ? null : _sendEmailOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)
              ),
              child: const Text("Verify", style: TextStyle(color: Colors.white)),
            ),
      ],
    );
  }

  Widget _buildOtpInput(TextEditingController controller, VoidCallback onVerify) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              hintText: "Enter 4-digit OTP",
              filled: true,
              fillColor: const Color(0xFFFFF8E1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: onVerify,
          child: const Text("Confirm OTP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        )
      ],
    );
  }
}

// --- Custom Slide to Confirm Widget (Standardized) ---
class SlideAction extends StatefulWidget {
  final bool isActive;
  final VoidCallback onSubmit;

  const SlideAction({super.key, required this.isActive, required this.onSubmit});

  @override
  State<SlideAction> createState() => _SlideActionState();
}

class _SlideActionState extends State<SlideAction> {
  double _dragValue = 0.0;
  final double _maxWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: widget.isActive ? (details) {
        setState(() {
          _dragValue = (_dragValue + details.delta.dx).clamp(0.0, _maxWidth - 50);
        });
      } : null,
      onHorizontalDragEnd: widget.isActive ? (details) {
        if (_dragValue > (_maxWidth - 60)) {
          setState(() => _dragValue = _maxWidth - 50);
          widget.onSubmit();
        } else {
          setState(() => _dragValue = 0.0);
        }
      } : null,
      child: Container(
        width: _maxWidth,
        height: 60,
        decoration: BoxDecoration(
          color: widget.isActive ? Colors.black : Colors.grey[300],
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                widget.isActive ? "Slide to Publish Trip" : "Verify Details First",
                style: TextStyle(
                  color: widget.isActive ? Colors.white : Colors.grey[500],
                  fontWeight: FontWeight.bold,
                  fontSize: 16
                ),
              ),
            ),
            Positioned(
              left: _dragValue,
              top: 5,
              bottom: 5,
              child: Container(
                width: 50,
                margin: const EdgeInsets.only(left: 5),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward, 
                  color: widget.isActive ? Colors.black : Colors.grey
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}