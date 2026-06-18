import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import '../models/grade_period.dart';
import '../models/grade_row.dart';

class GradeCheckerAuthSession {
  const GradeCheckerAuthSession({
    required this.token,
    required this.username,
    required this.displayName,
    required this.role,
  });

  final String token;
  final String username;
  final String displayName;
  final String role;
}



class InsertSmsGradeResult {
  const InsertSmsGradeResult({
    required this.created,
    required this.message,
    required this.reference,
  });

  final bool created;
  final String message;
  final String reference;
}

class CreateStudentProfileResult {
  const CreateStudentProfileResult({
    required this.created,
    required this.message,
    required this.student,
  });

  final bool created;
  final String message;
  final Map<String, dynamic> student;
}


class CourseOption {
  const CourseOption({
    required this.id,
    required this.code,
    required this.name,
    required this.major,
    required this.status,
  });

  final String id;
  final String code;
  final String name;
  final String major;
  final String status;

  String get displayLabel {
    final parts = <String>[];
    if (code.trim().isNotEmpty) parts.add(code.trim());
    if (name.trim().isNotEmpty) parts.add(name.trim());
    return parts.isEmpty ? 'Course #$id' : parts.join(' - ');
  }

  factory CourseOption.fromJson(Map<String, dynamic> json) {
    return CourseOption(
      id: json['course_id']?.toString() ?? '',
      code: json['course_code']?.toString() ?? '',
      name: json['course_name']?.toString() ?? '',
      major: json['course_major']?.toString() ?? '',
      status: json['course_status']?.toString() ?? '',
    );
  }
}

class GradeCheckApi {
  GradeCheckApi({required this.endpointUrl, this.authToken});

  final String endpointUrl;
  final String? authToken;

  Uri get _checkUri => Uri.parse(endpointUrl);

  Uri get parseExcelUri => _siblingUri('parse_excel.php');

  Uri get periodsUri => _siblingUri('periods.php');

  Uri get exportExcelUri => _siblingUri('export_excel.php');

  Uri get loginUri => _siblingUri('login.php');

  Uri get createStudentProfileUri => _siblingUri('create_student_profile.php');

  Uri get coursesUri => _siblingUri('courses.php');

  Uri get insertGradeUri => _siblingUri('insert_grade.php');



  Map<String, String> get _jsonHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = authToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, String> get _acceptJsonHeaders {
    final headers = <String, String>{'Accept': 'application/json'};
    final token = authToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, String> get _exportHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/vnd.ms-excel',
    };
    final token = authToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<GradeCheckerAuthSession> login({required String username, required String password}) async {
    final response = await http
        .post(
          loginUri,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'username': username,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Login failed: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Login failed.');
    }

    final user = decoded['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final token = decoded['token']?.toString() ?? '';
    if (token.isEmpty) throw Exception('Login did not return an access token.');

    return GradeCheckerAuthSession(
      token: token,
      username: user['username']?.toString() ?? username,
      displayName: user['display_name']?.toString() ?? username,
      role: user['role']?.toString() ?? 'user',
    );
  }

  Uri _siblingUri(String fileName) {
    final uri = _checkUri;
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty) {
      segments[segments.length - 1] = fileName;
      return uri.replace(pathSegments: segments);
    }
    return uri.replace(path: '/grades_checker_api/$fileName');
  }

  Exception _apiError(int status, String body, {String fallback = 'API error'}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final rawMessage = decoded['message']?.toString();
        final rawExpectedFormat = decoded['expected_format']?.toString();
        final message = rawMessage?.trim();
        final expectedFormat = rawExpectedFormat?.trim();
        if (message != null && message.isNotEmpty) {
          return Exception(expectedFormat == null || expectedFormat.isEmpty ? message : '$message Expected: $expectedFormat');
        }
      }
    } catch (_) {
      // Keep the raw body below when the API did not return JSON.
    }
    return Exception('$fallback $status: $body');
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
    final token = authToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.setRequestHeader('Authorization', 'Bearer $token');
    }

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
        onPhase?.call('Decoding UNO response');
        await Future<void>.delayed(Duration.zero);
        final int status = request.status ?? 0;
        final body = request.responseText ?? '';
        if (status < 200 || status >= 300) {
          throw _apiError(status, body);
        }
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        if (decoded['ok'] != true) {
          throw Exception(decoded['message']?.toString() ?? 'Unable to parse UNO file on server.');
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
      ..headers.addAll(_acceptJsonHeaders)
      ..fields['school_year'] = schoolYear
      ..fields['semester'] = semester
      ..fields['period_id'] = periodId
      ..files.add(http.MultipartFile.fromBytes('excel', bytes, filename: fileName));

    final streamed = await request.send().timeout(const Duration(minutes: 4));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw _apiError(streamed.statusCode, body);
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to parse UNO file on server.');
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
      ..headers.addAll(_acceptJsonHeaders)
      ..fields['school_year'] = schoolYear
      ..fields['semester'] = semester
      ..fields['period_id'] = periodId
      ..files.add(http.MultipartFile('excel', stream, length, filename: fileName));

    final streamed = await request.send().timeout(const Duration(minutes: 4));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw _apiError(streamed.statusCode, body);
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to parse UNO file on server.');
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
          headers: _exportHeaders,
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
      throw _apiError(response.statusCode, response.body);
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
        .get(periodsUri, headers: _acceptJsonHeaders)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, response.body);
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



  Future<List<CourseOption>> fetchCourses() async {
    final response = await http
        .get(coursesUri, headers: _acceptJsonHeaders)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to load courses.');
    }

    return (decoded['courses'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CourseOption.fromJson)
        .where((course) => course.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<CreateStudentProfileResult> createStudentProfile({
    required String studentId,
    required String firstName,
    required String middleName,
    required String lastName,
    String courseId = '',
    required String course,
    required String yearLevel,
    String gender = '',
    String birthDate = '',
  }) async {
    final response = await http
        .post(
          createStudentProfileUri,
          headers: _jsonHeaders,
          body: jsonEncode({
            'student_id': studentId,
            'first_name': firstName,
            'middle_name': middleName,
            'last_name': lastName,
            'course_id': courseId,
            'course': course,
            'year_level': yearLevel,
            'gender': gender,
            'birthdate': birthDate,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to create student profile.');
    }

    return CreateStudentProfileResult(
      created: decoded['created'] == true,
      message: decoded['message']?.toString() ?? 'Student profile saved.',
      student: decoded['student'] is Map<String, dynamic>
          ? decoded['student'] as Map<String, dynamic>
          : <String, dynamic>{},
    );
  }


  Future<InsertSmsGradeResult> insertSmsGrade({
    required String studentId,
    required String subjectId,
    required String periodId,
    required String grade,
    required String credits,
    required String course,
    required String yearLevel,
    required int subjectNo,
  }) async {
    final response = await http
        .post(
          insertGradeUri,
          headers: _jsonHeaders,
          body: jsonEncode({
            'student_id': studentId,
            'subject_id': subjectId,
            'period_id': periodId,
            'grade': grade,
            'credits': credits,
            'course': course,
            'year_level': yearLevel,
            'subject_no': subjectNo,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Unable to insert grade.');
    }

    return InsertSmsGradeResult(
      created: decoded['created'] == true,
      message: decoded['message']?.toString() ?? 'Grade saved.',
      reference: decoded['sg_id']?.toString() ?? '',
    );
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
            headers: _jsonHeaders,
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
