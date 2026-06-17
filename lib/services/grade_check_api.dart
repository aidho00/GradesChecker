import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/grade_period.dart';
import '../models/grade_row.dart';

class GradeCheckApi {
  GradeCheckApi({required this.endpointUrl});

  final String endpointUrl;

  Uri get _checkUri => Uri.parse(endpointUrl);

  Uri get periodsUri {
    final uri = _checkUri;
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty) {
      segments[segments.length - 1] = 'periods.php';
      return uri.replace(pathSegments: segments);
    }
    return uri.replace(path: '/grades_checker_api/periods.php');
  }

  Future<List<GradePeriod>> fetchPeriods() async {
    final response = await http
        .get(periodsUri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to load periods.');
    }

    return (decoded['periods'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(GradePeriod.fromJson)
        .where((period) => period.id.isNotEmpty)
        .toList();
  }

  Future<List<GradeRow>> checkRows({
    required List<GradeRow> rows,
    required String periodId,
    int chunkSize = 500,
    void Function(int checked, int total)? onProgress,
    void Function(int startIndex, List<GradeRow> checkedChunk)? onChunkChecked,
  }) async {
    final checkedRows = <GradeRow>[];
    var processed = 0;

    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = (start + chunkSize > rows.length) ? rows.length : start + chunkSize;
      final chunk = rows.sublist(start, end);

      final response = await http
          .post(
            _checkUri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'period_id': periodId,
              'rows': chunk.map((row) => row.toApiJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('API error ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        throw Exception(decoded['message']?.toString() ?? 'Unknown API error.');
      }

      final results = (decoded['results'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      final checkedChunk = <GradeRow>[];
      for (var i = 0; i < chunk.length; i++) {
        final result = i < results.length ? results[i] : <String, dynamic>{};
        checkedChunk.add(chunk[i].copyWithCheckResult(result));
      }

      checkedRows.addAll(checkedChunk);
      processed += chunk.length;
      onChunkChecked?.call(start, checkedChunk);
      onProgress?.call(processed, rows.length);

      // Give Flutter Web time to repaint progress and keep pointer/scroll responsive.
      await Future<void>.delayed(Duration.zero);
    }

    return checkedRows;
  }
}
