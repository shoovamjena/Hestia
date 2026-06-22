import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'landing_screen.dart';
import 'search_location_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String _name = 'User';
  String _email = '';
  String _phone = '';
  String _primaryReason = 'New mother';
  List<dynamic> _members = [];
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
    setState(() {
      _isLoading = true;
    });
    final user = SupabaseService.currentUser;
    if (user != null) {
      // Pre-populate with auth metadata
      _name = user.userMetadata?['full_name'] ?? 'User';
      _email = user.email ?? '';
      _phone = user.phone ?? user.userMetadata?['phone'] ?? '';

      try {
        var data = await SupabaseService.getUserProfile(user.id);
        if (data == null || data['address'] == null) {
          data = await SupabaseService.downloadProfileJson(user.id);
        }
        final profileMap = data;
        if (profileMap != null) {
          setState(() {
            _name = profileMap['name'] ?? _name;
            _email = profileMap['email'] ?? _email;
            _phone = profileMap['phone'] ?? _phone;
            _primaryReason = profileMap['primary_reason'] ?? _primaryReason;
            _members = profileMap['household_members'] ?? [];
            if (profileMap['address'] != null) {
              _address = Map<String, dynamic>.from(profileMap['address']);
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading profile details: $e');
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  String _getEmojiForAge(int age) {
    if (age <= 2) return '👶';
    if (age <= 12) return '🧒';
    if (age <= 19) return '🧑';
    if (age <= 59) return '🧑';
    return '👵';
  }

  Color _getColorForAge(int age) {
    if (age <= 2) return const Color(0xFFFFE6CC);
    if (age <= 12) return const Color(0xFFE1F5FE);
    if (age <= 19) return const Color(0xFFEDE7F6);
    if (age <= 59) return const Color(0xFFFCE4EC);
    return const Color(0xFFE4F1D8);
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
        primaryReason: _primaryReason,
        members: _members,
        address: _address,
      );

      final profileData = {
        'id': user.id,
        'name': _name,
        'email': _email,
        'phone': _phone,
        'primary_reason': _primaryReason,
        'household_members': _members,
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
    final streetController = TextEditingController(text: _address['street'] ?? '');
    final cityController = TextEditingController(text: _address['city'] ?? '');
    final pincodeController = TextEditingController(text: _address['pincode'] ?? _address['pin_code'] ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.edit_note_rounded, color: HestiaColors.primary, size: 28),
              SizedBox(width: 8),
              Text(
                'Edit Profile & Address',
                style: TextStyle(fontWeight: FontWeight.bold, color: HestiaColors.textDark),
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
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 12),
                    _buildInputField('Full Name', nameController, (val) => val == null || val.trim().isEmpty ? 'Enter name' : null),
                    const SizedBox(height: 12),
                    _buildInputField('Email Address', emailController, (val) {
                      if (val == null || val.trim().isEmpty) return 'Enter email';
                      if (!val.contains('@')) return 'Enter valid email';
                      return null;
                    }),
                    const SizedBox(height: 20),
                    const Text(
                      'ADDRESS DETAILS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 12),
                    _buildInputField('Flat / House No. / Building', flatController, null),
                    const SizedBox(height: 12),
                    _buildInputField('Street / Locality', streetController, (val) => val == null || val.trim().isEmpty ? 'Enter street' : null),
                    const SizedBox(height: 12),
                    _buildInputField('City', cityController, (val) => val == null || val.trim().isEmpty ? 'Enter city' : null),
                    const SizedBox(height: 12),
                    _buildInputField('Pincode', pincodeController, (val) => val == null || val.trim().isEmpty ? 'Enter pincode' : null),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildInputField(String label, TextEditingController controller, String? Function(String?)? validator) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: HestiaColors.textDark),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
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
    final phoneController = TextEditingController(text: _phone);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Edit Personal Details',
            style: TextStyle(fontWeight: FontWeight.bold, color: HestiaColors.textDark),
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
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent),
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
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'EMAIL ADDRESS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent),
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
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Enter email';
                      if (!val.contains('@')) return 'Enter valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PHONE NUMBER',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: phoneController,
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
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Enter phone' : null,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  setState(() {
                    _name = nameController.text.trim();
                    _email = emailController.text.trim();
                    _phone = phoneController.text.trim();
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

  void _showAddMemberDialog() {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    final roleController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Add Household Member',
            style: TextStyle(fontWeight: FontWeight.bold, color: HestiaColors.textDark),
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
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Meera',
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
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'AGE (YEARS)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'e.g. 68',
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
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Enter age';
                      final age = int.tryParse(val);
                      if (age == null || age < 0) return 'Enter valid age';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ROLE / CARE REASON',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HestiaColors.textAccent),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: roleController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Grandmother / Mobility Support',
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
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Enter role/reason' : null,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final age = int.parse(ageController.text);
                  setState(() {
                    _members.add({
                      'name': nameController.text.trim(),
                      'age': age,
                      'role': roleController.text.trim(),
                    });
                  });
                  Navigator.pop(context);
                  _saveProfileChanges();
                }
              },
              child: const Text('Add'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Primary Reason for Care',
            style: TextStyle(fontWeight: FontWeight.bold, color: HestiaColors.textDark),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              'New mother',
              'Post-surgery',
              'Elderly care',
              'Childcare',
              'Other',
            ].map((reason) {
              return ListTile(
                title: Text(reason, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: _primaryReason == reason ? const Icon(Icons.check_circle, color: HestiaColors.primary) : null,
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

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Confirm Logout',
            style: TextStyle(fontWeight: FontWeight.bold, color: HestiaColors.textDark),
          ),
          content: const Text(
            'Are you sure you want to log out of your Hestia account?',
            style: TextStyle(fontSize: 15, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC0392B), // Crimson Red
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(color: HestiaColors.primary),
                  ),
                );
                try {
                  await SupabaseService.signOut();
                  if (context.mounted) {
                    Navigator.pop(context); // Close loading indicator
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const LandingScreen()),
                      (route) => false,
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to logout: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
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
    final String addressString = _address['street'].toString().trim().isNotEmpty
        ? '${_address['flat'] ?? ''} ${_address['street']}, ${_address['city'] ?? ''} - ${_address['pincode'] ?? ''}'
        : 'No address set';

    return Scaffold(
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : SafeArea(
                child: Column(
                  children: [
                    // Custom Integrated AppBar with white coloring for the dark gradient top
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
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
                              ),
                              child: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                            ),
                          ),
                          const Text(
                            'Hestia Profile',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(width: 40), // Spacer to balance the back button
                        ],
                      ),
                    ),

                    // Scrollable content
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Profile Header Glassmorphic Badge
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: const BoxDecoration(
                                      color: Colors.white24,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      initials,
                                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _name,
                                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: _showEditProfileDialog,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Row(
                                                  children: const [
                                                    Icon(Icons.edit, color: Colors.white, size: 14),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Edit',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _phone,
                                          style: const TextStyle(fontSize: 14, color: Colors.white70),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _email,
                                          style: const TextStyle(fontSize: 14, color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 28),

                            // Personal Details Card
                            _buildSectionHeader('Personal Details', _showEditPersonalDetailsDialog),
                            const SizedBox(height: 12),
                            _buildProfileCard([
                              _buildDetailRow(Icons.person_outline, 'Full Name', _name),
                              const Divider(height: 24, thickness: 0.8),
                              _buildDetailRow(Icons.email_outlined, 'Email Address', _email),
                              const Divider(height: 24, thickness: 0.8),
                              _buildDetailRow(Icons.phone_outlined, 'Phone Number', _phone),
                            ]),

                            const SizedBox(height: 28),

                            // Saved Address Card
                            _buildSectionHeader('Primary Address', () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const SearchLocationScreen(),
                                ),
                              ).then((_) => _loadProfileData());
                            }),
                            const SizedBox(height: 12),
                            _buildProfileCard([
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_outlined, color: HestiaColors.primary, size: 22),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Current Location',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          addressString,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: HestiaColors.textDark,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ]),

                            const SizedBox(height: 28),

                            // Care Profile Card
                            _buildSectionHeader('Care Profile', _showChangeReasonDialog, actionLabel: 'Change Reason'),
                            const SizedBox(height: 12),
                            _buildProfileCard([
                              _buildDetailRow(Icons.health_and_safety_outlined, 'Primary Reason for Care', _primaryReason),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Household Members under Care',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                                  ),
                                  GestureDetector(
                                    onTap: _showAddMemberDialog,
                                    child: const Text(
                                      '+ Add Member',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: HestiaColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_members.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'No members added yet.',
                                    style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _members.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final member = _members[index];
                                    final name = member['name'] ?? '';
                                    final age = member['age'] as int? ?? 0;
                                    final role = member['role'] ?? '';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.grey.shade200, width: 0.8),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: _getColorForAge(age),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              _getEmojiForAge(age),
                                              style: const TextStyle(fontSize: 16),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: HestiaColors.textDark,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$role • ${age > 0 ? '$age yrs' : 'Newborn'}',
                                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _members.removeAt(index);
                                              });
                                              _saveProfileChanges();
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ]),

                            const SizedBox(height: 36),

                            // Logout Button
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFC0392B),
                                  side: const BorderSide(color: Color(0xFFFADBD8), width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: _showLogoutConfirmationDialog,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.logout_rounded, size: 20),
                                    SizedBox(width: 8),
                                    Text('Log Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 40),
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

  Widget _buildSectionHeader(String title, VoidCallback onAction, {String actionLabel = 'Edit'}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HestiaColors.textDark),
        ),
        GestureDetector(
          onTap: onAction,
          child: Text(
            actionLabel,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HestiaColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: HestiaColors.primary, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                value.isNotEmpty ? value : 'Not provided',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: HestiaColors.textDark),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
