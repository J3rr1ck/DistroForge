import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For debugPrint and kDebugMode
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path; // For path manipulation

import 'package:distroforge_frontend/src/models/distro.dart';
import 'package:distroforge_frontend/src/models/project.dart';
// Import other models as needed, e.g., BuildStatus

// JSON-RPC Request and Response Structures (simplified for client use)
class JsonRpcRequest {
  final String jsonrpc = '2.0';
  final String method;
  final dynamic params;
  final String id;

  JsonRpcRequest({required this.method, this.params, required this.id});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'method': method,
      'id': id,
    };
    if (params != null) {
      map['params'] = params;
    }
    return map;
  }
}

class JsonRpcResponse {
  final String jsonrpc;
  final dynamic result;
  final Map<String, dynamic>? error;
  final String? id; // Nullable if it's a notification/stream chunk without ID

  JsonRpcResponse({required this.jsonrpc, this.result, this.error, this.id});

  factory JsonRpcResponse.fromJson(Map<String, dynamic> json) {
    return JsonRpcResponse(
      jsonrpc: json['jsonrpc'] as String? ?? '2.0', // Default if missing
      result: json['result'],
      error: json['error'] as Map<String, dynamic>?,
      id: json['id'] as String?,
    );
  }
}


class EngineService {
  Process? _process;
  final Uuid _uuid = const Uuid();
  final Map<String, Completer<JsonRpcResponse>> _pendingRequests = {};
  final StreamController<String> _buildLogStreamController = StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _engineMessagesController = StreamController<Map<String, dynamic>>.broadcast();


  // TODO: Determine backend path more robustly, perhaps via configuration
  String get _backendCommand {
      // In debug mode from IDE, current path is often project root ('frontend')
      // In release mode, it depends on bundling.
      // This path assumes backend executable is one level up from frontend, in 'backend' dir.

      String backendDir = path.join(Directory.current.path, '..', 'backend');
      if (Platform.isWindows) {
          return path.join(backendDir, 'distroforge-engine.exe');
      }
      return path.join(backendDir, 'distroforge-engine');
  }

  String get _goRunCommand => "go";
  List<String> get _goRunArgs => ["run", path.join("..", "backend", "main.go")];


  bool get isRunning => _process != null;

  Stream<String> get buildLogStream => _buildLogStreamController.stream;
  Stream<Map<String, dynamic>> get engineMessages => _engineMessagesController.stream;


  EngineService() {
    // Listen to general engine messages (e.g. stream output not tied to a specific request completer)
    _engineMessagesController.stream.listen((message) {
      if (message['method'] == 'project.buildOutputChunk' ||
          (message['result'] != null && message['result'] is Map && message['result']['log_line'] != null) ) {
        // This is how CLI sends it: result: { project_id, build_id, log_line }
        var resultData = message['result'] as Map<String, dynamic>;
        if (resultData['log_line'] != null) {
           _buildLogStreamController.add(resultData['log_line'] as String);
        }
      }
    });
  }

