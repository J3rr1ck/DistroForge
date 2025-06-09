import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:distroforge_frontend/src/models/project.dart';
import 'package:distroforge_frontend/src/providers/project_providers.dart';
import 'package:distroforge_frontend/src/providers/services_provider.dart'; // For buildLogStreamProvider

// Tabs for ProjectDetailsScreen
enum ProjectDetailsTab { packages, configuration, build }

// Provider for the current tab
final currentProjectTabProvider = StateProvider<ProjectDetailsTab>((ref) => ProjectDetailsTab.packages);

class ProjectDetailsScreen extends ConsumerStatefulWidget {
  final Project project; // Expect a Project object to be passed

  const ProjectDetailsScreen({super.key, required this.project});

  @override
  ConsumerState<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends ConsumerState<ProjectDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: ProjectDetailsTab.values.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(currentProjectTabProvider.notifier).state = ProjectDetailsTab.values[_tabController.index];
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch project details for potential updates if we implement refresh logic
    final projectDetailsAsync = ref.watch(projectDetailsProvider(widget.project.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Project: ${widget.project.name} (${widget.project.distroId})'),
        bottom: TabBar(
          controller: _tabController,
          tabs: ProjectDetailsTab.values.map((tab) => Tab(text: tab.name.toUpperCase())).toList(),
        ),
      ),
      body: projectDetailsAsync.when(
        data: (details) { // `details` is the Map<String, dynamic> from projectDetailsProvider
          // We can pass `details` or specific parts to tabs if needed,
          // or tabs can use their own focused providers.
          return TabBarView(
            controller: _tabController,
            children: [
              PackagesTab(projectId: widget.project.id),
              ConfigurationTab(projectId: widget.project.id, projectDetails: details),
              BuildTab(projectId: widget.project.id),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading project details: $err')),
      ),
    );
  }
}

// --- Packages Tab ---
class PackagesTab extends ConsumerStatefulWidget {
  final String projectId;
  const PackagesTab({super.key, required this.projectId});

  @override
  ConsumerState<PackagesTab> createState() => _PackagesTabState();
}

class _PackagesTabState extends ConsumerState<PackagesTab> {
  final _newPackageController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(projectPackagesProvider(widget.projectId));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _newPackageController,
                  decoration: const InputDecoration(labelText: 'New Package Name'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () async {
                  if (_newPackageController.text.isNotEmpty) {
                    final currentPackages = await ref.read(projectPackagesProvider(widget.projectId).future);
                    final newPackages = [...currentPackages, _newPackageController.text];
                    try {
                      await ref.read(engineServiceProvider).setPackages(widget.projectId, newPackages);
                      _newPackageController.clear();
                      ref.invalidate(projectPackagesProvider(widget.projectId)); // Refresh
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error adding package: $e')),
                      );
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Installed Packages:', style: Theme.of(context).textTheme.titleMedium),
          Expanded(
            child: packagesAsync.when(
              data: (packages) {
                if (packages.isEmpty) {
                  return const Center(child: Text('No packages added yet.'));
                }
                return ListView.builder(
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final pkg = packages[index];
                    return ListTile(
                      title: Text(pkg),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () async {
                           final currentPackages = List<String>.from(packages); // Create mutable copy
                           currentPackages.remove(pkg);
                            try {
                              await ref.read(engineServiceProvider).setPackages(widget.projectId, currentPackages);
                              ref.invalidate(projectPackagesProvider(widget.projectId)); // Refresh
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error removing package: $e')),
                              );
                            }
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error loading packages: $err')),
            ),
          ),
        ],
      ),
    );
  }
   @override
  void dispose() {
    _newPackageController.dispose();
    super.dispose();
  }
}

// --- Configuration Tab ---
class ConfigurationTab extends ConsumerStatefulWidget {
  final String projectId;
  final Map<String, dynamic> projectDetails; // Initial details

  const ConfigurationTab({super.key, required this.projectId, required this.projectDetails});

  @override
  ConsumerState<ConfigurationTab> createState() => _ConfigurationTabState();
}

class _ConfigurationTabState extends ConsumerState<ConfigurationTab> {
  late TextEditingController _hostnameController;
  String? _selectedBootloader; // Example: "grub", "systemd-boot"
  final List<String> _availableBootloaders = ["grub", "systemd-boot", "syslinux"]; // Example

  @override
  void initState() {
    super.initState();
    _hostnameController = TextEditingController(text: widget.projectDetails['hostname'] as String? ?? '');
    _selectedBootloader = widget.projectDetails['bootloader'] as String?;
     if (_selectedBootloader != null && !_availableBootloaders.contains(_selectedBootloader) && _availableBootloaders.isNotEmpty) {
        _selectedBootloader = _availableBootloaders.first;
    } else if (_selectedBootloader == null && _availableBootloaders.isNotEmpty) {
        _selectedBootloader = _availableBootloaders.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use specific providers for hostname and bootloader to get live updates
    // final hostnameAsync = ref.watch(projectHostnameProvider(widget.projectId)); // This was unused
    final bootloaderAsync = ref.watch(projectBootloaderProvider(widget.projectId));


    // Update local state if providers change (e.g. after a save)
    // This can be tricky, ensure not to create infinite loops.
    // One way is to only update if the incoming value is different from current text field value.
    ref.listen(projectHostnameProvider(widget.projectId), (_, next) {
      next.whenData((hostname) {
        if (hostname != null && hostname != _hostnameController.text) {
          _hostnameController.text = hostname;
        }
      });
    });
     ref.listen(projectBootloaderProvider(widget.projectId), (_, next) {
      next.whenData((bootloader) {
        if (bootloader != null && bootloader != _selectedBootloader) {
          setState(() {
            _selectedBootloader = bootloader;
          });
        }
      });
    });


    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          // Hostname
          TextFormField(
            controller: _hostnameController,
            decoration: const InputDecoration(labelText: 'Hostname'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(engineServiceProvider).setHostname(widget.projectId, _hostnameController.text);
                ref.invalidate(projectHostnameProvider(widget.projectId)); // Refresh hostname
                ref.invalidate(projectDetailsProvider(widget.projectId)); // Also refresh general details
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Hostname updated!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating hostname: $e')),
                );
              }
            },
            child: const Text('Set Hostname'),
          ),
          const SizedBox(height: 20),

          // Bootloader
          bootloaderAsync.when(
            data: (currentBootloader) { // currentBootloader might be the initial value
              // Ensure _selectedBootloader is initialized properly
              if (_selectedBootloader == null && currentBootloader != null && _availableBootloaders.contains(currentBootloader)) {
                 _selectedBootloader = currentBootloader;
              } else if (_selectedBootloader == null && _availableBootloaders.isNotEmpty) {
                 _selectedBootloader = _availableBootloaders.first;
              }

              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Bootloader'),
                value: _selectedBootloader,
                items: _availableBootloaders.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedBootloader = newValue;
                  });
                },
              );
            },
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => Text("Error loading bootloader: $e"),
          ),
          ElevatedButton(
            onPressed: _selectedBootloader == null ? null : () async {
              if (_selectedBootloader != null) {
                try {
                  await ref.read(engineServiceProvider).setBootloader(widget.projectId, _selectedBootloader!);
                  ref.invalidate(projectBootloaderProvider(widget.projectId)); // Refresh
                  ref.invalidate(projectDetailsProvider(widget.projectId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bootloader updated!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating bootloader: $e')),
                  );
                }
              }
            },
            child: const Text('Set Bootloader'),
          ),
          // Future: Config file editor placeholder
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hostnameController.dispose();
    super.dispose();
  }
}


