package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

// JSONRPCRequest defines the structure for outgoing JSON-RPC requests.
type JSONRPCRequest struct {
	JSONRPC string      `json:"jsonrpc"`
	Method  string      `json:"method"`
	Params  interface{} `json:"params,omitempty"`
	ID      int         `json:"id"`
}

// JSONRPCResponse defines the structure for incoming JSON-RPC responses.
// We only care about Result and Error for the CLI's purpose.
type JSONRPCResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   json.RawMessage `json:"error,omitempty"` // Keep as RawMessage to print as is
	ID      int             `json:"id"`
	// If the response is a stream notification, it might not have an ID
	// and might have a "method" field indicating "project.buildOutputChunk"
	StreamMethod string `json:"method,omitempty"`
}

const backendCommand = "distroforge-engine" // Assumes backend is built and in PATH or local dir
// Alternative: use "go" with "run" and path to backend main.go
// const backendGoRunPath = "../backend/main.go"

var requestIDCounter = 0

func main() {
	log.SetFlags(0) // No timestamps, just the message for cleaner CLI output

	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	method := os.Args[1]
	var paramsStr string
	if len(os.Args) > 2 {
		paramsStr = os.Args[2]
	}

	var params interface{}
	if paramsStr != "" {
		// Attempt to unmarshal paramsStr as a JSON object or array
		var jsonObj map[string]interface{}
		err := json.Unmarshal([]byte(paramsStr), &jsonObj)
		if err != nil {
			var jsonArr []interface{}
			err2 := json.Unmarshal([]byte(paramsStr), &jsonArr)
			if err2 != nil {
				// If it's not a valid JSON object or array, treat as a simple string
				// This might not be what the backend expects for complex params,
				// but some simple params might be strings.
				// For this CLI, we'll require params to be valid JSON if complex.
				log.Fatalf("Error: Parameters string is not valid JSON: %v, %v. Please provide parameters as a valid JSON string.", err, err2)
			}
			params = jsonArr
		} else {
			params = jsonObj
		}
	}

	requestIDCounter++
	req := JSONRPCRequest{
		JSONRPC: "2.0",
		Method:  method,
		Params:  params,
		ID:      requestIDCounter,
	}

	reqBytes, err := json.Marshal(req)
	if err != nil {
		log.Fatalf("Error marshalling JSON-RPC request: %v", err)
	}

	// Determine backend executable path
	// Prefer a pre-built executable for speed and simplicity in this subtask
	backendExecutablePath := backendCommand
	// Check if backend executable is in current dir or one level up (e.g. ../backend/distroforge-engine)
	localBackendPath := filepath.Join("..", "backend", backendCommand)
	if _, err := os.Stat(localBackendPath); err == nil {
		backendExecutablePath = localBackendPath
	} else {
		// If not found locally, try `go run` relative to typical project structure
		// This assumes CLI is run from /app/cli or /app
		goRunPath := filepath.Join("..", "backend", "main.go")
		if _, err := os.Stat(goRunPath); err == nil {
			log.Printf("Backend executable not found, attempting to use 'go run %s'", goRunPath)
			// Prepend "run" and the path to os.Args for exec.Command("go", ...)
			// This is handled below
		} else {
			log.Printf("Warning: Backend executable '%s' not found locally or via go run path '%s'. Assuming it's in PATH.", backendCommand, goRunPath)
		}
	}

	var cmd *exec.Cmd
	if _, err := os.Stat(backendExecutablePath); err == nil && !os.IsNotExist(err) {
		cmd = exec.Command(backendExecutablePath)
	} else {
		// Fallback to go run
		goRunPath := filepath.Join("..", "backend", "main.go")
		if _, ferr := os.Stat(goRunPath); ferr == nil {
			cmd = exec.Command("go", "run", goRunPath)
		} else {
			log.Fatalf("Failed to find backend executable at %s or %s", backendExecutablePath, goRunPath)
		}
	}


	stdin, err := cmd.StdinPipe()
	if err != nil {
		log.Fatalf("Error getting stdin pipe: %v", err)
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		log.Fatalf("Error getting stdout pipe: %v", err)
	}

	// Stderr pipe for backend logs (optional to display, but good to have)
	stderr, err := cmd.StderrPipe()
	if err != nil {
		log.Fatalf("Error getting stderr pipe: %v", err)
	}

	if err := cmd.Start(); err != nil {
		log.Fatalf("Error starting backend engine: %v. Ensure backend is built (e.g., cd ../backend && go build) or accessible via 'go run'.", err)
	}

	// Goroutine to print backend's stderr (engine logs)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		scanner := bufio.NewScanner(stderr)
		for scanner.Scan() {
			log.Printf("[ENGINE LOG] %s", scanner.Text())
		}
	}()

	_, err = stdin.Write(append(reqBytes, '\n'))
	if err != nil {
		log.Fatalf("Error writing to backend stdin: %v", err)
	}
	stdin.Close() // Close stdin to signal end of input

	// Read response(s) from backend stdout
	// The backend might send multiple JSON objects if it's streaming (e.g. for build output)
	// For methods like buildIso or streamBuildOutput, we expect multiple responses.
	// For others, we expect one.

	// Special handling for streaming methods
	isStreamingMethod := method == "project.streamBuildOutput" || method == "project.buildIso"

	// Timeout for non-streaming responses
	if !isStreamingMethod {
		done := make(chan bool)
		go func() {
			processBackendOutput(stdout, req.ID, isStreamingMethod)
			done <- true
		}()
		select {
		case <-done:
			// completed
		case <-time.After(10 * time.Second): // Adjust timeout as needed
			log.Println("Timeout waiting for backend response.")
		}
	} else {
		// For streaming methods, process output until stdout is closed
		processBackendOutput(stdout, req.ID, isStreamingMethod)
	}


	if err := cmd.Wait(); err != nil {
		// This error is about the process exiting, not necessarily an application error.
		// Application errors are in the JSON-RPC response.
		// Log it if it's unexpected (e.g., non-zero exit code) but don't os.Exit(1) unless severe.
		if exitErr, ok := err.(*exec.ExitError); ok {
			log.Printf("Backend engine exited with error: %v. Stderr: %s", err, string(exitErr.Stderr))
		} else {
			log.Printf("Backend engine wait error: %v", err)
		}
	}
	wg.Wait() // Wait for stderr goroutine to finish
}

