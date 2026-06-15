import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'schedule_screen.dart';

class ServiceDetail {
  final String title;
  final String category;
  final String headline;
  final String price;
  final String priceSub;
  final String duration;
  final String durationSub;
  final String rating;
  final String ratingSub;
  final List<String> whatsIncluded;

  const ServiceDetail({
    required this.title,
    required this.category,
    required this.headline,
    required this.price,
    required this.priceSub,
    required this.duration,
    required this.durationSub,
    required this.rating,
    required this.ratingSub,
    required this.whatsIncluded,
  });
}

class ServiceDetailScreen extends StatelessWidget {
  final String serviceKey;

  const ServiceDetailScreen({
    super.key,
    required this.serviceKey,
  });

  // Static service data matching the home screen options
  static final Map<String, ServiceDetail> _servicesData = {
    'post-delivery': const ServiceDetail(
      title: 'Post-Delivery Care',
      category: 'MATERNAL CARE',
      headline: 'Professional support for mother & newborn at home',
      price: '₹499',
      priceSub: 'per hour',
      duration: '2–8 hrs',
      durationSub: 'per session',
      rating: '4.9',
      ratingSub: 'avg. rating',
      whatsIncluded: [
        'Newborn bathing & swaddling',
        'Breastfeeding assistance',
        'Light meal preparation',
        'Real-time activity log',
      ],
    ),
    'babysitting': const ServiceDetail(
      title: 'Babysitting Care',
      category: 'CHILD CARE',
      headline: 'Reliable and engaging supervision for your little ones',
      price: '₹399',
      priceSub: 'per hour',
      duration: '3–12 hrs',
      durationSub: 'per session',
      rating: '4.8',
      ratingSub: 'avg. rating',
      whatsIncluded: [
        'Playtime & creative activities',
        'Diapering & meal feeding',
        'Bedtime routine management',
        'Light cleanup of child\'s area',
      ],
    ),
    'mobility': const ServiceDetail(
      title: 'Mobility Assistance',
      category: 'ELDERLY & ADULT CARE',
      headline: 'Safe assistance for daily movement and exercises',
      price: '₹449',
      priceSub: 'per hour',
      duration: '2–6 hrs',
      durationSub: 'per session',
      rating: '4.9',
      ratingSub: 'avg. rating',
      whatsIncluded: [
        'Support with transfers & walking',
        'Guided physical exercises',
        'Wheelchair and walker support',
        'Companion conversation & care',
      ],
    ),
    'pre-pregnancy': const ServiceDetail(
      title: 'Pre-Pregnancy Care',
      category: 'MATERNAL CARE',
      headline: 'Birth planning and holistic prenatal preparations',
      price: '₹599',
      priceSub: 'per hour',
      duration: '2–4 hrs',
      durationSub: 'per session',
      rating: '4.7',
      ratingSub: 'avg. rating',
      whatsIncluded: [
        'Birth planning & consultation',
        'Holistic prenatal nutrition advice',
        'Gentle stretching & breathing exercises',
        'Partner support coaching',
      ],
    ),
    'bathing': const ServiceDetail(
      title: 'Bathing Assistance',
      category: 'PERSONAL CARE',
      headline: 'Dignified and safe personal hygiene support',
      price: '₹349',
      priceSub: 'per hour',
      duration: '1–3 hrs',
      durationSub: 'per session',
      rating: '4.8',
      ratingSub: 'avg. rating',
      whatsIncluded: [
        'Safe transfers in & out of bath',
        'Gentle bathing & hair washing',
        'Drying & skin moisturizing',
        'Dressing & grooming assistance',
      ],
    ),
    'concierge': const ServiceDetail(
      title: 'Concierge & Errands',
      category: 'HOME SUPPORT',
      headline: 'Help with grocery shopping, errands, and organization',
      price: '₹299',
      priceSub: 'per hour',
      duration: '1–5 hrs',
      durationSub: 'per session',
      rating: '4.6',
      ratingSub: 'avg. rating',
      whatsIncluded: [
        'Grocery shopping & prescription runs',
        'Light household organization',
        'Travel escort & companion setup',
        'Mail & bill organizing support',
      ],
    ),
  };

  ServiceDetail _getServiceDetail() {
    // Clean key and lookup
    final key = serviceKey.replaceAll('\n', '').replaceAll(' ', '').replaceAll('-', '').toLowerCase();
    
    // Find closest match or default to post-delivery
    if (key.contains('postdelivery')) return _servicesData['post-delivery']!;
    if (key.contains('babysitting')) return _servicesData['babysitting']!;
    if (key.contains('mobility')) return _servicesData['mobility']!;
    if (key.contains('prepregnancy')) return _servicesData['pre-pregnancy']!;
    if (key.contains('bathing')) return _servicesData['bathing']!;
    if (key.contains('concierge')) return _servicesData['concierge']!;
    
    return _servicesData['post-delivery']!;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _getServiceDetail();

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 252, 252, 252),
      body: Container(
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
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button (Circular matching mockup)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 10,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chevron_left,
                          color: HestiaColors.primary,
                          size: 24,
                        ),
                      ),
                    ),
                    
                    // Service Title
                    Text(
                      detail.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    // Share Button (Circular matching mockup)
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Sharing ${detail.title}...'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 5,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.share_outlined,
                          color: HestiaColors.primary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main Content Area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      // Hero Card (Large Cream Rounded Container)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF5F0),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: HestiaColors.primary,
                            width: 2,
                          ),
                          gradient: const RadialGradient(
                            center: Alignment(0.0, -0.6),
                            radius: 0.9,
                            colors: [
                              Color(0xFFFEFDFB),
                              Color(0xFFFAF5F0),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              detail.category,
                              style: const TextStyle(
                                color: Color(0xFF8B7361),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              detail.headline,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: HestiaColors.textDark,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Three Badge Cards
                      Row(
                        children: [
                          Expanded(child: _buildBadge(detail.price, detail.priceSub)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildBadge(detail.duration, detail.durationSub)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildBadge(detail.rating, detail.ratingSub)),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // What's Included Heading
                      const Text(
                        'What\'s included',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Included Items List with slim checkmarks and dividers
                      Column(
                        children: List.generate(
                          detail.whatsIncluded.length,
                          (index) {
                            final item = detail.whatsIncluded[index];
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.check,
                                        color: HestiaColors.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (index < detail.whatsIncluded.length - 1)
                                  Divider(
                                    color: HestiaColors.inputBorder.withValues(alpha: 0.3),
                                    height: 24,
                                    thickness: 1.0,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      
      // Sticky Bottom Book Now Button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 20.0),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: HestiaColors.primary,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: HestiaColors.primary.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ScheduleScreen(serviceTitle: detail.title),
                    ),
                  );
                },
                child: const Center(
                  child: Text(
                    'Book now',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HestiaColors.primary,
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: HestiaColors.textMedium,
            ),
          ),
        ],
      ),
    );
  }
}
