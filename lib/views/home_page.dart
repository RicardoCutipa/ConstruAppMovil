import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart'; // Importar AuthService
import 'login_view.dart'; // Importar LoginView para el logout
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
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
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
            SnackBar(
              content: Text(
                'Notificación: ${message.notification?.title ?? ""}',
              ),
            ),
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
    ContactosEmergenciaView(
      authService: widget.authService,
    ), // Pasar authService
  ];

  void _handleFullScreenToggle(bool isFullScreen) {
    if (_isFullScreenVideo != isFullScreen) {
      setState(() {
        _isFullScreenVideo = isFullScreen;
      });
      if (isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeLeft,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }
  }

  void _onSelectItem(int index) {
    if (_isFullScreenVideo && index != 0) {
      // Solo salir de fullscreen si no es la vista de cámara
      _handleFullScreenToggle(false);
    }
    if (index != _selectedIndex) {
      setState(() {
        _selectedIndex = index;
      });
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  // En HomePage, mejora la función _logout
// En HomePage, mejora la función _logout
void _logout() async {
  print('🔄 Iniciando proceso de logout desde HomePage...');
  
  try {
    // Mostrar indicador de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    // Ejecutar logout
    await widget.authService.logout();
    
    // Cerrar diálogo de carga
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    
    // Verificar que el logout fue exitoso
    final stillLoggedIn = await widget.authService.isLoggedIn();
    if (stillLoggedIn) {
      print('⚠️ Usuario aún aparece como logueado, forzando logout');
      await widget.authService.storage.deleteAll();
    }
    
    // Navegar a login
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => LoginView(authService: widget.authService),
        ),
        (Route<dynamic> route) => false,
      );
    }
    
    print('✅ Logout completado exitosamente');
  } catch (e) {
    print('❌ Error durante logout: $e');
    
    // Cerrar diálogo si está abierto
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    
    // Mostrar error al usuario
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cerrar sesión: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _isFullScreenVideo && _selectedIndex == 0
              ? null
              : AppBar(
                title: Text(_appBarTitles[_selectedIndex]),
              ),
      drawer:
          _isFullScreenVideo && _selectedIndex == 0
              ? null
              : BarraLateral(
                selectedIndex: _selectedIndex,
                onItemSelected: _onSelectItem,
                onLogout: _logout, // Pass the logout function
              ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _buildWidgetOptions(),
      ),
    );
  }
}
