import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/contacto_emergencia_service.dart';
import '../models/contacto_emergencia_modelo.dart';

class ContactosEmergenciaView extends StatefulWidget {
  final AuthService authService;
  const ContactosEmergenciaView({super.key, required this.authService});

  @override
  State<ContactosEmergenciaView> createState() => _ContactosEmergenciaViewState();
}

class _ContactosEmergenciaViewState extends State<ContactosEmergenciaView> {
  late ContactoEmergenciaService _contactoService;
  List<ContactoEmergenciaModelo> _contactos = [];
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _parentescoOtroController = TextEditingController();
  String? _parentescoSeleccionadoForm;
  bool _esPrincipalForm = false;
  int? _editandoIdForm; // Para saber si estamos editando o agregando

  final List<String> _parentescosPredefinidos = [
    "Padre", "Madre", "Hermano/a", "Cónyuge", "Hijo/a", "Amigo/a", "Otro"
  ];

  @override
  void initState() {
    super.initState();
    _contactoService = ContactoEmergenciaService();
    _cargarContactos();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _telefonoController.dispose();
    _parentescoOtroController.dispose();
    super.dispose();
  }

  Future<void> _cargarContactos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _contactos = await _contactoService.listarContactos();
    } catch (e) {
      if (mounted) {
        _showSnackbar('Error al cargar contactos: ${e.toString()}', isError: true);
      }
      _contactos = [];
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
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

  void _limpiarFormularioDialogo() {
    _formKey.currentState?.reset();
    _nombreController.clear();
    _apellidoController.clear();
    _telefonoController.clear();
    _parentescoOtroController.clear();
    // Usar setState del StatefulBuilder del diálogo para estos
    // _parentescoSeleccionadoForm = null;
    // _esPrincipalForm = false;
    _editandoIdForm = null;
  }

  void _mostrarFormularioContactoDialogo({ContactoEmergenciaModelo? contacto}) {
    _limpiarFormularioDialogo(); // Limpiar antes de poblar o mostrar vacío

    if (contacto != null) {
      _editandoIdForm = contacto.idContactoEmergencia;
      _nombreController.text = contacto.nombre;
      _apellidoController.text = contacto.apellido;
      _telefonoController.text = contacto.numeroTelefono;
      _esPrincipalForm = contacto.esPrincipal;
      if (_parentescosPredefinidos.contains(contacto.parentesco)) {
        _parentescoSeleccionadoForm = contacto.parentesco;
      } else {
        _parentescoSeleccionadoForm = "Otro";
        _parentescoOtroController.text = contacto.parentesco;
      }
    } else {
       _parentescoSeleccionadoForm = null; // Asegurar que esté nulo para nuevos
       _esPrincipalForm = false;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_editandoIdForm == null ? 'Agregar Contacto' : 'Editar Contacto'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: _nombreController,
                        decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Ingrese un nombre' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _apellidoController,
                        decoration: const InputDecoration(labelText: 'Apellido', border: OutlineInputBorder()),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Ingrese un apellido' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _telefonoController,
                        decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
                        keyboardType: TextInputType.phone,
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Ingrese un teléfono' : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _parentescoSeleccionadoForm,
                        decoration: const InputDecoration(labelText: 'Parentesco', border: OutlineInputBorder()),
                        hint: const Text('Seleccione Parentesco'),
                        items: _parentescosPredefinidos.map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value));
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() => _parentescoSeleccionadoForm = newValue);
                        },
                        validator: (value) => value == null ? 'Seleccione un parentesco' : null,
                      ),
                      if (_parentescoSeleccionadoForm == 'Otro') ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _parentescoOtroController,
                          decoration: const InputDecoration(labelText: 'Especificar Otro Parentesco', border: OutlineInputBorder()),
                          validator: (value) => (_parentescoSeleccionadoForm == 'Otro' && (value == null || value.trim().isEmpty))
                              ? 'Especifique el parentesco' : null,
                        ),
                      ],
                      CheckboxListTile(
                        title: const Text("Contacto Principal"),
                        value: _esPrincipalForm,
                        onChanged: (bool? value) {
                          setDialogState(() => _esPrincipalForm = value ?? false);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _limpiarFormularioDialogo(); 
                  },
                ),
                ElevatedButton(
                  child: Text(_editandoIdForm == null ? 'Agregar' : 'Actualizar'),
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      String parentescoFinal = _parentescoSeleccionadoForm!;
                      if (_parentescoSeleccionadoForm == 'Otro') {
                        parentescoFinal = _parentescoOtroController.text.trim();
                      }
                      final contactoModel = ContactoEmergenciaModelo(
                        idContactoEmergencia: _editandoIdForm ?? 0,
                        nombre: _nombreController.text.trim(),
                        apellido: _apellidoController.text.trim(),
                        numeroTelefono: _telefonoController.text.trim(),
                        parentesco: parentescoFinal,
                        esPrincipal: _esPrincipalForm,
                        parentescoOtro: _parentescoSeleccionadoForm == 'Otro' ? _parentescoOtroController.text.trim() : null,
                      );
                      
                      Map<String,dynamic> response;
                      if (_editandoIdForm == null) {
                        response = await _contactoService.agregarContacto(contactoModel);
                      } else {
                        response = await _contactoService.editarContacto(contactoModel);
                      }

                      if (mounted) {
                        Navigator.of(context).pop();
                         _showSnackbar(response['message'] ?? (_editandoIdForm == null ? 'Contacto agregado' : 'Contacto actualizado'), isError: !(response['success'] ?? false));
                        if (response['success'] == true) {
                          _cargarContactos();
                        }
                        _limpiarFormularioDialogo();
                      }
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarContactos,
              child: _contactos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_outline, size: 60, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No hay contactos de emergencia.', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar Nuevo Contacto'),
                            onPressed: () => _mostrarFormularioContactoDialogo(),
                          )
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: _contactos.length,
                      itemBuilder: (context, index) {
                        final contacto = _contactos[index];
                        return Card(
                          elevation: 2.0,
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          color: contacto.esPrincipal ? Colors.green.shade50 : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            side: contacto.esPrincipal 
                                ? BorderSide(color: Colors.green.shade300, width: 1.5) 
                                : BorderSide.none,
                          ),
                          child: ListTile(
                            leading: Icon(Icons.person_pin_circle, color: contacto.esPrincipal ? Colors.green : Theme.of(context).primaryColor),
                            title: Text('${contacto.nombre} ${contacto.apellido}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${contacto.parentesco}\n${contacto.numeroTelefono}'),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (contacto.esPrincipal)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Icon(Icons.star, color: Colors.amber.shade600, size: 20),
                                  ),
                                IconButton(
                                  icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.secondary),
                                  tooltip: 'Editar',
                                  onPressed: () => _mostrarFormularioContactoDialogo(contacto: contacto),
                                ),
                                if (!contacto.esPrincipal)
                                 IconButton(
                                  icon: const Icon(Icons.star_outline, color: Colors.grey),
                                  tooltip: 'Marcar como Principal',
                                  onPressed: () async {
                                     final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                            title: const Text('Confirmar'),
                                            content: const Text('¿Marcar este contacto como principal?'),
                                            actions: [
                                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí')),
                                            ],
                                        ));
                                     if (confirm == true) {
                                        Map<String, dynamic> response = await _contactoService.marcarComoPrincipal(contacto.idContactoEmergencia);
                                        _showSnackbar(response['message'] ?? 'Operación completada', isError: !(response['success'] ?? false));
                                        if (response['success'] == true) _cargarContactos();
                                     }
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                                  tooltip: 'Eliminar',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Confirmar Eliminación'),
                                        content: const Text('¿Está seguro de que desea eliminar este contacto?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                          TextButton(
                                            onPressed: () => Navigator.pop(c, true), 
                                            child: Text('Eliminar', style: TextStyle(color: Theme.of(context).colorScheme.error))
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      Map<String, dynamic> response = await _contactoService.eliminarContacto(contacto.idContactoEmergencia);
                                      _showSnackbar(response['message'] ?? 'Operación completada', isError: !(response['success'] ?? false));
                                      if(response['success'] == true) _cargarContactos();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarFormularioContactoDialogo(),
        tooltip: 'Agregar Nuevo Contacto',
        child: const Icon(Icons.add),
      ),
    );
  }
}