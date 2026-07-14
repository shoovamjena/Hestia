import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'onboarding_screen.dart';
import 'otp_screen.dart';
import 'referral_code_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _phoneController = TextEditingController();
  bool _hasReferralCode = false;
  bool _isLoading = false;

  static const _collageImages = [
    'assets/images/services/steps/post_delivery/step_1.png',
    'assets/images/services/steps/babysitting/step_2.png',
    'assets/images/services/steps/mobility/step_1.png',
    'assets/images/services/steps/bathing/step_3.png',
    'assets/images/services/steps/concierge/step_1.png',
    'assets/images/services/steps/pre_pregnancy/step_2.png',
    'assets/images/services/steps/post_delivery/step_3.png',
    'assets/images/services/steps/babysitting/step_4.png',
    'assets/images/services/steps/mobility/step_3.png',
    'assets/images/services/steps/bathing/step_1.png',
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  bool get _isPhoneValid {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10;
  }

  Future<void> _continueWithPhone() async {
    if (!_isPhoneValid || _isLoading) return;

    final phone = '+91${_phoneController.text.trim().replaceAll(' ', '')}';

    // If the user has a referral code, take them to the referral screen first;
    // the OTP is sent from there once they continue or skip.
    if (_hasReferralCode) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ReferralCodeScreen(phoneNumber: phone),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await SupabaseService.signInWithOtp(phone: phone);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OtpScreen.phone(phoneNumber: phone),
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
      backgroundColor: HestiaColors.background,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildFadingCarousel(),
                  const SizedBox(height: 4),
                  _buildAuthSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFadingCarousel() {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: const _TripleRowImageCarousel(images: _collageImages),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(36),
        bottomRight: Radius.circular(36),
      ),
      child: ColoredBox(
        color: HestiaColors.primary,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const OnboardingScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF4A3324),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Skip login',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Hestia',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Get trusted home care in minutes!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Log in or Sign up',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: HestiaColors.inputBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4E4E4)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text(
                  '+91',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: HestiaColors.textDark,
                  ),
                ),
                Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0xFFE4E4E4),
                ),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: HestiaColors.textDark,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter mobile number',
                      hintStyle: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isPhoneValid && !_isLoading ? _continueWithPhone : null,
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
          const SizedBox(height: 18),
          InkWell(
            onTap: () => setState(() => _hasReferralCode = !_hasReferralCode),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _hasReferralCode,
                      onChanged: (value) {
                        setState(() => _hasReferralCode = value ?? false);
                      },
                      activeColor: HestiaColors.primary,
                      side: const BorderSide(color: Color(0xFFBDBDBD), width: 1.5),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Have a referral code?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HestiaColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF8A8A8A),
                height: 1.5,
              ),
              children: [
                TextSpan(text: 'By continuing, you agree to our '),
                TextSpan(
                  text: 'Terms of Service',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: Color(0xFF5C5C5C),
                  ),
                ),
                TextSpan(text: ' & '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: Color(0xFF5C5C5C),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TripleRowImageCarousel extends StatelessWidget {
  final List<String> images;

  const _TripleRowImageCarousel({required this.images});

  static const double _tileSize = 96;
  static const double _spacing = 10;
  static const double _radius = 18;

  List<String> _imagesForRow(int rowIndex) {
    final offset = rowIndex * 3;
    return [
      for (var i = 0; i < images.length; i++)
        images[(i + offset) % images.length],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfiniteCarouselRow(
          images: _imagesForRow(0),
          tileSize: _tileSize,
          spacing: _spacing,
          radius: _radius,
          duration: const Duration(seconds: 26),
        ),
        const SizedBox(height: _spacing),
        _InfiniteCarouselRow(
          images: _imagesForRow(1),
          tileSize: _tileSize,
          spacing: _spacing,
          radius: _radius,
          duration: const Duration(seconds: 32),
          reverse: true,
        ),
        const SizedBox(height: _spacing),
        _InfiniteCarouselRow(
          images: _imagesForRow(2),
          tileSize: _tileSize,
          spacing: _spacing,
          radius: _radius,
          duration: const Duration(seconds: 28),
        ),
      ],
    );
  }
}

class _InfiniteCarouselRow extends StatefulWidget {
  final List<String> images;
  final double tileSize;
  final double spacing;
  final double radius;
  final Duration duration;
  final bool reverse;

  const _InfiniteCarouselRow({
    required this.images,
    required this.tileSize,
    required this.spacing,
    required this.radius,
    required this.duration,
    this.reverse = false,
  });

  @override
  State<_InfiniteCarouselRow> createState() => _InfiniteCarouselRowState();
}

class _InfiniteCarouselRowState extends State<_InfiniteCarouselRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double get _segmentWidth =>
      widget.images.length * (widget.tileSize + widget.spacing);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildTile(String asset) {
    return Container(
      width: widget.tileSize,
      height: widget.tileSize,
      margin: EdgeInsets.only(right: widget.spacing),
      decoration: BoxDecoration(
        color: const Color(0xFFF3ECE6),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      padding: EdgeInsets.all(widget.tileSize * 0.1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius * 0.7),
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFFEFE7E1),
            child: Center(
              child: Icon(
                Icons.image_outlined,
                color: Color(0xFF8B6B52),
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTiles() {
    return [
      for (final asset in widget.images) _buildTile(asset),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return SizedBox(height: widget.tileSize);
    }

    return SizedBox(
      height: widget.tileSize,
      width: double.infinity,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value * _segmentWidth;
            final offset = widget.reverse ? progress - _segmentWidth : -progress;
            return OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(offset, 0),
                child: Row(
                  children: [
                    ..._buildTiles(),
                    ..._buildTiles(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
