class ContactoEmergenciaModelo {
  int idContactoEmergencia;
  int idUsuario;
  String nombre;
  String apellido;
  String numeroTelefono;
  String parentesco;
  bool esPrincipal;
  String? parentescoOtro; // Para el UI, no se envía directamente si se combina en 'parentesco'

  ContactoEmergenciaModelo({
    this.idContactoEmergencia = 0,
    this.idUsuario = 0, // El backend lo asociará con el usuario del token JWT
    required this.nombre,
    required this.apellido,
    required this.numeroTelefono,
    required this.parentesco,
    this.esPrincipal = false,
    this.parentescoOtro,
  });

  factory ContactoEmergenciaModelo.fromJson(Map<String, dynamic> json) {
    return ContactoEmergenciaModelo(
      idContactoEmergencia: json['IdContactoEmergencia'] ?? 0,
      idUsuario: json['IdUsuario'] ?? 0, // El backend podría o no devolverlo en listados
      nombre: json['Nombre'] ?? '',
      apellido: json['Apellido'] ?? '',
      numeroTelefono: json['NumeroTelefono'] ?? '',
      parentesco: json['Parentesco'] ?? '',
      esPrincipal: json['EsPrincipal'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (idContactoEmergencia != 0) {
      data['IdContactoEmergencia'] = idContactoEmergencia;
    }
    data['Nombre'] = nombre;
    data['Apellido'] = apellido;
    data['NumeroTelefono'] = numeroTelefono;
    
    // Lógica para enviar el parentesco correcto
    // Si 'parentesco' es 'Otro' y 'parentescoOtro' tiene valor, se envía 'parentescoOtro'
    // De lo contrario, se envía el valor de 'parentesco' (que sería una opción predefinida)
    if (parentesco == 'Otro' && parentescoOtro != null && parentescoOtro!.trim().isNotEmpty) {
      data['Parentesco'] = parentescoOtro!.trim();
    } else {
      data['Parentesco'] = parentesco;
    }
    
    data['EsPrincipal'] = esPrincipal;
    // No es necesario enviar 'ParentescoOtro' como un campo separado si ya lo incluiste en 'Parentesco'
    return data;
  }
}