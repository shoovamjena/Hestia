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
  /// Email-based OTP sign-in (6 digits)
  emailSignIn,
}

class OtpScreen extends StatefulWidget {
  /// The phone number (for phoneSms) or email address (for emailSignUp/emailSignIn)
  final String contactInfo;
  final OtpVerificationType verificationType;

  /// Optional callback invoked after successful verification.
  /// When provided, this is called instead of the default post-auth navigation.
  /// Use this when launching OtpScreen from contexts like the profile screen
  /// where you want to control navigation yourself (e.g. just pop back).
  final VoidCallback? onVerified;

  const OtpScreen({
    super.key,
    required this.contactInfo,
    required this.verificationType,
    this.onVerified,
  });

  /// Convenience constructor for phone OTP
  const OtpScreen.phone({super.key, required String phoneNumber})
      : contactInfo = phoneNumber,
        verificationType = OtpVerificationType.phoneSms,
        onVerified = null;

  /// Convenience constructor for email sign-up OTP
  const OtpScreen.email({super.key, required String email})
      : contactInfo = email,
        verificationType = OtpVerificationType.emailSignUp,
        onVerified = null;

  /// Convenience constructor for email sign-in OTP
  const OtpScreen.emailSignIn({super.key, required String email})
      : contactInfo = email,
        verificationType = OtpVerificationType.emailSignIn,
        onVerified = null;

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
        if (SupabaseService.currentUser != null) {
          await SupabaseService.sendPhoneVerificationOtp(phone: widget.contactInfo);
        } else {
          await SupabaseService.signInWithOtp(phone: widget.contactInfo);
        }
      } else if (widget.verificationType == OtpVerificationType.emailSignIn) {
        await SupabaseService.resendSignInEmailOtp(email: widget.contactInfo);
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
      final isComplete = await SupabaseService.isProfileComplete(user.id);
      if (mounted) {
        if (isComplete) {
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

    // Dismiss the keyboard so the loading overlay covers the full screen
    // instead of just the region above the keyboard.
    FocusScope.of(context).unfocus();

    setState(() => _isVerifying = true);
    try {
      if (widget.verificationType == OtpVerificationType.phoneSms) {
        await SupabaseService.verifyPhoneOtp(
          phone: widget.contactInfo,
          token: otp,
        );
        // Update phone verification status to true in user metadata and profile JSON
        await SupabaseService.updatePhoneVerifiedStatus(true);
        
        // If there's a pending signup name, update profile and auth user metadata
        if (SupabaseService.pendingSignUpName != null) {
          await SupabaseService.client.auth.updateUser(
            UserAttributes(
              data: {
                'full_name': SupabaseService.pendingSignUpName,
              },
            ),
          );
          final user = SupabaseService.currentUser;
          if (user != null) {
            await SupabaseService.createProfile(
              id: user.id,
              fullName: SupabaseService.pendingSignUpName!,
              email: SupabaseService.currentUserEmail,
              phone: widget.contactInfo,
            );
          }
          SupabaseService.pendingSignUpName = null; // Clear static state
        }
      } else if (widget.verificationType == OtpVerificationType.emailSignIn) {
        await SupabaseService.verifyEmailOtp(
          email: widget.contactInfo,
          token: otp,
        );
      } else {
        await SupabaseService.verifyEmailSignUp(
          email: widget.contactInfo,
          token: otp,
        );
        SupabaseService.pendingSignUpName = null;
        SupabaseService.pendingSignUpPhone = null;
      }
      if (mounted) {
        // Show success message for verification
        if (widget.verificationType == OtpVerificationType.emailSignUp || widget.verificationType == OtpVerificationType.emailSignIn) {
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
        if (widget.onVerified != null) {
          // Caller controls navigation (e.g. profile screen → just pop back)
          widget.onVerified!();
        } else {
          await _handlePostAuthNavigation();
        }
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

  String get _displayContact {
    if (widget.verificationType == OtpVerificationType.phoneSms) {
      final digits = widget.contactInfo.replaceAll(RegExp(r'\D'), '');
      final local = digits.startsWith('91') ? digits.substring(2) : digits;
      if (local.length == 10) {
        return '+91 ${local.substring(0, 5)} ${local.substring(5)}';
      }
      return widget.contactInfo;
    }
    return widget.contactInfo;
  }

  String get _instructionText {
    switch (widget.verificationType) {
      case OtpVerificationType.phoneSms:
        return 'Enter the OTP sent to';
      case OtpVerificationType.emailSignUp:
      case OtpVerificationType.emailSignIn:
        return 'Enter the OTP sent to';
    }
  }

  String get _resendLabel {
    final prefix = widget.verificationType == OtpVerificationType.phoneSms
        ? 'Resend SMS'
        : 'Resend email';
    if (_canResend) return prefix;
    return '$prefix in ${_secondsRemaining}s';
  }

  void _checkAutoVerify() {
    final otp = _controllers.map((c) => c.text).join();
    if (otp.length == _otpLength && !_isVerifying) {
      _verifyOtp();
    }
  }

  void _handleOtpChanged(int index, String value) {
    if (value.length > 1) {
      final cleanValue = value.replaceAll(RegExp(r'\D'), '');
      final isPaste = value.length > 2;

      if (isPaste) {
        for (var i = 0; i < _otpLength; i++) {
          final valueIndex = i - index;
          if (valueIndex >= 0 && valueIndex < cleanValue.length) {
            _controllers[i].text = cleanValue[valueIndex];
          }
        }
        var lastFilledIndex = index + cleanValue.length - 1;
        if (lastFilledIndex >= _otpLength) {
          lastFilledIndex = _otpLength - 1;
        }
        if (lastFilledIndex < _otpLength - 1) {
          _focusNodes[lastFilledIndex + 1].requestFocus();
        } else {
          _focusNodes[lastFilledIndex].unfocus();
        }
        _checkAutoVerify();
        return;
      }

      final newChar = value.startsWith(_controllers[index].text)
          ? value.substring(value.length - 1)
          : value.substring(0, 1);

      _controllers[index].text = newChar;
      _controllers[index].selection = TextSelection.fromPosition(
        TextPosition(offset: newChar.length),
      );

      if (index < _otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
      _checkAutoVerify();
      return;
    }

    if (value.isNotEmpty) {
      if (index < _otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
      _checkAutoVerify();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HestiaColors.appBackground,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        color: HestiaColors.textDark,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'OTP verification',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: HestiaColors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _instructionText,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: HestiaColors.textDark,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _displayContact,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: HestiaColors.textDark,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: List.generate(_otpLength, (index) {
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index < _otpLength - 1 ? 10 : 0,
                        ),
                        child: SizedBox(
                          width: 48,
                          height: 52,
                          child: KeyboardListener(
                            focusNode: FocusNode(skipTraversal: true),
                            onKeyEvent: (event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.backspace &&
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
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
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
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF2B2B2B),
                                    width: 1.2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF2B2B2B),
                                    width: 1.2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: HestiaColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onChanged: (value) =>
                                  _handleOtpChanged(index, value),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _canResend ? _resendOtp : null,
                    child: Text(
                      _resendLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _canResend
                            ? HestiaColors.primary
                            : const Color(0xFF8A8A8A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isVerifying)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Please wait...',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
