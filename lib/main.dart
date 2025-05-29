import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'views/login_view.dart';
import 'views/home_page.dart'; // Tu HomePage existente
import 'services/auth_service.dart';

@pragma('vm:entry-point') 
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  final authService = AuthService();
  bool loggedIn = await authService.isLoggedIn();

  runApp(MyApp(isInitiallyLoggedIn: loggedIn, authService: authService));
}

class MyApp extends StatelessWidget {
  final bool isInitiallyLoggedIn;
  final AuthService authService;

  const MyApp({super.key, required this.isInitiallyLoggedIn, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stream y Notificaciones',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
           backgroundColor: Colors.indigo[700],
           foregroundColor: Colors.white,
        ),
      ),
      home: isInitiallyLoggedIn 
            ? HomePage(authService: authService) // Pasa authService a tu HomePage
            : LoginView(authService: authService),
      routes: {
        '/login': (context) => LoginView(authService: authService),
        '/home': (context) => HomePage(authService: authService),
      },
    );
  }
}