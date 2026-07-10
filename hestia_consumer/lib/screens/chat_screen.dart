import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String caregiverName;
  final DateTime? actualStart;
  final double? durationHours;

  const ChatScreen({
    super.key,
    required this.sessionId,
    this.caregiverName = 'Sunita Rao',
    this.actualStart,
    this.durationHours,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _messageController.clear();
    await SupabaseService.sendMessage(
      sessionId: widget.sessionId,
      senderId: user.id,
      senderType: 'client',
      content: text,
    );
    _scrollToBottom();
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
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          title: Text(
            widget.caregiverName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
        child: Column(
          children: [
            // Caregiver Info Header Card
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: _glassCard(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                borderRadius: 24,
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _getInitials(widget.caregiverName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.caregiverName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFB8FFD0),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _buildSessionStatusText(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Chat Log
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: SupabaseService.getMessagesStream(widget.sessionId),
                builder: (context, snapshot) {
                  final messages = snapshot.data;
                  if (snapshot.connectionState == ConnectionState.waiting && messages == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: HestiaColors.primary),
                    );
                  }

                  final rows = messages ?? const <Map<String, dynamic>>[];
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                  return ListView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    children: [
                      _glassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        borderRadius: 18,
                        margin: const EdgeInsets.only(bottom: 24),
                        child: Text(
                          'This chat is only available during active sessions. No phone numbers are shared.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        )
                      ),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No messages yet. Start the conversation.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        ...rows.map((msg) => _buildMessageBubble(msg)),
                    ],
                  );
                },
              ),
            ),

            // Chat Input Panel
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _glassCard(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                borderRadius: 28,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.centerLeft,
                        child: TextField(
                          controller: _messageController,
                          onSubmitted: (_) => _sendMessage(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final senderId = msg['sender_id']?.toString();
    final senderType = msg['sender_type']?.toString() ?? '';
    final bool isOutgoing = senderId != null && senderId == currentUserId;
    final String text = msg['content']?.toString() ?? '';
    final String time = _formatMessageTime(msg['sent_at']);
    final String senderLabel = _senderLabel(senderType, isOutgoing);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18.0),
      child: Column(
        crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isOutgoing)
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
              child: Text(
                senderLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _glassCard(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            borderRadius: 24,
            tint: isOutgoing
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.16),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.96),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              time,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  String _formatMessageTime(dynamic sentAt) {
    if (sentAt == null) return '--:--';
    final parsed = sentAt is DateTime ? sentAt : DateTime.parse(sentAt.toString());
    final local = parsed.toLocal();
    int hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  String _senderLabel(String senderType, bool isMe) {
    if (isMe) return 'You';
    if (senderType == 'hub_manager') return 'Hub Dispatch';
    if (senderType == 'professional') return widget.caregiverName;
    return senderType.isEmpty ? 'Support' : senderType.replaceAll('_', ' ');
  }

  String _buildSessionStatusText() {
    final start = widget.actualStart;
    if (start == null) return 'Session chat';
    final durationMinutes = ((widget.durationHours ?? 2.0) * 60).round();
    final end = start.add(Duration(minutes: durationMinutes)).toLocal();
    int hour = end.hour;
    final minute = end.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return 'Active session · ends $hour:$minute $period';
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 20,
    BoxConstraints? constraints,
    Color? tint,
  }) {
    return Container(
      margin: margin,
      constraints: constraints,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint ?? Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
