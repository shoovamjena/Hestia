import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'schedule_screen.dart';

class ServiceStep {
  final String title;
  final String description;
  final String iconAsset;

  const ServiceStep({
    required this.title,
    required this.description,
    required this.iconAsset,
  });
}

class ServiceFAQ {
  final String question;
  final String answer;

  const ServiceFAQ({
    required this.question,
    required this.answer,
  });
}

class ServiceDetail {
  final String title;
  final String category;
  final String tagline;
  final String description;
  final String price;
  final String originalPrice;
  final String rating;
  final String ratingCount;
  final String detailImageAsset;
  final String iconAsset;
  final List<String> whatsIncluded;
  final List<String> doesNotInclude;
  final List<ServiceStep> howItsDone;
  final List<ServiceFAQ> faqs;

  const ServiceDetail({
    required this.title,
    required this.category,
    required this.tagline,
    required this.description,
    required this.price,
    required this.originalPrice,
    required this.rating,
    required this.ratingCount,
    required this.detailImageAsset,
    required this.iconAsset,
    required this.whatsIncluded,
    required this.doesNotInclude,
    required this.howItsDone,
    required this.faqs,
  });
}

class ServiceDetailScreen extends StatefulWidget {
  final String serviceKey;
  final Map<String, int> initialServicesMap;
  final ValueChanged<int>? onMinutesChanged;
  final bool bookingEnabled;

