import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import '../models/grade_period.dart';
import '../models/grade_row.dart';

class GradeCheckApi {
  GradeCheckApi({required this.endpointUrl});

  final String endpointUrl;

  Uri get _checkUri => Uri.parse(endpointUrl);

  Uri get parseExcelUri => _siblingUri('parse_excel.php');

  Uri get periodsUri => _siblingUri('periods.php');

  Uri get exportExcelUri => _siblingUri('export_excel.php');

  Uri _siblingUri(String fileName) {
    final uri = _checkUri;
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty) {
      segments[segments.length - 1] = fileName;
      return uri.replace(pathSegments: segments);
    }
    return uri.replace(path: '/grades_checker_api/$fileName');
  }


  Future<List<GradeRow>> parseExcelHtmlFile({
    required html.File file,
    required String schoolYear,
    required String semester,
    required String periodId,
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    void Function(String phase)? onPhase,
  }) async {
    final completer = Completer<List<GradeRow>>();
    final request = html.HttpRequest();
    final formData = html.FormData()
      ..append('school_year', schoolYear)
      ..append('semester', semester)
      ..append('period_id', periodId)
      ..appendBlob('excel', file, file.name);

    request.open('POST', parseExcelUri.toString());
    request.setRequestHeader('Accept', 'application/json');

    request.upload.onProgress.listen((event) {
      final int totalBytes = event.lengthComputable
          ? (event.total ?? file.size)
          : file.size;
      final int loadedBytes = event.loaded ?? 0;
      if (totalBytes > 0) {
        onUploadProgress?.call(loadedBytes, totalBytes);
      }
    });

    request.onLoad.listen((_) async {
      try {
        onPhase?.call('Decoding parsed Excel response');
        await Future<void>.delayed(Duration.zero);
        final int status = request.status ?? 0;
        final body = request.responseText ?? '';
        if (status < 200 || status >= 300) {
          throw Exception('API error $status: $body');
        }
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        if (decoded['ok'] != true) {
          throw Exception(decoded['message']?.toString() ?? 'Unable to parse Excel on server.');
        }
        final rawRows = (decoded['rows'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);

        onPhase?.call('Building local preview rows');
        await Future<void>.delayed(Duration.zero);

        final rows = <GradeRow>[];
        for (var i = 0; i < rawRows.length; i++) {
          rows.add(GradeRow.fromParsedJson(rawRows[i]));
          if (i % 2000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        completer.complete(rows);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }
    });

    request.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Upload failed. Check Apache, PHP upload limits, and the API URL.'));
      }
    });

    request.onAbort.listen((_) {
      if (!completer.isCompleted) completer.completeError(Exception('Upload was cancelled.'));
    });

    request.send(formData);
    return completer.future.timeout(const Duration(minutes: 6));
  }

  Future<List<GradeRow>> parseExcelFile({
    required List<int> bytes,
    required String fileName,
    required String schoolYear,
    required String semester,
    required String periodId,
  }) async {
    final request = http.MultipartRequest('POST', parseExcelUri)
      ..fields['school_year'] = schoolYear
      ..fields['semester'] = semester
      ..fields['period_id'] = periodId
      ..files.add(http.MultipartFile.fromBytes('excel', bytes, filename: fileName));

    final streamed = await request.send().timeout(const Duration(minutes: 4));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('API error ${streamed.statusCode}: $body');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to parse Excel on server.');
    }

    return (decoded['rows'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(GradeRow.fromParsedJson)
        .toList(growable: false);
  }

  Future<List<GradeRow>> parseExcelStream({
    required Stream<List<int>> stream,
    required int length,
    required String fileName,
    required String schoolYear,
    required String semester,
    required String periodId,
  }) async {
    final request = http.MultipartRequest('POST', parseExcelUri)
      ..fields['school_year'] = schoolYear
      ..fields['semester'] = semester
      ..fields['period_id'] = periodId
      ..files.add(http.MultipartFile('excel', stream, length, filename: fileName));

    final streamed = await request.send().timeout(const Duration(minutes: 4));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('API error ${streamed.statusCode}: $body');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to parse Excel on server.');
    }

    return (decoded['rows'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(GradeRow.fromParsedJson)
        .toList(growable: false);
  }


  Future<List<int>> exportExcel({
    required List<Map<String, dynamic>> students,
    required Map<String, dynamic> summary,
    required String periodLabel,
    required String fileName,
    String interpretation = '',
  }) async {
    final response = await http
        .post(
          exportExcelUri,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/vnd.ms-excel',
          },
          body: jsonEncode({
            'period_label': periodLabel,
            'source_file': fileName,
            'summary': summary,
            'interpretation': interpretation,
            'students': students,
          }),
        )
        .timeout(const Duration(minutes: 4));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }

    return response.bodyBytes;
  }

  bool _isAllowedSmsSemester(String semester) {
    final normalized = semester.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (normalized.contains('tri') || normalized.contains('trimester') || normalized.contains('3rd') || normalized.contains('third')) {
      return false;
    }
    return normalized == '1' ||
        normalized == '1st' ||
        normalized.contains('1stsem') ||
        normalized.contains('first') ||
        normalized == '2' ||
        normalized == '2nd' ||
        normalized.contains('2ndsem') ||
        normalized.contains('second') ||
        normalized.contains('summer');
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
        .where((period) => period.id.isNotEmpty && _isAllowedSmsSemester(period.semester))
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
