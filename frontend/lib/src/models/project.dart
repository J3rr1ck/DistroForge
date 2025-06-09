class Project {
  final String id;
  final String name;
  final String distroId;
  // Add other relevant fields like description, creationDate, lastBuildStatus, etc.

  Project({
    required this.id,
    required this.name,
    required this.distroId,
  });

  // Optional: Factory constructor for JSON serialization if needed later
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      distroId: json['distro_id'] as String,
    );
  }

  // Optional: Method for JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'distro_id': distroId,
    };
  }
}
