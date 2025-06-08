import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:distroforge_frontend/src/models/project.dart';
import 'package:distroforge_frontend/src/providers/services_provider.dart'; // To access EngineService

// State Notifier for Projects List
class ProjectListNotifier extends StateNotifier<List<Project>> {
  final Ref _ref;

  ProjectListNotifier(this._ref) : super([]); // Initial empty list

  // Method to add a new project (typically called after creation via engine)
  Future<void> createProject(String distroId, String projectName) async {
    final engineService = _ref.read(engineServiceProvider);
    try {
      // The EngineService.createProject already returns a Project object
      // based on the passed name and distroId, and the returned project_id.
      final newProject = await engineService.createProject(distroId, projectName);
      state = [...state, newProject];
    } catch (e) {
      // Handle or rethrow error to be caught by UI
      print("Error creating project in ProjectListNotifier: $e");
      rethrow;
    }
  }

  // Method to remove a project (example, not directly requested but good for completeness)
  void removeProject(String projectId) {
    state = state.where((p) => p.id != projectId).toList();
  }

  // Method to fetch initial projects if needed (e.g., from a persistent store via engine)
  // Future<void> fetchProjects() async { ... }
}

// Provider for the ProjectListNotifier
final projectListProvider = StateNotifierProvider<ProjectListNotifier, List<Project>>((ref) {
  return ProjectListNotifier(ref);
});

// Provider to get details for a single project.
// This will call the engine service when a project's details are needed.
// It's a family provider because it depends on the projectId.
final projectDetailsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, projectId) async {
  final engineService = ref.watch(engineServiceProvider);
  return engineService.getProjectDetails(projectId);
});

// Provider for packages of a specific project
final projectPackagesProvider = FutureProvider.family<List<String>, String>((ref, projectId) async {
  final engineService = ref.watch(engineServiceProvider);
  return engineService.getPackages(projectId);
});

// Provider for hostname of a specific project
final projectHostnameProvider = FutureProvider.family<String?, String>((ref, projectId) async {
  final engineService = ref.watch(engineServiceProvider);
  // Call the specific method on engineService
  final response = await engineService.getHostname(projectId); // getHostname returns Future<Map<String, dynamic>>
  return response['hostname'] as String?; // Extract the hostname string
});

// Provider for bootloader of a specific project
final projectBootloaderProvider = FutureProvider.family<String?, String>((ref, projectId) async {
  final engineService = ref.watch(engineServiceProvider);
  // Call the specific method on engineService
  final response = await engineService.getBootloader(projectId); // getBootloader returns Future<Map<String, dynamic>>
  return response['bootloader'] as String?; // Extract the bootloader string
});


// Provider to manage the current build ID for a project (if a build is active)
final currentBuildIdProvider = StateProvider.family<String?, String>((ref, projectId) => null);

// Provider for build status of a specific project and build
final projectBuildStatusProvider = FutureProvider.family<Map<String, dynamic>, ({String projectId, String buildId})>((ref, ids) async {
  if (ids.buildId.isEmpty) return {"status": "No active build"}; // Or some other default
  final engineService = ref.watch(engineServiceProvider);
  return engineService.getBuildStatus(ids.projectId, ids.buildId);
});
