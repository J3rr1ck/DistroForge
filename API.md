# JSON-RPC API v1.0

This document defines the JSON-RPC API for interacting with the image building service.

## General Concepts

*   **JSON-RPC 2.0:** The API adheres to the JSON-RPC 2.0 specification.
*   **Versioning:** The API version is v1.0.
*   **Error Handling:** Errors are returned in the standard JSON-RPC error object format. Common error codes will be defined in a separate section (TBD).

## API Commands

### Engine Commands

#### `engine.getDistroPlugins()`

*   **Description:** Retrieves a list of available distribution plugins.
*   **Parameters:** None
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "distros": [
          {
            "id": "string", // Unique identifier for the distro
            "name": "string", // Human-readable name of the distro
            "description": "string" // Short description of the distro
          }
        ]
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InternalError`: If the server fails to retrieve the plugins.

#### `engine.createProject(distro_id: string)`

*   **Description:** Creates a new project for a given distribution.
*   **Parameters:**
    *   `distro_id` (string): The unique identifier of the distribution plugin to use.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "project_id": "string" // Unique identifier for the newly created project
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `distro_id` is missing or invalid.
    *   `DistroNotFound`: If no distribution plugin exists for the given `distro_id`.
    *   `InternalError`: If the server fails to create the project.

### Project Commands

#### `project.getDetails(project_id: string)`

*   **Description:** Retrieves detailed information about a specific project.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "project_id": "string",
        "distro_id": "string",
        "packages": ["string"], // List of currently selected packages
        "bootloader": "string", // Currently selected bootloader
        "hostname": "string", // Currently set hostname
        "build_status": "string", // Current build status (e.g., "pending", "building", "completed", "failed")
        // Potentially other project-specific details
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` is missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `InternalError`: If the server fails to retrieve project details.

#### `project.setPackages(project_id: string, packages: list[string])`

*   **Description:** Sets the list of packages for a project.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
    *   `packages` (list[string]): A list of package names.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "success": true
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` or `packages` are missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `InvalidPackage`: If one or more package names are not valid for the project's distribution.
    *   `InternalError`: If the server fails to set the packages.

#### `project.getPackages(project_id: string)`

*   **Description:** Retrieves the list of currently selected packages for a project.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "packages": ["string"]
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` is missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `InternalError`: If the server fails to retrieve the packages.

#### `project.setBootloader(project_id: string, bootloader: string)`

*   **Description:** Sets the bootloader for a project.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
    *   `bootloader` (string): The name of the bootloader to use (e.g., "grub", "systemd-boot").
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "success": true
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` or `bootloader` are missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `InvalidBootloader`: If the specified bootloader is not supported by the project's distribution.
    *   `InternalError`: If the server fails to set the bootloader.

#### `project.getBootloader(project_id: string)`

*   **Description:** Retrieves the currently selected bootloader for a project.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "bootloader": "string"
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` is missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `InternalError`: If the server fails to retrieve the bootloader.

#### `project.setHostname(project_id: string, hostname: string)`

*   **Description:** Sets the hostname for the project's output image.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
    *   `hostname` (string): The desired hostname.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "success": true
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` or `hostname` are missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `InvalidHostname`: If the hostname format is invalid.
    *   `InternalError`: If the server fails to set the hostname.

#### `project.getHostname(project_id: string)`

*   **Description:** Retrieves the currently set hostname for a project.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "hostname": "string"
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` is missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `InternalError`: If the server fails to retrieve the hostname.

#### `project.buildIso(project_id: string)`

*   **Description:** Initiates the ISO build process for a project. This is an asynchronous operation.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "build_id": "string", // Unique identifier for this specific build instance
        "status": "string" // Initial status, e.g., "queued" or "starting"
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` is missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `ProjectNotConfigured`: If the project is missing required configuration (e.g., packages).
    *   `BuildInProgress`: If a build is already in progress for this project.
    *   `InternalError`: If the server fails to start the build.

#### `project.streamBuildOutput(project_id: string, build_id: string)`

*   **Description:** Streams live build output for a given build. This might be implemented as a WebSocket connection or long-polling HTTP requests that return chunks of log data. The exact mechanism is TBD, but the conceptual command is listed here.
    *Alternatively, this could be part of the `project.buildIso` response if using WebSockets, or events pushed from the server.*
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
    *   `build_id` (string): The unique identifier of the build (obtained from `project.buildIso`).
*   **Expected Response:** (Stream of data, format TBD, e.g., JSON lines)
    ```json // Example line
    { "type": "log", "message": "Building package xyz..." }
    { "type": "progress", "percentage": 25 }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` or `build_id` are missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `BuildNotFound`: If no build exists for the given `build_id`.
    *   `StreamError`: If there's an issue establishing or maintaining the stream.

#### `project.getBuildStatus(project_id: string, build_id: string)`

*   **Description:** Retrieves the current status of a specific build.
*   **Parameters:**
    *   `project_id` (string): The unique identifier of the project.
    *   `build_id` (string): The unique identifier of the build (obtained from `project.buildIso`).
*   **Expected Response:**
    ```json
    {
      "jsonrpc": "2.0",
      "result": {
        "build_id": "string",
        "status": "string", // e.g., "queued", "running", "completed", "failed"
        "progress": "integer", // Optional: percentage completion (0-100)
        "error_message": "string" // Optional: present if status is "failed"
        // "download_url": "string" // Optional: present if status is "completed"
      },
      "id": "request_id"
    }
    ```
*   **Potential Errors:**
    *   `InvalidParams`: If `project_id` or `build_id` are missing or invalid.
    *   `ProjectNotFound`: If no project exists for the given `project_id`.
    *   `BuildNotFound`: If no build exists for the given `build_id`.
    *   `InternalError`: If the server fails to retrieve the build status.

## Common Error Codes (TBD)

*   `-32700 Parse error`
*   `-32600 Invalid Request`
*   `-32601 Method not found`
*   `-32602 Invalid params`
*   `-32603 Internal error`
*   `(Application-specific error codes will be defined here)`
    *   `ProjectNotFound`
    *   `DistroNotFound`
    *   `InvalidPackage`
    *   `InvalidBootloader`
    *   `InvalidHostname`
    *   `BuildInProgress`
    *   `ProjectNotConfigured`
    *   `BuildNotFound`
    *   `StreamError`
