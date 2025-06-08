package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"strings"

	"example.com/jsonrpcengine/plugin"
	"example.com/jsonrpcengine/plugin/arch" // Import the arch plugin
)

// JSONRPCRequest defines the structure for incoming JSON-RPC requests.
type JSONRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"` // Use RawMessage to delay parsing of params
	ID      interface{}     `json:"id"`     // Can be string, number, or null
}

// JSONRPCResponse defines the structure for outgoing JSON-RPC responses.
type JSONRPCResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	Result  interface{} `json:"result,omitempty"`
	Error   *RPCError   `json:"error,omitempty"`
	ID      interface{} `json:"id"`
}

// RPCError defines the structure for JSON-RPC error objects.
type RPCError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// Error Constants
const (
	ParseErrorCode     = -32700
	InvalidRequestCode = -32600
	MethodNotFoundCode = -32601
	InvalidParamsCode  = -32602
	InternalErrorCode  = -32603
	ProjectNotFoundCode = -32000 // Example application-specific error
	PluginNotFoundCode  = -32001
)

// ProjectDataStore defines a simple in-memory store for project metadata.
// In a real application, this would be a database.
var ProjectDataStore = make(map[string]ProjectMetadata)

// ProjectMetadata stores basic info about a project, including its distro type.
type ProjectMetadata struct {
	ID       string `json:"id"`
	DistroID string `json:"distro_id"`
	// Other project-specific metadata can be stored here
}

var pluginManager *plugin.PluginManager

func main() {
	pluginManager = plugin.NewPluginManager()

	// Define root paths for plugins. These could come from config in a real app.
	// Using /app/ as the base, assuming the container/build environment works from there.
	projectsRoot := "/app/projects"
	isosRoot := "/app/isos"
	workRootBase := "/app/work" // Base for work directories

	// Register Arch Plugin
	archPlugin, err := arch.NewArchPlugin(
		filepath.Join(projectsRoot), // Arch projects will be in /app/projects/<projectID>
		filepath.Join(isosRoot),     // Arch ISOs will be in /app/isos/<projectID>
		filepath.Join(workRootBase, "archiso"), // Arch work dirs in /app/work/archiso/<projectID>
	)
	if err != nil {
		log.Fatalf("Failed to initialize Arch plugin: %v", err)
	}
	pluginManager.RegisterPlugin("arch", archPlugin)
	log.Printf("Registered plugin: arch")

	log.Println("JSON-RPC Engine Started. Listening on stdin...")

	reader := bufio.NewReader(os.Stdin)
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err != io.EOF {
				log.Printf("Error reading from stdin: %v", err)
			}
			break // Exit on EOF or error
		}

		var req JSONRPCRequest
		if err := json.Unmarshal(line, &req); err != nil {
			sendErrorResponse(nil, ParseErrorCode, "Parse error", err.Error())
			continue
		}

		if req.JSONRPC != "2.0" {
			sendErrorResponse(req.ID, InvalidRequestCode, "Invalid Request", "Invalid JSON-RPC version")
			continue
		}

		resp := handleRequest(req)
		sendResponse(resp)
	}
	log.Println("JSON-RPC Engine Shutting Down.")
}

func sendResponse(resp JSONRPCResponse) {
	jsonData, err := json.Marshal(resp)
	if err != nil {
		log.Printf("Error marshalling response: %v", err)
		// Fallback error response
		fallbackResp := JSONRPCResponse{
			JSONRPC: "2.0",
			Error: &RPCError{
				Code:    InternalErrorCode,
				Message: "Internal error marshalling response",
			},
			ID: resp.ID, // Try to use original ID
		}
		jsonData, _ = json.Marshal(fallbackResp)
	}
	fmt.Fprintln(os.Stdout, string(jsonData))
}

func sendErrorResponse(id interface{}, code int, message string, data interface{}) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		Error:   &RPCError{Code: code, Message: message, Data: data},
		ID:      id,
	}
	sendResponse(resp)
}

func handleRequest(req JSONRPCRequest) JSONRPCResponse {
	parts := strings.SplitN(req.Method, ".", 2)
	if len(parts) != 2 {
		return JSONRPCResponse{
			JSONRPC: "2.0",
			Error:   &RPCError{Code: MethodNotFoundCode, Message: "Invalid method format. Expected 'namespace.method'"},
			ID:      req.ID,
		}
	}
	namespace, method := parts[0], parts[1]

	switch namespace {
	case "engine":
		return handleEngineCommands(req, method)
	case "project":
		return handleProjectCommands(req, method)
	default:
		return JSONRPCResponse{
			JSONRPC: "2.0",
			Error:   &RPCError{Code: MethodNotFoundCode, Message: fmt.Sprintf("Namespace '%s' not found", namespace)},
			ID:      req.ID,
		}
	}
}