// --- Build Tab ---
class BuildTab extends ConsumerWidget {
  final String projectId;
  const BuildTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildLog = ref.watch(buildLogStreamProvider); // Global build log for now
    final currentBuildId = ref.watch(currentBuildIdProvider(projectId));
    final buildStatusAsync = ref.watch(projectBuildStatusProvider((projectId: projectId, buildId: currentBuildId ?? "")));


    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: () async {
              try {
                // Clear previous build ID for this project
                ref.read(currentBuildIdProvider(projectId).notifier).state = null;
                final response = await ref.read(engineServiceProvider).buildIso(projectId);
                final buildId = response['build_id'] as String?;
                if (buildId != null) {
                  ref.read(currentBuildIdProvider(projectId).notifier).state = buildId;
                   // Request stream explicitly if needed, though buildIso might start it
                  await ref.read(engineServiceProvider).requestBuildOutputStream(projectId, buildId);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Build started! Build ID: ${buildId ?? 'N/A'}')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error starting build: $e')),
                );
              }
            },
            child: const Text('Build ISO'),
          ),
          const SizedBox(height: 10),
          buildStatusAsync.when(
            data: (status) => Text('Status: ${status['status']} ${status['progress'] != null ? "(${status['progress']}%)" : ""}\n${status['download_url'] != null ? "URL: ${status['download_url']}" : "" }'),
            loading: () => const Text('Status: Loading...'),
            error: (e, st) => Text('Status: Error ($e)'),
          ),
          const SizedBox(height: 10),
          Text('Build Log:', style: Theme.of(context).textTheme.titleMedium),
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              padding: const EdgeInsets.all(8.0),
              child: buildLog.when(
                data: (logLine) {
                  // This will only show the latest line. We need to accumulate lines.
                  // A better approach is a local list in a StatefulWidget or another provider.
                  // For simplicity now, this will just update with the latest.
                  // To show all logs, you'd use a StateProvider<List<String>> and append.
                  return SingleChildScrollView(reverse: true, child: SelectableText(logLine));
                },
                loading: () => const Center(child: Text("Waiting for build log...")),
                error: (err, stack) => Text('Error in build log stream: $err'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
