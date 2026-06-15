import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'home_screen.dart';
import 'post_sign_in_journey_screen.dart';

/// The type of OTP verification being performed.
enum OtpVerificationType {
  /// Phone-based OTP sign-in (6 digits)
  phoneSms,
  /// Email-based OTP for sign-up verification (6 digits)
  emailSignUp,
}

class OtpScreen extends StatefulWidget {
  /// The phone number (for phoneSms) or email address (for emailSignUp)
  final String contactInfo;
  final OtpVerificationType verificationType;

  const OtpScreen({
    super.key,
    required this.contactInfo,
    required this.verificationType,
  });

  /// Convenience constructor for phone OTP
  const OtpScreen.phone({super.key, required String phoneNumber})
      : contactInfo = phoneNumber,
        verificationType = OtpVerificationType.phoneSms;

  /// Convenience constructor for email sign-up OTP
  const OtpScreen.email({super.key, required String email})
      : contactInfo = email,
        verificationType = OtpVerificationType.emailSignUp;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late final int _otpLength;
  late final List<FocusNode> _focusNodes;
  late final List<TextEditingController> _controllers;
  bool _isVerifying = false;
  
  // Timer state
  Timer? _timer;
  int _secondsRemaining = 45;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _otpLength = 6;
    _focusNodes = List.generate(_otpLength, (index) => FocusNode());
    _controllers = List.generate(_otpLength, (index) => TextEditingController());
    _startTimer();
    
