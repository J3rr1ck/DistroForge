package arch

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"example.com/jsonrpcengine/plugin" // Module path from go.mod
)

// ArchPlugin implements the plugin.DistroPlugin interface for Arch Linux.
type ArchPlugin struct {
	projectsRoot string
	isosRoot     string
	workRoot     string
}

// NewArchPlugin creates and initializes a new ArchPlugin.
// It now determines paths based on the user's home directory.
func NewArchPlugin() (*ArchPlugin, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Printf("Warning: Could not get user home directory (%v), using current directory for .distroforge_data", err)
		// Get current working directory as fallback base
		currentDir, cwdErr := os.Getwd()
		if cwdErr != nil {
			// This is a more serious fallback, unlikely to happen but possible
			log.Printf("Critical: Could not get current working directory (%v), using \".\" as homeDir fallback", cwdErr)
			homeDir = "."
		} else {
			homeDir = currentDir
		}
		// To avoid cluttering the current directory directly if it's a fallback,
		// still use a subdirectory.
		homeDir = filepath.Join(homeDir, ".distroforge_data_fallback")
		log.Printf("Fallback data directory will be: %s", homeDir)
	}

	projectsRoot := filepath.Join(homeDir, ".distroforge", "projects")
	isosRoot := filepath.Join(homeDir, ".distroforge", "isos")
	workRoot := filepath.Join(homeDir, ".distroforge", "work", "archiso")

	for _, path := range []string{projectsRoot, isosRoot, workRoot} {
		if err := os.MkdirAll(path, 0755); err != nil {
			return nil, fmt.Errorf("failed to create directory %s: %w", path, err)
		}
	}

	log.Printf("ArchPlugin initialized with paths: projectsRoot=%s, isosRoot=%s, workRoot=%s", projectsRoot, isosRoot, workRoot)

	return &ArchPlugin{
		projectsRoot: projectsRoot,
		isosRoot:     isosRoot,
		workRoot:     workRoot,
	}, nil
}

// GetDistroDetails returns static information about the Arch Linux plugin.
func (p *ArchPlugin) GetDistroDetails() (plugin.DistroDetails, error) {
	return plugin.DistroDetails{
		ID:          "arch",
		Name:        "Arch Linux",
		Description: "Plugin for building Arch Linux ISOs using mkarchiso.",
	}, nil
}

func (p *ArchPlugin) projectProfilePath(projectID string) string {
	return filepath.Join(p.projectsRoot, projectID, "arch_profile")
}

// CreateProject initializes a new Arch Linux project.
func (p *ArchPlugin) CreateProject(projectID string, params map[string]interface{}) error {
	profilePath := p.projectProfilePath(projectID)
	airootfsPath := filepath.Join(profilePath, "airootfs")

	if err := os.MkdirAll(airootfsPath, 0755); err != nil {
		return fmt.Errorf("failed to create project directory %s: %w", airootfsPath, err)
	}

	packagesFile := filepath.Join(profilePath, "packages.x86_64")
	defaultPackages := []byte("base\nlinux\nxf86-video-vesa\n") // Added vesa for better fallback graphics
	if err := os.WriteFile(packagesFile, defaultPackages, 0644); err != nil {
		return fmt.Errorf("failed to write packages.x86_64: %w", err)
	}

	// profiledef.sh content now uses projectID for uniqueness in iso_name and iso_label
	profileDefFile := filepath.Join(profilePath, "profiledef.sh")
	profileDefContent := []byte(fmt.Sprintf(`#!/usr/bin/env bash
# shellcheck disable=SC2034
iso_name="archlinux-%s"
iso_label="ARCH_%s"
iso_publisher="Arch Linux Custom Build"
iso_application="Arch Linux Live/Rescue Image"
iso_version="$(date +%%Y.%%m.%%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-x64.grub.esp' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
)
# More configurations can be added here
`, projectID, strings.ToUpper(projectID))) // Ensure label is valid (e.g. uppercase)
	if err := os.WriteFile(profileDefFile, profileDefContent, 0755); err != nil {
		return fmt.Errorf("failed to write profiledef.sh: %w", err)
	}

	pacmanConfFile := filepath.Join(profilePath, "pacman.conf")
	// A very basic pacman.conf. For a real build, this needs to be more robust,
	// potentially copying from host or allowing user customization.
	// IMPORTANT: mkarchiso needs a valid mirrorlist. This basic conf assumes
	// the build environment (container/VM) has /etc/pacman.d/mirrorlist correctly set up.
	pacmanConfContent := []byte(`[options]
HoldPkg     = pacman glibc
Architecture = auto
SigLevel    = Never

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist
`)
	if err := os.WriteFile(pacmanConfFile, pacmanConfContent, 0644); err != nil {
		return fmt.Errorf("failed to write pacman.conf: %w", err)
	}
	return nil
}