  const ServiceDetailScreen({
    super.key,
    required this.serviceKey,
    required this.initialServicesMap,
    this.onMinutesChanged,
    this.bookingEnabled = true,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();

  // Static service data matching the home screen options
  static final Map<String, ServiceDetail> servicesData = {
    'post-delivery': const ServiceDetail(
      title: 'Post-Delivery Care',
      category: 'MATERNAL CARE',
      tagline: 'Nurturing support for new mothers & newborns',
      description: 'Bring home professional maternal care and newborn support. Our trained specialists assist with postpartum recovery, baby hygiene, feeding support, and maternal well-being.',
      price: '₹499',
      originalPrice: '₹799',
      rating: '4.9',
      ratingCount: '(12.4k ratings)',
      detailImageAsset: 'assets/images/services/details/post_delivery.png',
      iconAsset: 'assets/images/services/post_delivery.png',
      whatsIncluded: [
        'Newborn bathing, skin care & swaddling',
        'Breastfeeding positioning & latch support',
        'Postpartum recovery massage & mother care',
        'Light, nutritious meal prep for the mother',
        'Real-time activity log & updates for family',
      ],
      doesNotInclude: [
        'Medical procedures (injections, IV therapy)',
        'Heavy household chores or laundry',
        'Caring for other children or pets',
        'Deep cleaning of rooms or kitchen',
      ],
      howItsDone: [
        ServiceStep(
          title: 'Initial Consultation',
          description: 'Assessing mother & newborn needs for the session',
          iconAsset: 'assets/images/services/steps/post_delivery/step_1.png',
        ),
        ServiceStep(
          title: 'Newborn Care & Bathing',
          description: 'Safe bathing, grooming, and swaddling of the baby',
          iconAsset: 'assets/images/services/steps/post_delivery/step_2.png',
        ),
        ServiceStep(
          title: 'Mother Recovery Support',
          description: 'Assisting with posture, meals, and recovery exercises',
          iconAsset: 'assets/images/services/steps/post_delivery/step_3.png',
        ),
        ServiceStep(
          title: 'Logging & Summary',
          description: 'Documenting feed times, sleep, and logs',
          iconAsset: 'assets/images/services/steps/post_delivery/step_4.png',
        ),
      ],
      faqs: [
        ServiceFAQ(
          question: 'Are the professionals certified?',
          answer: 'Yes, all our postpartum professionals are certified with nursing or maternal care backgrounds, thoroughly verified.',
        ),
        ServiceFAQ(
          question: 'Can I book for a full day?',
          answer: 'Absolutely. Sessions can range from 2 to 8 hours daily, and can be booked recurringly or as a single session.',
        ),
        ServiceFAQ(
          question: 'What equipment do I need to provide?',
          answer: 'Please provide newborn clothes, towels, baby wash, and ingredients if you need maternal meals prepared.',
        ),
      ],
    ),
    'babysitting': const ServiceDetail(
      title: 'Babysitting Care',
      category: 'CHILD CARE',
      tagline: 'Engaging and reliable supervision for your kids',
      description: 'Keep your children safe, engaged, and happy. Our professional babysitters provide playful companionship, homework support, meal feeding, and strict adherence to your child\'s routine.',
      price: '₹399',
      originalPrice: '₹599',
      rating: '4.8',
      ratingCount: '(18.2k ratings)',
      detailImageAsset: 'assets/images/services/details/babysitting.png',
      iconAsset: 'assets/images/services/babysitting.png',
      whatsIncluded: [
        'Age-appropriate playtime & creative activities',
        'Assistance with homework and reading',
        'Feeding, diapering, and toilet training support',
        'Bedtime and nap routine management',
        'Light tidying of the child\'s play area',
      ],
      doesNotInclude: [
        'Cooking meals for the entire household',
        'Deep cleaning or general household chores',
        'Driving children to external locations',
        'Administering prescription medications without consent',
      ],
      howItsDone: [
        ServiceStep(
          title: 'Introduction & Handover',
          description: 'Meeting the child and understanding parents\' guidelines',
          iconAsset: 'assets/images/services/steps/babysitting/step_1.png',
        ),
        ServiceStep(
          title: 'Active Playtime',
          description: 'Interactive games, drawing, and reading books',
          iconAsset: 'assets/images/services/steps/babysitting/step_2.png',
        ),
        ServiceStep(
          title: 'Meal & Routine',
          description: 'Feeding prepared food and managing nap schedule',
          iconAsset: 'assets/images/services/steps/babysitting/step_3.png',
        ),
        ServiceStep(
          title: 'Area Tidying',
          description: 'Putting away toys and leaving the room clean',
          iconAsset: 'assets/images/services/steps/babysitting/step_4.png',
        ),
      ],
      faqs: [
        ServiceFAQ(
          question: 'What is the minimum booking duration?',
          answer: 'The minimum booking duration is 3 hours to ensure a stable and meaningful care session.',
        ),
        ServiceFAQ(
          question: 'Are your babysitters background checked?',
          answer: 'Yes, all babysitters undergo rigorous background verification, reference checks, and training.',
        ),
        ServiceFAQ(
          question: 'Do you care for infants under 1 year?',
          answer: 'Yes, we have specialized infant-care babysitters trained in infant routines and safety.',
        ),
      ],
    ),
    'mobility': const ServiceDetail(
      title: 'Mobility Assistance',
      category: 'ELDERLY & ADULT CARE',
      tagline: 'Safe and dignified support for daily movement',
      description: 'Help your loved ones regain their confidence and mobility. Our professionals assist with transfers, walking, light exercise, wheelchair navigation, and companionship.',
      price: '₹449',
      originalPrice: '₹699',
      rating: '4.9',
      ratingCount: '(9.8k ratings)',
      detailImageAsset: 'assets/images/services/details/mobility.png',
      iconAsset: 'assets/images/services/mobility.png',
      whatsIncluded: [
        'Assistance with transfers (bed to chair, etc.)',
        'Support with walking and outdoor walks',
        'Guiding light physical exercises & stretches',
        'Wheelchair and walker navigation',
        'Warm companionship and active conversation',
      ],
      doesNotInclude: [
        'Physical therapy or rehabilitation treatment',
        'Lifting heavy objects or cleaning rooms',
        'Giving injections or medical diagnosis',
        'Errands outside without client accompaniment',
      ],
      howItsDone: [
        ServiceStep(
          title: 'Warmup & Safety Check',
          description: 'Checking client comfort and walking aids condition',
          iconAsset: 'assets/images/services/steps/mobility/step_1.png',
        ),
        ServiceStep(
          title: 'Guided Movement',
          description: 'Assisting with walks in/around the house safely',
          iconAsset: 'assets/images/services/steps/mobility/step_2.png',
        ),
        ServiceStep(
          title: 'Exercise & Stretching',
          description: 'Conducting prescribed exercises or gentle stretches',
          iconAsset: 'assets/images/services/steps/mobility/step_3.png',
        ),
        ServiceStep(
          title: 'Companionship Pause',
          description: 'Relaxing with tea, books, or warm conversation',
          iconAsset: 'assets/images/services/steps/mobility/step_4.png',
        ),
      ],
      faqs: [
        ServiceFAQ(
          question: 'Can you help with post-surgery recovery?',
          answer: 'Yes, we help with general mobility and safety walks during recovery, but do not provide clinical nursing.',
        ),
        ServiceFAQ(
          question: 'Is support available for wheelchair users?',
          answer: 'Yes, our professionals are trained in safe wheelchair transfers and navigation techniques.',
        ),
        ServiceFAQ(
          question: 'Can this be booked daily?',
          answer: 'Yes, we offer recurring daily bookings to help establish a consistent routine.',
        ),
      ],
    ),
    'pre-pregnancy': const ServiceDetail(
      title: 'Pre-Pregnancy Care',
      category: 'MATERNAL CARE',
      tagline: 'Holistic prenatal planning & preparation',
      description: 'Prepare for a smooth journey into motherhood. Get expert guidance on birth planning, prenatal nutrition, safe physical stretching, breathing techniques, and nursery preparation.',
      price: '₹599',
      originalPrice: '₹899',
      rating: '4.7',
      ratingCount: '(5.1k ratings)',
      detailImageAsset: 'assets/images/services/details/pre_pregnancy.png',
      iconAsset: 'assets/images/services/pre_pregnancy.png',
      whatsIncluded: [
        'Personalized birth planning & consultation',
        'Holistic prenatal nutrition & diet advice',
        'Gentle stretching, yoga & breathing exercises',
        'Nursery organization & baby shopping lists',
        'Partner coaching & preparation tips',
      ],
      doesNotInclude: [
        'Medical scans or ultrasound diagnostics',
        'Medical prescriptions or labor delivery',
        'Heavy housekeeping or general cooking',
      ],
      howItsDone: [
        ServiceStep(
          title: 'Goal Setting',
          description: 'Understanding the maternal timeline and target areas',
          iconAsset: 'assets/images/services/steps/pre_pregnancy/step_1.png',
        ),
        ServiceStep(
          title: 'Nutrition & Planning',
          description: 'Structuring diet and drafting birth plans',
          iconAsset: 'assets/images/services/steps/pre_pregnancy/step_2.png',
        ),
        ServiceStep(
          title: 'Gentle Exercise',
          description: 'Breathing exercises and pregnancy safe stretches',
          iconAsset: 'assets/images/services/steps/pre_pregnancy/step_3.png',
        ),
        ServiceStep(
          title: 'Nursery Check',
          description: 'Reviewing nursery layout and items checklist',
          iconAsset: 'assets/images/services/steps/pre_pregnancy/step_4.png',
        ),
      ],
      faqs: [
        ServiceFAQ(
          question: 'When should I start this care?',
          answer: 'You can start at any stage of your pregnancy, though starting in the second trimester is popular.',
        ),
        ServiceFAQ(
          question: 'Can my partner attend the sessions?',
          answer: 'Yes! We encourage partners to attend, especially for coaching and labor support tips.',
        ),
        ServiceFAQ(
          question: 'Is this service virtual or in-person?',
          answer: 'This is an in-person, in-home service, allowing for hands-on planning and exercise guide.',
        ),
      ],
    ),
    'bathing': const ServiceDetail(
      title: 'Bathing and Grooming',
      category: 'PERSONAL CARE',
      tagline: 'Dignified and safe personal hygiene support',
      description: 'Maintain personal hygiene with comfort and dignity. Our care providers ensure a safe bathing environment, assisting with bathroom transfers, washing, drying, and skin moisturizing.',
      price: '₹349',
      originalPrice: '₹499',
      rating: '4.8',
      ratingCount: '(7.6k ratings)',
      detailImageAsset: 'assets/images/services/details/bathing.png',
      iconAsset: 'assets/images/services/bathing.png',
      whatsIncluded: [
        'Safe transfers in & out of bath area',
        'Gentle bathing, body wash & hair washing',
        'Towel drying & skin moisturizing',
        'Assistance with dressing & grooming',
        'Immediate bathroom safety monitoring',
      ],
      doesNotInclude: [
        'Cleaning of the entire bathroom (only quick rinse after bath)',
        'Giving haircuts or nail trimming with sharp tools',
        'Washing piles of laundry',
      ],
      howItsDone: [
        ServiceStep(
          title: 'Setup & Warmup',
          description: 'Preparing the bathroom, adjusting water temperature',
          iconAsset: 'assets/images/services/steps/bathing/step_1.png',
        ),
        ServiceStep(
          title: 'Safe Transfer',
          description: 'Assisting the client into the bath area safely',
          iconAsset: 'assets/images/services/steps/bathing/step_2.png',
        ),
        ServiceStep(
          title: 'Bathing & Washing',
          description: 'Respectful and thorough cleansing of body and hair',
          iconAsset: 'assets/images/services/steps/bathing/step_3.png',
        ),
        ServiceStep(
          title: 'Drying & Dressing',
          description: 'Drying, moisturizing, and assisting with clean clothes',
          iconAsset: 'assets/images/services/steps/bathing/step_4.png',
        ),
      ],
      faqs: [
        ServiceFAQ(
          question: 'How do you ensure client privacy?',
          answer: 'Our professionals are highly trained to maintain client dignity by using cover-ups and professional care protocols.',
        ),
        ServiceFAQ(
          question: 'What if the bathroom is not elder-friendly?',
          answer: 'During the first visit, our professional will suggest simple safety adjustments (like anti-slip mats).',
        ),
        ServiceFAQ(
          question: 'Do you provide soaps and shampoo?',
          answer: 'No, we use the client\'s preferred toiletries to avoid skin allergies or irritations.',
        ),
      ],
    ),
    'concierge': const ServiceDetail(
      title: 'Administrative & Concierge',
      category: 'HOME SUPPORT',
      tagline: 'Help with grocery, runs, and organization',
      description: 'Delegate your daily errands to a reliable assistant. We help with grocery shopping, picking up prescription refills, coordinating mail, home sorting, and escorting to appointments.',
      price: '₹299',
      originalPrice: '₹399',
      rating: '4.6',
      ratingCount: '(3.4k ratings)',
      detailImageAsset: 'assets/images/services/details/concierge.png',
      iconAsset: 'assets/images/services/concierge.png',
      whatsIncluded: [
        'Grocery shopping & prescription refills',
        'Post office runs & package drop-offs',
        'Light home sorting & closet organization',
        'Coordinating and paying bills online (with supervision)',
        'Escorting to doctor visits or local social events',
      ],
      doesNotInclude: [
        'Driving the client\'s personal vehicle (we use cabs or walk)',
        'Heavy lifting or furniture moving',
        'Deep cleaning or window washing',
        'Authorized signatures on legal documents',
      ],
      howItsDone: [
        ServiceStep(
          title: 'List Verification',
          description: 'Reviewing the shopping list, budgets, and keys',
          iconAsset: 'assets/images/services/steps/concierge/step_1.png',
        ),
        ServiceStep(
          title: 'Errand Run',
          description: 'Going to local markets or stores to fetch items',
          iconAsset: 'assets/images/services/steps/concierge/step_2.png',
        ),
        ServiceStep(
          title: 'Delivery & Sorting',
          description: 'Bringing items back and organizing them in the pantry',
          iconAsset: 'assets/images/services/steps/concierge/step_3.png',
        ),
        ServiceStep(
          title: 'Billing Review',
          description: 'Presenting bills and checking matching receipts',
          iconAsset: 'assets/images/services/steps/concierge/step_4.png',
        ),
      ],
      faqs: [
        ServiceFAQ(
          question: 'Who pays for the purchases?',
          answer: 'The client must pay for all purchases directly. We do not advance funds for purchases.',
        ),
        ServiceFAQ(
          question: 'Can you drive my parents to the doctor?',
          answer: 'We can accompany them in a cab or walk with them, but our professionals do not drive personal vehicles for liability reasons.',
        ),
        ServiceFAQ(
          question: 'Is there a weight limit for grocery bags?',
          answer: 'Yes, our professionals can carry standard grocery bags up to 10kg.',
        ),
      ],
    ),
  };

  static ServiceDetail? resolveServiceDetail(String labelOrKey) {
    if (servicesData.containsKey(labelOrKey)) {
      return servicesData[labelOrKey];
    }

    final key = labelOrKey
        .replaceAll('\n', '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .toLowerCase();

    if (key.contains('postdelivery')) return servicesData['post-delivery'];
    if (key.contains('babysitting')) return servicesData['babysitting'];
    if (key.contains('mobility')) return servicesData['mobility'];
    if (key.contains('prepregnancy')) return servicesData['pre-pregnancy'];
    if (key.contains('bathing') || key.contains('grooming')) {
      return servicesData['bathing'];
    }
    if (key.contains('concierge') || key.contains('administrative')) {
      return servicesData['concierge'];
    }
    return null;
  }

  static String iconAssetFor(String labelOrKey) {
    return resolveServiceDetail(labelOrKey)?.iconAsset ??
        'assets/images/services/post_delivery.png';
  }
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late int _selectedMinutes;
  late Map<String, int> _selectedServicesMap;

  @override
  void initState() {
    super.initState();
    _selectedServicesMap = Map<String, int>.from(widget.initialServicesMap);
    _selectedMinutes = _selectedServicesMap[widget.serviceKey] ?? 0;
  }

  ServiceDetail _getServiceDetail() {
    return ServiceDetailScreen.resolveServiceDetail(widget.serviceKey) ??
        ServiceDetailScreen.servicesData['post-delivery']!;
  }

  Widget _buildBookOrStepper(ServiceDetail detail) {
    if (!widget.bookingEnabled) {
      return const SizedBox.shrink();
    }

    if (_selectedMinutes <= 0) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedMinutes = 30;
            _selectedServicesMap[widget.serviceKey] = 30;
          });
          widget.onMinutesChanged?.call(30);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: HestiaColors.primary,
              width: 1.5,
            ),
          ),
          child: const Text(
            'BOOK',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: HestiaColors.primary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 120,
      height: 46,
      decoration: BoxDecoration(
        color: HestiaColors.primary,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: HestiaColors.primary.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minus Button
          GestureDetector(
            onTap: () {
              setState(() {
                final next = _selectedMinutes - 30;
                _selectedMinutes = next < 0 ? 0 : next;
                if (_selectedMinutes <= 0) {
                  _selectedServicesMap.remove(widget.serviceKey);
                } else {
                  _selectedServicesMap[widget.serviceKey] = _selectedMinutes;
                }
              });
              widget.onMinutesChanged?.call(_selectedMinutes);
            },
            child: Container(
              width: 36,
              height: 46,
              color: Colors.transparent,
              child: const Icon(
                Icons.remove,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          // Minutes display
          Expanded(
            child: Center(
              child: Text(
                '$_selectedMinutes min',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Plus Button
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedMinutes += 30;
                _selectedServicesMap[widget.serviceKey] = _selectedMinutes;
              });
              widget.onMinutesChanged?.call(_selectedMinutes);
            },
            child: Container(
              width: 36,
              height: 46,
              color: Colors.transparent,
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _getServiceDetail();
    final double hourlyPrice = double.tryParse(detail.price.replaceAll('₹', '').trim()) ?? 0.0;
    final double origHourlyPrice = double.tryParse(detail.originalPrice.replaceAll('₹', '').trim()) ?? 0.0;
    final displayPrice = _selectedMinutes > 0 
        ? '₹${(hourlyPrice * (_selectedMinutes / 60.0)).toStringAsFixed(0)}' 
        : '₹${hourlyPrice.toStringAsFixed(0)}/hr';
    final displayOriginalPrice = _selectedMinutes > 0 
        ? '₹${(origHourlyPrice * (_selectedMinutes / 60.0)).toStringAsFixed(0)}' 
        : '₹${origHourlyPrice.toStringAsFixed(0)}/hr';

    return Scaffold(
      body: Container(
        color: HestiaColors.appBackground,
        child: Stack(
          children: [
            SingleChildScrollView(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image with floating back and share buttons
            Stack(
              children: [
                // Top Cover Image
                Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    child: Image.asset(
                      detail.detailImageAsset,
                      width: double.infinity,
                      height: 280,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 280,
                          color: const Color(0xFFFAF5F0),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported_outlined,
                                size: 50,
                                color: HestiaColors.primary,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Add detail image PNG to assets/images/services/details/',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: HestiaColors.textMedium,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Floating Back Button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // Floating Share Button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  right: 16,
                  child: GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sharing ${detail.title}...'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.share,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content Sections
            // Title, Price & Book Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title & Price on the left
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: HestiaColors.textDark,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              displayPrice,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: HestiaColors.textDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              displayOriginalPrice,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: HestiaColors.textLight,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // BOOK button on the right
                  // BOOK button / stepper on the right
                  _buildBookOrStepper(detail),
                ],
              ),
            ),

            Divider(color: Colors.grey.withValues(alpha: 0.2), height: 16, thickness: 1),

            // Rating Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Color(0xFFFFC107), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${detail.rating} ${detail.ratingCount}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HestiaColors.textMedium,
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: Colors.grey.withValues(alpha: 0.2), height: 16, thickness: 1),

            // Tagline & Description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.tagline,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail.description,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: HestiaColors.textMedium,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Includes Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Includes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...detail.whatsIncluded.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF0F9D58), // Google Green
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              color: HestiaColors.textDark,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Does Not Include Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Does not include',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...detail.doesNotInclude.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.cancel,
                          color: Color(0xFFEA4335), // Google Red
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              color: HestiaColors.textDark,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // How It's Done Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How it\'s done?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...detail.howItsDone.map((step) => Padding(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: Image.asset(
                            step.iconAsset,
                            width: 60,
                            height: 60,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.image_not_supported_outlined,
                                color: HestiaColors.primary,
                                size: 42,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: HestiaColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                step.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: HestiaColors.textMedium,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // FAQs Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FAQs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...detail.faqs.map((faq) => FaqAccordionItem(faq: faq)),
                ],
              ),
            ),

            // Padding at the bottom of the scroll view (space for floating cart bar)
            const SizedBox(height: 110),
          ],
        ),
      ),
      
      // Floating Cart Bar (just like on home screen!)
      _buildFloatingCartBar(detail),
    ],
  ),
      ),
    );
  }

  Widget _buildFloatingCartBar(ServiceDetail currentDetail) {
    final hasServices =
        widget.bookingEnabled && _selectedServicesMap.isNotEmpty;
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      bottom: hasServices ? 16 : -80,
      left: 20,
      right: 20,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: hasServices ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color.fromARGB(255, 65, 40, 18),
                Color.fromARGB(255, 120, 80, 40),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: HestiaColors.primary.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Cart icon + count pill
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              // Label
              Expanded(
                child: Text(
                  '${_selectedServicesMap.length} ${_selectedServicesMap.length == 1 ? 'service' : 'services'} added',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Go to Cart button
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ScheduleScreen(
                        serviceTitle: currentDetail.title,
                        initialServicesMap: Map<String, int>.from(_selectedServicesMap),
                        onServicesChanged: (updatedMap) {
                          setState(() {
                            _selectedServicesMap.clear();
                            _selectedServicesMap.addAll(updatedMap);
                            _selectedMinutes = _selectedServicesMap[widget.serviceKey] ?? 0;
                          });
                          widget.onMinutesChanged?.call(_selectedMinutes);
                        },
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Go to Cart',
                        style: TextStyle(
                          color: HestiaColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: HestiaColors.primary,
                        size: 11,
                      ),
                    ],
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

class FaqAccordionItem extends StatefulWidget {
  final ServiceFAQ faq;

  const FaqAccordionItem({super.key, required this.faq});

  @override
  State<FaqAccordionItem> createState() => _FaqAccordionItemState();
}

class _FaqAccordionItemState extends State<FaqAccordionItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: HestiaColors.mutedBrown,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HestiaColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.faq.question,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.remove : Icons.add,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.faq.answer,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.45,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
