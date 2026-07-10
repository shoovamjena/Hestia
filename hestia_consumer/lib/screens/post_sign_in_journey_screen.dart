import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'search_location_screen.dart';

class PostSignInJourneyScreen extends StatefulWidget {
  const PostSignInJourneyScreen({super.key});

  @override
  State<PostSignInJourneyScreen> createState() => _PostSignInJourneyScreenState();
}

class _PostSignInJourneyScreenState extends State<PostSignInJourneyScreen> {
  bool _checkingProfile = true;

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
        if (isComplete) {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          }
          return;
        }
      } catch (e) {
        debugPrint('Error checking profile status in PostSignInJourneyScreen: $e');
      }
    }
    if (mounted) {
      setState(() {
        _checkingProfile = false;
      });
    }
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
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _HouseholdIntroPage(),
        ),
      ),
    );
  }
}

class _JourneyShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget primaryButton;

  const _JourneyShell({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primaryButton,
  });

  @override
  Widget build(BuildContext context) {
    const currentPage = 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
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
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(
              2,
              (index) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 1 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: index <= currentPage ? Colors.white : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6F4E37).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF6F4E37).withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          primaryButton,
        ],
      ),
    );
  }
}

class _HouseholdIntroPage extends StatefulWidget {
  const _HouseholdIntroPage();

  @override
  State<_HouseholdIntroPage> createState() => _HouseholdIntroPageState();
}

class _HouseholdIntroPageState extends State<_HouseholdIntroPage> {
  String _selectedReason = 'Post-Delivery Care';
  final List<Map<String, dynamic>> _members = [];

  // Helper to determine emoji based on age
  String _getEmojiForAge(int age) {
    if (age <= 2) return '👶';
    if (age <= 12) return '🧒';
    if (age <= 19) return '🧑';
    if (age <= 59) return '🧑';
    return '👵';
  }

  // Helper to determine accent color based on age
  Color _getColorForAge(int age) {
    if (age <= 2) return const Color(0xFFFFE6CC);
    if (age <= 12) return const Color(0xFFE1F5FE);
    if (age <= 19) return const Color(0xFFEDE7F6);
    if (age <= 59) return const Color(0xFFFCE4EC);
    return const Color(0xFFE4F1D8);
  }

  void _showAddMemberDialog() {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    String? selectedRole = 'Post-Delivery Care';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: HestiaColors.background,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Add Household Member',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MEMBER NAME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          hintText: 'e.g. Meera',
                          filled: true,
                          fillColor: HestiaColors.inputBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'AGE (YEARS)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: ageController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 68',
                          filled: true,
                          fillColor: HestiaColors.inputBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter age';
                          }
                          final age = int.tryParse(value);
                          if (age == null || age < 0) {
                            return 'Please enter a valid age';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'SERVICE PREFERRED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        hint: const Text('Select service preferred'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: HestiaColors.inputBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                          ),
                        ),
                        items: [
                          'Post-Delivery Care',
                          'Mobility Support',
                          'Elder Care',
                          'Babysitting',
                          'Other',
                        ].map((val) => DropdownMenuItem(
                          value: val,
                          child: Text(val),
                        )).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedRole = val;
                          });
                        },
                        validator: (val) => val == null ? 'Select service preferred' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: HestiaColors.textMedium)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: HestiaColors.buttonText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final age = int.parse(ageController.text);
                      setState(() {
                        _members.add({
                          'name': nameController.text.trim(),
                          'age': age,
                          'role': selectedRole ?? 'Other',
                        });
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _JourneyShell(
      title: 'Tell us about\nyour household',
      subtitle: 'This helps us personalise your care experience',
      primaryButton: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => SearchLocationScreen(
                  isPostSignInJourney: true,
                  primaryReason: _selectedReason,
                  members: _members,
                ),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: HestiaColors.primary,
            foregroundColor: HestiaColors.buttonText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Continue',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SERVICE PREFERRED',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: HestiaColors.textLight,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                'Post-Delivery Care',
                'Mobility Support',
                'Elder Care',
                'Babysitting',
                'Other',
              ].map((reason) {
                final isSelected = _selectedReason == reason;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedReason = reason;
                    });
                  },
                  child: _ReasonChip(
                    label: reason,
                    selected: isSelected,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            const Text(
              'Household members',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: HestiaColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            ..._members.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;
              final age = member['age'] as int;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _HouseholdMemberCard(
                  name: '${member['name']} (${age > 0 ? '$age yr' : 'Newborn'})',
                  subtitle: member['role'],
                  icon: _getEmojiForAge(age),
                  accentColor: _getColorForAge(age),
                  onRemove: () {
                    setState(() {
                      _members.removeAt(index);
                    });
                  },
                ),
              );
            }),
            GestureDetector(
              onTap: _showAddMemberDialog,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5ECE3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE6D5C5)),
                ),
                child: Row(
                  children: const [
                    _IconBadge(icon: Icons.add, background: Color(0xFFE6D5C5)),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add household member',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: HestiaColors.textDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Newborn, elderly parent, patient...',
                            style: TextStyle(
                              fontSize: 13,
                              color: HestiaColors.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final bool selected;

  const _ReasonChip({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: selected 
            ? HestiaColors.primary 
            : HestiaColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected 
              ? HestiaColors.primary 
              : HestiaColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: selected ? Colors.white : HestiaColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HouseholdMemberCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String icon;
  final Color accentColor;
  final VoidCallback onRemove;

  const _HouseholdMemberCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5ECE3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: HestiaColors.textMedium,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: HestiaColors.textLight, size: 20),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color background;

  const _IconBadge({required this.icon, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: HestiaColors.primary, size: 24),
    );
  }
}
