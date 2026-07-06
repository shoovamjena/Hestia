import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'otp_screen.dart';
import 'home_screen.dart';
import 'post_sign_in_journey_screen.dart';

enum SignInMethod { email, mobile }
enum SignUpMethod { emailPassword, phoneOtp }

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
  SignUpMethod _signUpMethod = SignUpMethod.emailPassword;

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

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        if (_isSignIn) {
          if (_signInMethod == SignInMethod.email) {
            // Email password sign in
            final email = _emailController.text.trim();
            final password = _passwordController.text;
            await SupabaseService.signIn(
              identifier: email,
              password: password,
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
          if (_signUpMethod == SignUpMethod.emailPassword) {
            SupabaseService.pendingSignUpPassword = _passwordController.text;
            SupabaseService.pendingSignUpName = _nameController.text.trim();
            SupabaseService.pendingSignUpPhone = phone;
            final response = await SupabaseService.signUpWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              name: _nameController.text.trim(),
              phone: phone,
            );
            if (response.user != null) {
              try {
                await SupabaseService.createProfile(
                  id: response.user!.id,
                  fullName: _nameController.text.trim(),
                  phone: phone,
                );
              } catch (e) {
                // Ignore initial create profile error (e.g. due to unauthenticated RLS)
                // because it will be retried and created successfully on the OTP verification screen
                // once the user session is authenticated.
                print('Note: Initial createProfile failed (expected if RLS requires auth): $e');
              }
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Verification code sent to your email!'),
                  backgroundColor: HestiaColors.primary,
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => OtpScreen.email(
                    email: _emailController.text.trim(),
                  ),
                ),
              );
            }
          } else {
            SupabaseService.pendingSignUpName = _nameController.text.trim();
            SupabaseService.pendingSignUpPhone = phone;
            await SupabaseService.signInWithOtp(phone: phone);
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => OtpScreen.phone(
                    phoneNumber: phone,
                  ),
                ),
              );
            }
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
    return Container(
      color: const Color(0xFF5E3D1D),
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.0,
                            ),
                          ),
                          child: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      const Text(
                        'Hestia',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignIn 
                        ? 'Sign in to continue your care journey' 
                        : 'Start your care journey with Hestia',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                
                  const SizedBox(height: 24),
                  
                  // Glassmorphic Card Container
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 28.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sign-in method toggle (only in sign-in mode)
                            if (_isSignIn) ...[
                              _buildSignInMethodToggle(),
                              const SizedBox(height: 24),
                            ] else ...[
                              _buildSignUpMethodToggle(),
                              const SizedBox(height: 24),
                            ],
                            
                            // Form Fields
                            if (!_isSignIn) ...[ 
                              if (_signUpMethod == SignUpMethod.emailPassword) ...[
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
                              ] else ...[
                                // SIGN-UP FORM: Phone + OTP (Name, Phone)
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
                                
                                _buildInputLabel('MOBILE NUMBER'),
                                const SizedBox(height: 8),
                                _buildPhoneField(),
                              ],
                            ] else if (_signInMethod == SignInMethod.email) ...[
                              // SIGN-IN: Email + Password method
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
                              _buildInputLabel('PASSWORD'),
                              const SizedBox(height: 8),
                              _buildPasswordField(),
                            ] else ...[
                              // SIGN-IN: Mobile method
                              _buildInputLabel('MOBILE NUMBER'),
                              const SizedBox(height: 8),
                              _buildPhoneField(),
                            ],
                            
                            const SizedBox(height: 28),
                            
                            // Submit Button
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitForm,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromARGB(255, 51, 33, 20),
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
                                            ? (_signInMethod == SignInMethod.email ? 'Sign In' : 'Send OTP')
                                            : (_signUpMethod == SignUpMethod.phoneOtp ? 'Send OTP' : 'Create Account'),
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
                                      color: Colors.white,
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
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 28),
                            
                            // Terms & Privacy Agreement Disclaimer
                            Center(
                              child: Text(
                                _isSignIn 
                                    ? 'By continuing, you sign in to Hestia.'
                                    : 'By continuing, you agree to our\nTerms of Service & Privacy Policy',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ),
   );
  }

  /// Segmented toggle to switch between Email and Mobile sign-up
  Widget _buildSignUpMethodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildToggleOption(
            label: 'Email + Pass',
            icon: Icons.email_outlined,
            isSelected: _signUpMethod == SignUpMethod.emailPassword,
            onTap: () {
              if (_signUpMethod != SignUpMethod.emailPassword) {
                setState(() {
                  _signUpMethod = SignUpMethod.emailPassword;
                  _formKey.currentState?.reset();
                });
              }
            },
          ),
          _buildToggleOption(
            label: 'Phone + OTP',
            icon: Icons.phone_android_outlined,
            isSelected: _signUpMethod == SignUpMethod.phoneOtp,
            onTap: () {
              if (_signUpMethod != SignUpMethod.phoneOtp) {
                setState(() {
                  _signUpMethod = SignUpMethod.phoneOtp;
                  _formKey.currentState?.reset();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  /// Segmented toggle to switch between Email and Mobile sign-in
  Widget _buildSignInMethodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
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
            color: isSelected ? const Color.fromARGB(255, 63, 42, 26) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
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
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.85),
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
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: const Text(
            '+91',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Phone number textfield
        Expanded(
          child: _buildTextFormField(
            controller: _phoneController,
            placeholder: '8146512345',
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your phone number';
              }
              if (value.trim().replaceAll(' ', '').length != 10) {
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
          color: Colors.white70,
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
        color: Colors.white,
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
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontWeight: FontWeight.normal,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
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
