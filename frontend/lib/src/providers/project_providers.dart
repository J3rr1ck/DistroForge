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
  // Assuming getHostname might return null or throw if not set.
  // The engine service's getHostname needs to be defined or adjusted.
  // For now, let's assume it's part of getProjectDetails or a new method.
  // Let's add getHostname to EngineService:
  // Future<String?> getHostname(String projectId) async {
  //   final response = await _sendRequestInternal('project.getHostname', {'project_id': projectId});
  //   return response['hostname'] as String?;
  // }
  // This is simplified; actual parsing might be needed.
  // For now, let's assume getProjectDetails contains hostname.
  final details = await ref.watch(projectDetailsProvider(projectId).future);
  return details['hostname'] as String?;
});

// Provider for bootloader of a specific project
final projectBootloaderProvider = FutureProvider.family<String?, String>((ref, projectId) async {
  final engineService = ref.watch(engineServiceProvider);
  // Similar to hostname, assuming it's part of getProjectDetails for now.
  // Let's add getBootloader to EngineService:
  // Future<String?> getBootloader(String projectId) async {
  //   final response = await _sendRequestInternal('project.getBootloader', {'project_id': projectId});
  //   return response['bootloader'] as String?;
  // }
  final details = await ref.watch(projectDetailsProvider(projectId).future);
  return details['bootloader'] as String?;
});


// Provider to manage the current build ID for a project (if a build is active)
final currentBuildIdProvider = StateProvider.family<String?, String>((ref, projectId) => null);

// Provider for build status of a specific project and build
final projectBuildStatusProvider = FutureProvider.family<Map<String, dynamic>, ({String projectId, String buildId})>((ref, ids) async {
  if (ids.buildId.isEmpty) return {"status": "No active build"}; // Or some other default
  final engineService = ref.watch(engineServiceProvider);
  return engineService.getBuildStatus(ids.projectId, ids.buildId);
});
