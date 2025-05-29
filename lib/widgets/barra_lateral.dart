import 'package:flutter/material.dart';

class BarraLateral extends StatelessWidget {
  final ValueChanged<int> onItemSelected;
  final int selectedIndex;
  final VoidCallback? onLogout; // Add logout callback

  const BarraLateral({
    super.key,
    required this.onItemSelected,
    required this.selectedIndex,
    this.onLogout, // Optional logout callback
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(color: Colors.indigo[700]),
                  child: const Row(
                    children: [
                      Icon(Icons.security, size: 40, color: Colors.white),
                      SizedBox(width: 12),
                      Text(
                        'App Cámara',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
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
                ListTile(
                  leading: const Icon(Icons.contacts_outlined),
                  title: const Text('Contactos de Emergencia'),
                  selected: selectedIndex == 2,
                  selectedTileColor: Colors.indigo.withOpacity(0.1),
                  onTap: () => onItemSelected(2),
                ),
              ],
            ),
          ),
          // Logout section at the bottom
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              Navigator.of(context).pop(); // Close drawer first
              onLogout?.call(); // Call logout function
            },
          ),
          const SizedBox(height: 16), // Bottom padding
        ],
      ),
    );
  }
}
