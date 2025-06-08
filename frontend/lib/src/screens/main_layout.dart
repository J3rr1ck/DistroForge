import 'package:flutter/material.dart';
// import 'package:flutter/material.dart'; // Removed duplicate import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:distroforge_frontend/src/screens/settings_screen.dart';
import 'package:distroforge_frontend/src/widgets/project_creation_dialog.dart';

// import 'package:distroforge_frontend/src/models/project.dart'; // Unused import
import 'package:distroforge_frontend/src/providers/project_providers.dart';
import 'package:distroforge_frontend/src/screens/project_details_screen.dart';

// Provider to manage the current page index for the BottomNavigationBar
final mainPageIndexProvider = StateProvider<int>((ref) => 0);

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageIndex = ref.watch(mainPageIndexProvider);

    // Define the pages for the IndexedStack
    final List<Widget> pages = [
      const ProjectsListScreen(), // Actual ProjectsScreen
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('DistroForge'),
        //backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              ref.read(mainPageIndexProvider.notifier).state = 1; // Navigate to Settings tab
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: pageIndex,
        children: pages,
      ),
      floatingActionButton: pageIndex == 0 // Show FAB only on Projects screen
          ? FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return const ProjectCreationDialog();
            },
          );
        },
        tooltip: 'Create Project',
        child: const Icon(Icons.add),
      ) : null, // Explicit null and added comma
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: pageIndex,
        onTap: (index) {
          ref.read(mainPageIndexProvider.notifier).state = index;
        }, // Comma is fine here
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_copy_outlined),
            label: 'Projects',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// New Widget for displaying the list of projects
class ProjectsListScreen extends ConsumerWidget {
  const ProjectsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectListProvider);

    if (projects.isEmpty) {
      return const Center(
        child: Text(
          'No projects yet. Click the + button to create one!',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        return ListTile(
          title: Text(project.name),
          subtitle: Text('Distro: ${project.distroId} (ID: ${project.id})'),
          leading: const Icon(Icons.rocket_launch_outlined), // Or distro-specific icon
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProjectDetailsScreen(project: project),
              ),
            );
          },
        );
      },
    );
  }
}
