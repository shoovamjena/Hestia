import 'package:flutter/material.dart';
import '../theme/colors.dart';

class OnboardingSlide {
  final String imagePath;
  final String titleNormal;
  final String titleAccent;
  final String description;

  const OnboardingSlide({
    required this.imagePath,
    required this.titleNormal,
    required this.titleAccent,
    required this.description,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingSlide> _slides = const [
    OnboardingSlide(
      imagePath: 'assets/images/onboarding_1.png',
      titleNormal: 'Care that comes ',
      titleAccent: 'to you',
      description: 'Trained Professionals visit your home for pre & post-natal care, elderly support, babysitting and more',
    ),
    OnboardingSlide(
      imagePath: 'assets/images/onboarding_2.png',
      titleNormal: 'Verified & ',
      titleAccent: 'trained staff',
      description: 'All professionals are background-checked, certified employees - not gig workers. Your family\'s safety comes first.',
    ),
    OnboardingSlide(
      imagePath: 'assets/images/onboarding_3.png',
      titleNormal: 'Track every ',
      titleAccent: 'Session Live',
      description: 'Follow your care professional in real-time, get live activity updates and stay in full control from your phone.',
    ),
  ];

  void _onNextPressed() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Onboarding finished: return to the landing screen where the user
      // signs in with their phone number via OTP.
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        color: HestiaColors.appBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              children: [
                // Header Row: Back Button and Hestia Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_currentPage > 0) {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
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
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 40), // Placeholder to balance back button
                  ],
                ),
              
              // Carousel Body
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Padding(
                      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Illustration
                          Expanded(
                            flex: 5,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 16.0),
                              child: Image.asset(
                                slide.imagePath,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Rich Text Title
                          Align(
                            alignment: Alignment.centerLeft,
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: slide.titleNormal,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: HestiaColors.textDark,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '\n${slide.titleAccent}',
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      fontStyle: FontStyle.italic,
                                      color: HestiaColors.textAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Description Text
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              slide.description,
                              style: const TextStyle(
                                fontSize: 15,
                                color: HestiaColors.textMedium,
                                height: 1.4,
                              ),
                            ),
                          ),
                          
                          const Spacer(flex: 1),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom Area: Indicators & Next Button
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _currentPage == index
                              ? HestiaColors.indicatorActive
                              : HestiaColors.indicatorInactive,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Next Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _onNextPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HestiaColors.primary,
                        foregroundColor: HestiaColors.buttonText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
   );
  }
}
