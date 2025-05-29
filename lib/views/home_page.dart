import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart'; // Importar AuthService
import 'login_view.dart';            // Importar LoginView para el logout
import '../widgets/barra_lateral.dart';
import 'camara_en_vivo_view.dart';
import 'clips_view.dart';
import 'contactos_emergencia_view.dart'; // Importar para la nueva vista

class HomePage extends StatefulWidget {
  final AuthService authService; // Recibe AuthService
  const HomePage({super.key, required this.authService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isFullScreenVideo = false;

  // Lista de títulos y widgets se expande para incluir Contactos
  static const List<String> _appBarTitles = <String>[
    'Cámara en Vivo',
    'Clips',
    'Contactos de Emergencia',
  ];

  @override
  void initState() {
    super.initState();
    _initFCM();
  }

  void _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true, announcement: false, badge: true, carPlay: false,
      criticalAlert: false, provisional: false, sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      print("Firebase Messaging Token (HomePage): $token");
      await messaging.subscribeToTopic("todos");
      print("Suscrito al topic 'todos'");
    } else {
      print('User declined or has not accepted permission for notifications');
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Notificación: ${message.notification?.title ?? ""}')),
            );
        }
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Message opened app from notification: ${message.data}');
    });
  }
  
  // Lista de widgets se expande
  List<Widget> _buildWidgetOptions() => <Widget>[
    CamaraEnVivoView(
      onFullScreenToggle: _handleFullScreenToggle,
      isActive: _selectedIndex == 0,
      // authService: widget.authService, // Pasar si CamaraEnVivoView lo necesita
    ),
    const ClipsView(), // Asumimos que ClipsView no necesita authService directamente
    ContactosEmergenciaView(authService: widget.authService), // Pasar authService
  ];


  void _handleFullScreenToggle(bool isFullScreen) {
     if(_isFullScreenVideo != isFullScreen){
        setState(() { _isFullScreenVideo = isFullScreen; });
        if (isFullScreen) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        }
     }
  }

  void _onSelectItem(int index) {
     if (_isFullScreenVideo && index != 0) { // Solo salir de fullscreen si no es la vista de cámara
       _handleFullScreenToggle(false);
     }
    if (index != _selectedIndex) {
      setState(() { _selectedIndex = index; });
    }
    if (Navigator.of(context).canPop()) { Navigator.of(context).pop(); }
  }

  void _logout() async {
    await widget.authService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginView(authService: widget.authService)),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullScreenVideo && _selectedIndex == 0 ? null : AppBar(
        title: Text(_appBarTitles[_selectedIndex]),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Cerrar Sesión')
        ],
      ),
      drawer: _isFullScreenVideo && _selectedIndex == 0 ? null : BarraLateral(
        selectedIndex: _selectedIndex,
        onItemSelected: _onSelectItem,
        // Necesitarás modificar BarraLateral para incluir el ítem de "Contactos de Emergencia"
        // y para que onItemSelected pueda manejar el nuevo índice.
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _buildWidgetOptions(),
      ),
    );
  }
}