  Future<void> startEngine() async {
    if (isRunning) {
      debugPrint('Engine already running.');
      return;
    }

    String command = _backendCommand;
    List<String> arguments = [];

    // Check if pre-built backend exists
    File backendExecutable = File(command);
    bool preBuiltExists = await backendExecutable.exists();

    if (!preBuiltExists) {
        debugPrint("Pre-built backend not found at $command. Attempting 'go run'.");
        // Check if backend main.go exists for go run
        String mainGoPath = path.join(Directory.current.path, _goRunArgs[1]);
        File mainGoFile = File(mainGoPath);
        if (!await mainGoFile.exists()) {
            debugPrint("Backend main.go not found at $mainGoPath. Cannot start engine.");
            throw Exception("Backend source (main.go) not found at $mainGoPath for 'go run'.");
        }
        command = _goRunCommand;
        arguments = _goRunArgs;
    }

    debugPrint("Starting engine with command: $command ${arguments.join(' ')}");

    try {
      _process = await Process.start(command, arguments, workingDirectory: Directory.current.parent.path); // Run from repo root ideally
      debugPrint('Engine process started (PID: ${_process!.pid}).');

      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          debugPrint('[ENGINE STDOUT] $line');
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final response = JsonRpcResponse.fromJson(json);

            if (response.id != null && _pendingRequests.containsKey(response.id)) {
              _pendingRequests.remove(response.id)!.complete(response);
            } else {
              // This could be a stream notification or an unmatched response
              _engineMessagesController.add(json);
            }
          } catch (e) {
            debugPrint('Error parsing JSON from engine stdout: $e. Line: $line');
            // Could also push this to a general error stream for UI to see
          }
        },
        onError: (error) {
          debugPrint('Engine stdout error: $error');
          _cleanupProcess();
        },
        onDone: () {
          debugPrint('Engine stdout closed.');
          _cleanupProcess();
        },
      );

      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          debugPrint('[ENGINE STDERR] $line');
          // Optionally, add stderr lines to a separate stream for UI display
        },
        onError: (error) {
          debugPrint('Engine stderr error: $error');
        },
        onDone: () {
          debugPrint('Engine stderr closed.');
        },
      );

      _process!.exitCode.then((code) {
        debugPrint('Engine process exited with code $code.');
        _cleanupProcess();
      });

    } catch (e) {
      debugPrint('Error starting engine process: $e');
      _cleanupProcess();
      throw Exception('Failed to start engine: $e');
    }
  }

  void _cleanupProcess() {
    _process = null;
    // Fail any pending requests
    for (var completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception("Engine process terminated or connection lost."));
      }
    }
    _pendingRequests.clear();
    debugPrint("Engine process cleaned up.");
  }


  Future<void> stopEngine() async {
    if (!isRunning || _process == null) {
      debugPrint('Engine not running.');
      return;
    }
    debugPrint('Stopping engine process (PID: ${_process!.pid})...');
    _process!.kill(ProcessSignal.sigterm); // Or sigint
    // await _process!.exitCode; // Wait for it to exit
    _cleanupProcess();
  }

  Future<Map<String, dynamic>> _sendRequestInternal(String method, [Map<String, dynamic>? params]) async {
    if (!isRunning || _process == null) {
      throw Exception('Engine not running. Call startEngine() first.');
    }

    final requestId = _uuid.v4();
    final request = JsonRpcRequest(method: method, params: params, id: requestId);
    final completer = Completer<JsonRpcResponse>();
    _pendingRequests[requestId] = completer;

    final requestJson = jsonEncode(request.toJson());
    debugPrint('[SEND >>>] $requestJson');
    _process!.stdin.writeln(requestJson);
    try {
       await _process!.stdin.flush();
    } catch (e) {
        debugPrint("Error flushing stdin: $e");
        _pendingRequests.remove(requestId);
        throw Exception("Failed to write to engine stdin: $e");
    }


    // Timeout for the request
    final future = completer.future.timeout(const Duration(seconds: 30), onTimeout: () { // Adjust timeout as needed
      _pendingRequests.remove(requestId);
      throw TimeoutException('Request timed out for method $method after 30 seconds.');
    });


    final response = await future;

    if (response.error != null) {
      debugPrint('Engine returned error for method $method: ${response.error}');
      throw Exception('Engine error: ${response.error!['message']} (Code: ${response.error!['code']})');
    }
    return response.result as Map<String, dynamic>;
  }

  // --- Type-safe API methods (examples) ---

  Future<List<Distro>> getDistroPlugins() async {
    final response = await _sendRequestInternal('engine.getDistroPlugins');
    // API.md says: { "distros": [ { "id": "string", "name": "string", "description": "string" } ] }
    final List<dynamic> distroListJson = response['distros'] as List<dynamic>;
    return distroListJson.map((json) => Distro.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<Project> createProject(String distroId, String projectName) async {
    // Assuming the backend's createProject now expects a project_name or similar.
    // The API.md for engine.createProject only lists 'distro_id'.
    // Let's assume for now the backend can take additional params or this needs adjustment.
    // For this example, we'll send both, but the backend might only use distro_id from API.md.
    // The Go backend's engine.createProject handler only parses "distro_id".
    // The plugin's CreateProject might take more, but that's an internal detail.
    // For now, stick to API.md for the direct call.
    // The `projectName` would be used at a higher level or if API changes.
    final response = await _sendRequestInternal('engine.createProject', {'distro_id': distroId});
    // API.md says: { "project_id": "string" }
    // We need to construct a Project object. We're missing the name and distroId from the response directly.
    // This suggests the Project model in Flutter might need to be populated differently after creation,
    // or the createProject API method on EngineService should just return project_id.
    // Let's assume for now it just returns the ID, and higher layers manage the full Project object.
    // OR, the `project.getDetails` should be called immediately after.

    // For a more complete Project object, we'd typically call getDetails right after.
    // For now, let's return a partial Project or just the ID.
    // Let's adjust to return a simple map for now, or define a specific response model.
    // Project.fromJson expects name and distroId which are not in the response.
    // So, let's return the raw map or a dedicated response type.

    // Returning a basic Project object for now, using the passed projectName and distroId.
    return Project(id: response['project_id'] as String, name: projectName, distroId: distroId);
  }

  Future<Map<String, dynamic>> getProjectDetails(String projectId) async {
      return await _sendRequestInternal('project.getDetails', {'project_id': projectId});
  }

  Future<void> setPackages(String projectId, List<String> packages) async {
    await _sendRequestInternal('project.setPackages', {'project_id': projectId, 'packages': packages});
  }

  Future<List<String>> getPackages(String projectId) async {
    final response = await _sendRequestInternal('project.getPackages', {'project_id': projectId});
    // API.md: { "packages": ["string"] }
    final List<dynamic> pkgListJson = response['packages'] as List<dynamic>;
    return pkgListJson.map((p) => p as String).toList();
  }

  Future<Map<String, dynamic>> buildIso(String projectId) async {
    // This call will return an initial response like { "build_id": "string", "status": "string" }
    // The actual build logs will be streamed via the _engineMessagesController / _buildLogStreamController
    // due to the stdout handling.
    return await _sendRequestInternal('project.buildIso', {'project_id': projectId});
  }

  // For explicitly requesting the stream (though buildIso also triggers it)
  Future<void> requestBuildOutputStream(String projectId, String buildId) async {
    // This method might not need to complete a request via _pendingRequests if the backend
    // just starts streaming without a specific ack response to this call itself.
    // However, our current backend sends an ack for streamBuildOutput.
    await _sendRequestInternal('project.streamBuildOutput', {'project_id': projectId, 'build_id': buildId});
    // The stream is handled by the global stdout listener.
  }
   Future<Map<String,dynamic>> getBuildStatus(String projectId, String buildId) async {
    return await _sendRequestInternal('project.getBuildStatus', {'project_id': projectId, 'build_id': buildId});
  }

  // Add other type-safe methods here corresponding to API.md
  // e.g., setHostname, getHostname, setBootloader, getBootloader
}
