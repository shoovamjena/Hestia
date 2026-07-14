import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/supabase_service.dart';
import '../theme/colors.dart';

class ReferAndEarnScreen extends StatelessWidget {
  const ReferAndEarnScreen({super.key});

  String get _referralCode {
    final user = SupabaseService.currentUser;
    final source = user?.id ?? SupabaseService.currentUserPhone;
    final cleaned = source.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (cleaned.length >= 6) {
      return 'HESTIA${cleaned.substring(cleaned.length - 6)}';
    }
    return 'HESTIA${cleaned.padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final code = _referralCode;
    return Scaffold(
      backgroundColor: HestiaColors.appBackground,
      appBar: AppBar(
        backgroundColor: HestiaColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Refer & Earn',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: Color(0xFFFAF2EB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_giftcard,
                  color: HestiaColors.primary,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Give ₹100, Get ₹100',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: HestiaColors.textDark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Invite your friends to Hestia. They get ₹100 off their first '
                'booking, and you earn ₹100 in Pronto Money when they book.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: HestiaColors.textMedium,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _buildCodeCard(context, code),
            const SizedBox(height: 28),
            const Text(
              'How it works',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: HestiaColors.textDark,
              ),
            ),
            const SizedBox(height: 16),
            _buildStep(
              number: '1',
              title: 'Share your code',
              subtitle: 'Send your unique referral code to friends and family.',
            ),
            _buildStep(
              number: '2',
              title: 'They book a service',
              subtitle:
                  'Your friend gets ₹100 off their first Hestia booking.',
            ),
            _buildStep(
              number: '3',
              title: 'You earn ₹100',
              subtitle:
                  '₹100 lands in your Pronto Money wallet after their first visit.',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeCard(BuildContext context, String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: HestiaColors.primary.withValues(alpha: 0.3),
          width: 1.4,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'YOUR REFERRAL CODE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: HestiaColors.textAccent,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF2EB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: HestiaColors.primary.withValues(alpha: 0.25),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                color: HestiaColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Referral code copied!'),
                        backgroundColor: HestiaColors.primary,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HestiaColors.primary,
                    side: const BorderSide(color: HestiaColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            'Join me on Hestia! Use my code $code to get ₹100 '
                            'off your first booking.',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite message copied to clipboard!'),
                        backgroundColor: HestiaColors.primary,
                      ),
                    );
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String subtitle,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: HestiaColors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: HestiaColors.primary.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                      height: 1.4,
                      color: HestiaColors.textMedium,
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
