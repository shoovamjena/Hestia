import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'otp_screen.dart';

class ReferralCodeScreen extends StatefulWidget {
  static const illustrationAsset = 'assets/images/referral_illustration.png';

  final String phoneNumber;

  const ReferralCodeScreen({super.key, required this.phoneNumber});

  @override
  State<ReferralCodeScreen> createState() => _ReferralCodeScreenState();
}

class _ReferralCodeScreenState extends State<ReferralCodeScreen> {
  final _referralController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _sendOtpAndProceed() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await SupabaseService.signInWithOtp(phone: widget.phoneNumber);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OtpScreen.phone(phoneNumber: widget.phoneNumber),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } on SocketException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to reach the server. Check your internet connection.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HestiaColors.appBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Image.asset(
                        ReferralCodeScreen.illustrationAsset,
                        height: 220,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 220,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(
                              Icons.image_outlined,
                              size: 48,
                              color: Color(0xFFBDBDBD),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Enter referral code',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: HestiaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "It's optional, you can skip this",
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF9A9A9A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      decoration: BoxDecoration(
                        color: HestiaColors.inputBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _referralController,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: HestiaColors.textDark,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter referral code',
                          hintStyle: TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: HestiaColors.background,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOtpAndProceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                disabledBackgroundColor: const Color(0xFFD9D9D9),
                disabledForegroundColor: Colors.white,
                foregroundColor: HestiaColors.buttonText,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _isLoading ? null : _sendOtpAndProceed,
            style: TextButton.styleFrom(
              foregroundColor: HestiaColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'Skip for now',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
