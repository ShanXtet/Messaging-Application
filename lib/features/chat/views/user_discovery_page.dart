import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/user.dart';
import '../../../core/services/user_discovery_service.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../controllers/chat_controller.dart';
import 'conversation_page.dart';

class UserDiscoveryPage extends StatefulWidget {
  const UserDiscoveryPage({super.key});

  @override
  State<UserDiscoveryPage> createState() => _UserDiscoveryPageState();
}

class _UserDiscoveryPageState extends State<UserDiscoveryPage> {
  final UserDiscoveryService _userDiscoveryService = UserDiscoveryService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<User> _users = [];
  List<User> _searchResults = [];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasMore = false;
  int _offset = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore && _searchQuery.isEmpty) {
        _loadMoreUsers();
      }
    }
  }

  Future<void> _loadUsers() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _userDiscoveryService.getUsers(limit: 20, offset: 0);
      setState(() {
        _users = result['users'] as List<User>;
        _hasMore = result['hasMore'] as bool;
        _offset = _users.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoading || !_hasMore) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _userDiscoveryService.getUsers(limit: 20, offset: _offset);
      final newUsers = result['users'] as List<User>;
      
      setState(() {
        _users.addAll(newUsers);
        _hasMore = result['hasMore'] as bool;
        _offset = _users.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchQuery = '';
      });
      return;
    }

    if (query.trim().length < 2) return;

    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });

    try {
      final results = await _userDiscoveryService.searchUsers(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  Future<void> _startConversation(User user) async {
    try {
      final chatController = context.read<ChatController>();
      final conversationId = await chatController.startConversation(user.id);
      
      if (mounted && conversationId != null) {
        // Navigate directly to the conversation page
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ConversationPage(
              conversationId: conversationId,
              peerName: user.name,
              peerId: user.id,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start conversation: $e')),
        );
      }
    }
  }

  Widget _buildUserTile(User user) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.teal,
        child: Text(
          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        user.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(user.email),
      trailing: IconButton(
        icon: const Icon(Icons.chat_bubble_outline),
        onPressed: () => _startConversation(user),
        tooltip: 'Start conversation',
      ),
      onTap: () => _startConversation(user),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search users by name or email...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _searchUsers('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[100],
        ),
        onChanged: (value) {
          _searchUsers(value);
        },
      ),
    );
  }

  Widget _buildUserList() {
    final displayUsers = _searchQuery.isNotEmpty ? _searchResults : _users;
    
    if (_isSearching) {
      return const Center(child: LoadingIndicator(message: 'Searching...'));
    }
    
    if (displayUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty 
                  ? 'No users found for "$_searchQuery"'
                  : 'No users available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: displayUsers.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == displayUsers.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: LoadingIndicator(message: 'Loading more...')),
          );
        }
        
        return _buildUserTile(displayUsers[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find People'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading && _users.isEmpty
                ? const Center(child: LoadingIndicator(message: 'Loading users...'))
                : _buildUserList(),
          ),
        ],
      ),
    );
  }
}