func (p *ArchPlugin) GetDetails(projectID string) (plugin.DetailsResponse, error) {
	profilePath := p.projectProfilePath(projectID)
	if _, err := os.Stat(profilePath); os.IsNotExist(err) {
		return plugin.DetailsResponse{}, fmt.Errorf("project %s not found: %w", projectID, err)
	}

	packagesResp, _ := p.GetPackages(projectID) // Errors ignored for now, default to empty
	hostnameResp, _ := p.GetHostname(projectID)
	bootloaderResp, _ := p.GetBootloader(projectID)
	buildStatusResp, _ := p.GetBuildStatus(projectID, projectID) // Use projectID as a simple buildID

	return plugin.DetailsResponse{
		ProjectID:   projectID,
		DistroID:    "arch",
		Packages:    packagesResp.Packages,
		Bootloader:  bootloaderResp.Bootloader,
		Hostname:    hostnameResp.Hostname,
		BuildStatus: buildStatusResp.Status,
	}, nil
}

func (p *ArchPlugin) SetPackages(projectID string, packages []string) error {
	profilePath := p.projectProfilePath(projectID)
	packagesFile := filepath.Join(profilePath, "packages.x86_64")
	var content strings.Builder
	for _, pkg := range packages {
		content.WriteString(pkg)
		content.WriteString("\n")
	}
	if err := os.WriteFile(packagesFile, []byte(content.String()), 0644); err != nil {
		return fmt.Errorf("failed to write packages to %s: %w", packagesFile, err)
	}
	return nil
}

func (p *ArchPlugin) GetPackages(projectID string) (plugin.PackagesResponse, error) {
	profilePath := p.projectProfilePath(projectID)
	packagesFile := filepath.Join(profilePath, "packages.x86_64")
	content, err := os.ReadFile(packagesFile)
	if err != nil {
		if os.IsNotExist(err) { // If file doesn't exist, return empty list
			return plugin.PackagesResponse{Packages: []string{}}, nil
		}
		return plugin.PackagesResponse{}, fmt.Errorf("failed to read packages from %s: %w", packagesFile, err)
	}
	lines := strings.Split(strings.TrimSpace(string(content)), "\n")
	var packageList []string
	for _, line := range lines {
		if line != "" {
			packageList = append(packageList, line)
		}
	}
	return plugin.PackagesResponse{Packages: packageList}, nil
}

func (p *ArchPlugin) SetHostname(projectID string, hostname string) error {
	hostnameFile := filepath.Join(p.projectProfilePath(projectID), ".hostname")
	if err := os.WriteFile(hostnameFile, []byte(hostname), 0644); err != nil {
		return fmt.Errorf("failed to store hostname: %w", err)
	}
	// For actual effect, one would need to add scripts to airootfs/etc/systemd/system/
	// or similar to set the hostname on boot, using this stored value.
	// Example: airootfs/etc/hostname could be written with this value.
	// Or, a first-boot script in airootfs could set it.
	// For `mkarchiso` specifically, you can customize `airootfs/etc/hostname`.
	airootfsHostnameFile := filepath.Join(p.projectProfilePath(projectID), "airootfs", "etc", "hostname")
	if err := os.MkdirAll(filepath.Dir(airootfsHostnameFile), 0755); err != nil {
		return fmt.Errorf("failed to create etc dir in airootfs: %w", err)
	}
	if err := os.WriteFile(airootfsHostnameFile, []byte(hostname+"\n"), 0644); err != nil {
		return fmt.Errorf("failed to write hostname to airootfs/etc/hostname: %w", err)
	}
	return nil
}

func (p *ArchPlugin) GetHostname(projectID string) (plugin.HostnameResponse, error) {
	// Attempt to read from the airootfs/etc/hostname file first, as it's more canonical
	airootfsHostnameFile := filepath.Join(p.projectProfilePath(projectID), "airootfs", "etc", "hostname")
	content, err := os.ReadFile(airootfsHostnameFile)
	if err == nil {
		return plugin.HostnameResponse{Hostname: strings.TrimSpace(string(content))}, nil
	}

	// Fallback to the .hostname file if airootfs/etc/hostname doesn't exist
	hostnameFile := filepath.Join(p.projectProfilePath(projectID), ".hostname")
	content, err = os.ReadFile(hostnameFile)
	if err != nil {
		if os.IsNotExist(err) {
			return plugin.HostnameResponse{Hostname: ""}, nil
		}
		return plugin.HostnameResponse{}, fmt.Errorf("failed to read hostname: %w", err)
	}
	return plugin.HostnameResponse{Hostname: strings.TrimSpace(string(content))}, nil
}

