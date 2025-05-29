import 'package:flutter/material.dart';

class BarraLateral extends StatelessWidget {
  final ValueChanged<int> onItemSelected;
  final int selectedIndex;

  const BarraLateral({
    super.key,
    required this.onItemSelected,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.indigo[700],
            ),
            child: const Row(
              children: [
                Icon(Icons.security, size: 40, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'App Cámara',
                  style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Cámara en Vivo'),
            selected: selectedIndex == 0,
            selectedTileColor: Colors.indigo.withOpacity(0.1),
            onTap: () => onItemSelected(0),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Clips'),
            selected: selectedIndex == 1,
            selectedTileColor: Colors.indigo.withOpacity(0.1),
            onTap: () => onItemSelected(1),
          ),
          // Nuevo ListTile para Contactos de Emergencia
          ListTile(
            leading: const Icon(Icons.contacts_outlined), // Ícono para contactos
            title: const Text('Contactos de Emergencia'),
            selected: selectedIndex == 2, // Nuevo índice
            selectedTileColor: Colors.indigo.withOpacity(0.1),
            onTap: () => onItemSelected(2), // Llama con el nuevo índice
          ),
        ],
      ),
    );
  }
}