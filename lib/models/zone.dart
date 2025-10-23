import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'report.dart';

class Zone {
  final int id;
  final LatLng center;
  final double averageRisk;
  final int reportCount;

  const Zone({
    required this.id,
    required this.center,
    required this.averageRisk,
    required this.reportCount,
  });

  factory Zone.fromJson(Map<String, dynamic> json) {
    return Zone(
      id: json['id'] as int,
      center: LatLng(
        (json['center_latitude'] as num).toDouble(),
        (json['center_longitude'] as num).toDouble(),
      ),
      averageRisk: (json['average_risk'] as num).toDouble(),
      reportCount: json['report_count'] as int,
    );
  }

  RiskLevel get riskLevel {
    if (averageRisk < 1.5) return RiskLevel.low;
    if (averageRisk < 2.5) return RiskLevel.medium;
    return RiskLevel.high;
  }

  Color get color {
    switch (riskLevel) {
      case RiskLevel.low:
        return Colors.green.withValues(alpha: 0.25);
      case RiskLevel.medium:
        return Colors.orange.withValues(alpha: 0.35);
      case RiskLevel.high:
        return Colors.red.withValues(alpha: 0.35);
    }
  }
}