func handleEngineCommands(req JSONRPCRequest, method string) JSONRPCResponse {
	switch method {
	case "getDistroPlugins":
		// Implementation for engine.getDistroPlugins
		distros := pluginManager.GetAvailablePlugins()
		return JSONRPCResponse{JSONRPC: "2.0", Result: map[string]interface{}{"distros": distros}, ID: req.ID}

	case "createProject":
		var params struct {
			DistroID string `json:"distro_id"`
		}
		if err := json.Unmarshal(req.Params, &params); err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Invalid params for createProject", Data: err.Error()}, ID: req.ID}
		}
		if params.DistroID == "" {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Missing distro_id"}, ID: req.ID}
		}

		p, found := pluginManager.GetPlugin(params.DistroID)
		if !found {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: PluginNotFoundCode, Message: fmt.Sprintf("Distro plugin '%s' not found", params.DistroID)}, ID: req.ID}
		}

		// Generate a unique project ID (simple example)
		projectID := fmt.Sprintf("project-%d", len(ProjectDataStore)+1)
		ProjectDataStore[projectID] = ProjectMetadata{ID: projectID, DistroID: params.DistroID}

		// Call plugin's CreateProject method if it needs to initialize anything
		// For now, assuming a generic CreateProject on the plugin interface
		var createParams map[string]interface{} // Or a more specific struct
		if err := json.Unmarshal(req.Params, &createParams); err != nil {
			// This unmarshal is for any *additional* params the plugin might want for CreateProject
			// If only distro_id is passed, this might be empty or handled gracefully by the plugin
		}

		if err := p.CreateProject(projectID, createParams) ; err != nil {
			// If plugin fails to create, remove metadata (or handle more gracefully)
			delete(ProjectDataStore, projectID)
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: fmt.Sprintf("Error creating project with plugin: %v", err)}, ID: req.ID}
		}


		return JSONRPCResponse{JSONRPC: "2.0", Result: map[string]string{"project_id": projectID}, ID: req.ID}

	default:
		return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: MethodNotFoundCode, Message: fmt.Sprintf("Method '%s' not found in engine namespace", method)}, ID: req.ID}
	}
}

