import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/grade_row.dart';

class GradeCheckApi {
  GradeCheckApi({required this.endpointUrl});

  final String endpointUrl;

  Future<List<GradeRow>> checkRows({
    required List<GradeRow> rows,
    int chunkSize = 250,
    void Function(int checked, int total)? onProgress,
  }) async {
    final checkedRows = <GradeRow>[];
    var processed = 0;

    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = (start + chunkSize > rows.length) ? rows.length : start + chunkSize;
      final chunk = rows.sublist(start, end);
      final uri = Uri.parse(endpointUrl);

      final response = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'rows': chunk.map((row) => row.toApiJson()).toList(),
        }),
      );

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

      for (var i = 0; i < chunk.length; i++) {
        final result = i < results.length ? results[i] : <String, dynamic>{};
        checkedRows.add(chunk[i].copyWithCheckResult(result));
      }

      processed += chunk.length;
      onProgress?.call(processed, rows.length);
    }

    return checkedRows;
  }
}
