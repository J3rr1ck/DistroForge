import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:distroforge_frontend/src/models/distro.dart'; // Using Distro model
import 'package:distroforge_frontend/src/providers/services_provider.dart'; // For engineServiceProvider
import 'package:distroforge_frontend/src/providers/project_providers.dart'; // For projectListProvider

// Provider to fetch available distros from the engine
final availableDistrosProvider = FutureProvider<List<Distro>>((ref) async {
  final engineService = ref.watch(engineServiceProvider);
  return engineService.getDistroPlugins();
});

class ProjectCreationDialog extends ConsumerStatefulWidget {
  const ProjectCreationDialog({super.key});

  @override
  ConsumerState<ProjectCreationDialog> createState() => _ProjectCreationDialogState();
}

class _ProjectCreationDialogState extends ConsumerState<ProjectCreationDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _projectName;
  Distro? _selectedDistroValue; // Store the selected Distro object

  @override
  Widget build(BuildContext context) {
    final asyncDistros = ref.watch(availableDistrosProvider);

    return AlertDialog(
      title: const Text('Create New Project'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              decoration: const InputDecoration(labelText: 'Project Name'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a project name';
                }
                return null;
              },
              onSaved: (value) {
                _projectName = value;
              },
            ),
            const SizedBox(height: 20),
            asyncDistros.when(
              data: (distros) {
                if (distros.isEmpty) {
                  return const Text("No distributions available.");
                }
                // Ensure _selectedDistroValue is set if null and distros are available
                if (_selectedDistroValue == null && distros.isNotEmpty) {
                  // Check if the current _selectedDistro (by id) is still in the list
                  // This part is tricky if _selectedDistro was just a string.
                  // Let's refine to select the first one by default.
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                     if (mounted) { // ensure widget is still in the tree
                        setState(() {
                          _selectedDistroValue = distros.first;
                        });
                     }
                   });
                } else if (_selectedDistroValue != null && !distros.any((d) => d.id == _selectedDistroValue!.id)) {
                  // If previously selected distro is no longer valid, reset
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                     if (mounted) {
                        setState(() {
                          _selectedDistroValue = distros.first;
                        });
                     }
                   });
                }


                return DropdownButtonFormField<Distro>(
                  decoration: const InputDecoration(labelText: 'Distribution'),
                  value: _selectedDistroValue,
                  items: distros.map((Distro distro) {
                    return DropdownMenuItem<Distro>(
                      value: distro,
                      child: Text(distro.name),
                    );
                  }).toList(),
                  onChanged: (Distro? newValue) {
                    setState(() {
                      _selectedDistroValue = newValue;
                    });
                  },
                  validator: (value) => value == null ? 'Please select a distribution' : null,
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, stack) => Text('Error loading distributions: $err'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: const Text('Create'),
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              if (_projectName != null && _selectedDistroValue != null) {
                try {
                  // Call the notifier method to create the project
                  await ref.read(projectListProvider.notifier).createProject(_selectedDistroValue!.id, _projectName!);
                  Navigator.of(context).pop(); // Close dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Project "$_projectName" created successfully!')),
                  );
                  // Optionally, navigate to the project details screen
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating project: $e')),
                  );
                }
              }
            }
          },
        ),
      ],
    );
  }
}