func processBackendOutput(stdout io.ReadCloser, requestID int, isStreaming bool) {
	reader := bufio.NewReader(stdout)
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err != io.EOF { // EOF is expected when stream ends or process closes stdout
				log.Printf("Error reading from backend stdout: %v", err)
			}
			break // Exit loop on EOF or any other error
		}

		var resp JSONRPCResponse
		if err := json.Unmarshal(line, &resp); err != nil {
			log.Printf("Error unmarshalling JSON-RPC response line: %v. Line: %s", err, string(line))
			continue
		}

		// If it's a streaming method, we might get notifications (no ID or different method)
		// or multiple responses related to the build.
		// The backend's `project.streamBuildOutput` handler sends JSON objects that might not have an ID,
		// or might have a specific "method" field for notifications.
		// The current backend implementation for streaming sends full JSONRPCResponse structures
		// as separate JSON lines.

		// Print the formatted JSON response
		var prettyOutput bytes.Buffer
		if err := json.Indent(&prettyOutput, line, "", "  "); err != nil {
			fmt.Println(string(line)) // Print raw if indent fails
		} else {
			fmt.Println(prettyOutput.String())
		}

		// For non-streaming methods, we expect only one response with the matching ID.
		if !isStreaming && resp.ID == requestID {
			break // Stop after processing the specific response for non-streaming calls
		}
		// For streaming methods, continue reading until stdout is closed (EOF).
	}
}


func printUsage() {
	fmt.Println("Usage: ./distroforge-cli <method> [params_json_string]")
	fmt.Println("\nExamples:")
	fmt.Println("  ./distroforge-cli engine.getDistroPlugins")
	fmt.Println("  ./distroforge-cli engine.createProject '{\"distro_id\": \"arch\"}'")
	fmt.Println("  ./distroforge-cli project.getDetails '{\"project_id\": \"your_project_id\"}'")
	fmt.Println("  ./distroforge-cli project.setPackages '{\"project_id\": \"your_project_id\", \"packages\": [\"nginx\", \"git\"]}'")
	fmt.Println("  ./distroforge-cli project.getPackages '{\"project_id\": \"your_project_id\"}'")
	fmt.Println("  ./distroforge-cli project.buildIso '{\"project_id\": \"your_project_id\"}'")
	fmt.Println("  ./distroforge-cli project.streamBuildOutput '{\"project_id\": \"your_project_id\", \"build_id\": \"your_project_id\"}'")
	fmt.Println("\nNote: Parameters must be a valid JSON string enclosed in single quotes.")
}
