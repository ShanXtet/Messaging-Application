import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../features/chat/controllers/chat_controller.dart';
import '../../core/constants/api_constants.dart';

class ServerStatusDialog extends StatefulWidget {
  const ServerStatusDialog({super.key});

  @override
  State<ServerStatusDialog> createState() => _ServerStatusDialogState();
}

class _ServerStatusDialogState extends State<ServerStatusDialog> {
  bool _isChecking = false;
  Map<String, dynamic>? _serverStatus;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server Status'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildServerInfo(),
          const SizedBox(height: 16),
          _buildConnectionStatus(),
          const SizedBox(height: 16),
          _buildServerHealth(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checkServerHealth,
          child: _isChecking 
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Check Server'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildServerInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Server Information',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('URL: ${ApiConstants.baseUrl}'),
        Text('Protocol: ${Uri.parse(ApiConstants.baseUrl).scheme}'),
        Text('Host: ${Uri.parse(ApiConstants.baseUrl).host}'),
        Text('Port: ${Uri.parse(ApiConstants.baseUrl).port}'),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Consumer<ChatController>(
      builder: (context, chatController, child) {
        final status = chatController.getConnectionStatus();
        final isConnected = status['isConnected'] as bool;
        final isConnecting = status['isConnecting'] as bool;
        final attempts = status['connectionAttempts'] as int;
        final maxAttempts = status['maxAttempts'] as int;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Socket Connection',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isConnected 
                    ? Icons.check_circle 
                    : isConnecting 
                      ? Icons.hourglass_empty 
                      : Icons.error,
                  color: isConnected 
                    ? Colors.green 
                    : isConnecting 
                      ? Colors.orange 
                      : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected 
                    ? 'Connected' 
                    : isConnecting 
                      ? 'Connecting... ($attempts/$maxAttempts)' 
                      : 'Disconnected',
                  style: TextStyle(
                    color: isConnected 
                      ? Colors.green 
                      : isConnecting 
                        ? Colors.orange 
                        : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildServerHealth() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Server Health',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_serverStatus == null)
          const Text('Not checked yet')
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _serverStatus!['isHealthy'] ? Icons.check_circle : Icons.error,
                    color: _serverStatus!['isHealthy'] ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _serverStatus!['isHealthy'] ? 'Healthy' : 'Unhealthy',
                    style: TextStyle(
                      color: _serverStatus!['isHealthy'] ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (_serverStatus!['responseTime'] != null)
                Text('Response time: ${_serverStatus!['responseTime']}ms'),
              if (_serverStatus!['error'] != null)
                Text(
                  'Error: ${_serverStatus!['error']}',
                  style: const TextStyle(color: Colors.red),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _checkServerHealth() async {
    setState(() {
      _isChecking = true;
    });

    try {
      final stopwatch = Stopwatch()..start();
      
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      stopwatch.stop();
      
      setState(() {
        _serverStatus = {
          'isHealthy': response.statusCode == 200,
          'statusCode': response.statusCode,
          'responseTime': stopwatch.elapsedMilliseconds,
          'response': response.body,
        };
      });
    } catch (e) {
      setState(() {
        _serverStatus = {
          'isHealthy': false,
          'error': e.toString(),
        };
      });
    } finally {
      setState(() {
        _isChecking = false;
      });
    }
  }
}
