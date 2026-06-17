class GradePeriod {
  const GradePeriod({
    required this.id,
    required this.name,
    required this.semester,
    required this.status,
    required this.label,
  });

  final String id;
  final String name;
  final String semester;
  final String status;
  final String label;

  factory GradePeriod.fromJson(Map<String, dynamic> json) {
    final id = json['period_id']?.toString() ?? '';
    final name = json['period_name']?.toString() ?? '';
    final semester = json['period_semester']?.toString() ?? '';
    final fallbackLabel = [name, semester]
        .where((part) => part.trim().isNotEmpty)
        .join(' - ');

    return GradePeriod(
      id: id,
      name: name,
      semester: semester,
      status: json['period_status']?.toString() ?? '',
      label: (json['label']?.toString().trim().isNotEmpty ?? false)
          ? json['label'].toString()
          : fallbackLabel,
    );
  }
}
