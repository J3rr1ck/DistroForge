import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:distroforge_frontend/src/services/engine_service.dart';
import 'package:distroforge_frontend/src/models/distro.dart'; // Added import for Distro model

// Provider for the EngineService
// Using a simple Provider as EngineService manages its own state internally.
// If we needed to dispose of resources in EngineService when the provider is disposed,
// we might use a different type of provider or manage lifecycle explicitly.
final engineServiceProvider = Provider<EngineService>((ref) {
  final engineService = EngineService();

  // Start the engine when the provider is first read.
  // This is a common pattern, but consider if explicit start/stop from UI is better.
  // For now, auto-start on first use.
  // Note: startEngine is async, but provider initialization should be synchronous.
  // So, we call it but don't await it here. The service handles its internal state.
  // Proper error handling for startup failures should be exposed to the UI.
  engineService.startEngine().catchError((e) {
    // Log error or update an error state provider
    print("Failed to start engine via provider: $e");
    // Consider setting an error state in another provider that the UI can watch.
  });

  // Optional: Ensure engine is stopped when the provider is disposed.
  // This is important if the provider can be auto-disposed or family-disposed.
  // For a global provider like this, app lifecycle might handle it, but good practice.
  ref.onDispose(() {
    print("Disposing engineServiceProvider, stopping engine...");
    engineService.stopEngine();
  });

  return engineService;
});

// Example: A FutureProvider to get distro plugins, depending on EngineService
final distroPluginsProvider = FutureProvider<List<Distro>>((ref) async {
  final engineService = ref.watch(engineServiceProvider);
  // Ensure engine is running or wait for it if startEngine() was deferred
  if (!engineService.isRunning) {
    // This might be an issue if startEngine() in the provider above hasn't completed
    // or failed silently. A robust solution might involve a separate state provider
    // for engine readiness.
    // For now, assuming startEngine is called and we proceed.
    // Alternatively, make startEngine() part of getDistroPlugins if not auto-started.
    // await engineService.startEngine(); // if not auto-started
  }
  return engineService.getDistroPlugins();
});

// Provider for build log stream
final buildLogStreamProvider = StreamProvider<String>((ref) {
  final engineService = ref.watch(engineServiceProvider);
  return engineService.buildLogStream;
});
