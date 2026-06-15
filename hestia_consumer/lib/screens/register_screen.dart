import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'home_screen.dart';
import 'otp_screen.dart';
import 'post_sign_in_journey_screen.dart';

enum SignInMethod { email, mobile }

class RegisterScreen extends StatefulWidget {
  final bool isSignIn;
  const RegisterScreen({super.key, this.isSignIn = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late bool _isSignIn;
  bool _obscurePassword = true;
  bool _isLoading = false;
  SignInMethod _signInMethod = SignInMethod.email;

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isSignIn = widget.isSignIn;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
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

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        if (_isSignIn) {
          if (_signInMethod == SignInMethod.email) {
            // Email + Password sign in
            await SupabaseService.signIn(
              identifier: _emailController.text.trim(),
              password: _passwordController.text,
            );
            if (mounted) {
              await _handlePostAuthNavigation();
            }
          } else {
            // Mobile OTP sign in
            final phone = '+91${_phoneController.text.trim().replaceAll(' ', '')}';
            await SupabaseService.signInWithOtp(phone: phone);
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => OtpScreen.phone(phoneNumber: phone),
                ),
              );
            }
          }
        } else {
          final phone = '+91${_phoneController.text.trim().replaceAll(' ', '')}';
          await SupabaseService.signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            name: _nameController.text.trim(),
            phone: phone,
          );
          if (mounted) {
            // Navigate to OTP screen for phone verification
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => OtpScreen.phone(
                  phoneNumber: phone,
                ),
              ),
            );
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
      } on SocketException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to reach Supabase. Check your internet connection or emulator DNS.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('An unexpected error occurred: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HestiaColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
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
                          color: HestiaColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.chevron_left,
                          color: HestiaColors.background  ,
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
                
                const SizedBox(height: 32),
                
                // Screen Title & Subtitle
                Text(
                  _isSignIn ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignIn 
                      ? 'Sign in to continue your care journey' 
                      : 'Start your care journey with Hestia',
                  style: const TextStyle(
                    fontSize: 15,
                    color: HestiaColors.textMedium,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Sign-in method toggle (only in sign-in mode)
                if (_isSignIn) ...[
                  _buildSignInMethodToggle(),
                  const SizedBox(height: 28),
                ] else ...[
                  const SizedBox(height: 8),
                ],
                
                // Form Fields
                if (!_isSignIn) ...[ 
                  // SIGN-UP FORM: Name, Email, Phone, Password
                  _buildInputLabel('FULL NAME'),
                  const SizedBox(height: 8),
                  _buildTextFormField(
                    controller: _nameController,
                    placeholder: 'Priya Sharma',
                    keyboardType: TextInputType.name,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your full name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  _buildInputLabel('EMAIL ADDRESS'),
                  const SizedBox(height: 8),
                  _buildTextFormField(
                    controller: _emailController,
                    placeholder: 'Priya@example.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email address';
                      }
                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  _buildInputLabel('MOBILE NUMBER'),
                  const SizedBox(height: 8),
                  _buildPhoneField(),
                  const SizedBox(height: 20),
                  
                  _buildInputLabel('PASSWORD'),
                  const SizedBox(height: 8),
                  _buildPasswordField(),
                ] else if (_signInMethod == SignInMethod.email) ...[
                  // SIGN-IN: Email or Mobile method
                  _buildInputLabel('EMAIL OR MOBILE NUMBER'),
                  const SizedBox(height: 8),
                  _buildTextFormField(
                    controller: _emailController,
                    placeholder: 'Priya@example.com or 9876543210',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email or mobile number';
                      }
                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      final phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');
                      final cleanValue = value.trim().replaceAll(' ', '');
                      if (!emailRegex.hasMatch(cleanValue) && !phoneRegex.hasMatch(cleanValue)) {
                        return 'Please enter a valid email or mobile number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  _buildInputLabel('PASSWORD'),
                  const SizedBox(height: 8),
                  _buildPasswordField(),
                ] else ...[
                  // SIGN-IN: Mobile method
                  _buildInputLabel('MOBILE NUMBER'),
                  const SizedBox(height: 8),
                  _buildPhoneField(),
                ],
                
                const SizedBox(height: 40),
                
                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HestiaColors.primary,
                      foregroundColor: HestiaColors.buttonText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            _isSignIn
                                ? (_signInMethod == SignInMethod.mobile
                                    ? 'Send OTP'
                                    : 'Sign In')
                                : 'Create Account',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Toggle between SignUp and SignIn
                Center(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSignIn = !_isSignIn;
                        _formKey.currentState?.reset();
                      });
                    },
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 15,
                          color: HestiaColors.textMedium,
                        ),
                        children: [
                          TextSpan(
                            text: _isSignIn 
                                ? "Don't have an account? " 
                                : "Already have an account? ",
                          ),
                          TextSpan(
                            text: _isSignIn ? 'SignUp' : 'SignIn',
                            style: const TextStyle(
                              color: HestiaColors.textAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 48),
                
                // Terms & Privacy Agreement Disclaimer
                Center(
                  child: Text(
                    _isSignIn 
                        ? 'By continuing, you sign in to Hestia.'
                        : 'By continuing, you agree to our\nTerms of Service & Privacy Policy',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HestiaColors.textLight,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Segmented toggle to switch between Email and Mobile sign-in
  Widget _buildSignInMethodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: HestiaColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: HestiaColors.inputBorder.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildToggleOption(
            label: 'Email',
            icon: Icons.email_outlined,
            isSelected: _signInMethod == SignInMethod.email,
            onTap: () {
              if (_signInMethod != SignInMethod.email) {
                setState(() {
                  _signInMethod = SignInMethod.email;
                  _formKey.currentState?.reset();
                });
              }
            },
          ),
          _buildToggleOption(
            label: 'Mobile',
            icon: Icons.phone_android_outlined,
            isSelected: _signInMethod == SignInMethod.mobile,
            onTap: () {
              if (_signInMethod != SignInMethod.mobile) {
                setState(() {
                  _signInMethod = SignInMethod.mobile;
                  _formKey.currentState?.reset();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? HestiaColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: HestiaColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? HestiaColors.buttonText
                    : HestiaColors.textMedium,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? HestiaColors.buttonText
                      : HestiaColors.textMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Phone number input with +91 prefix
  Widget _buildPhoneField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Country Code Prefix block
        Container(
          height: 56,
          width: 65,
          decoration: BoxDecoration(
            color: HestiaColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: HestiaColors.inputBorder.withValues(alpha: 0.5),
            ),
          ),
          alignment: Alignment.center,
          child: const Text(
            '+91',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: HestiaColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Phone number textfield
        Expanded(
          child: _buildTextFormField(
            controller: _phoneController,
            placeholder: '81465 12345',
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your phone number';
              }
              if (value.trim().replaceAll(' ', '').length < 10) {
                return 'Enter a valid 10-digit number';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  /// Password input field with visibility toggle
  Widget _buildPasswordField() {
    return _buildTextFormField(
      controller: _passwordController,
      placeholder: '**********',
      obscureText: _obscurePassword,
      keyboardType: TextInputType.visiblePassword,
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: HestiaColors.textLight,
        ),
        onPressed: () {
          setState(() {
            _obscurePassword = !_obscurePassword;
          });
        },
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter a password';
        }
        if (value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: HestiaColors.textAccent,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String placeholder,
    required TextInputType keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 16,
        color: HestiaColors.textDark,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: const TextStyle(
          color: HestiaColors.textLight,
          fontWeight: FontWeight.normal,
        ),
        filled: true,
        fillColor: HestiaColors.inputBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HestiaColors.inputBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HestiaColors.inputBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}
