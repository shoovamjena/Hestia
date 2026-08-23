import 'package:flutter/material.dart';

import '../services/location_acquisition_service.dart';
import '../services/location_geocoding_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'home_screen.dart';
import 'search_location_screen.dart';

class PostSignInJourneyScreen extends StatefulWidget {
  const PostSignInJourneyScreen({super.key});

  @override
  State<PostSignInJourneyScreen> createState() => _PostSignInJourneyScreenState();
}

class _PostSignInJourneyScreenState extends State<PostSignInJourneyScreen> {
  bool _checkingProfile = true;
  int _step = 0;
  String _fullName = '';
  String? _email;

  @override
  void initState() {
    super.initState();
    _checkProfileStatus();
  }

  Future<void> _checkProfileStatus() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        final isComplete = await SupabaseService.isProfileComplete(user.id);
        if (isComplete && mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
          return;
        }
      } catch (e) {
        debugPrint('Error checking profile status: $e');
      }
    }

    if (mounted) {
      setState(() => _checkingProfile = false);
    }
  }

  Future<void> _onProfileConfirmed({
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    final fullName = lastName.trim().isEmpty
        ? firstName.trim()
        : '${firstName.trim()} ${lastName.trim()}';
    final trimmedEmail = email.trim();

    SupabaseService.pendingOnboardingFullName = fullName;
    SupabaseService.pendingOnboardingEmail =
        trimmedEmail.isEmpty ? null : trimmedEmail;

    await SupabaseService.saveOnboardingBasics(
      id: user.id,
      fullName: fullName,
      email: trimmedEmail.isEmpty ? null : trimmedEmail,
      phone: SupabaseService.currentUserPhone.isNotEmpty
          ? SupabaseService.currentUserPhone
          : null,
    );

    if (!mounted) return;
    setState(() {
      _fullName = fullName;
      _email = trimmedEmail.isEmpty ? null : trimmedEmail;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingProfile) {
      return const Scaffold(
        backgroundColor: HestiaColors.background,
        body: Center(
          child: CircularProgressIndicator(color: HestiaColors.primary),
        ),
      );
    }

    if (_step == 0) {
      return _ProfileDetailsPage(onConfirm: _onProfileConfirmed);
    }

    return _LocationSetupPage(
      fullName: _fullName,
      email: _email,
    );
  }
}

class _ProfileDetailsPage extends StatefulWidget {
  final Future<void> Function({
    required String firstName,
    required String lastName,
    required String email,
  }) onConfirm;

  const _ProfileDetailsPage({required this.onConfirm});

  @override
  State<_ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

class _ProfileDetailsPageState extends State<_ProfileDetailsPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool get _canConfirm => _firstNameController.text.trim().isNotEmpty && !_isSaving;

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    setState(() => _isSaving = true);
    try {
      await widget.onConfirm(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save details: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HestiaColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: HestiaColors.textDark,
                          height: 1.2,
                        ),
                        children: [
                          TextSpan(text: 'Help us '),
                          TextSpan(
                            text: 'know you',
                            style: TextStyle(color: HestiaColors.primary),
                          ),
                          TextSpan(text: ' better'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildField(
                      controller: _firstNameController,
                      hint: 'First name',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _lastNameController,
                      hint: 'Last name (optional)',
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _emailController,
                      hint: 'Email (optional)',
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _canConfirm ? _confirm : null,
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
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Confirm details',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: HestiaColors.inputBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: HestiaColors.textDark,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFF9E9E9E),
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _LocationSetupPage extends StatefulWidget {
  final String fullName;
  final String? email;

  const _LocationSetupPage({
    required this.fullName,
    this.email,
  });

  @override
  State<_LocationSetupPage> createState() => _LocationSetupPageState();
}

class _LocationSetupPageState extends State<_LocationSetupPage> {
  static const _illustrationAsset = 'assets/images/location_illustration.png';

  bool _isLoading = false;

  Future<void> _useCurrentLocation() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final position = await LocationAcquisitionService.acquirePosition();

      if (position == null) {
        throw Exception(
          'Could not get your location. On emulator, open Extended Controls '
          '→ Location, pick a point, tap Set Location, then try again. '
          'Or enter your address manually.',
        );
      }

      final address = await LocationGeocodingService.reverseGeocode(
        position.latitude,
        position.longitude,
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => null,
      );

      if (address == null ||
          (address['street']?.trim().isEmpty ?? true) ||
          (address['city']?.trim().isEmpty ?? true)) {
        throw Exception('Could not resolve your address. Try entering it manually.');
      }

      final user = SupabaseService.currentUser;
      if (user == null) return;

      final bool withinCoverage = await SupabaseService.isPointWithinCoverage(
        position.latitude,
        position.longitude,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => true,
      );

      await SupabaseService.completeOnboarding(
        id: user.id,
        fullName: widget.fullName,
        email: widget.email,
        phone: SupabaseService.currentUserPhone.isNotEmpty
            ? SupabaseService.currentUserPhone
            : null,
        address: {
          ...address,
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        withinCoverage: withinCoverage,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
          'Saving your details timed out. Please check your connection and try again.',
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _enterLocationManually() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SearchLocationScreen(
          isPostSignInJourney: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HestiaColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 40, bottom: 24),
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            "What's your location?",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: HestiaColors.textDark,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'We need your location to show you our serviceable hubs.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF8A8A8A),
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.2, 0.65, 1.0],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: Image.asset(
                            _illustrationAsset,
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 240,
                              child: Center(
                                child: Icon(
                                  Icons.location_city_outlined,
                                  size: 72,
                                  color: Color(0xFFD0C4BA),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _useCurrentLocation,
                          icon: const Icon(Icons.my_location, size: 20),
                          label: const Text(
                            'Use current location',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HestiaColors.primary,
                            disabledBackgroundColor: const Color(0xFFD9D9D9),
                            foregroundColor: HestiaColors.buttonText,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading ? null : _enterLocationManually,
                        child: const Text(
                          'Enter location manually',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: HestiaColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
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
