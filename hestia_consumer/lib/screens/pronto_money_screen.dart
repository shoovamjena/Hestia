import 'package:flutter/material.dart';

import '../theme/colors.dart';

class ProntoMoneyScreen extends StatefulWidget {
  final bool showBackButton;
  final VoidCallback? onBack;

  const ProntoMoneyScreen({
    super.key,
    this.showBackButton = true,
    this.onBack,
  });

  @override
  State<ProntoMoneyScreen> createState() => _ProntoMoneyScreenState();
}

class _ProntoMoneyScreenState extends State<ProntoMoneyScreen> {
  static const List<int> _presetAmounts = [250, 500, 1000];
  static const int _minAmount = 1;
  static const int _maxAmount = 100000;

  late final TextEditingController _amountController;
  int _selectedAmount = 250;

  double get _cashback => _selectedAmount * 0.05;

  double get _totalInWallet => _selectedAmount + _cashback;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: '$_selectedAmount');
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _setAmount(int amount, {bool updateField = true}) {
    final clamped = amount.clamp(_minAmount, _maxAmount);
    setState(() => _selectedAmount = clamped);
    if (updateField) {
      final text = '$clamped';
      if (_amountController.text != text) {
        _amountController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  void _onAmountTextChanged(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      setState(() => _selectedAmount = 0);
      return;
    }
    final parsed = int.tryParse(digits) ?? 0;
    if (digits != value) {
      _amountController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    setState(() {
      _selectedAmount = parsed.clamp(0, _maxAmount);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.alphaBlend(
        HestiaColors.mutedBrown.withValues(alpha: 0.25),
        Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildBalanceCard(),
                    const SizedBox(height: 12),
                    _buildAddMoneyCard(context),
                    const SizedBox(height: 12),
                    _buildGiftCardRow(),
                    const SizedBox(height: 12),
                    _buildFeaturesRow(),
                    const SizedBox(height: 12),
                    _buildHowItWorksCard(),
                    const SizedBox(height: 12),
                    _buildUsingBalanceCard(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        52,
      ),
      decoration: const BoxDecoration(
        color: HestiaColors.primary,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.showBackButton)
            Align(
              alignment: Alignment.centerLeft,
              child: _headerIconButton(
                icon: Icons.chevron_left,
                onTap: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
          const Column(
            children: [
              Text(
                'Hestia',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                'MONEY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  height: 1.05,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _headerIconButton(
              icon: Icons.help_outline,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hestia Money help is coming soon!'),
                    backgroundColor: HestiaColors.primary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.22),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Wallet Balance',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: HestiaColors.textDark,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.info_outline,
                size: 16,
                color: Colors.grey.shade500,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '₹0',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: HestiaColors.primary,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your balance is low. Please add money to continue enjoying coin benefits.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B6B4A), Color(0xFF6F4E37)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_offer_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Get 5% Extra!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'On adding ₹250 or more',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildAddMoneyCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add money',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8E8E8), width: 1.5),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        '₹',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      IntrinsicWidth(
                        child: TextField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: HestiaColors.textDark,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: '0',
                            hintStyle: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFCCCCCC),
                            ),
                          ),
                          onChanged: _onAmountTextChanged,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF2EB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: HestiaColors.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      'Get ₹${_cashback.toStringAsFixed(1)} cashback',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: HestiaColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _selectedAmount > 0
                ? 'You will get ₹${_totalInWallet.toStringAsFixed(1)} in the wallet!'
                : 'Enter an amount to top up your wallet',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: _presetAmounts.map((amount) {
              final isSelected = amount == _selectedAmount;
              final bonus = amount * 0.05;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: amount != _presetAmounts.last ? 10 : 0,
                  ),
                  child: GestureDetector(
                    onTap: () => _setAmount(amount),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFAF2EB)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? HestiaColors.primary
                              : const Color(0xFFE0E0E0),
                          width: isSelected ? 2 : 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '₹$amount',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isSelected
                                  ? HestiaColors.textDark
                                  : HestiaColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF2EB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '+₹${bonus.toStringAsFixed(bonus == bonus.roundToDouble() ? 0 : 1)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: HestiaColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selectedAmount > 0
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Add ₹$_selectedAmount to wallet is coming soon!',
                          ),
                          backgroundColor: HestiaColors.primary,
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFCFCFCF),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _selectedAmount > 0
                    ? 'Add ₹$_selectedAmount to wallet'
                    : 'Enter amount',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftCardRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFAF2EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.card_giftcard,
              color: HestiaColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Claim a gift card',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: HestiaColors.textDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Enter gift card details to claim',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22),
        ],
      ),
    );
  }

  Widget _buildFeaturesRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
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
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _featureColumn(
                icon: Icons.bolt,
                title: 'Earn Rewards',
                subtitle: 'on every top-up',
              ),
            ),
            VerticalDivider(
              color: Colors.grey.shade200,
              width: 1,
              thickness: 1,
            ),
            Expanded(
              child: _featureColumn(
                icon: Icons.verified_user_outlined,
                title: 'Quick Checkout',
                subtitle: 'on every booking',
              ),
            ),
            VerticalDivider(
              color: Colors.grey.shade200,
              width: 1,
              thickness: 1,
            ),
            Expanded(
              child: _featureColumn(
                icon: Icons.calendar_month_outlined,
                title: 'Universal Access',
                subtitle: 'on all bookings',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureColumn({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFFAF2EB),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: HestiaColors.primary, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: HestiaColors.textDark,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    const steps = [
      'Add money to your Hestia wallet and receive promotional rewards.',
      'Checkout instantly with balance in your Hestia wallet across all orders.',
      'Wallet balance cannot be withdrawn and can only be used on Hestia, in accordance with applicable laws.',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          const Text(
            'How it works',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(steps.length, (index) {
            final isLast = index == steps.length - 1;
            return _timelineStep(
              text: steps[index],
              showLine: !isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _timelineStep({required String text, required bool showLine}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: HestiaColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: CustomPaint(
                      painter: _DashedLinePainter(
                        color: HestiaColors.primary.withValues(alpha: 0.45),
                      ),
                      size: const Size(2, double.infinity),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? 20 : 0),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsingBalanceCard() {
    const points = [
      'Seamlessly pay for bookings with balance in your wallet at Hestia.',
      'Promotional rewards expire 15 days after being credited.',
      'Cash balance expires 1 year from the date of credit.',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          const Text(
            'Using your Balance',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          ...points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: HestiaColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.grey.shade700,
                      ),
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

class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 4.0;
    const dashSpace = 4.0;
    double startY = 4;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
