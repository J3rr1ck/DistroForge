class Distro {
  final String id;
  final String name;
  final String description;
  // Add other relevant fields like iconPath, supportedFeatures, etc.

  Distro({
    required this.id,
    required this.name,
    required this.description,
  });

  // Optional: Factory constructor for JSON serialization if needed later
  factory Distro.fromJson(Map<String, dynamic> json) {
    return Distro(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '', // Handle missing description
    );
  }

  // Optional: Method for JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }
}