func (p *ArchPlugin) SetBootloader(projectID string, bootloader string) error {
	// Storing the choice. Real implementation requires modifying profiledef.sh bootmodes
	// and ensuring necessary packages (grub, systemd-boot, syslinux) are listed.
	bootloaderFile := filepath.Join(p.projectProfilePath(projectID), ".bootloader")
	if err := os.WriteFile(bootloaderFile, []byte(bootloader), 0644); err != nil {
		return fmt.Errorf("failed to store bootloader choice: %w", err)
	}
	log.Printf("Bootloader for project %s set to '%s'. Manual profiledef.sh adjustment may be needed.", projectID, bootloader)
	return nil
}

func (p *ArchPlugin) GetBootloader(projectID string) (plugin.BootloaderResponse, error) {
	// Reading stored choice. A more advanced version would parse profiledef.sh.
	bootloaderFile := filepath.Join(p.projectProfilePath(projectID), ".bootloader")
	content, err := os.ReadFile(bootloaderFile)
	if err != nil {
		if os.IsNotExist(err) {
			// Try to infer from default profiledef.sh if possible, or return common default
			return plugin.BootloaderResponse{Bootloader: "grub/syslinux"}, nil // Default from template
		}
		return plugin.BootloaderResponse{}, fmt.Errorf("failed to read bootloader choice: %w", err)
	}
	return plugin.BootloaderResponse{Bootloader: strings.TrimSpace(string(content))}, nil
}

// projectBuildLogPath returns the path to the build log file for a given project and build ID.
func (p *ArchPlugin) projectBuildLogPath(projectID string, buildID string) string {
	// For simplicity, using projectID as buildID for now if buildID is empty
	// In a multi-build system, buildID would be distinct.
	effectiveBuildID := buildID
	if effectiveBuildID == "" {
		effectiveBuildID = projectID
	}
	return filepath.Join(p.projectProfilePath(projectID), fmt.Sprintf("build-%s.log", effectiveBuildID))
}


// BuildISO executes mkarchiso. This is a simplified blocking version.
// TODO: Implement non-blocking execution and proper streaming.
func (p *ArchPlugin) BuildISO(projectID string) (plugin.BuildResponse, error) {
	profilePath := p.projectProfilePath(projectID)
	isoOutputDir := filepath.Join(p.isosRoot, projectID)
	workDir := filepath.Join(p.workRoot, projectID)
	buildID := projectID // Simple build ID for now

	for _, path := range []string{isoOutputDir, workDir} {
		if err := os.MkdirAll(path, 0755); err != nil {
			return plugin.BuildResponse{}, fmt.Errorf("failed to create directory %s: %w", path, err)
		}
	}

	// Store initial build status (simplified)
	p.updateBuildStatus(projectID, buildID, "building", "", 0, "")


	logFile, err := os.Create(p.projectBuildLogPath(projectID, buildID))
	if err != nil {
		return plugin.BuildResponse{}, fmt.Errorf("failed to create build log file: %w", err)
	}
	defer logFile.Close()

	cmd := exec.Command("sudo", "mkarchiso", // mkarchiso often needs root for loopback mounts, etc.
		"-v",
		"-w", workDir,
		"-o", isoOutputDir,
		profilePath,
	)
	cmd.Stdout = logFile
	cmd.Stderr = logFile

	log.Printf("Executing command for project %s: %s", projectID, cmd.String())
	log.Printf("Build log: %s", logFile.Name())

	err = cmd.Start()
	if err != nil {
		p.updateBuildStatus(projectID, buildID, "failed", fmt.Sprintf("Failed to start mkarchiso: %v", err), 0, "")
		return plugin.BuildResponse{}, fmt.Errorf("mkarchiso failed to start: %w", err)
	}

	// This is still somewhat blocking for the purpose of the JSON-RPC call,
	// but the actual build runs in a subprocess. A true non-blocking approach
	// would return immediately and update status via background goroutine.
	go func() {
		err := cmd.Wait()
		if err != nil {
			log.Printf("mkarchiso project %s (build %s) failed: %v", projectID, buildID, err)
			p.updateBuildStatus(projectID, buildID, "failed", err.Error(), 0, "")
		} else {
			isoNamePattern := fmt.Sprintf("archlinux-%s-*.iso", projectID)
			matches, _ := filepath.Glob(filepath.Join(isoOutputDir, isoNamePattern))
			if len(matches) > 0 {
				downloadURL := fmt.Sprintf("/isos/%s/%s", projectID, filepath.Base(matches[0]))
				p.updateBuildStatus(projectID, buildID, "completed", "", 100, downloadURL)
				log.Printf("mkarchiso project %s (build %s) completed. ISO: %s", projectID, buildID, matches[0])
			} else {
				p.updateBuildStatus(projectID, buildID, "failed", "Build succeeded but ISO not found", 0, "")
				log.Printf("mkarchiso project %s (build %s) completed but no ISO found matching pattern %s in %s.", projectID, buildID, isoNamePattern, isoOutputDir)
			}
		}
	}()

	return plugin.BuildResponse{BuildID: buildID, Status: "building"}, nil
}

