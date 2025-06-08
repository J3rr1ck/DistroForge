package plugin

// DetailsResponse represents the data returned by GetDetails.
// This will be expanded based on API.md.
type DetailsResponse struct {
	ProjectID   string   `json:"project_id"`
	DistroID    string   `json:"distro_id"`
	Packages    []string `json:"packages"`
	Bootloader  string   `json:"bootloader"`
	Hostname    string   `json:"hostname"`
	BuildStatus string   `json:"build_status"`
}

// PackagesResponse represents the data returned by GetPackages.
type PackagesResponse struct {
	Packages []string `json:"packages"`
}

// BootloaderResponse represents the data returned by GetBootloader.
type BootloaderResponse struct {
	Bootloader string `json:"bootloader"`
}

// HostnameResponse represents the data returned by GetHostname.
type HostnameResponse struct {
	Hostname string `json:"hostname"`
}

// BuildResponse represents the data returned by BuildISO.
// This will be expanded based on API.md.
type BuildResponse struct {
	BuildID string `json:"build_id"`
	Status  string `json:"status"`
}

// DistroPlugin defines the interface for distribution-specific operations.
// Methods will correspond to the project-specific commands in API.md.
type DistroPlugin interface {
	// GetDistroDetails returns static information about the distribution plugin.
	GetDistroDetails() (DistroDetails, error)

	// CreateProject initializes a new project instance for this distro.
	// It might store some initial state or validate distro-specific parameters.
	CreateProject(projectID string, params map[string]interface{}) error // params can be used for distro-specific creation options

	GetDetails(projectID string) (DetailsResponse, error)
	SetPackages(projectID string, packages []string) error
	GetPackages(projectID string) (PackagesResponse, error)
	SetBootloader(projectID string, bootloader string) error
	GetBootloader(projectID string) (BootloaderResponse, error)
	SetHostname(projectID string, hostname string) error
	GetHostname(projectID string) (HostnameResponse, error)
	BuildISO(projectID string) (BuildResponse, error)
	StreamBuildOutput(projectID string, buildID string) (<-chan []byte, error) // Returns a channel for streaming output
	GetBuildStatus(projectID string, buildID string) (BuildStatusResponse, error)
}

// DistroDetails contains information about a distribution plugin.
type DistroDetails struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

// BuildStatusResponse represents the data returned by GetBuildStatus.
type BuildStatusResponse struct {
	BuildID      string `json:"build_id"`
	Status       string `json:"status"`
	Progress     int    `json:"progress,omitempty"`
	ErrorMessage string `json:"error_message,omitempty"`
	DownloadURL  string `json:"download_url,omitempty"`
}

// PluginManager manages available distribution plugins.
// For now, it's a simple map.
type PluginManager struct {
	plugins map[string]DistroPlugin
}

// NewPluginManager creates a new PluginManager.
func NewPluginManager() *PluginManager {
	return &PluginManager{
		plugins: make(map[string]DistroPlugin),
	}
}

// RegisterPlugin adds a plugin to the manager.
func (pm *PluginManager) RegisterPlugin(id string, plugin DistroPlugin) {
	pm.plugins[id] = plugin
}

// GetPlugin retrieves a plugin by its ID.
func (pm *PluginManager) GetPlugin(id string) (DistroPlugin, bool) {
	plugin, found := pm.plugins[id]
	return plugin, found
}

// GetAvailablePlugins returns a list of details for all registered plugins.
func (pm *PluginManager) GetAvailablePlugins() []DistroDetails {
	var details []DistroDetails
	for _, p := range pm.plugins {
		d, err := p.GetDistroDetails() // Assuming GetDistroDetails doesn't fail for valid loaded plugins
		if err == nil { // Should ideally handle this error better
			details = append(details, d)
		}
	}
	return details
}
// TODO: Implement methods for loading plugins (e.g., from disk or compiled in).
// For now, plugins will be registered manually in main.go.
