import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/config/config.dart';
import '../../../routes.dart';

const String baseUrl = AppConfig.baseUrl;

class PaymentDetailsPage extends StatefulWidget {
  const PaymentDetailsPage({super.key});

  @override
  State<PaymentDetailsPage> createState() => _PaymentDetailsPageState();
}

class _PaymentDetailsPageState extends State<PaymentDetailsPage> {
  // --- State ---
  int? _tripId;
  DateTime? _tripStartDate;
  int _passengerCount = 1;

  final TextEditingController _priceController = TextEditingController();
  
  // Deadlines
  DateTime? _bookingDeadline;
  DateTime? _cancelDeadline;

  // Payment
  String _paymentMethod = "UPI"; // Defaults to UPI
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _accountNoController = TextEditingController();
  final TextEditingController _ifscController = TextEditingController();

  bool _isVerified = false;
  bool _isVerifying = false; // For the spinner
  bool _isLoading = false;   // For the submit button

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    if (args != null) {
      _tripId = args['tripId'];
      // FIX: Ensure we catch the passenger count correctly
      _passengerCount = args['passengers'] ?? 1; 
      
      if (args['tripStartDate'] != null) {
        _tripStartDate = DateTime.parse(args['tripStartDate']);
      }
    }
  }

  // --- Logic ---

  void _verifyPaymentDetails() async {
    // Mock Verification Logic
    setState(() => _isVerifying = true);
    
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _isVerifying = false;
      _isVerified = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Account Verified Successfully!"), backgroundColor: Colors.green),
    );
  }

  Future<void> _pickDateTime(bool isBooking) async {
    if (_tripStartDate == null) return;

    DateTime initial = isBooking 
      ? (_bookingDeadline ?? _tripStartDate!) 
      : (_cancelDeadline ?? _tripStartDate!);

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: _tripStartDate!, // Absolute max is trip start
    );

    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return;

    final DateTime selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    // --- VALIDATION RULES ---
    
    if (isBooking) {
      // Rule: Booking must close at least 1 hour before trip
      DateTime limit = _tripStartDate!.subtract(const Duration(hours: 1));
      if (selected.isAfter(limit)) {
        _showError("Booking must close at least 1 hour before the trip.");
        return;
      }
      setState(() => _bookingDeadline = selected);
    } else {
      // Rule: Cancellation must close at least 2 hours before trip
      DateTime limit = _tripStartDate!.subtract(const Duration(hours: 2));
      if (selected.isAfter(limit)) {
        _showError("Cancellation must close at least 2 hours before the trip.");
        return;
      }
      setState(() => _cancelDeadline = selected);
    }
  }

  Future<void> _submitTrip() async {
    // 1. Verification Check
    if (!_isVerified) {
      _showError("Please verify your payment details first.");
      return;
    }

    // 2. Price Validation (50 - 99,999)
    if (_priceController.text.isEmpty) {
      _showError("Please enter a price per head.");
      return;
    }
    int price = int.tryParse(_priceController.text) ?? 0;
    if (price < 50 || price >= 100000) {
      _showError("Price per head must be between ₹50 and ₹99,999.");
      return;
    }

    // 3. Deadline Check
    if (_bookingDeadline == null || _cancelDeadline == null) {
      _showError("Please set both booking and cancellation deadlines.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      // Construct Payment Details JSON
      Map<String, String> paymentDetails = {};
      if (_paymentMethod == "UPI") {
        paymentDetails["upi_id"] = _upiController.text;
      } else {
        paymentDetails["account_no"] = _accountNoController.text;
        paymentDetails["ifsc"] = _ifscController.text;
      }

      final body = {
        "trip_id": _tripId,
        "price_per_head": price,
        "booking_deadline": _bookingDeadline!.toIso8601String(),
        "cancel_deadline": _cancelDeadline!.toIso8601String(),
        "payment_method": _paymentMethod,
        "payment_details": paymentDetails, 
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/savetrip/payment/'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Token $token",
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // --- UPDATED: Navigate to Contact Details instead of Home ---
        Navigator.pushNamed(
          context,
          AppRoutes.contactDetails, 
          arguments: {
            'tripId': _tripId, // Pass ID in case we need it later
          }
        );
      } else {
        _showError("Server Error: ${response.body}");
      }
    } catch (e) {
      _showError("Connection failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    // Calculate Earnings
    int price = int.tryParse(_priceController.text) ?? 0;
    int totalEarnings = price * _passengerCount; // Now uses correctly passed count

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Payment & Rules"),
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
              
              // --- 1. PRICING ---
              const Text("Set Your Price", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 15),
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                onChanged: (val) => setState(() {}), // Update calculation
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: "₹ ",
                  hintText: "0",
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                ),
              ),
              const SizedBox(height: 10),
              // Earning Preview
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      "Potential Earning: ₹$totalEarnings ($price x $_passengerCount seats)",
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 20),

              // --- 2. BOOKING POLICIES ---
              const Text("Booking Policies", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 5),
              const Text("Set deadlines based on the trip start time.", style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 20),

              _buildDateRow("Last Date to Book", _bookingDeadline, () => _pickDateTime(true)),
              const SizedBox(height: 15),
              _buildDateRow("Last Date to Cancel", _cancelDeadline, () => _pickDateTime(false)),

              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 20),

              // --- 3. PAYMENT METHOD ---
              const Text("Receive Money Via", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 15),
              
              // Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    _buildTab("UPI", _paymentMethod == "UPI"),
                    _buildTab("Bank Transfer", _paymentMethod == "Bank"),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Inputs based on selection
              if (_paymentMethod == "UPI")
                Row(
                  children: [
                    Expanded(child: _buildTextField(_upiController, "Enter UPI ID", Icons.qr_code)),
                    const SizedBox(width: 10),
                    _buildVerifyButton(),
                  ],
                )
              else 
                Column(
                  children: [
                    _buildTextField(_accountNoController, "Account Number", Icons.account_balance),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_ifscController, "IFSC Code", Icons.code)),
                        const SizedBox(width: 10),
                        _buildVerifyButton(),
                      ],
                    ),
                  ],
                ),

              const SizedBox(height: 40),

              // --- SUBMIT BUTTON ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitTrip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Post Trip", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Components ---

  Widget _buildDateRow(String label, DateTime? date, VoidCallback onTap) {
    String text = date != null ? DateFormat('MMM dd, hh:mm a').format(date) : "Select Date";
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Row(
              children: [
                Text(text, style: TextStyle(color: date != null ? Colors.black : Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                const Icon(Icons.edit_calendar, size: 18, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String text, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _paymentMethod = text == "UPI" ? "UPI" : "Bank";
            _isVerified = false; // Reset verification on change
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() => _isVerified = false), // Reset if edited
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildVerifyButton() {
    if (_isVerified) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.check, color: Colors.green),
      );
    }
    
    return GestureDetector(
      onTap: _verifyPaymentDetails,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15)),
        child: _isVerifying 
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text("Verify", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}