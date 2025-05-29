import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart'; // Importar app_links
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class AuthService {
  final String _apiBaseUrl = "https://monitoreoweb.azurewebsites.net/Usuario";
  final String _webLoginBaseUrl = "https://monitoreoweb.azurewebsites.net/Usuario";
  final String _flutterAppCallbackScheme = "monitoreoapp"; // Asegúrate que este sea tu scheme

  final _storage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
     serverClientId: '646247150307-n0nnp29b4f5ubln8nnr5j04vhuv4tob4.apps.googleusercontent.com',
     scopes: ['email', 'profile'],
  );

  final _appLinks = AppLinks(); // Instancia de AppLinks
  StreamSubscription<Uri>? _linkSubscription;

  String getWebLoginUrl() => "$_webLoginBaseUrl/Login?origin=flutterapp";

  Future<String?> getJwtToken() async => await _storage.read(key: 'jwt_token');
  Future<void> saveJwtToken(String token) async => await _storage.write(key: 'jwt_token', value: token);
  Future<void> deleteJwtToken() async => await _storage.delete(key: 'jwt_token');

  Future<void> logout() async {
    await deleteJwtToken();
    try { 
      await _googleSignIn.signOut(); 
    } catch (e) {
      print('Error en Google Sign Out (puede ser ignorado): $e');
    }
  }

  Future<Map<String, dynamic>> nativeGoogleSignIn() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return {'Success': false, 'Message': 'Login con Google cancelado.'};
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      if (idToken == null) return {'Success': false, 'Message': 'No se pudo obtener ID Token.'};
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/GoogleSignInApi'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'IdToken': idToken}),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResp = jsonDecode(response.body);
        if (decodedResp['Success'] == true && decodedResp['Token'] != null) {
          await saveJwtToken(decodedResp['Token']);
        }
        return decodedResp;
      } else {
        return {'Success': false, 'Message': 'Error del servidor: ${response.statusCode}.'};
      }
    } catch (error) {
      return {'Success': false, 'Message': 'Error en Google Sign-In nativo: $error'};
    }
  }

  void _handleLink(Uri uri, Function(String token) onTokenReceived) {
    print("DEBUG: Link recibido por app_links: $uri");
    if (uri.scheme == _flutterAppCallbackScheme && uri.host == 'auth' && uri.path == '/callback') {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        print("DEBUG: Token extraído del deep link: $token");
        onTokenReceived(token);
      } else {
        print("DEBUG: Token no encontrado en el link recibido: $uri");
      }
    } else {
        print("DEBUG: Link recibido NO COINCIDE con el callback esperado: $uri. Scheme esperado: $_flutterAppCallbackScheme, Host esperado: auth, Path esperado: /callback");
    }
  }

  Future<void> initAppLinks(Function(String token) onTokenReceived) async {
    try {
      final Uri? initialUri = await _appLinks.getInitialLink(); 
      if (initialUri != null) {
        _handleLink(initialUri, onTokenReceived);
      }
      _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
        _handleLink(uri, onTokenReceived);
      }, onError: (err) { 
          print('app_links stream error: $err');
      });
    } on PlatformException catch(e) { 
      print('Failed to get initial app link (PlatformException): $e'); 
    } catch (e) { 
      print('Error en initAppLinks (General Exception): $e');
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