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
  // String? _projectName; // Replaced by _projectNameController
  final _projectNameController = TextEditingController();
  Distro? _selectedDistroValue; // Store the selected Distro object

  @override
  void dispose() {
    _projectNameController.dispose();
    super.dispose();
  }

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
              controller: _projectNameController, // Use controller
              decoration: const InputDecoration(labelText: 'Project Name'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a project name';
                }
                return null;
              },
              // onSaved is not strictly needed if using controller, but can be kept
              // onSaved: (value) {
              //   // _projectName = value; // Controller holds the value
              // },
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
            debugPrint('Create button pressed.');
            if (_formKey.currentState!.validate()) {
              debugPrint('Form is valid.');
              _formKey.currentState!.save(); // Ensure onSaved is called if still used, or rely on controller

              final projectName = _projectNameController.text;
              final selectedDistro = _selectedDistroValue;

              debugPrint('Selected distro ID: ${selectedDistro?.id}');
              debugPrint('Entered project name: $projectName');

              if (projectName.isNotEmpty && selectedDistro != null) {
                try {
                  debugPrint('Calling projectListProvider.notifier.createProject...');
                  await ref.read(projectListProvider.notifier).createProject(selectedDistro.id, projectName);
                  debugPrint('Project creation method called.');

                  if (mounted) { // Check if the widget is still in the tree
                    Navigator.of(context).pop(); // Close dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Project "$projectName" created successfully!')),
                    );
                  }
                  // Optionally, navigate to the project details screen
                } catch (e) {
                  debugPrint('Error during project creation call: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error creating project: $e')),
                    );
                  }
                }
              } else {
                debugPrint('Project name or selected distro is null/empty after validation.');
                debugPrint('Project Name actual: $projectName');
                debugPrint('Selected Distro actual: ${selectedDistro?.id}');
              }
            } else {
              debugPrint('Form is invalid.');
            }
          },
        ),
      ],
    );
  }
}
