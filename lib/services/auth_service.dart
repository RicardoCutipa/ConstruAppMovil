import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class AuthService {
  final String _apiBaseUrl = "https://monitoreoweb.azurewebsites.net/Usuario";
  final String _webLoginBaseUrl = "https://monitoreoweb.azurewebsites.net/Usuario";
  final String _flutterAppCallbackScheme = "monitoreoapp";

  final _storage = const FlutterSecureStorage();
  FlutterSecureStorage get storage => _storage; 
  
  // ✅ CORRECCIÓN: Configuración más robusta de GoogleSignIn
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '646247150307-n0nnp29b4f5ubln8nnr5j04vhuv4tob4.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
    signInOption: SignInOption.standard, // ✅ Agregar esta línea
  );

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  String getWebLoginUrl() => "$_webLoginBaseUrl/Login?origin=flutterapp";

  Future<String?> getJwtToken() async => await _storage.read(key: 'jwt_token');
  Future<void> saveJwtToken(String token) async => await _storage.write(key: 'jwt_token', value: token);
  Future<void> deleteJwtToken() async => await _storage.delete(key: 'jwt_token');

  // ✅ CORRECCIÓN: Logout mejorado
Future<void> logout() async {
    print('🔄 Iniciando logout...');
    
    try {
      // 1. Eliminar token JWT PRIMERO
      await deleteJwtToken();
      print('✅ Token JWT eliminado');
      
      // 2. Verificar que se eliminó correctamente
      final tokenCheck = await getJwtToken();
      if (tokenCheck != null) {
        print('⚠️ Token aún existe, intentando eliminar nuevamente');
        await _storage.deleteAll(); // Eliminar todo el storage
      }
      
      // 3. Cerrar sesión de Google
      try {
        final isSignedIn = await _googleSignIn.isSignedIn();
        if (isSignedIn) {
          print('🔄 Cerrando sesión de Google...');
          await _googleSignIn.signOut();
          await _googleSignIn.disconnect();
          print('✅ Google Sign-Out completado');
        }
      } catch (e) {
        print('⚠️ Error en Google Sign-Out: $e');
      }
      
      print('✅ Logout completado');
    } catch (e) {
      print('❌ Error durante logout: $e');
      // Forzar eliminación de storage en caso de error
      await _storage.deleteAll();
    }
  }

  // ✅ CORRECCIÓN: Manejo de errores mejorado y logs detallados
  Future<Map<String, dynamic>> nativeGoogleSignIn() async {
    try {
      print('🔄 Iniciando Google Sign-In...');
      
      // ✅ Limpiar estado previo
      await _googleSignIn.signOut();
      
      // ✅ Verificar disponibilidad
      final bool isAvailable = await _googleSignIn.isSignedIn();
      print('📱 Google Play Services disponible: $isAvailable');
      
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print('❌ Usuario canceló el login');
        return {'Success': false, 'Message': 'Login con Google cancelado.'};
      }
      
      print('✅ Usuario obtenido: ${googleUser.email}');
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      final String? accessToken = googleAuth.accessToken;
      
      print('🔑 ID Token obtenido: ${idToken != null}');
      print('🔑 Access Token obtenido: ${accessToken != null}');
      
      if (idToken == null) {
        print('❌ No se pudo obtener ID Token');
        return {'Success': false, 'Message': 'No se pudo obtener ID Token.'};
      }
      
      print('🌐 Enviando token al servidor...');
      
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/GoogleSignInApi'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'IdToken': idToken}),
      );
      
      print('📡 Respuesta del servidor: ${response.statusCode}');
      print('📄 Cuerpo de respuesta: ${response.body}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResp = jsonDecode(response.body);
        if (decodedResp['Success'] == true && decodedResp['Token'] != null) {
          await saveJwtToken(decodedResp['Token']);
          print('✅ Token guardado exitosamente');
        }
        return decodedResp;
      } else {
        return {'Success': false, 'Message': 'Error del servidor: ${response.statusCode}. ${response.body}'};
      }
      
    } on PlatformException catch (error) {
      // ✅ CORRECCIÓN: Manejo específico de PlatformException
      print('❌ PlatformException detallada:');
      print('   Código: ${error.code}');
      print('   Mensaje: ${error.message}');
      print('   Detalles: ${error.details}');
      print('   Stack: ${error.stacktrace}');
      
      String userMessage;
      switch (error.code) {
        case 'sign_in_failed':
          userMessage = 'Error de configuración. Verifica SHA-1 y configuración de Firebase.';
          break;
        case 'network_error':
          userMessage = 'Error de conexión. Verifica tu internet.';
          break;
        case 'sign_in_canceled':
          userMessage = 'Inicio de sesión cancelado.';
          break;
        case 'sign_in_required':
          userMessage = 'Se requiere iniciar sesión nuevamente.';
          break;
        default:
          userMessage = 'Error de Google Sign-In: ${error.code}';
      }
      
      return {'Success': false, 'Message': userMessage};
    } catch (error) {
      print('❌ Error general: $error');
      return {'Success': false, 'Message': 'Error inesperado: $error'};
    }
  }

  void _handleLink(Uri uri, Function(String token) onTokenReceived) {
    print("🔗 DEBUG: Link recibido por app_links: $uri");
    if (uri.scheme == _flutterAppCallbackScheme && uri.host == 'auth' && uri.path == '/callback') {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        print("✅ DEBUG: Token extraído del deep link: $token");
        onTokenReceived(token);
      } else {
        print("❌ DEBUG: Token no encontrado en el link recibido: $uri");
      }
    } else {
      print("❌ DEBUG: Link NO COINCIDE. Recibido: $uri");
      print("   Esperado: $_flutterAppCallbackScheme://auth/callback");
    }
  }

  Future<void> initAppLinks(Function(String token) onTokenReceived) async {
    try {
      final Uri? initialUri = await _appLinks.getInitialLink(); 
      if (initialUri != null) {
        print("🔗 Initial link encontrado: $initialUri");
        _handleLink(initialUri, onTokenReceived);
      }
      
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          print("🔗 Nuevo link recibido: $uri");
          _handleLink(uri, onTokenReceived);
        }, 
        onError: (err) { 
          print('❌ app_links stream error: $err');
        }
      );
    } on PlatformException catch(e) { 
      print('❌ Failed to get initial app link (PlatformException): $e'); 
    } catch (e) { 
      print('❌ Error en initAppLinks (General Exception): $e');
    }
  }

  void disposeAppLinks() {
    _linkSubscription?.cancel();
  }

  Future<bool> isLoggedIn() async {
    final token = await getJwtToken();
    return token != null;
  }
}