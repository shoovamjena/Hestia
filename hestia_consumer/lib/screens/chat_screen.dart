import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/colors.dart';
import '../services/supabase_service.dart';

class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String caregiverName;
  final DateTime? actualStart;
  final double? durationHours;

  const ChatScreen({
    super.key,
    required this.sessionId,
    this.caregiverName = 'Professional',
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
    SupabaseService.markChatRead(widget.sessionId);
  }

  @override
  void dispose() {
    SupabaseService.markChatRead(widget.sessionId);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _messageController.clear();
    try {
      await SupabaseService.sendMessage(
        sessionId: widget.sessionId,
        senderId: user.id,
        senderType: 'client',
        content: text,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _sortedOldestFirst(
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = List<Map<String, dynamic>>.from(rows);
    sorted.sort((a, b) {
      final aTime = DateTime.tryParse(a['sent_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b['sent_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F0),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAF2EB),
                shape: BoxShape.circle,
                border: Border.all(
                  color: HestiaColors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                color: HestiaColors.primary,
                size: 22,
              ),
            ),
          ),
        ),
        title: Text(
          widget.caregiverName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: HestiaColors.primary,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: HestiaColors.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: HestiaColors.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.caregiverName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF81C784),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _buildSessionStatusText(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
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
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.getMessagesStream(widget.sessionId),
              builder: (context, snapshot) {
                final messages = snapshot.data;
                if (snapshot.connectionState == ConnectionState.waiting &&
                    messages == null) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: HestiaColors.primary,
                    ),
                  );
                }

                final rows = _sortedOldestFirst(
                  messages ?? const <Map<String, dynamic>>[],
                );
                SupabaseService.markChatRead(widget.sessionId);

                // reverse:true keeps the viewport pinned to the newest message
                // at the bottom, so the thread grows downward.
                return ListView(
                  controller: _scrollController,
                  reverse: true,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No messages yet. Start the conversation.',
                            style: TextStyle(
                              color: HestiaColors.textDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      ...rows.reversed.map(_buildMessageBubble),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8, bottom: 18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: HestiaColors.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        'This chat is only available during active sessions. No phone numbers are shared.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: HestiaColors.textDark,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF2EB),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: HestiaColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: _messageController,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(
                          color: HestiaColors.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: HestiaColors.primary,
                        borderRadius: BorderRadius.circular(16),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isOutgoing)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                senderLabel,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isOutgoing ? HestiaColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isOutgoing
                    ? HestiaColors.primary
                    : HestiaColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isOutgoing ? Colors.white : HestiaColors.textDark,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              time,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    if (parts.length > 1 && parts.last.isNotEmpty) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }

  String _formatMessageTime(dynamic sentAt) {
    if (sentAt == null) return '--:--';
    final parsed =
        sentAt is DateTime ? sentAt : DateTime.parse(sentAt.toString());
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
    if (start == null) return 'Session chat · Live';
    final durationMinutes = ((widget.durationHours ?? 2.0) * 60).round();
    final end = start.add(Duration(minutes: durationMinutes)).toLocal();
    int hour = end.hour;
    final minute = end.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return 'Active session · ends $hour:$minute $period';
  }
}
