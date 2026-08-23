import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../services/notifications_state.dart';
import '../services/supabase_service.dart';
import 'landing_screen.dart';
import 'search_location_screen.dart';
import 'pronto_money_screen.dart';
import 'refer_and_earn_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool showBackButton;
  const ProfileScreen({super.key, this.showBackButton = true});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String _name = 'User';
  String _email = '';
  String _phone = '';
  bool _isPhoneVerified = false;
  String _primaryReason = 'New mother';
  Map<String, dynamic> _address = {
    'flat': '',
    'street': '',
    'city': '',
    'pincode': '',
  };

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    final user = SupabaseService.currentUser;
    if (user != null) {
      // Pre-populate with auth metadata
      _name = user.userMetadata?['full_name'] ?? 'User';
      _email = SupabaseService.currentUserEmail;
      _phone = SupabaseService.currentUserPhone;
      _isPhoneVerified = SupabaseService.isPhoneVerified();

      try {
        var data = await SupabaseService.getUserProfile(user.id);
        if (data == null || data['address'] == null) {
          data = await SupabaseService.downloadProfileJson(user.id);
        }
        final profileMap = data;
        if (profileMap != null) {
          if (mounted) {
            setState(() {
              _name = profileMap['name'] ?? _name;
              _email = profileMap['email'] ?? _email;
              _phone = profileMap['phone'] ?? _phone;
              _isPhoneVerified =
                  profileMap['phone_verified'] == true ||
                  SupabaseService.isPhoneVerified();
              _primaryReason = profileMap['primary_reason'] ?? _primaryReason;
              if (profileMap['address'] != null) {
                _address = Map<String, dynamic>.from(profileMap['address']);
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading profile details: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Future<void> _saveProfileChanges() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    try {
      await SupabaseService.saveUserProfile(
        id: user.id,
        fullName: _name,
        email: _email,
        phone: _phone,
        address: _address,
      );

      final profileData = {
        'id': user.id,
        'name': _name,
        'email': _email,
        'phone': _phone,
        'primary_reason': _primaryReason,
        'address': _address,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await SupabaseService.uploadProfileJson(
        id: user.id,
        profileData: profileData,
      );

      await SupabaseService.createProfile(
        id: user.id,
        fullName: _name,
        email: _email,
        phone: _phone,
      );

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save changes: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _name);
    final emailController = TextEditingController(text: _email);
    final flatController = TextEditingController(text: _address['flat'] ?? '');
    final streetController = TextEditingController(
      text: _address['street'] ?? '',
    );
    final cityController = TextEditingController(text: _address['city'] ?? '');
    final pincodeController = TextEditingController(
      text: _address['pincode'] ?? _address['pin_code'] ?? '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(
                Icons.edit_note_rounded,
                color: HestiaColors.primary,
                size: 28,
              ),
              SizedBox(width: 8),
              Text(
                'Edit Profile & Address',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PERSONAL DETAILS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textAccent,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      'Full Name',
                      nameController,
                      (val) => val == null || val.trim().isEmpty
                          ? 'Enter name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _buildInputField('Email Address', emailController, (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Enter email';
                      }
                      if (!val.contains('@')) return 'Enter valid email';
                      return null;
                    }),
                    const SizedBox(height: 20),
                    const Text(
                      'ADDRESS DETAILS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textAccent,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      'Flat / House No. / Building',
                      flatController,
                      null,
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      'Street / Locality',
                      streetController,
                      (val) => val == null || val.trim().isEmpty
                          ? 'Enter street'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      'City',
                      cityController,
                      (val) => val == null || val.trim().isEmpty
                          ? 'Enter city'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      'Pincode',
                      pincodeController,
                      (val) => val == null || val.trim().isEmpty
                          ? 'Enter pincode'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  setState(() {
                    _name = nameController.text.trim();
                    _email = emailController.text.trim();
                    _address = {
                      'flat': flatController.text.trim(),
                      'street': streetController.text.trim(),
                      'city': cityController.text.trim(),
                      'pincode': pincodeController.text.trim(),
                    };
                  });
                  Navigator.pop(context);
                  _saveProfileChanges();
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller,
    String? Function(String?)? validator,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: HestiaColors.textDark,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: HestiaColors.primary,
                width: 1.5,
              ),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  void _showEditPersonalDetailsDialog() {
    final nameController = TextEditingController(text: _name);
    final emailController = TextEditingController(text: _email);
    String initialPhone = _phone.trim();
    if (initialPhone.startsWith('+91')) {
      initialPhone = initialPhone.substring(3);
    } else if (initialPhone.startsWith('91') && initialPhone.length > 10) {
      initialPhone = initialPhone.substring(2);
    }
    final phoneController = TextEditingController(text: initialPhone);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Edit Personal Details',
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
                    'FULL NAME',
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
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: HestiaColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (val) =>
                        val == null || val.trim().isEmpty ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'EMAIL ADDRESS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: emailController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: HestiaColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Enter email';
                      }
                      if (!val.contains('@')) return 'Enter valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PHONE NUMBER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      prefixIcon: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Text(
                          '+91 ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: HestiaColors.textDark,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: HestiaColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Enter phone';
                      }
                      if (val.trim().replaceAll(' ', '').length != 10) {
                        return 'Enter a valid 10-digit number';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  setState(() {
                    _name = nameController.text.trim();
                    _email = emailController.text.trim();
                    String typedPhone = phoneController.text.trim().replaceAll(
                      ' ',
                      '',
                    );
                    if (typedPhone.isNotEmpty && !typedPhone.startsWith('+')) {
                      typedPhone = '+91$typedPhone';
                    }
                    _phone = typedPhone;
                  });
                  Navigator.pop(context);
                  _saveProfileChanges();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showChangeReasonDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Service Preferred',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                [
                  'Post-Delivery Care',
                  'Mobility Support',
                  'Elder Care',
                  'Babysitting',
                  'Other',
                ].map((reason) {
                  return ListTile(
                    title: Text(
                      reason,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: _primaryReason == reason
                        ? const Icon(
                            Icons.check_circle,
                            color: HestiaColors.primary,
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        _primaryReason = reason;
                      });
                      Navigator.pop(context);
                      _saveProfileChanges();
                    },
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _performLogout() async {
    if (!mounted) return;

    final rootNavigator = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(color: HestiaColors.primary),
        ),
      ),
    );

    try {
      NotificationsState.instance.disposeSubscription();
      await SupabaseService.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to logout: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LandingScreen()),
      (route) => false,
    );
  }

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Confirm Logout',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          content: const Text(
            'Are you sure you want to log out of your Hestia account?',
            style: TextStyle(fontSize: 15, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC0392B), // Crimson Red
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _performLogout();
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(_name);
    final mutedBg = Color.alphaBlend(
      HestiaColors.mutedBrown.withValues(alpha: 0.18),
      const Color(0xFFF5F6FA),
    );

    return Scaffold(
      backgroundColor: mutedBg,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: HestiaColors.primary),
            )
          : Column(
              children: [
                _buildHeader(initials),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Column(
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -28),
                          child: Column(
                            children: [
                              _buildQuickActions(),
                              const SizedBox(height: 12),
                              _buildReferCard(),
                              const SizedBox(height: 12),
                              _buildMenuList(),
                            ],
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

  Widget _buildHeader(String initials) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 4,
        16,
        48,
      ),
      decoration: const BoxDecoration(color: HestiaColors.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.showBackButton)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                )
              else
                const SizedBox(width: 48),
              const Expanded(
                child: Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8D9CB),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: HestiaColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phone.isNotEmpty ? _phone : 'No phone added',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _showEditPersonalDetailsDialog,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Edit profile',
                              style: TextStyle(
                                color: Color(0xFFF5D9A8),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFFF5D9A8),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _quickActionCard(
            icon: Icons.assignment_outlined,
            label: 'My bookings',
            onTap: () {
              Navigator.of(context).pop();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _quickActionCard(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Hestia Money',
            badge: '₹0',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProntoMoneyScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _quickActionCard(
            icon: Icons.headset_mic_outlined,
            label: 'Help & Support',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Help & Support is coming soon!'),
                  backgroundColor: HestiaColors.primary,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 96,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: HestiaColors.textDark, size: 24),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: HestiaColors.textDark,
                      height: 1.2,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: HestiaColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: HestiaColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferCard() {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ReferAndEarnScreen()));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFAF2EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.card_giftcard,
                color: Color(0xFFC9A227),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Refer & earn',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: HestiaColors.textDark,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Upto ₹100',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9A6B1F),
                ),
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuList() {
    final items = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.menu_book_outlined,
        label: 'Saved addresses',
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(builder: (_) => const SearchLocationScreen()),
              )
              .then((_) => _loadProfileData());
        },
      ),
      (
        icon: Icons.info_outline,
        label: 'About us',
        onTap: () => _comingSoon('About us'),
      ),
      (
        icon: Icons.assignment_outlined,
        label: 'Terms of services',
        onTap: () => _comingSoon('Terms of services'),
      ),
      (
        icon: Icons.privacy_tip_outlined,
        label: 'Privacy policy',
        onTap: () => _comingSoon('Privacy policy'),
      ),
      (
        icon: Icons.person_remove_outlined,
        label: 'Request account deletion',
        onTap: () => _comingSoon('Account deletion'),
      ),
      (
        icon: Icons.logout_rounded,
        label: 'Log out',
        onTap: _showLogoutConfirmationDialog,
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.grey.shade200, indent: 56),
            InkWell(
              onTap: items[i].onTap,
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? const Radius.circular(16) : Radius.zero,
                bottom: i == items.length - 1
                    ? const Radius.circular(16)
                    : Radius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Icon(
                      items[i].icon,
                      color: items[i].label == 'Log out'
                          ? const Color(0xFFC0392B)
                          : HestiaColors.textDark,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: items[i].label == 'Log out'
                              ? const Color(0xFFC0392B)
                              : HestiaColors.textDark,
                        ),
                      ),
                    ),
                    if (items[i].label != 'Log out')
                      Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon!'),
        backgroundColor: HestiaColors.primary,
      ),
    );
  }
}
