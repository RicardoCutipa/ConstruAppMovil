import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // Importar url_launcher
import '../services/auth_service.dart';
import 'home_page.dart'; // O CamaraEnVivoView si esa es tu home

class LoginView extends StatefulWidget {
  final AuthService authService;
  const LoginView({super.key, required this.authService});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  bool _isLoading = false;
  // Ya no se necesita InAppBrowser aquí
  // final InAppBrowser _browser = InAppBrowser(); 

  @override
  void initState() {
    super.initState();
    // initAppLinks sigue siendo necesario para capturar el deep link
    // cuando la app vuelve al primer plano después de la autenticación web externa.
    widget.authService.initAppLinks(_handleTokenReceivedAndNavigate);
  }

  @override
  void dispose() {
    widget.authService.disposeAppLinks();
    super.dispose();
  }

  void _handleTokenReceivedAndNavigate(String token) {
    widget.authService.saveJwtToken(token).then((_) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => HomePage(authService: widget.authService)),
          (Route<dynamic> route) => false,
        );
      }
    });
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
      ),
    );
  }

  Future<void> _nativeGoogleSignIn() async {
    setState(() => _isLoading = true);
    final response = await widget.authService.nativeGoogleSignIn();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (response['Success'] == true && response['Token'] != null) {
      _showSnackbar('Login con Google (Nativo) exitoso!');
       _handleTokenReceivedAndNavigate(response['Token']);
    } else if (response['IsPendingApproval'] == true) {
      _showSnackbar('Pendiente de aprobación: ${response['Message']}.');
    } else {
      _showSnackbar(response['Message'] ?? 'Error con Google (Nativo).', isError: true);
    }
  }

  Future<void> _openWebLoginExternalBrowser() async { // Nombre cambiado para claridad
    final String urlString = widget.authService.getWebLoginUrl();
    final Uri url = Uri.parse(urlString);
    
    if (await canLaunchUrl(url)) {
      // Abre la URL en el navegador externo del sistema
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showSnackbar('No se pudo abrir el navegador para iniciar sesión.', isError: true);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bienvenido')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _isLoading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ElevatedButton.icon(
                      icon: const Icon(Icons.login), // Puedes usar un icono de Google si prefieres
                      label: const Text('Continuar con Google'),
                      onPressed: _nativeGoogleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black54,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: const BorderSide(color: Colors.grey)
                        ),
                        elevation: 2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _openWebLoginExternalBrowser, // Llama al nuevo método
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      child: const Text('Iniciar Sesión con Credenciales'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}