import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/chat_controller.dart';
import 'user_discovery_page.dart';
import 'conversation_page.dart';
import '../../settings/views/notification_settings_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThreads();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Refresh threads when app becomes active
      _loadThreads();
    }
  }

  Future<void> _loadThreads() async {
    final chatController = context.read<ChatController>();
    await chatController.getThreads();
  }

  // Manual refresh method
  Future<void> _refreshChat() async {
    await _loadThreads();
  }

  Future<void> _navigateToUserDiscovery() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const UserDiscoveryPage(),
      ),
    );
    
    // If a conversation was started, refresh the threads
    if (result != null) {
      _loadThreads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshChat,
            tooltip: 'Refresh conversations',
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsPage(),
                ),
              );
            },
            tooltip: 'Notification Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatController>(
              builder: (context, chatController, child) {
                if (chatController.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (chatController.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${chatController.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadThreads,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (chatController.threads.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No conversations yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap the + button to find people and start chatting',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadThreads,
                  child: ListView.builder(
                    itemCount: chatController.threads.length,
                    itemBuilder: (context, index) {
                      final thread = chatController.threads[index];
                      return _buildThreadTile(thread);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToUserDiscovery,
        backgroundColor: Colors.teal,
        child: const Icon(
          Icons.person_add,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildThreadTile(Map<String, dynamic> thread) {
    final name = thread['name'] ?? 'Unknown';
    final lastMessage = thread['lastMessage'] ?? '';
    final lastAt = thread['lastAt'] != null 
        ? DateTime.parse(thread['lastAt']) 
        : null;
    final unreadCount = thread['unreadCount'] ?? 0;
    final conversationId = thread['conversationId'];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.teal,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        lastMessage.isNotEmpty ? lastMessage : 'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unreadCount > 0 ? Colors.black87 : Colors.grey[600],
          fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastAt != null)
            Text(
              _formatTime(lastAt),
              style: TextStyle(
                fontSize: 12,
                color: unreadCount > 0 ? Colors.teal : Colors.grey[600],
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          if (unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        // TODO: Navigate to conversation detail page
        _navigateToConversation(conversationId, name);
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  void _navigateToConversation(String conversationId, String peerName) {
    final chatController = context.read<ChatController>();
    final thread = chatController.threads.firstWhere(
      (t) => t['conversationId'] == conversationId,
    );
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConversationPage(
          conversationId: conversationId,
          peerName: peerName,
          peerId: thread['peerId'],
        ),
      ),
    );
  }
}
