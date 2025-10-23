import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum RiskLevel { low, medium, high }

class Report {
  final int? id;
  final String userId;
  final LatLng position;
  final RiskLevel riskLevel;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  Report({
    this.id,
    required this.userId,
    required this.position,
    required this.riskLevel,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'],
      userId: json['user_id'],
      position: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      riskLevel: RiskLevel.values[((json['risk_level'] as num).toInt()) - 1],
      description: json['description'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'risk_level': riskLevel.index + 1,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Color get color {
    switch (riskLevel) {
      case RiskLevel.low:
        return Colors.green;
      case RiskLevel.medium:
        return Colors.orange;
      case RiskLevel.high:
        return Colors.red;
    }
  }
}
