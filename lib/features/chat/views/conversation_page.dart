import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:io';
import '../controllers/chat_controller.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/constants/api_constants.dart';

class ConversationPage extends StatefulWidget {
  final String conversationId;
  final String peerName;
  final String peerId;

  const ConversationPage({
    super.key,
    required this.conversationId,
    required this.peerName,
    required this.peerId,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SocketService _socketService = SocketService();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  String? _error;
  bool _isTyping = false;
  bool _peerIsTyping = false;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
    _loadMessages();
  }

  Future<void> _initializeSocket() async {
    try {
      await _socketService.connect();
      _setupSocketListeners();
      // Join the conversation room for better message delivery
      _socketService.joinRoom(widget.conversationId);
      debugPrint('Socket initialized successfully');
    } catch (e) {
      debugPrint('Socket connection failed: $e');
      _showErrorSnackBar('Failed to connect to real-time messaging. Retrying...');
      // Retry connection after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _initializeSocket();
        }
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // Leave the conversation room before disconnecting
    _socketService.leaveRoom(widget.conversationId);
    _socketService.disconnect();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final chatController = context.read<ChatController>();
      final response = await chatController.getMessages(
        conversationId: widget.conversationId,
        limit: 50,
      );

      if (response != null && response['messages'] != null) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response['messages']);
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        setState(() {
          _error = 'Failed to load messages';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _setupSocketListeners() {
    // Listen for new messages
    _socketService.onMessage((message) {
      debugPrint('Received message: $message');
      debugPrint('Message type: ${message['messageType']}');
      debugPrint('File attachment: ${message['fileAttachment']}');
      
      // Check if this message belongs to this conversation
      // Either by conversationId or by checking if it's from/to the peer
      final messageConversationId = message['conversationId'];
      final messageFrom = message['from'];
      final messageTo = message['to'];
      
      bool isRelevantMessage = false;
      
      if (messageConversationId != null && messageConversationId == widget.conversationId) {
        isRelevantMessage = true;
      } else if (messageFrom == widget.peerId || messageTo == widget.peerId) {
        // If no conversationId but it's from/to our peer, it's relevant
        isRelevantMessage = true;
        // Update the message with the conversationId
        message['conversationId'] = widget.conversationId;
      }
      
      if (isRelevantMessage) {
        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
      }
    });

    // Listen for typing indicators
    _socketService.onTypingStart((data) {
      debugPrint('Typing start: $data');
      if (data['fromId'] == widget.peerId) {
        setState(() {
          _peerIsTyping = true;
        });
      }
    });

    _socketService.onTypingStop((data) {
      debugPrint('Typing stop: $data');
      if (data['fromId'] == widget.peerId) {
        setState(() {
          _peerIsTyping = false;
        });
      }
    });

    // Listen for message read receipts
    _socketService.onMessageRead((data) {
      debugPrint('Message read: $data');
      // Update message status to read
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          if (_messages[i]['_id'] == data['messageId']) {
            _messages[i]['status'] = 'read';
            _messages[i]['seenAt'] = DateTime.now().toIso8601String();
            break;
          }
        }
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    _stopTyping();

    // Check if socket is connected
    if (!_socketService.isConnected) {
      _showErrorSnackBar('Not connected to server. Please try again.');
      // Try to reconnect
      try {
        await _initializeSocket();
        if (!_socketService.isConnected) {
          return;
        }
      } catch (e) {
        _showErrorSnackBar('Failed to reconnect. Please try again.');
        return;
      }
    }

    try {
      // Send message directly via socket service
      await _socketService.sendMessage(
        toId: widget.peerId,
        text: text,
      );
    } catch (e) {
      debugPrint('Error sending message: $e');
      _showErrorSnackBar('Failed to send message: $e');
    }
  }

  Future<void> _sendFile() async {
    try {
      // Show file type selection dialog
      final fileType = await _showFileTypeDialog();
      if (fileType == null) return;

      // For images, allow multiple selection
      final allowMultiple = fileType == FileType.image;

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: fileType,
        allowMultiple: allowMultiple,
      );

      if (result != null && result.files.isNotEmpty) {
        // Handle multiple images
        if (allowMultiple && result.files.length > 1) {
          await _sendMultipleImages(result.files);
        } else {
          // Handle single file
          final file = File(result.files.first.path!);
          final fileName = result.files.first.name;
          final fileSize = file.lengthSync();

          // Check file size limit (10MB)
          if (fileSize > 10 * 1024 * 1024) {
            _showErrorSnackBar('File size must be less than 10MB');
            return;
          }

          // Show loading indicator
          _showLoadingSnackBar('Uploading ${fileType == FileType.image ? 'image' : 'file'}...');

          // Upload file to server
          final chatController = context.read<ChatController>();
          final uploadResponse = await chatController.uploadFile(file);

          if (uploadResponse != null && uploadResponse['file'] != null) {
            final fileInfo = uploadResponse['file'];
            
            // Check if socket is connected
            if (!_socketService.isConnected) {
              _showErrorSnackBar('Not connected to server. Please try again.');
              return;
            }
            
            // Determine message type based on file type
            final messageType = fileType == FileType.image ? 'image' : 'file';
            
            // Send file message via socket
            await _socketService.sendMessage(
              toId: widget.peerId,
              messageType: messageType,
              fileAttachment: fileInfo,
            );
            
            _showSuccessSnackBar('${fileType == FileType.image ? 'Image' : 'File'} sent successfully');
          } else {
            _showErrorSnackBar('Failed to upload file');
          }
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error selecting file: $e');
    }
  }

  Future<void> _sendMultipleImages(List<PlatformFile> files) async {
    try {
      // Check file sizes
      for (final file in files) {
        if (file.size > 10 * 1024 * 1024) {
          _showErrorSnackBar('File ${file.name} is too large (max 10MB)');
          return;
        }
      }

      // Show loading indicator
      _showLoadingSnackBar('Uploading ${files.length} images...');

      // Upload all files
      final chatController = context.read<ChatController>();
      final List<Map<String, dynamic>> uploadedFiles = [];

      for (final file in files) {
        final uploadResponse = await chatController.uploadFile(File(file.path!));
        if (uploadResponse != null && uploadResponse['file'] != null) {
          uploadedFiles.add(uploadResponse['file']);
        } else {
          _showErrorSnackBar('Failed to upload ${file.name}');
          return;
        }
      }

      // Check if socket is connected
      if (!_socketService.isConnected) {
        _showErrorSnackBar('Not connected to server. Please try again.');
        return;
      }

      // Send multi-image message via socket
      await _socketService.sendMessage(
        toId: widget.peerId,
        messageType: 'multi_image',
        fileAttachment: {
          'images': uploadedFiles,
          'count': uploadedFiles.length,
        },
      );

      _showSuccessSnackBar('${files.length} images sent successfully');
    } catch (e) {
      _showErrorSnackBar('Error uploading images: $e');
    }
  }

  Future<FileType?> _showFileTypeDialog() async {
    return showDialog<FileType>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select File Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text('Single Photo'),
              subtitle: const Text('Send one photo or image'),
              onTap: () => Navigator.of(context).pop(FileType.image),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.purple),
              title: const Text('Multiple Photos'),
              subtitle: const Text('Send multiple photos as gallery'),
              onTap: () => Navigator.of(context).pop(FileType.image),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.grey),
              title: const Text('Any File'),
              subtitle: const Text('Send any type of file'),
              onTap: () => Navigator.of(context).pop(FileType.any),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _startTyping() {
    if (!_isTyping) {
      _isTyping = true;
      _socketService.sendTypingStart(widget.peerId);
    }
  }

  void _stopTyping() {
    if (_isTyping) {
      _isTyping = false;
      _socketService.sendTypingStop(widget.peerId);
    }
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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showLoadingSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.peerName),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _socketService.isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            if (_peerIsTyping)
              const Text(
                'typing...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
        actions: [
          if (!_socketService.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _initializeSocket,
              tooltip: 'Reconnect',
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // TODO: Show conversation info
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessagesList(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
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
              'Error: $_error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMessages,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
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
              'No messages yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Start the conversation!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['from'] == context.read<ChatController>().currentUserId;
    final text = message['text'] ?? '';
    final messageType = message['messageType'] ?? 'text';
    final fileAttachment = message['fileAttachment'];
    final timestamp = message['createdAt'] != null 
        ? DateTime.parse(message['createdAt']) 
        : null;
    final status = message['status'] ?? 'sent';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? Colors.teal : Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
              child: (messageType == 'file' || messageType == 'image' || messageType == 'multi_image') && fileAttachment != null
                  ? _buildFileMessage(fileAttachment, isMe, messageType)
                  : Text(
                      text,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (timestamp != null)
                  Text(
                    _formatTime(timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _buildMessageStatus(status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileMessage(Map<String, dynamic> fileAttachment, bool isMe, String messageType) {
    // Handle multi-image messages
    if (messageType == 'multi_image' && fileAttachment['images'] != null) {
      return _buildMultiImageMessage(fileAttachment, isMe);
    }

    final fileName = fileAttachment['fileName'] ?? 'Unknown file';
    final fileSize = fileAttachment['fileSize'] ?? 0;
    final mimeType = fileAttachment['mimeType'] ?? '';
    final url = fileAttachment['url'] ?? '';

    // Check if it's an image file (either by MIME type, file extension, or message type)
    final isImageFile = messageType == 'image' ||
                       mimeType.startsWith('image/') || 
                       fileName.toLowerCase().endsWith('.jpg') ||
                       fileName.toLowerCase().endsWith('.jpeg') ||
                       fileName.toLowerCase().endsWith('.png') ||
                       fileName.toLowerCase().endsWith('.gif') ||
                       fileName.toLowerCase().endsWith('.webp') ||
                       fileName.toLowerCase().endsWith('.bmp') ||
                       fileName.toLowerCase().endsWith('.tiff') ||
                       fileName.toLowerCase().endsWith('.svg');
    
    debugPrint('Image detection - messageType: $messageType, mimeType: $mimeType, fileName: $fileName, isImageFile: $isImageFile');
    
    if (isImageFile && url.isNotEmpty) {
      return _buildImageMessage(fileAttachment, isMe);
    }

    // For non-image files, show the file info
    String fileIcon = '📄';
    if (mimeType.startsWith('video/')) {
      fileIcon = '🎥';
    } else if (mimeType.startsWith('audio/')) {
      fileIcon = '🎵';
    } else if (mimeType.contains('pdf')) {
      fileIcon = '📕';
    } else if (mimeType.contains('zip') || mimeType.contains('rar')) {
      fileIcon = '📦';
    }

    return GestureDetector(
      onTap: () {
        _showFileDialog(fileName, url);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.2) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fileIcon,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(fileSize),
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.download,
              color: isMe ? Colors.white70 : Colors.grey[600],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiImageMessage(Map<String, dynamic> fileAttachment, bool isMe) {
    final images = fileAttachment['images'] as List<dynamic>? ?? [];
    final count = fileAttachment['count'] ?? images.length;

    if (images.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No images to display',
          style: TextStyle(
            color: isMe ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        _showMultiImagePhotoViewDialog(images, 0);
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gallery grid
              _buildImageGrid(images, isMe),
              // Gallery info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe ? Colors.black.withOpacity(0.7) : Colors.grey[100],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.photo_library,
                      color: isMe ? Colors.white70 : Colors.grey[600],
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$count photos',
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.zoom_in,
                      color: isMe ? Colors.white70 : Colors.grey[600],
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<dynamic> images, bool isMe) {
    if (images.length == 1) {
      // Single image - show full size
      return _buildSingleImageInGrid(images[0], isMe, 0);
    } else if (images.length == 2) {
      // Two images - show side by side
      return Row(
        children: [
          Expanded(child: _buildSingleImageInGrid(images[0], isMe, 0)),
          const SizedBox(width: 2),
          Expanded(child: _buildSingleImageInGrid(images[1], isMe, 1)),
        ],
      );
    } else if (images.length == 3) {
      // Three images - show 2 on top, 1 on bottom
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildSingleImageInGrid(images[0], isMe, 0)),
              const SizedBox(width: 2),
              Expanded(child: _buildSingleImageInGrid(images[1], isMe, 1)),
            ],
          ),
          const SizedBox(height: 2),
          _buildSingleImageInGrid(images[2], isMe, 2),
        ],
      );
    } else {
      // Four or more images - show 2x2 grid with overflow indicator
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildSingleImageInGrid(images[0], isMe, 0)),
              const SizedBox(width: 2),
              Expanded(child: _buildSingleImageInGrid(images[1], isMe, 1)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: _buildSingleImageInGrid(images[2], isMe, 2)),
              const SizedBox(width: 2),
              Expanded(
                child: Stack(
                  children: [
                    _buildSingleImageInGrid(images[3], isMe, 3),
                    if (images.length > 4)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '+${images.length - 4}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }
  }

  Widget _buildSingleImageInGrid(dynamic imageData, bool isMe, int index) {
    final url = imageData['url'] ?? '';
    final fullUrl = url.startsWith('http') ? url : '${ApiConstants.baseUrl}$url';
    final height = 120.0;

    return GestureDetector(
      onTap: () {
        _showMultiImagePhotoViewDialog([imageData], index);
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            fullUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: height,
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: height,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                    size: 32,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildImageMessage(Map<String, dynamic> fileAttachment, bool isMe) {
    final fileName = fileAttachment['fileName'] ?? 'Unknown image';
    final fileSize = fileAttachment['fileSize'] ?? 0;
    final url = fileAttachment['url'] ?? '';
    
    // Construct full URL if it's a relative path
    final fullUrl = url.startsWith('http') ? url : '${ApiConstants.baseUrl}$url';

    return GestureDetector(
      onTap: () {
        _showPhotoViewDialog(fullUrl, fileName);
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75, // Increased from 0.7 to 0.75 for better use of space
          maxHeight: 400, // Increased from 300 to 400 for larger images
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14), // Slightly reduced from 16px to 14px for better visual balance
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14), // Match the container border radius
          child: Stack(
            children: [
              // Main image display
              Image.network(
                fullUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  
                  // Calculate image dimensions for proper sizing
                  final imageWidth = MediaQuery.of(context).size.width * 0.6;
                  final imageHeight = imageWidth * 0.75; // 4:3 aspect ratio
                  
                  return Container(
                    width: imageWidth,
                    height: imageHeight,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isMe ? Colors.white : Colors.teal,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Loading image...',
                            style: TextStyle(
                              color: isMe ? Colors.white70 : Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  final imageWidth = MediaQuery.of(context).size.width * 0.6;
                  final imageHeight = imageWidth * 0.75;
                  
                  return Container(
                    width: imageWidth,
                    height: imageHeight,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image,
                          size: 48,
                          color: isMe ? Colors.white60 : Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load image',
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.grey[600],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Object detection overlay
              Positioned.fill(
                child: GestureDetector(
                  onTapDown: (details) {
                    _onImageTap(details, fullUrl, fileName);
                  },
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              // Object detection indicator
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.search,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              // Image info overlay (optional, can be shown on hover or tap)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.image,
                        color: Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatFileSize(fileSize),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
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

  void _onImageTap(TapDownDetails details, String imageUrl, String fileName) {
    // Calculate tap position relative to image
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    // Show object detection dialog
    _showObjectDetectionDialog(imageUrl, fileName, localPosition);
  }

  void _showObjectDetectionDialog(String imageUrl, String fileName, Offset tapPosition) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.search, color: Colors.blue),
            SizedBox(width: 8),
            Text('Object Detection'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Analyzing objects in this image...'),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Tap anywhere on the image to identify objects',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performObjectDetection(imageUrl, fileName, tapPosition);
            },
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
  }

  Future<void> _performObjectDetection(String imageUrl, String fileName, Offset tapPosition) async {
    try {
      _showLoadingSnackBar('Analyzing image for objects...');
      
      // Simulate object detection (in a real app, you'd call an AI service)
      await Future.delayed(const Duration(seconds: 2));
      
      // Mock detected objects (replace with real AI detection)
      final detectedObjects = _mockObjectDetection(imageUrl, tapPosition);
      
      _showObjectResultsDialog(detectedObjects, imageUrl, fileName);
    } catch (e) {
      _showErrorSnackBar('Failed to analyze image: $e');
    }
  }

  List<Map<String, dynamic>> _mockObjectDetection(String imageUrl, Offset tapPosition) {
    // Mock object detection results
    // In a real implementation, this would call an AI service like Google Vision API, AWS Rekognition, etc.
    return [
      {
        'name': 'Person',
        'confidence': 0.95,
        'description': 'A person detected in the image',
        'boundingBox': {
          'x': tapPosition.dx - 50,
          'y': tapPosition.dy - 50,
          'width': 100,
          'height': 100,
        },
        'category': 'human',
        'attributes': ['standing', 'facing camera'],
      },
      {
        'name': 'Car',
        'confidence': 0.87,
        'description': 'A vehicle detected in the background',
        'boundingBox': {
          'x': tapPosition.dx + 20,
          'y': tapPosition.dy + 20,
          'width': 80,
          'height': 60,
        },
        'category': 'vehicle',
        'attributes': ['blue color', 'sedan'],
      },
      {
        'name': 'Building',
        'confidence': 0.92,
        'description': 'A building or structure in the background',
        'boundingBox': {
          'x': tapPosition.dx - 100,
          'y': tapPosition.dy - 100,
          'width': 200,
          'height': 150,
        },
        'category': 'architecture',
        'attributes': ['modern', 'glass facade'],
      },
    ];
  }

  void _showObjectResultsDialog(List<Map<String, dynamic>> objects, String imageUrl, String fileName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detected Objects',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${objects.length} objects found',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              // Object list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: objects.length,
                  itemBuilder: (context, index) {
                    final object = objects[index];
                    return _buildObjectCard(object);
                  },
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showImageDialog(imageUrl, fileName);
                        },
                        child: const Text('View Full Image'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _searchObjectInfo(objects.first['name']);
                        },
                        child: const Text('Search Online'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObjectCard(Map<String, dynamic> object) {
    final confidence = (object['confidence'] * 100).round();
    final category = object['category'] ?? 'unknown';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(category).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getCategoryIcon(category),
                    color: _getCategoryColor(category),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        object['name'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${confidence}% confidence',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getConfidenceColor(confidence),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$confidence%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              object['description'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            if (object['attributes'] != null && (object['attributes'] as List).isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: (object['attributes'] as List).map<Widget>((attr) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      attr.toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'human':
        return Colors.blue;
      case 'vehicle':
        return Colors.green;
      case 'architecture':
        return Colors.orange;
      case 'animal':
        return Colors.purple;
      case 'food':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'human':
        return Icons.person;
      case 'vehicle':
        return Icons.directions_car;
      case 'architecture':
        return Icons.business;
      case 'animal':
        return Icons.pets;
      case 'food':
        return Icons.restaurant;
      default:
        return Icons.category;
    }
  }

  Color _getConfidenceColor(int confidence) {
    if (confidence >= 90) return Colors.green;
    if (confidence >= 70) return Colors.orange;
    return Colors.red;
  }

  void _searchObjectInfo(String objectName) {
    // Open web search for the object
    _showSuccessSnackBar('Searching for "$objectName" online...');
    // In a real app, you'd open a web browser or search within the app
  }

  void _showFileDialog(String fileName, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fileName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('File received!'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // TODO: Implement file download
                Navigator.of(context).pop();
                _showSuccessSnackBar('Download started');
              },
              child: const Text('Download'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMultiImagePhotoViewDialog(List<dynamic> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // Full screen photo view with page view
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final imageData = images[index];
                final url = imageData['url'] ?? '';
                final fullUrl = url.startsWith('http') ? url : '${ApiConstants.baseUrl}$url';
                
                return PhotoView(
                  imageProvider: NetworkImage(fullUrl),
                  minScale: PhotoViewComputedScale.contained * 0.5,
                  maxScale: PhotoViewComputedScale.covered * 2.0,
                  initialScale: PhotoViewComputedScale.contained,
                  backgroundDecoration: const BoxDecoration(
                    color: Colors.black,
                  ),
                  loadingBuilder: (context, event) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            size: 64,
                            color: Colors.white,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            // Image counter and info
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_library,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${initialIndex + 1} of ${images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.download,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        _showSuccessSnackBar('Download started');
                      },
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

  void _showMultiImageDialog(List<dynamic> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // Full screen image gallery
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final imageData = images[index];
                final url = imageData['url'] ?? '';
                final fullUrl = url.startsWith('http') ? url : '${ApiConstants.baseUrl}$url';
                final fileName = imageData['fileName'] ?? 'Image ${index + 1}';
                
                return Center(
                  child: InteractiveViewer(
                    panEnabled: true,
                    boundaryMargin: const EdgeInsets.all(20),
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.9,
                        maxHeight: MediaQuery.of(context).size.height * 0.8,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          fullUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 300,
                              color: Colors.black87,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 300,
                              color: Colors.black87,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.broken_image,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Failed to load image',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            // Image counter and info
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_library,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${initialIndex + 1} of ${images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.download,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        // TODO: Implement image download
                        _showSuccessSnackBar('Download started');
                      },
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

  void _showPhotoViewDialog(String imageUrl, String fileName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // Full screen photo view
            PhotoView(
              imageProvider: NetworkImage(imageUrl),
              minScale: PhotoViewComputedScale.contained * 0.5,
              maxScale: PhotoViewComputedScale.covered * 2.0,
              initialScale: PhotoViewComputedScale.contained,
              backgroundDecoration: const BoxDecoration(
                color: Colors.black,
              ),
              loadingBuilder: (context, event) => Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            // Image info at bottom
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.image,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.search,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showObjectDetectionDialog(imageUrl, fileName, const Offset(0, 0));
                      },
                      tooltip: 'Detect Objects',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.download,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        _showSuccessSnackBar('Download started');
                      },
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

  void _showImageDialog(String imageUrl, String fileName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // Full screen image
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 300,
                          color: Colors.black87,
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 300,
                          color: Colors.black87,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.white,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            // Image info at bottom
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.image,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.search,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showObjectDetectionDialog(imageUrl, fileName, const Offset(0, 0));
                      },
                      tooltip: 'Detect Objects',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.download,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        // TODO: Implement image download
                        _showSuccessSnackBar('Download started');
                      },
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildMessageStatus(String status) {
    IconData icon;
    Color color;

    switch (status) {
      case 'sent':
        icon = Icons.check;
        color = Colors.grey;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.grey;
        break;
      case 'read':
        icon = Icons.done_all;
        color = Colors.blue;
        break;
      default:
        icon = Icons.schedule;
        color = Colors.grey;
    }

    return Icon(
      icon,
      size: 16,
      color: color,
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _sendFile,
            color: Colors.teal,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
              onChanged: (text) {
                if (text.isNotEmpty) {
                  _startTyping();
                } else {
                  _stopTyping();
                }
              },
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            mini: true,
            onPressed: _sendMessage,
            backgroundColor: Colors.teal,
            child: const Icon(
              Icons.send,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}
