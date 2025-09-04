import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/chat/controllers/chat_controller.dart';
import 'server_status_dialog.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, chatController, child) {
        final status = chatController.getConnectionStatus();
        final isConnected = status['isConnected'] as bool;
        final isConnecting = status['isConnecting'] as bool;
        final attempts = status['connectionAttempts'] as int;
        final maxAttempts = status['maxAttempts'] as int;

        if (isConnected) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Connected',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        } else if (isConnecting) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Connecting... ($attempts/$maxAttempts)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        } else {
          return GestureDetector(
            onTap: () => _showServerStatusDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Offline',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 14,
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  void _showServerStatusDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ServerStatusDialog(),
    );
  }
}

class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, chatController, child) {
        final status = chatController.getConnectionStatus();
        final isConnected = status['isConnected'] as bool;
        final isConnecting = status['isConnecting'] as bool;

        // Only show banner when not connected
        if (isConnected) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isConnecting ? Colors.orange[100] : Colors.red[100],
            border: Border(
              bottom: BorderSide(
                color: isConnecting ? Colors.orange : Colors.red,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isConnecting ? Icons.wifi_find : Icons.wifi_off,
                color: isConnecting ? Colors.orange[800] : Colors.red[800],
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isConnecting
                      ? 'Connecting to server...'
                      : 'No connection to server. Tap to retry.',
                  style: TextStyle(
                    color: isConnecting ? Colors.orange[800] : Colors.red[800],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!isConnecting)
                TextButton(
                  onPressed: () async {
                    await chatController.retryConnection();
                    // Force a rebuild to update the connection status
                    chatController.refreshConnectionStatus();
                  },
                  child: Text(
                    'Retry',
                    style: TextStyle(
                      color: Colors.red[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