// StreamBuildOutput provides a channel to stream lines from the build log.
func (p *ArchPlugin) StreamBuildOutput(projectID string, buildID string) (<-chan []byte, error) {
	logPath := p.projectBuildLogPath(projectID, buildID)
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("build log for project %s build %s not found", projectID, buildID)
	}

	outputChan := make(chan []byte)

	// This is a simplified streaming: it will try to stream the current content
	// and then new content as it's written. True real-time tailing is more complex.
	go func() {
		defer close(outputChan)
		file, err := os.Open(logPath)
		if err != nil {
			log.Printf("Error opening log file for streaming: %v", err)
			return
		}
		defer file.Close()

		reader := bufio.NewReader(file)
		for {
			line, err := reader.ReadBytes('\n')
			if len(line) > 0 {
				outputChan <- line
			}
			if err == io.EOF {
				// Check build status, if completed or failed, stop streaming.
				// This requires access to the build status or a way to signal completion.
				// For this example, we'll just sleep and try again for a while.
				// A more robust solution would use fsnotify or a similar mechanism.
				status, _ := p.GetBuildStatus(projectID, buildID)
				if status.Status == "completed" || status.Status == "failed" {
					break
				}
				time.Sleep(1 * time.Second) // Poll for new lines
			} else if err != nil {
				log.Printf("Error reading log file line: %v", err)
				break
			}
		}
	}()
	return outputChan, nil
}

// buildStatusStore is a simple in-memory store for build statuses.
// In a real app, this would be persistent (e.g., database, Redis).
var buildStatusStore = make(map[string]plugin.BuildStatusResponse)
var buildStatusMutex = &sync.Mutex{}

func (p *ArchPlugin) updateBuildStatus(projectID, buildID, status, errMsg string, progress int, downloadURL string) {
	buildStatusMutex.Lock()
	defer buildStatusMutex.Unlock()
	key := projectID + "_" + buildID
	buildStatusStore[key] = plugin.BuildStatusResponse{
		BuildID:      buildID,
		Status:       status,
		Progress:     progress,
		ErrorMessage: errMsg,
		DownloadURL:  downloadURL,
	}
}


func (p *ArchPlugin) GetBuildStatus(projectID string, buildID string) (plugin.BuildStatusResponse, error) {
	buildStatusMutex.Lock()
	defer buildStatusMutex.Unlock()
	key := projectID + "_" + buildID
	status, found := buildStatusStore[key]
	if !found {
		// If not in store, check if an old ISO exists (very rough heuristic for pre-existing builds)
		isoNamePattern := fmt.Sprintf("archlinux-%s-*.iso", projectID)
		isoDir := filepath.Join(p.isosRoot, projectID)
		matches, _ := filepath.Glob(filepath.Join(isoDir, isoNamePattern))
		if len(matches) > 0 {
			return plugin.BuildStatusResponse{
				BuildID:     buildID,
				Status:      "completed",
				DownloadURL: fmt.Sprintf("/isos/%s/%s", projectID, filepath.Base(matches[0])),
				Progress: 100,
			}, nil
		}
		return plugin.BuildStatusResponse{BuildID: buildID, Status: "unknown"}, nil
	}
	return status, nil
}

var _ plugin.DistroPlugin = (*ArchPlugin)(nil)
// Required imports: bufio, io, sync, time (for StreamBuildOutput and GetBuildStatus with polling/mutex)