    // Auto-focus the first OTP field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startTimer() {
    setState(() {
      _secondsRemaining = 45;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canResend = true;
          _timer?.cancel();
        });
      }
    });
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;

    // Clear fields
    for (var controller in _controllers) {
      controller.clear();
    }
    _focusNodes[0].requestFocus();

    try {
      if (widget.verificationType == OtpVerificationType.phoneSms) {
        await SupabaseService.signInWithOtp(phone: widget.contactInfo);
      } else {
        await SupabaseService.resendEmailOtp(email: widget.contactInfo);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A new OTP has been sent!'),
            backgroundColor: HestiaColors.primary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resend OTP: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    
    _startTimer();
  }

  Future<void> _handlePostAuthNavigation() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
      return;
    }

    try {
      final profileExists = await SupabaseService.checkProfileExists(user.id);
      if (mounted) {
        if (profileExists) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const PostSignInJourneyScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const PostSignInJourneyScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _verifyOtp() async {
    String otp = _controllers.map((c) => c.text).join();
    if (otp.length < _otpLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter the complete $_otpLength-digit code'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);
    try {
      if (widget.verificationType == OtpVerificationType.phoneSms) {
        await SupabaseService.verifyPhoneOtp(
          phone: widget.contactInfo,
          token: otp,
        );
      } else {
        await SupabaseService.verifyEmailSignUp(
          email: widget.contactInfo,
          token: otp,
        );
      }
      if (mounted) {
        // Show success message for verification
        if (widget.verificationType == OtpVerificationType.emailSignUp) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully! Welcome to Hestia.'),
              backgroundColor: HestiaColors.primary,
              duration: Duration(seconds: 3),
            ),
          );
        } else if (widget.verificationType == OtpVerificationType.phoneSms) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Phone verified successfully! Welcome to Hestia.'),
              backgroundColor: HestiaColors.primary,
              duration: Duration(seconds: 3),
            ),
          );
        }
        await _handlePostAuthNavigation();
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var node in _focusNodes) {
      node.dispose();
    }
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _subtitlePrefix {
    switch (widget.verificationType) {
      case OtpVerificationType.phoneSms:
        return 'We sent a $_otpLength-digit code to\n';
      case OtpVerificationType.emailSignUp:
        return 'We sent a $_otpLength-digit verification code to\n';
    }
  }

  String get _titleText {
    switch (widget.verificationType) {
      case OtpVerificationType.phoneSms:
        return 'Verify OTP';
      case OtpVerificationType.emailSignUp:
        return 'Verify Email';
    }
  }

  IconData get _headerIcon {
    switch (widget.verificationType) {
      case OtpVerificationType.phoneSms:
        return Icons.sms_outlined;
      case OtpVerificationType.emailSignUp:
        return Icons.mark_email_read_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    String timerText = "0:${_secondsRemaining.toString().padLeft(2, '0')}";
    // Calculate box size based on digit count
    final double boxSize = _otpLength == 6 ? 46.0 : 68.0;
    final double fontSize = _otpLength == 6 ? 20.0 : 24.0;

    return Scaffold(
      backgroundColor: HestiaColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Back Button and Hestia Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: HestiaColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        color: HestiaColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                  const Text(
                    'Hestia',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.primary,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              
              const SizedBox(height: 40),

              // Icon badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HestiaColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _headerIcon,
                  color: HestiaColors.primary,
                  size: 28,
                ),
              ),

              const SizedBox(height: 20),
              
              // Title and Subtitle
              Text(
                _titleText,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 15,
                    color: HestiaColors.textMedium,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(text: _subtitlePrefix),
                    TextSpan(
                      text: widget.contactInfo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // OTP Digit Inputs
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_otpLength, (index) {
                  return SizedBox(
                    width: boxSize,
                    height: boxSize,
                    child: KeyboardListener(
                      focusNode: FocusNode(skipTraversal: true),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent && 
                            event.logicalKey == LogicalKeyboardKey.backspace && 
                            _controllers[index].text.isEmpty && 
                            index > 0) {
                          _controllers[index - 1].clear();
                          _focusNodes[index - 1].requestFocus();
                        }
                      },
                      child: TextFormField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: HestiaColors.inputBackground,
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: HestiaColors.primary, width: 2.0),
                          ),
                        ),
                        onChanged: (value) {
                          if (value.length > 1) {
                            String cleanValue = value.replaceAll(RegExp(r'\D'), '');
                            bool isPaste = value.length > 2;

                            if (isPaste) {
                              // Distribute the characters across controllers starting from index
                              for (int i = 0; i < _otpLength; i++) {
                                int valueIndex = i - index;
                                if (valueIndex >= 0 && valueIndex < cleanValue.length) {
                                  _controllers[i].text = cleanValue[valueIndex];
                                }
                              }
                              // Focus the last filled box or unfocus
                              int lastFilledIndex = index + cleanValue.length - 1;
                              if (lastFilledIndex >= _otpLength) {
                                lastFilledIndex = _otpLength - 1;
                              }
                              if (lastFilledIndex < _otpLength - 1) {
                                _focusNodes[lastFilledIndex + 1].requestFocus();
                              } else {
                                _focusNodes[lastFilledIndex].unfocus();
                              }
                              return;
                            } else {
                              // This is typing a digit in a box that already has a digit (overwrite)
                              // Extract the new character
                              String newChar = "";
                              if (value.startsWith(_controllers[index].text)) {
                                newChar = value.substring(value.length - 1);
                              } else {
                                newChar = value.substring(0, 1);
                              }

                              _controllers[index].text = newChar;
                              _controllers[index].selection = TextSelection.fromPosition(
                                TextPosition(offset: newChar.length),
                              );

                              if (index < _otpLength - 1) {
                                _focusNodes[index + 1].requestFocus();
                              } else {
                                _focusNodes[index].unfocus();
                              }
                              return;
                            }
                          }

                          if (value.isNotEmpty) {
                            if (index < _otpLength - 1) {
                              _focusNodes[index + 1].requestFocus();
                            } else {
                              _focusNodes[index].unfocus();
                            }
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),
              
              const SizedBox(height: 24),
              
              // Resend Countdown Timer
              Center(
                child: Text(
                  _canResend ? 'Resend OTP available' : 'Resend OTP in $timerText',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _canResend ? HestiaColors.textLight : HestiaColors.textAccent,
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: HestiaColors.buttonText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Verify & Continue',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Didn't receive? Resend
              Center(
                child: GestureDetector(
                  onTap: _canResend ? _resendOtp : null,
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 15,
                        color: HestiaColors.textMedium,
                      ),
                      children: [
                        const TextSpan(text: "Didn't receive? "),
                        TextSpan(
                          text: 'Resend',
                          style: TextStyle(
                            color: _canResend ? HestiaColors.textAccent : HestiaColors.textLight,
                            fontWeight: FontWeight.bold,
                            decoration: _canResend ? TextDecoration.underline : TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
