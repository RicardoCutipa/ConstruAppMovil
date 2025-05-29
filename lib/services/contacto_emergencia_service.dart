import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart'; // Para obtener el token JWT
import '../models/contacto_emergencia_modelo.dart'; // El modelo que acabamos de crear

class ContactoEmergenciaService {
  // La URL base para los endpoints API de contactos de emergencia
  // Asegúrate que las rutas en tu `ConfiguracionController` coincidan (ej. si usas [Route("...")] )
  final String _apiBaseUrl = "https://monitoreoweb.azurewebsites.net/Configuracion"; 
  final AuthService _authService = AuthService();

  Future<Map<String, String>> _getAuthHeaders() async {
    String? token = await _authService.getJwtToken();
    if (token == null) {
      throw Exception('Usuario no autenticado. Token no encontrado.');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<ContactoEmergenciaModelo>> listarContactos() async {
    final headers = await _getAuthHeaders();
    // La URL debe coincidir con la ruta de tu endpoint API en el backend
    final response = await http.get(Uri.parse('$_apiBaseUrl/ListarContactosApi'), headers: headers);

    if (response.statusCode == 200) {
      try {
        // El backend devuelve directamente una lista JSON de contactos
        List<dynamic> body = jsonDecode(response.body);
        List<ContactoEmergenciaModelo> contactos = body.map((dynamic item) => ContactoEmergenciaModelo.fromJson(item)).toList();
        return contactos;
      } catch (e) {
        throw Exception('Fallo al decodificar la respuesta de contactos: $e');
      }
    } else {
      throw Exception('Fallo al cargar contactos: ${response.statusCode} ${response.body}');
    }
  }

  Future<Map<String, dynamic>> agregarContacto(ContactoEmergenciaModelo nuevoContacto) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/AgregarContactoApi'),
      headers: headers,
      body: jsonEncode(nuevoContacto.toJson()),
    );
    if (response.statusCode == 200) {
       return jsonDecode(response.body); // Devuelve el JSON { success: true/false, message: "..." }
    } else {
      print("Error agregarContacto API: ${response.statusCode} ${response.body}");
      try {
        return jsonDecode(response.body);
      } catch(e) {
        return {'success': false, 'message': 'Error de servidor: ${response.statusCode}'};
      }
    }
  }

  Future<ContactoEmergenciaModelo?> obtenerContacto(int id) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(Uri.parse('$_apiBaseUrl/ObtenerContactoApi/$id'), headers: headers);
    
    if (response.statusCode == 200) {
      Map<String, dynamic> body = jsonDecode(response.body);
      if (body['success'] == true && body['data'] != null) {
        return ContactoEmergenciaModelo.fromJson(body['data']);
      }
      return null;
    } else {
      return null;
    }
  }

  Future<Map<String, dynamic>> editarContacto(ContactoEmergenciaModelo contactoEditado) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/EditarContactoApi'), 
      headers: headers,
      body: jsonEncode(contactoEditado.toJson()),
    );
     if (response.statusCode == 200) {
       return jsonDecode(response.body);
    } else {
      print("Error editarContacto API: ${response.statusCode} ${response.body}");
      try {
        return jsonDecode(response.body);
      } catch(e) {
        return {'success': false, 'message': 'Error de servidor: ${response.statusCode}'};
      }
    }
  }

  Future<Map<String, dynamic>> marcarComoPrincipal(int id) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/MarcarComoPrincipalApi/$id'), 
      headers: headers,
    );
    if (response.statusCode == 200) {
       return jsonDecode(response.body);
    } else {
      try {
        return jsonDecode(response.body);
      } catch(e) {
        return {'success': false, 'message': 'Error de servidor: ${response.statusCode}'};
      }
    }
  }

  Future<Map<String, dynamic>> eliminarContacto(int id) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/EliminarContactoApi/$id'), 
      headers: headers,
    );
     if (response.statusCode == 200) {
       return jsonDecode(response.body);
    } else {
      try {
        return jsonDecode(response.body);
      } catch(e) {
        return {'success': false, 'message': 'Error de servidor: ${response.statusCode}'};
      }
    }
  }
}