func handleProjectCommands(req JSONRPCRequest, method string) JSONRPCResponse {
	// All project commands require a project_id as the first parameter.
	// We need to parse it to find the correct plugin.
	var baseParams struct {
		ProjectID string `json:"project_id"`
	}
	// This is a bit tricky as params structure varies.
	// A common approach is to unmarshal into a map[string]json.RawMessage first,
	// extract project_id, then pass the rest to the plugin.
	// For simplicity, we'll try to unmarshal to get project_id.
	// More robust parsing might be needed here.

	// Let's try to unmarshal into a temporary map to extract project_id
    var tempParams map[string]interface{}
    if err := json.Unmarshal(req.Params, &tempParams); err != nil {
        return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Invalid params structure", Data: err.Error()}, ID: req.ID}
    }

    projectIDInterface, ok := tempParams["project_id"]
    if !ok {
        return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Missing project_id in params"}, ID: req.ID}
    }
    projectID, ok := projectIDInterface.(string)
    if !ok || projectID == "" {
         return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Invalid or empty project_id"}, ID: req.ID}
    }


	meta, found := ProjectDataStore[projectID]
	if !found {
		return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: ProjectNotFoundCode, Message: fmt.Sprintf("Project '%s' not found", projectID)}, ID: req.ID}
	}

	p, found := pluginManager.GetPlugin(meta.DistroID)
	if !found {
		// This should ideally not happen if project creation was successful
		return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: PluginNotFoundCode, Message: fmt.Sprintf("Plugin '%s' for project '%s' not found", meta.DistroID, projectID)}, ID: req.ID}
	}

	// Now dispatch to the plugin method
	switch method {
	case "getDetails":
		details, err := p.GetDetails(projectID)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: details, ID: req.ID}

	case "setPackages":
		var params struct {
			Packages []string `json:"packages"`
		}
		if err := json.Unmarshal(req.Params, &params); err != nil { // req.Params already has project_id, this will fail.
			// We need to pass only the packages part to this unmarshal or handle params better.
			// For now, let's assume params only contains packages after project_id is extracted.
			// This part needs robust parameter handling.
			// A quick fix: re-marshal tempParams excluding project_id
			packageParamsMap, _ := tempParams["packages"].([]interface{})
			var packages []string
			for _, pkg := range packageParamsMap {
				packages = append(packages, pkg.(string))
			}

			err := p.SetPackages(projectID, packages)
			if err != nil {
				return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
			}
			return JSONRPCResponse{JSONRPC: "2.0", Result: map[string]bool{"success": true}, ID: req.ID}
		}
		// This path will likely not be hit due to the above quick fix.
		// Proper solution involves a custom unmarshaler or passing req.Params directly if plugin methods expect raw json.
		err := p.SetPackages(projectID, params.Packages)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: map[string]bool{"success": true}, ID: req.ID}


	case "getPackages":
		pkgs, err := p.GetPackages(projectID)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: pkgs, ID: req.ID}

	case "setBootloader":
		var params struct {
			Bootloader string `json:"bootloader"`
		}
		// Similar param handling issue as setPackages
		bootloaderStr, _ := tempParams["bootloader"].(string)
		err := p.SetBootloader(projectID, bootloaderStr)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: map[string]bool{"success": true}, ID: req.ID}


	case "getBootloader":
		bootloader, err := p.GetBootloader(projectID)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: bootloader, ID: req.ID}

	case "setHostname":
		var params struct {
			Hostname string `json:"hostname"`
		}
		// Similar param handling issue
		hostnameStr, _ := tempParams["hostname"].(string)
		err := p.SetHostname(projectID, hostnameStr)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: map[string]bool{"success": true}, ID: req.ID}

	case "getHostname":
		hostname, err := p.GetHostname(projectID)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: hostname, ID: req.ID}

	case "buildIso":
		// buildIso might not have other params than project_id
		buildResp, err := p.BuildISO(projectID)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: buildResp, ID: req.ID}

	case "streamBuildOutput":
		buildIDInterface, ok := tempParams["build_id"]
		if !ok {
			 return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Missing build_id in params for streamBuildOutput"}, ID: req.ID}
		}
		buildID, ok := buildIDInterface.(string)
		if !ok || buildID == "" {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Invalid or empty build_id for streamBuildOutput"}, ID: req.ID}
		}

		// Streaming is complex over simple request/response.
	// This is where the streaming logic for stdin/stdout would be.
	// It's complex because JSON-RPC is request/response.
	// A common way for CLI is to send multiple JSON objects (notifications) over stdout.
	streamChan, err := p.StreamBuildOutput(projectID, buildID)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: fmt.Sprintf("Failed to start stream: %v", err)}, ID: req.ID}
		}

	// For a stdin/stdout JSON-RPC, we can't easily "stream" in the typical sense
	// of keeping the original request open. Instead, the client would make this call,
	// and the server would start sending JSON objects (notifications or chunks of data)
	// to stdout, *outside* of a direct response to this specific request ID.
	// Or, this method could block and send multiple JSON responses if the client can handle that.

	// Simplification: Send an initial ack, then client must be able to handle separate JSON lines.
	// This goroutine will print log lines as they come, as distinct JSON objects.
	// This is a deviation from strict JSON-RPC request/response for this method if ID is reused.
	// A better way for true JSON-RPC might be repeated polling calls from client for new log lines.
	go func() {
		for line := range streamChan {
			// Send as a notification (no ID) or a custom response structure
			streamData := JSONRPCResponse{ // Using response structure for simplicity, could be a notification
				JSONRPC: "2.0",
				// Method: "project.buildOutputChunk", // For notification style
				Result: map[string]interface{}{
					"project_id": projectID,
					"build_id":   buildID,
					"log_line":   string(line),
				},
				// ID: nil, // For notifications
			}
			// Marshal and print this self-contained JSON object
			jsonData, marshalErr := json.Marshal(streamData)
			if marshalErr != nil {
				log.Printf("Error marshalling stream data: %v", marshalErr)
				continue
			}
			fmt.Fprintln(os.Stdout, string(jsonData))
		}
	}()

	return JSONRPCResponse{JSONRPC: "2.0", Result: map[string]string{"message": "Streaming initiated. Log lines will be sent as separate JSON objects if any."}, ID: req.ID}


	case "getBuildStatus":
		buildIDInterface, ok := tempParams["build_id"]
		if !ok {
			 return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Missing build_id in params for getBuildStatus"}, ID: req.ID}
		}
		buildID, ok := buildIDInterface.(string)
		if !ok || buildID == "" {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InvalidParamsCode, Message: "Invalid or empty build_id for getBuildStatus"}, ID: req.ID}
		}
		status, err := p.GetBuildStatus(projectID, buildID)
		if err != nil {
			return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: InternalErrorCode, Message: err.Error()}, ID: req.ID}
		}
		return JSONRPCResponse{JSONRPC: "2.0", Result: status, ID: req.ID}

	default:
		return JSONRPCResponse{JSONRPC: "2.0", Error: &RPCError{Code: MethodNotFoundCode, Message: fmt.Sprintf("Method '%s' not found in project namespace", method)}, ID: req.ID}
	}
}

// Note: The parameter handling for project-specific commands is simplified.
// In a robust implementation, each handler would unmarshal its specific parameters from req.Params.
// For example, for SetPackages:
// var params struct { ProjectID string `json:"project_id"`; Packages []string `json:"packages"` }
// if err := json.Unmarshal(req.Params, &params); err != nil { /* handle error */ }
// Then call p.SetPackages(params.ProjectID, params.Packages)
// The current implementation in handleProjectCommands makes broad assumptions about param extraction.
// This will be refined if specific issues arise during testing or further implementation.
// The CreateProject in plugin interface also needs to be aligned with how params are passed.
// The StreamBuildOutput method is particularly complex for a simple stdin/stdout JSON-RPC;
// it typically involves a persistent connection like a WebSocket. The current code is a placeholder.
// The module path "example.com/jsonrpc-engine/plugin" is a placeholder and should be updated
// when `go mod init` is run.
// Need to add "path/filepath" for plugin registration.
