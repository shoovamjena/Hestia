import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'home_screen.dart';
import 'landing_screen.dart';
import 'post_sign_in_journey_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    
    _controller.forward();

    _navigateNext();
  }

  Future<void> _navigateNext() async {
    final startTime = DateTime.now();
    final hasSession = SupabaseService.currentSession != null;
    Widget nextScreen = const LandingScreen();

    if (hasSession) {
      final user = SupabaseService.currentUser;
      if (user != null) {
        try {
          final isComplete = await SupabaseService.isProfileComplete(user.id);
          if (isComplete) {
            nextScreen = const HomeScreen();
          } else {
            nextScreen = const PostSignInJourneyScreen();
          }
        } catch (_) {
          nextScreen = const PostSignInJourneyScreen();
        }
      }
    }

    // Keep splash visible for at least 2 seconds for a premium micro-interaction feel
    final elapsed = DateTime.now().difference(startTime);
    final remaining = const Duration(seconds: 2) - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment(0.0, 0.4),
          colors: [
            Color.fromARGB(255, 94, 61, 29),
            Color.fromARGB(255, 139, 106, 65),
            Color.fromARGB(255, 252, 252, 252),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/images/logo.svg',
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 16),
                const Text(
                  'Hestia',
                  style: TextStyle(
                    fontFamily: 'Outfit', // A modern geometric sans-serif
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
