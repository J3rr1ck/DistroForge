# DistroForge- A Modular, Multi-Distro Linux Remastering Tool

DistroForge is a next-generation, user-friendly application for customizing and remastering Linux distributions across multiple bases.

It features a beautiful and modern user interface built with **Flutter**, providing a seamless experience on any desktop. The powerful backend engine, written in **Go**, handles all the complex, distro-specific operations, ensuring robust and reliable performance.

**Key Features:**

*   **Flutter-Powered GUI:** A beautiful, responsive, and cross-platform user interface that works on Linux, Windows, and macOS.
*   **Go Backend Engine:** A powerful and portable command-line engine that does the heavy lifting, interacting with native tools like `mkarchiso`, `live-build`, and `lorax`.
*   **Modular Backend:** A flexible architecture where each distro family is a self-contained plugin, allowing for tailored support and easier expansion.
*   **Cross-Distro Support (Phased Rollout):**
    *   **Phase 1 Target:** Arch Linux & derivatives (Manjaro, EndeavourOS).
    *   **Future Phases:** Debian/Ubuntu, Fedora (RPM), and Fedora Atomic (ostree).
*   **Release-Oriented Workflow:** Project-based management makes it simple to maintain multiple distro variants, update their base, and build new releases with a single click.

**Development Philosophy: Arch First, Flutter + Go**

We will build a solid foundation by focusing on a single, clean architecture: a Flutter UI communicating with a Go backend. Our initial development will target full support for Arch Linux to prove this model. Once perfected, we will rapidly expand to other distro families by adding new modules to our Go engine, with minimal changes required for the Flutter UI.

### 2. Development Plan / TODO

#### Phase 1: The Go Backend Engine & Arch Linux Core

This phase focuses exclusively on the non-UI part of the application, starting with Arch Linux support.

*   **[TODO] Define the JSON-RPC API:**
    *   Specify a clear, versioned JSON-RPC protocol for communication between the Flutter UI and the Go backend.
    *   Define commands like `engine.getDistroPlugins()`, `engine.createProject('arch')`, `project.installPackages(['package-a', 'package-b'])`, `project.buildIso()`, etc.
*   **[TODO] Implement the Go Command-Line Engine:**
    *   Create the main Go application that will parse the JSON-RPC commands.
    *   Design the plugin system in Go. Create an `interface` that all distro plugins (`arch.go`, `debian.go`) must implement.
*   **[TODO] Develop the Arch Linux Go Plugin:**
    *   Create the first plugin for Arch Linux.
    *   This plugin will be responsible for:
        *   Creating and managing `mkarchiso` profile directories.
        *   Programmatically editing the `packages.x86_64` file.
        *   Managing the `airootfs` directory.
        *   Executing `mkarchiso` as a subprocess and streaming its output (stdout/stderr) back to the caller over JSON-RPC.
*   **[TODO] Create a Simple CLI for Testing:**
    *   Build a simple command-line client (in any language) that can send JSON-RPC commands to the Go engine. This is crucial for testing the backend independently of the UI.

#### Phase 2: The Flutter UI

Now, we build the user-facing part of the application.

*   **[TODO] Set Up the Flutter Desktop Project:**
    *   Initialize a new Flutter project with support for Linux, Windows, and macOS enabled.
*   **[TODO] Design the Core UI Components:**
    *   Create the main layout, project creation dialog, and settings page.
    *   Use a state management solution (like Provider, Riverpod, or BLoC) to handle the application state.
*   **[TODO] Implement UI-to-Engine Communication:**
    *   Write a "service" or "repository" class in Dart that handles the JSON-RPC communication with the Go backend engine.
    *   This service will be responsible for starting the Go engine as a subprocess and communicating with it over `stdin`/`stdout`.
*   **[TODO] Build the Arch-Specific UI:**
    *   Develop the UI for an "Arch Project." This will include:
        *   A package list view.
        *   A simple file browser for the `airootfs`.
        *   A text editor view for configuration files.
        *   A "Build" button that triggers the `project.buildIso()` command.
        *   A console view that displays the real-time build output received from the Go engine.

#### Phase 3: Expansion to Other Distros

With the architecture proven, we can now easily add support for other distributions.

*   **[TODO] Develop the Debian/Ubuntu Go Plugin:**
    *   Create a new `debian.go` plugin that implements the standard plugin interface.
    *   This plugin will wrap tools like `live-build` and `debootstrap`.
*   **[TODO] Develop the Fedora Go Plugin:**
    *   Create a `fedora.go` plugin, wrapping `lorax` and the Kickstart file format.
*   **[TODO] Enhance the Flutter UI for Multi-Distro Support:**
    *   The project creation dialog will now list all available distro plugins returned by `engine.getDistroPlugins()`.
    *   The UI will adapt based on the project type, showing relevant options (e.g., "Edit Kickstart File" for Fedora, "Configure Pre-seeding" for Debian). This can be done by having the Go engine tell the UI which features are supported for the active plugin.
