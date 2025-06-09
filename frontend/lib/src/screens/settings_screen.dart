import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // AppBar might be part of MainLayout, so not strictly needed here if it's a page in IndexedStack
      // appBar: AppBar(
      //   title: const Text('Settings'),
      // ),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            subtitle: const Text('Change theme, colors, etc.'),
            onTap: () {
              // TODO: Navigate to Appearance settings or show a dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Appearance settings not implemented yet.')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_ethernet_outlined),
            title: const Text('Engine Configuration'),
            subtitle: const Text('Set path to backend engine, etc.'),
            onTap: () {
              // TODO: Navigate to Engine settings or show a dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Engine configuration not implemented yet.')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Default Project Paths'),
            subtitle: const Text('Manage where projects are stored'),
            onTap: () {
              // TODO: Implement
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path settings not implemented yet.')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About DistroForge'),
            onTap: () {
              // TODO: Show an About dialog
               showAboutDialog(
                context: context,
                applicationName: 'DistroForge',
                applicationVersion: '0.1.0 (Preview)', // Replace with actual version
                applicationLegalese: '© 2024 Your Name/Org Here',
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 15),
                    child: Text('DistroForge helps you build custom Linux distributions.'),
                  )
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
