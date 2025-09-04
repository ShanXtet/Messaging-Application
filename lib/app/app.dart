import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/auth/controllers/auth_controller.dart';
import '../features/chat/controllers/chat_controller.dart';
import '../shared/themes/app_theme.dart';
import '../shared/widgets/loading_indicator.dart';
import '../features/auth/views/login_page.dart';
import '../features/chat/views/home_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(create: (_) => ChatController()),
      ],
      child: MaterialApp(
        title: 'MessageApp',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const AppGate(),
      ),
    );
  }
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final authController = context.read<AuthController>();
    final chatController = context.read<ChatController>();
    
    await authController.initialize();
    
    // Initialize chat controller and notifications if user is logged in
    if (authController.isLoggedIn) {
      final token = await authController.token;
      await chatController.connectSocket(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, authController, child) {
        if (authController.isLoading) {
          return const Scaffold(
            body: Center(
              child: LoadingIndicator(),
            ),
          );
        }

        if (authController.isLoggedIn) {
          return const HomePage();
        }

        return const LoginPage();
      },
    );
  }
}
