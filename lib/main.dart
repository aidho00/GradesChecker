import 'dart:async';
import 'dart:collection';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'models/grade_period.dart';
import 'models/grade_row.dart';
import 'services/grade_check_api.dart';

const double _uiScale = 0.78;
const double _kHeaderFontSize = 15.0;
const double _kTableFontSize = 11.0;
const double _kBodyFontSize = 12.0;
const double _kDataRowHeight = 162.0;
double _s(num value) => value * _uiScale;

const List<String> _filterOptions = [
  'All',
  'Existing',
  'Missing',
  'Grade differs',
  'Units differ',
  'Student not found',
  'Subject not found',
  'Duplicate SMS grades',
];

void main() {
  runApp(const GradesCheckerApp());
}

class GradesCheckerApp extends StatelessWidget {
  const GradesCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2563EB);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UNO to SMS Grade Checker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F6FB),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textTheme: ThemeData.light().textTheme,
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_s(14)),
            side: const BorderSide(color: Color(0xFFE5EAF3)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: const TextStyle(fontSize: _kTableFontSize, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
          floatingLabelStyle: const TextStyle(fontSize: _kTableFontSize, color: Color(0xFF475569), fontWeight: FontWeight.w800),
          hintStyle: const TextStyle(fontSize: _kBodyFontSize, color: Color(0xFF64748B)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: _s(10), vertical: _s(10)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_s(10)),
            borderSide: const BorderSide(color: Color(0xFFD9E2F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_s(10)),
            borderSide: const BorderSide(color: Color(0xFFD9E2F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_s(10)),
            borderSide: const BorderSide(color: seed, width: 1.3),
          ),
          isDense: true,
        ),
      ),
      home: const GradesCheckerPage(),
    );
  }
}

class GradesCheckerPage extends StatefulWidget {
  const GradesCheckerPage({super.key});

  @override
  State<GradesCheckerPage> createState() => _GradesCheckerPageState();
}

class _GradesCheckerPageState extends State<GradesCheckerPage> {
  final _apiController = TextEditingController(
    text: 'http://localhost/grades_checker_api/check_grades.php',
  );
  final _searchController = TextEditingController();
  final _horizontalController = ScrollController();
  double _horizontalPixels = 0.0;
  double _horizontalMaxExtent = 0.0;
  double _horizontalViewportDimension = 1.0;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _authToken;
  String _authUsername = '';
  String _authDisplayName = '';
  String _authRole = '';
  bool _obscurePassword = true;
  bool _loggingIn = false;

  List<GradePeriod> _periods = [];
  GradePeriod? _selectedPeriod;
  List<GradeRow> _rows = [];
  List<_StudentGradeGroup> _allGroups = [];
  List<_StudentGradeGroup> _visibleGroups = [];

  String _fileName = '';
  String _status = 'Start by choosing an academic year, then upload the UNO promotional list.';
  String _filter = 'All';
  String? _interpretation;

  bool _isBusy = false;
  bool _loadingPeriods = false;
  int _operationDone = 0;
  int _operationTotal = 0;
  String _operationLabel = '';
  int _pageSize = 50;
  int _pageIndex = 0;

  int _studentCount = 0;
  int _existingCount = 0;
  int _missingCount = 0;
  int _gradeDiffCount = 0;
  int _unitsDiffCount = 0;
  int _studentMissingCount = 0;
  int _subjectMissingCount = 0;
  int _checkedCount = 0;
  int _duplicateGradeCount = 0;


  @override
  void initState() {
    super.initState();
    _restoreSavedSession();
  }

  @override
  void dispose() {
    _apiController.dispose();
    _searchController.dispose();
    _horizontalController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  GradeCheckApi get _api => GradeCheckApi(endpointUrl: _apiController.text.trim(), authToken: _authToken);

  bool get _isLoggedIn => _authToken?.trim().isNotEmpty == true;

  bool get _hasProgress => _isBusy && _operationLabel.trim().isNotEmpty;
  double? get _progressValue {
    if (!_hasProgress || _operationTotal <= 0) return null;
    return (_operationDone / _operationTotal).clamp(0, 1).toDouble();
  }

  double _safeScrollMetric(double value, {double fallback = 0.0}) {
    if (value.isNaN || value.isInfinite) return fallback;
    return value;
  }

  void _updateHorizontalMetrics({
    required double pixels,
    required double maxExtent,
    required double viewportDimension,
  }) {
    if (!mounted) return;

    final nextMax = math.max(0.0, _safeScrollMetric(maxExtent));
    final nextViewport = math.max(1.0, _safeScrollMetric(viewportDimension, fallback: 1.0));
    final nextPixels = _safeScrollMetric(pixels).clamp(0.0, nextMax).toDouble();

    final changed = (nextPixels - _horizontalPixels).abs() > 0.5 ||
        (nextMax - _horizontalMaxExtent).abs() > 0.5 ||
        (nextViewport - _horizontalViewportDimension).abs() > 0.5;
    if (!changed) return;

    setState(() {
      _horizontalPixels = nextPixels;
      _horizontalMaxExtent = nextMax;
      _horizontalViewportDimension = nextViewport;
    });
  }

  void _syncHorizontalMetricsFromController() {
    if (!mounted || !_horizontalController.hasClients) {
      return;
    }
    final position = _horizontalController.position;
    _updateHorizontalMetrics(
      pixels: position.pixels,
      maxExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
    );
  }

  void _queueHorizontalMetricSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHorizontalMetricsFromController();
    });
  }

  int _pageCount(int total) {
    if (total <= 0) return 1;
    return (total / _pageSize).ceil();
  }

  void _refreshDerivedData({bool resetPage = false}) {
    _allGroups = _groupByStudent(_rows);
    _studentCount = _allGroups.length;
    _existingCount = 0;
    _missingCount = 0;
    _gradeDiffCount = 0;
    _unitsDiffCount = 0;
    _studentMissingCount = 0;
    _subjectMissingCount = 0;
    _checkedCount = 0;
    _duplicateGradeCount = 0;

    for (final row in _rows) {
      if (row.existsInDatabase) _existingCount++;
      if (!row.existsInDatabase && row.studentFound == true && row.subjectFound == true) _missingCount++;
      if (row.gradeMatches == false) _gradeDiffCount++;
      if (row.unitsMatch == false) _unitsDiffCount++;
      if (row.studentFound == false) _studentMissingCount++;
      if (row.subjectFound == false) _subjectMissingCount++;
      if (row.studentFound != null || row.subjectFound != null || row.existsInDatabase) _checkedCount++;
      if (row.databaseMatches.length > 1) _duplicateGradeCount++;
    }

    _applyFilterNoSetState(resetPage: resetPage);
  }

  void _applyFilterNoSetState({bool resetPage = true}) {
    final query = _searchController.text.trim().toLowerCase();
    _visibleGroups = _allGroups.where((group) {
      if (!_groupPassesFilter(group)) return false;
      if (query.isEmpty) return true;
      return _groupMatchesSearch(group, query);
    }).toList(growable: false);

    if (resetPage) _pageIndex = 0;
    final pageCount = _pageCount(_visibleGroups.length);
    if (_pageIndex > pageCount - 1) _pageIndex = math.max(0, pageCount - 1);
  }

  bool _groupPassesFilter(_StudentGradeGroup group) {
    return switch (_filter) {
      'Existing' => group.rows.any((row) => row.existsInDatabase && row.gradeMatches != false && row.unitsMatch != false),
      'Missing' => group.rows.any((row) => !row.existsInDatabase && row.studentFound == true && row.subjectFound == true),
      'Grade differs' => group.rows.any((row) => row.gradeMatches == false),
      'Units differ' => group.rows.any((row) => row.unitsMatch == false),
      'Student not found' => group.rows.any((row) => row.studentFound == false),
      'Subject not found' => group.rows.any((row) => row.subjectFound == false),
      'Duplicate SMS grades' => group.rows.any((row) => row.databaseMatches.length > 1),
      _ => true,
    };
  }

  bool _groupMatchesSearch(_StudentGradeGroup group, String query) {
    final studentText = [
      group.studentId,
      group.studentName,
      group.firstName,
      group.lastName,
      group.middleName,
      group.course,
      group.yearLevel,
    ].join(' ').toLowerCase();
    if (studentText.contains(query)) return true;

    for (final row in group.rows) {
      final subjectText = [
        row.subjectCode,
        row.excelSubjectDescription,
        row.subjectDescription ?? '',
        row.excelGrade,
        row.databaseGrade ?? '',
        row.units,
        row.databaseCredits ?? '',
        row.statusLabel,
        row.message ?? '',
        for (final match in row.databaseMatches) '${match.grade} ${match.credits} ${match.subjectDescription} ${match.courseCode}',
      ].join(' ').toLowerCase();
      if (subjectText.contains(query)) return true;
    }
    return false;
  }

  String _rowGroupKey(GradeRow row) {
    return row.studentId.trim().isNotEmpty
        ? row.studentId.trim()
        : '${row.lastName}|${row.firstName}|${row.middleName}';
  }

  List<_StudentGradeGroup> _groupByStudent(List<GradeRow> source) {
    final map = LinkedHashMap<String, _StudentGradeGroup>();
    for (final row in source) {
      final key = _rowGroupKey(row);
      map.putIfAbsent(
        key,
        () => _StudentGradeGroup(
          key: key,
          studentId: row.studentId,
          lastName: row.lastName,
          firstName: row.firstName,
          middleName: row.middleName,
          studentName: row.studentName,
          course: row.databaseCourse?.isNotEmpty == true ? row.databaseCourse! : row.course,
          yearLevel: row.yearLevel,
          birthDate: row.birthDate,
          excelRowNumber: row.excelRowNumber,
          rows: <GradeRow>[],
        ),
      );
      map[key]!.rows.add(row);
    }

    final groups = map.values.toList(growable: false);
    for (final group in groups) {
      group.rows.sort((a, b) => a.subjectNo.compareTo(b.subjectNo));
    }
    return groups;
  }

  Map<String, dynamic> _summaryJson() {
    return {
      'students': _studentCount,
      'subject_records': _rows.length,
      'checked': _checkedCount,
      'existing': _existingCount,
      'missing': _missingCount,
      'grade_differs': _gradeDiffCount,
      'units_differs': _unitsDiffCount,
      'student_not_found': _studentMissingCount,
      'subject_not_found': _subjectMissingCount,
      'duplicate_db_grades': _duplicateGradeCount,
    };
  }

  void _restoreSavedSession() {
    final storage = html.window.localStorage;
    final token = storage['gc_auth_token'] ?? '';
    if (token.trim().isEmpty) return;

    _authToken = token;
    _authUsername = storage['gc_auth_username'] ?? '';
    _authDisplayName = storage['gc_auth_display_name'] ?? _authUsername;
    _authRole = storage['gc_auth_role'] ?? '';
    _status = 'Signed in as ${_authDisplayName.isEmpty ? _authUsername : _authDisplayName}. Loading academic years...';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPeriods();
    });
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _status = 'Enter your SMS username and password.');
      return;
    }

    setState(() {
      _loggingIn = true;
      _status = 'Signing in...';
    });

    try {
      final session = await GradeCheckApi(endpointUrl: _apiController.text.trim()).login(
        username: username,
        password: password,
      );

      html.window.localStorage['gc_auth_token'] = session.token;
      html.window.localStorage['gc_auth_username'] = session.username;
      html.window.localStorage['gc_auth_display_name'] = session.displayName;
      html.window.localStorage['gc_auth_role'] = session.role;

      setState(() {
        _authToken = session.token;
        _authUsername = session.username;
        _authDisplayName = session.displayName;
        _authRole = session.role;
        _passwordController.clear();
        _periods = [];
        _selectedPeriod = null;
        _status = 'Signed in as ${session.displayName}. Loading academic years...';
      });

      await _loadPeriods();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Login failed. $error');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _logout() {
    html.window.localStorage.remove('gc_auth_token');
    html.window.localStorage.remove('gc_auth_username');
    html.window.localStorage.remove('gc_auth_display_name');
    html.window.localStorage.remove('gc_auth_role');

    setState(() {
      _authToken = null;
      _authUsername = '';
      _authDisplayName = '';
      _authRole = '';
      _periods = [];
      _selectedPeriod = null;
      _rows = [];
      _allGroups = [];
      _visibleGroups = [];
      _fileName = '';
      _interpretation = null;
      _refreshDerivedData(resetPage: true);
      _status = 'Signed out. Please login to access Grades Checker.';
    });
  }

  Future<void> _loadPeriods() async {
    if (!_isLoggedIn) {
      setState(() => _status = 'Please login to load academic years.');
      return;
    }

    setState(() {
      _loadingPeriods = true;
      _status = 'Loading academic years from SMS...';
    });

    try {
      final periods = await _api.fetchPeriods();
      GradePeriod? selected;
      for (final period in periods) {
        final label = period.label.toUpperCase();
        if (label.contains('2019-2020') && label.contains('1ST')) {
          selected = period;
          break;
        }
      }
      selected ??= periods.isNotEmpty ? periods.first : null;

      setState(() {
        _periods = periods;
        _selectedPeriod = selected;
        _status = periods.isEmpty
            ? 'No academic years found. Check SMS academic year records and semester names.'
            : 'Selected academic year: ${selected?.label ?? periods.first.label}. Upload the UNO promotional list to continue.';
      });
    } catch (error) {
      setState(() {
        _status = 'Unable to load academic years. Check Apache, SMS connection, and Connection settings. $error';
      });
    } finally {
      if (mounted) setState(() => _loadingPeriods = false);
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final digits = unitIndex == 0 || value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  Future<void> _pickExcel() async {
    if (_selectedPeriod == null) {
      setState(() => _status = 'Please select an academic year first.');
      return;
    }

    final input = html.FileUploadInputElement()
      ..accept = '.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      ..multiple = false;

    final completer = Completer<html.File?>();
    input.onChange.take(1).listen((_) {
      final files = input.files;
      completer.complete(files != null && files.isNotEmpty ? files.first : null);
    });
    input.click();

    final file = await completer.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () => null,
    );

    if (file == null) {
      setState(() => _status = 'File selection cancelled.');
      return;
    }

    await _loadExcelHtmlFile(file);
  }

  Future<void> _loadExcelHtmlFile(html.File file) async {
    final period = _selectedPeriod!;
    final totalBytes = file.size;
    var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

    setState(() {
      _isBusy = true;
      _operationLabel = 'Preparing upload • 0 / ${_formatBytes(totalBytes)}';
      _operationDone = 0;
      _operationTotal = totalBytes;
      _status = 'Uploading the UNO promotional list to the server parser. Upload progress is shown live; the browser does not decode the XLSX locally.';
      _interpretation = null;
      _rows = [];
      _allGroups = [];
      _visibleGroups = [];
      _fileName = file.name;
      _refreshDerivedData(resetPage: true);
    });

    try {
      final parsedRows = await _api.parseExcelHtmlFile(
        file: file,
        schoolYear: period.name,
        semester: period.semester,
        periodId: period.id,
        onUploadProgress: (uploaded, total) {
          final now = DateTime.now();
          if (uploaded < total && now.difference(lastPaint).inMilliseconds < 120) return;
          lastPaint = now;
          if (!mounted) return;
          setState(() {
            _operationDone = uploaded;
            _operationTotal = total;
            _operationLabel = 'Uploading UNO • ${_formatBytes(uploaded)} / ${_formatBytes(total)}';
            _status = 'Uploading ${file.name}... ${_formatBytes(uploaded)} of ${_formatBytes(total)}';
          });
        },
        onPhase: (phase) {
          if (!mounted) return;
          setState(() {
            _operationLabel = phase;
            _operationDone = 0;
            _operationTotal = 0;
            _status = phase == 'Decoding UNO response'
                ? 'Server finished parsing. Preparing the preview rows...'
                : 'Preparing the loaded data for paginated display...';
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _rows = parsedRows;
        _fileName = file.name;
        _filter = 'All';
        _pageIndex = 0;
        _operationLabel = 'Parsed subject-grade records';
        _operationDone = parsedRows.length;
        _operationTotal = parsedRows.length;
        _refreshDerivedData(resetPage: true);
        _status = 'Parsed ${parsedRows.length} subject-grade records across $_studentCount students. Use 50 or 100 rows/page for the smoothest scrolling.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'UNO upload/parsing failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _operationLabel = '';
          _operationDone = 0;
          _operationTotal = 0;
        });
      }
    }
  }

  Future<void> _checkDatabase() async {
    if (_selectedPeriod == null) {
      setState(() => _status = 'Please select an academic year first.');
      return;
    }
    if (_rows.isEmpty) {
      setState(() => _status = 'Please upload and parse the UNO file first.');
      return;
    }

    final liveRows = List<GradeRow>.from(_rows);
    setState(() {
      _rows = liveRows;
      _isBusy = true;
      _operationLabel = 'Checking SMS in batches';
      _operationDone = 0;
      _operationTotal = liveRows.length;
      _interpretation = null;
      _status = 'Checking SMS in smaller batches to keep the browser responsive... 0 / ${liveRows.length}';
    });

    try {
      final checkedRows = await _api.checkRows(
        rows: liveRows,
        periodId: _selectedPeriod!.id,
        chunkSize: 1000,
        onChunkChecked: (startIndex, checkedChunk) {
          for (var i = 0; i < checkedChunk.length; i++) {
            final target = startIndex + i;
            if (target >= 0 && target < liveRows.length) liveRows[target] = checkedChunk[i];
          }
        },
        onProgress: (checked, total) {
          if (!mounted) return;
          setState(() {
            _operationDone = checked;
            _operationTotal = total;
            _status = 'Checking SMS in smaller batches... $checked / $total';
          });
        },
      );

      setState(() {
        _rows = checkedRows;
        _refreshDerivedData(resetPage: false);
        _status = 'Done. Existing: $_existingCount, Missing: $_missingCount, Grade differs: $_gradeDiffCount, Units differ: $_unitsDiffCount, Duplicate SMS grades: $_duplicateGradeCount.';
      });
    } catch (error) {
      setState(() => _status = 'SMS check failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _operationLabel = '';
        });
      }
    }
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) {
      setState(() => _status = 'Upload and check the UNO promotional list before exporting.');
      return;
    }

    setState(() {
      _isBusy = true;
      _operationLabel = 'Generating formatted UNO report';
      _operationDone = 0;
      _operationTotal = _studentCount;
      _status = 'Generating formatted UNO report on the PHP API...';
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final students = _allGroups.map((group) => group.toExportJson()).toList(growable: false);
      final interpretation = _interpretation ?? _buildInterpretationText();
      final bytes = await _api.exportExcel(
        students: students,
        summary: _summaryJson(),
        periodLabel: _selectedPeriod?.label ?? '',
        fileName: _fileName.isEmpty ? 'grades_checker_export.xlsx' : _fileName,
        interpretation: interpretation,
      );

      final safeName = _downloadName();
      final blob = html.Blob([bytes], 'application/vnd.ms-excel');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..download = safeName
        ..style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);

      setState(() {
        _operationDone = _studentCount;
        _status = 'Export generated: $safeName';
      });
    } catch (error) {
      setState(() => _status = 'Export failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _operationLabel = '';
        });
      }
    }
  }

  String _downloadName() {
    final base = (_fileName.isEmpty ? 'grades_checker_export' : _fileName.replaceAll(RegExp(r'\.xlsx$', caseSensitive: false), ''))
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    final period = (_selectedPeriod?.label ?? 'period').replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    return '${base}_checked_$period.xls';
  }

  void _generateInterpretation() {
    setState(() {
      _interpretation = _buildInterpretationText();
    });
  }

  String _buildInterpretationText() {
    if (_rows.isEmpty) {
      return 'No UNO promotional-list data has been loaded yet. Upload the file and run the SMS check first.';
    }

    final total = _rows.length;
    final issueCount = _missingCount + _gradeDiffCount + _unitsDiffCount + _studentMissingCount + _subjectMissingCount;
    final existingPct = total == 0 ? 0.0 : (_existingCount / total) * 100;
    final issuePct = total == 0 ? 0.0 : (issueCount / total) * 100;
    final duplicateText = _duplicateGradeCount > 0
        ? ' There are also $_duplicateGradeCount subject entries with more than one matching grade record in SMS; tap the subject cells to inspect all SMS grades.'
        : '';

    final overall = issueCount == 0 && _checkedCount == total
        ? 'Overall, the uploaded UNO file is consistent with the selected SMS academic year.'
        : issuePct <= 5 && _checkedCount == total
            ? 'Overall, the uploaded UNO file is mostly consistent with the selected SMS academic year, with only a small number of records requiring review.'
            : 'Overall, the uploaded UNO file still needs review before it can be considered fully matched with the selected SMS academic year.';

    return '$overall\n\n'
        'For ${_selectedPeriod?.label ?? 'the selected period'}, $_checkedCount of $total subject-grade records were checked across $_studentCount students. '
        'Existing records: $_existingCount (${existingPct.toStringAsFixed(1)}%). '
        'Records needing attention: $issueCount (${issuePct.toStringAsFixed(1)}%).$duplicateText\n\n'
        'Breakdown: Missing grade records: $_missingCount. Grade differences: $_gradeDiffCount. Units differences: $_unitsDiffCount. '
        'Students not found: $_studentMissingCount. Subjects not found: $_subjectMissingCount.';
  }

  void _openConnectionSettings() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _ModernDialogScaffold(
          title: 'Connection settings',
          subtitle: 'Update only when Apache is running on another port, folder, or server IP.',
          icon: Icons.link_rounded,
          width: 620,
          onClose: () => Navigator.of(dialogContext).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _apiController,
                enabled: !_isBusy,
                decoration: const InputDecoration(
                  labelText: 'API endpoint',
                  prefixIcon: Icon(Icons.link_rounded, size: 18),
                  hintText: 'http://localhost/grades_checker_api/check_grades.php',
                ),
              ),
              SizedBox(height: _s(8)),
              const Text(
                'Use this if your SMS API folder is hosted in a different Apache path or another computer in the network.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: _kBodyFontSize),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: _isBusy
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      _loadPeriods();
                    },
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Save & reload years'),
            ),
          ],
        );
      },
    );
  }


  bool _canSaveSmsGradeForRow(GradeRow row) {
    if (row.studentFound != true || row.subjectVariants.isEmpty) return false;
    final missingGrade = !row.existsInDatabase && row.subjectFound == true;
    final differs = row.existsInDatabase && (row.gradeMatches == false || row.unitsMatch == false);
    return missingGrade || differs;
  }

  bool _isUpdateSmsGradeAction(GradeRow row) {
    return row.existsInDatabase && (row.gradeMatches == false || row.unitsMatch == false);
  }

  String _smsGradeActionLabel(GradeRow row) {
    return _isUpdateSmsGradeAction(row) ? 'Update grade in SMS' : 'Insert grade to SMS';
  }

  void _openSubjectDetails(GradeRow row) {
    final visual = _visualForRow(row);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _ModernDialogScaffold(
          title: row.subjectCode.isEmpty ? 'Subject details' : row.subjectCode,
          subtitle: 'Review the UNO subject, matching SMS subject choices, and grade records.',
          icon: Icons.menu_book_rounded,
          iconColor: visual.color,
          width: 880,
          maxHeightFactor: 0.92,
          onClose: () => Navigator.of(dialogContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(_s(12)),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(_s(14)),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('UNO subject details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: _kHeaderFontSize, color: Color(0xFF0F172A))),
                    SizedBox(height: _s(6)),
                    Text('UNO description: ${row.excelSubjectDescription.trim().isNotEmpty ? row.excelSubjectDescription : '-'}', style: const TextStyle(color: Color(0xFF475569), fontSize: _kBodyFontSize, fontWeight: FontWeight.w800)),
                    SizedBox(height: _s(3)),
                    Text('SMS description: ${row.subjectDescription?.trim().isNotEmpty == true ? row.subjectDescription! : '-'}', style: const TextStyle(color: Color(0xFF475569), fontSize: _kBodyFontSize)),
                  ],
                ),
              ),
              SizedBox(height: _s(12)),
              _sectionLabel('Subject choices (${row.subjectVariants.length})', Icons.category_rounded),
              if (row.subjectVariants.isEmpty)
                const Text('No matching SMS subject choices were returned yet. Run Check to load subject descriptions and units.', style: TextStyle(color: Color(0xFF64748B), fontSize: _kBodyFontSize))
              else
                _SubjectCatalogTable(subjects: row.subjectVariants),
              SizedBox(height: _s(12)),
              Wrap(
                spacing: _s(8),
                runSpacing: _s(8),
                children: [
                  _DetailPill(label: 'Status', value: row.statusLabel, color: visual.color),
                  _DetailPill(label: 'UNO grade', value: row.excelGrade.isEmpty ? '-' : row.excelGrade, color: const Color(0xFF2563EB)),
                  _DetailPill(label: 'UNO units', value: row.units.isEmpty ? '-' : row.units, color: const Color(0xFF2563EB)),
                  _DetailPill(label: 'SMS grade', value: row.databaseGrade?.trim().isNotEmpty == true ? row.databaseGrade! : '-', color: const Color(0xFF334155)),
                  _DetailPill(label: 'SMS units', value: row.databaseCredits?.trim().isNotEmpty == true ? row.databaseCredits! : '-', color: const Color(0xFF334155)),
                ],
              ),
              SizedBox(height: _s(12)),
              if (row.message?.trim().isNotEmpty == true)
                Container(
                  padding: EdgeInsets.all(_s(10)),
                  decoration: BoxDecoration(
                    color: visual.background,
                    borderRadius: BorderRadius.circular(_s(12)),
                    border: Border.all(color: visual.border),
                  ),
                  child: Text(row.message!, style: TextStyle(color: visual.color, fontWeight: FontWeight.w800, fontSize: _kBodyFontSize)),
                ),
              SizedBox(height: _s(14)),
              _sectionLabel('Selected academic year grade records (${row.databaseMatches.length})', Icons.fact_check_rounded),
              if (row.databaseMatches.isEmpty)
                const Text('No SMS grade returned for this subject and selected academic year.', style: TextStyle(color: Color(0xFF64748B), fontSize: _kBodyFontSize))
              else
                _DatabaseMatchesTable(matches: row.databaseMatches),
              SizedBox(height: _s(16)),
              _sectionLabel('Other academic year grade records (${row.otherPeriodMatches.length})', Icons.history_rounded),
              if (row.otherPeriodMatches.isEmpty)
                const Text('No grade record found for this same student and subject in other academic years.', style: TextStyle(color: Color(0xFF64748B), fontSize: _kBodyFontSize))
              else
                _DatabaseMatchesTable(matches: row.otherPeriodMatches),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
            if (_canSaveSmsGradeForRow(row))
              FilledButton.icon(
                onPressed: _isBusy
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        _openInsertSmsGradeDialog(row);
                      },
                icon: Icon(_isUpdateSmsGradeAction(row) ? Icons.edit_note_rounded : Icons.add_task_rounded, size: 18),
                label: Text(_smsGradeActionLabel(row)),
              ),
          ],
        );
      },
    );
  }

  SubjectCatalogRecord? _subjectChoiceById(List<SubjectCatalogRecord> subjects, String? id) {
    if (id == null) return null;
    for (final subject in subjects) {
      if (subject.subjectId == id) return subject;
    }
    return null;
  }

  List<SubjectCatalogRecord> _filterSubjectChoices(List<SubjectCatalogRecord> subjects, String query) {
    final q = _courseCompareKey(query);
    if (q.isEmpty) return subjects;
    return subjects.where((subject) {
      return _courseCompareKey('${subject.subjectCode} ${subject.subjectDescription} ${subject.subjectUnits}').contains(q);
    }).toList(growable: false);
  }

  bool _subjectListContains(List<SubjectCatalogRecord> subjects, String id) {
    return subjects.any((subject) => subject.subjectId == id);
  }

  void _openInsertSmsGradeDialog(GradeRow row) {
    if (_selectedPeriod == null) {
      setState(() => _status = 'Please select an academic year first.');
      return;
    }
    if (row.studentFound == false) {
      setState(() => _status = 'Create the student profile first before inserting a grade.');
      return;
    }
    if (row.subjectVariants.isEmpty) {
      setState(() => _status = 'Run Check first so subject choices can be loaded.');
      return;
    }

    final actionLabel = _smsGradeActionLabel(row);
    final isUpdateAction = _isUpdateSmsGradeAction(row);
    const modalFieldStyle = TextStyle(fontSize: _kBodyFontSize, color: Color(0xFF0F172A), fontWeight: FontWeight.w700);
    const modalSmallStyle = TextStyle(fontSize: _kTableFontSize, color: Color(0xFF475569), fontWeight: FontWeight.w700);
    final gradeController = TextEditingController(text: row.excelGrade);
    final creditsController = TextEditingController(text: row.units.isNotEmpty ? row.units : (row.subjectUnits ?? ''));
    final subjectSearchController = TextEditingController(text: row.excelSubjectDescription.trim().isNotEmpty ? row.excelSubjectDescription : row.subjectCode);
    var selectedSubjectId = row.subjectVariants.first.subjectId;
    var saving = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredSubjects = _filterSubjectChoices(row.subjectVariants, subjectSearchController.text);
            final subjectChoices = filteredSubjects.isEmpty ? row.subjectVariants : filteredSubjects;
            if (!_subjectListContains(subjectChoices, selectedSubjectId)) {
              selectedSubjectId = subjectChoices.first.subjectId;
            }
            final selectedSubject = _subjectChoiceById(row.subjectVariants, selectedSubjectId) ?? row.subjectVariants.first;

            return _ModernDialogScaffold(
              title: actionLabel,
              subtitle: isUpdateAction ? 'Review the selected SMS subject and update the grade for the selected academic year.' : 'Choose the correct SMS subject and save the grade for the selected academic year.',
              icon: isUpdateAction ? Icons.edit_note_rounded : Icons.add_task_rounded,
              width: 740,
              maxHeightFactor: 0.88,
              onClose: () => Navigator.of(dialogContext).pop(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: _s(6),
                    runSpacing: _s(6),
                    children: [
                      _DetailPill(label: 'Student ID', value: row.studentId.isEmpty ? '-' : row.studentId, color: const Color(0xFF2563EB)),
                      _DetailPill(label: 'Academic year', value: _selectedPeriod?.label ?? '-', color: const Color(0xFF334155)),
                    ],
                  ),
                  SizedBox(height: _s(8)),
                  Container(
                    padding: EdgeInsets.all(_s(10)),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(_s(12)),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('UNO subject reference', style: TextStyle(fontSize: _kTableFontSize, fontWeight: FontWeight.w900, color: Color(0xFF334155))),
                        SizedBox(height: _s(4)),
                        Text(row.subjectCode.isEmpty ? '-' : row.subjectCode, style: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                        if (row.excelSubjectDescription.trim().isNotEmpty) ...[
                          SizedBox(height: _s(3)),
                          Text(row.excelSubjectDescription, style: modalSmallStyle),
                        ],
                        SizedBox(height: _s(6)),
                        Wrap(
                          spacing: _s(6),
                          runSpacing: _s(6),
                          children: [
                            _DetailPill(label: 'UNO grade', value: row.excelGrade.isEmpty ? '-' : row.excelGrade, color: const Color(0xFF2563EB)),
                            _DetailPill(label: 'UNO units', value: row.units.isEmpty ? '-' : row.units, color: const Color(0xFF2563EB)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: _s(9)),
                  TextField(
                    controller: subjectSearchController,
                    style: modalFieldStyle,
                    enabled: !saving,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Search SMS subject',
                      hintText: 'Code, description, or units',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: subjectSearchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: saving
                                  ? null
                                  : () {
                                      subjectSearchController.clear();
                                      setDialogState(() {});
                                    },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                    ),
                  ),
                  SizedBox(height: _s(7)),
                  DropdownButtonFormField<String>(
                    value: selectedSubjectId,
                    isExpanded: true,
                    style: modalFieldStyle,
                    decoration: InputDecoration(
                      labelText: 'SMS subject',
                      helperText: filteredSubjects.isEmpty && subjectSearchController.text.trim().isNotEmpty
                          ? 'No match found. Showing all options.'
                          : null,
                    ),
                    items: subjectChoices
                        .map((subject) => DropdownMenuItem(
                              value: subject.subjectId,
                              child: Text(
                                '${subject.subjectCode} - ${subject.subjectDescription} (${subject.subjectUnits} units)',
                                overflow: TextOverflow.ellipsis,
                                style: modalFieldStyle,
                              ),
                            ))
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(() {
                              selectedSubjectId = value ?? selectedSubjectId;
                              final nextSubject = _subjectChoiceById(row.subjectVariants, selectedSubjectId);
                              if (nextSubject != null && creditsController.text.trim().isEmpty) {
                                creditsController.text = nextSubject.subjectUnits;
                              }
                            }),
                  ),
                  SizedBox(height: _s(8)),
                  Container(
                    padding: EdgeInsets.all(_s(10)),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(_s(12)),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Chosen SMS subject', style: TextStyle(fontSize: _kTableFontSize, fontWeight: FontWeight.w900, color: Color(0xFF334155))),
                        SizedBox(height: _s(4)),
                        Text(selectedSubject.subjectDescription.isEmpty ? '-' : selectedSubject.subjectDescription, style: modalSmallStyle),
                        SizedBox(height: _s(2)),
                        Text('Units: ${selectedSubject.subjectUnits.isEmpty ? '-' : selectedSubject.subjectUnits}', style: modalSmallStyle),
                      ],
                    ),
                  ),
                  SizedBox(height: _s(8)),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: gradeController,
                          enabled: !saving,
                          style: modalFieldStyle,
                          decoration: const InputDecoration(labelText: 'Grade'),
                        ),
                      ),
                      SizedBox(width: _s(8)),
                      Expanded(
                        child: TextField(
                          controller: creditsController,
                          enabled: !saving,
                          style: modalFieldStyle,
                          decoration: const InputDecoration(labelText: 'Units'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                  style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800)),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final grade = gradeController.text.trim();
                          if (grade.isEmpty) {
                            setState(() => _status = 'Grade is required before inserting to SMS.');
                            return;
                          }
                          setDialogState(() => saving = true);
                          Navigator.of(dialogContext).pop();
                          await _insertSmsGradeForRow(
                            row,
                            subjectId: selectedSubjectId,
                            grade: grade,
                            credits: creditsController.text.trim(),
                          );
                        },
                  style: FilledButton.styleFrom(textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800)),
                  icon: saving ? SizedBox(width: _s(14), height: _s(14), child: const CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_task_rounded, size: 17),
                  label: Text(saving ? 'Saving...' : (isUpdateAction ? 'Update grade' : 'Insert grade')),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      gradeController.dispose();
      creditsController.dispose();
      subjectSearchController.dispose();
    });
  }

  Future<void> _insertSmsGradeForRow(
    GradeRow row, {
    required String subjectId,
    required String grade,
    required String credits,
  }) async {
    final period = _selectedPeriod;
    if (period == null) return;

    setState(() {
      _isBusy = true;
      _operationLabel = row.existsInDatabase ? 'Updating grade' : 'Inserting grade';
      _operationDone = 0;
      _operationTotal = 0;
      _status = row.existsInDatabase ? 'Updating grade in SMS...' : 'Inserting grade to SMS...';
    });

    try {
      final result = await _api.insertSmsGrade(
        studentId: row.studentId,
        subjectId: subjectId,
        periodId: period.id,
        grade: grade,
        credits: credits,
        course: row.databaseCourse?.trim().isNotEmpty == true ? row.databaseCourse! : row.course,
        yearLevel: row.yearLevel,
        subjectNo: row.subjectNo,
      );

      final checked = await _api.checkRows(rows: [row], periodId: period.id, chunkSize: 1);
      if (checked.isNotEmpty) {
        for (var i = 0; i < _rows.length; i++) {
          final current = _rows[i];
          if (current.excelRowNumber == row.excelRowNumber &&
              current.subjectNo == row.subjectNo &&
              current.studentId == row.studentId) {
            _rows[i] = checked.first;
            break;
          }
        }
      }

      setState(() {
        _refreshDerivedData(resetPage: false);
        _status = result.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Insert grade failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _operationLabel = '';
          _operationDone = 0;
          _operationTotal = 0;
        });
      }
    }
  }

  String _normalizeYearLevelLabel(String value) {
    final raw = value.trim();
    final compact = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (compact == '1' || compact == '1st' || compact == 'first' || compact == '1styear' || compact == 'firstyear') return '1st Year';
    if (compact == '2' || compact == '2nd' || compact == 'second' || compact == '2ndyear' || compact == 'secondyear') return '2nd Year';
    if (compact == '3' || compact == '3rd' || compact == 'third' || compact == '3rdyear' || compact == 'thirdyear') return '3rd Year';
    if (compact == '4' || compact == '4th' || compact == 'fourth' || compact == '4thyear' || compact == 'fourthyear') return '4th Year';
    return '1st Year';
  }

  String _courseCompareKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  CourseOption? _bestCourseForExcel(String excelCourse, List<CourseOption> courses) {
    final excelKey = _courseCompareKey(excelCourse);
    if (courses.isEmpty) return null;
    if (excelKey.isEmpty) return courses.first;

    for (final course in courses) {
      if (_courseCompareKey(course.code) == excelKey || _courseCompareKey(course.name) == excelKey) return course;
    }
    for (final course in courses) {
      final codeKey = _courseCompareKey(course.code);
      final nameKey = _courseCompareKey(course.name);
      if (codeKey.isNotEmpty && excelKey.contains(codeKey)) return course;
      if (nameKey.isNotEmpty && (excelKey.contains(nameKey) || nameKey.contains(excelKey))) return course;
    }
    return courses.first;
  }

  CourseOption? _courseById(List<CourseOption> courses, String? id) {
    if (id == null) return null;
    for (final course in courses) {
      if (course.id == id) return course;
    }
    return null;
  }

  void _handleStudentTap(_StudentGradeGroup group) {
    final studentMissing = group.rows.any((row) => row.studentFound == false);
    if (studentMissing) {
      _openStudentProfileForm(group);
      return;
    }
    _openStudentDetails(group);
  }

  DateTime? _parseFlexibleDate(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;

    final numeric = double.tryParse(raw);
    if (numeric != null && numeric > 20000 && numeric < 80000) {
      return DateTime.utc(1899, 12, 30).add(Duration(days: numeric.floor())).toLocal();
    }

    final iso = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(raw);
    if (iso != null) {
      return DateTime.tryParse('${iso.group(1)!}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}');
    }

    final slash = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(raw);
    if (slash != null) {
      final month = int.tryParse(slash.group(1)!);
      final day = int.tryParse(slash.group(2)!);
      var year = int.tryParse(slash.group(3)!);
      if (year != null && year < 100) year += year >= 50 ? 1900 : 2000;
      if (month != null && day != null && year != null) {
        return DateTime.tryParse('${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
      }
    }

    return DateTime.tryParse(raw);
  }

  String _formatDateIso(DateTime? date) {
    if (date == null) return '';
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<CourseOption> _filterCourses(List<CourseOption> courses, String query) {
    final q = _courseCompareKey(query);
    if (q.isEmpty) return courses;
    return courses.where((course) {
      return _courseCompareKey('${course.code} ${course.name} ${course.major} ${course.status}').contains(q);
    }).toList(growable: false);
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Padding(
      padding: EdgeInsets.only(bottom: _s(7)),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF2563EB)),
          SizedBox(width: _s(6)),
          Text(text, style: const TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  void _openStudentProfileForm(_StudentGradeGroup group) {
    final studentIdController = TextEditingController(text: group.studentId);
    final lastNameController = TextEditingController(text: group.lastName);
    final firstNameController = TextEditingController(text: group.firstName);
    final middleNameController = TextEditingController(text: group.middleName);
    final courseSearchController = TextEditingController(text: group.course);
    DateTime? selectedBirthDate = _parseFlexibleDate(group.birthDate);
    var selectedYear = _normalizeYearLevelLabel(group.yearLevel);
    var selectedGender = 'Male';
    CourseOption? selectedCourse;
    var saving = false;
    final coursesFuture = _api.fetchCourses();
    const profileFieldStyle = TextStyle(fontSize: _kBodyFontSize, color: Color(0xFF0F172A), fontWeight: FontWeight.w700);
    const profileSmallStyle = TextStyle(fontSize: _kTableFontSize, color: Color(0xFF64748B), fontWeight: FontWeight.w700);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickBirthdate() async {
              final now = DateTime.now();
              final initialDate = selectedBirthDate ?? DateTime(now.year - 18, now.month, now.day);
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: initialDate.isAfter(DateTime.now()) ? DateTime(now.year - 18, now.month, now.day) : initialDate,
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
                helpText: 'Select birthdate',
              );
              if (picked != null) {
                setDialogState(() => selectedBirthDate = picked);
              }
            }

            return Dialog(
              insetPadding: EdgeInsets.symmetric(horizontal: _s(22), vertical: _s(18)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(_s(18)), bottomRight: Radius.circular(_s(18)))),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _s(860), maxHeight: MediaQuery.of(context).size.height * 0.90),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(_s(16), _s(14), _s(12), _s(10)),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: _s(34),
                            height: _s(34),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withOpacity(0.10),
                              borderRadius: BorderRadius.circular(_s(13)),
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF2563EB), size: 18),
                          ),
                          SizedBox(width: _s(10)),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Create student profile', style: TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900)),
                                SizedBox(height: 2),
                                Text('Review and update the UNO student details before saving.', style: TextStyle(fontSize: _kBodyFontSize, color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(_s(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionLabel('Student information', Icons.badge_rounded),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: studentIdController,
                                    enabled: !saving,
                                    style: profileFieldStyle,
                                    decoration: const InputDecoration(labelText: 'Student ID'),
                                  ),
                                ),
                                SizedBox(width: _s(8)),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: selectedYear,
                                    style: profileFieldStyle,
                                    decoration: const InputDecoration(labelText: 'Year level'),
                                    items: const ['1st Year', '2nd Year', '3rd Year', '4th Year']
                                        .map((year) => DropdownMenuItem(value: year, child: Text(year, style: profileFieldStyle)))
                                        .toList(),
                                    onChanged: saving ? null : (value) => setDialogState(() => selectedYear = value ?? '1st Year'),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: _s(8)),
                            Row(
                              children: [
                                Expanded(child: TextField(controller: lastNameController, enabled: !saving, style: profileFieldStyle, decoration: const InputDecoration(labelText: 'Last name'))),
                                SizedBox(width: _s(8)),
                                Expanded(child: TextField(controller: firstNameController, enabled: !saving, style: profileFieldStyle, decoration: const InputDecoration(labelText: 'First name'))),
                                SizedBox(width: _s(8)),
                                Expanded(child: TextField(controller: middleNameController, enabled: !saving, style: profileFieldStyle, decoration: const InputDecoration(labelText: 'Middle name'))),
                              ],
                            ),
                            SizedBox(height: _s(14)),
                            _sectionLabel('Personal details', Icons.cake_rounded),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: selectedGender,
                                    style: profileFieldStyle,
                                    decoration: const InputDecoration(labelText: 'Gender'),
                                    items: const ['Male', 'Female']
                                        .map((gender) => DropdownMenuItem(value: gender, child: Text(gender, style: profileFieldStyle)))
                                        .toList(),
                                    onChanged: saving ? null : (value) => setDialogState(() => selectedGender = value ?? 'Male'),
                                  ),
                                ),
                                SizedBox(width: _s(8)),
                                Expanded(
                                  child: InkWell(
                                    onTap: saving ? null : pickBirthdate,
                                    borderRadius: BorderRadius.circular(_s(10)),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Birthdate',
                                        hintText: '(YYYY-MM-DD)',
                                        prefixIcon: const Icon(Icons.calendar_month_rounded, size: 18),
                                        suffixIcon: IconButton(
                                          tooltip: 'Pick date',
                                          onPressed: saving ? null : pickBirthdate,
                                          icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                                        ),
                                      ),
                                      child: Text(
                                        selectedBirthDate == null ? '(YYYY-MM-DD)' : _formatDateIso(selectedBirthDate),
                                        style: TextStyle(
                                          fontSize: _kBodyFontSize,
                                          fontWeight: FontWeight.w700,
                                          color: selectedBirthDate == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (group.birthDate.trim().isNotEmpty) ...[
                              SizedBox(height: _s(5)),
                              Text('UNO birthdate: ${group.birthDate} → ${selectedBirthDate == null ? 'not recognized' : _formatDateIso(selectedBirthDate)}', style: profileSmallStyle),
                            ],
                            SizedBox(height: _s(14)),
                            _sectionLabel('Course', Icons.school_rounded),
                            FutureBuilder<List<CourseOption>>(
                              future: coursesFuture,
                              builder: (context, snapshot) {
                                final courses = snapshot.data ?? const <CourseOption>[];
                                if (selectedCourse == null && courses.isNotEmpty) {
                                  selectedCourse = _bestCourseForExcel(group.course, courses);
                                }
                                if (snapshot.connectionState != ConnectionState.done) {
                                  return const LinearProgressIndicator(minHeight: 3);
                                }
                                if (snapshot.hasError) {
                                  return Text('Unable to load course choices: ${snapshot.error}', style: const TextStyle(color: Color(0xFF991B1B), fontSize: _kBodyFontSize, fontWeight: FontWeight.w700));
                                }

                                final filteredCourses = _filterCourses(courses, courseSearchController.text);
                                if (selectedCourse != null && !filteredCourses.any((course) => course.id == selectedCourse!.id) && filteredCourses.isNotEmpty) {
                                  selectedCourse = filteredCourses.first;
                                }
                                final dropdownCourseValue = selectedCourse != null && filteredCourses.any((course) => course.id == selectedCourse!.id)
                                    ? selectedCourse!.id
                                    : null;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      controller: courseSearchController,
                                      enabled: !saving,
                                      style: profileFieldStyle,
                                      onChanged: (_) => setDialogState(() {}),
                                      decoration: InputDecoration(
                                        labelText: 'Search course',
                                        hintText: 'Search course code or name',
                                        helperText: group.course.trim().isEmpty ? null : 'From UNO: ${group.course}',
                                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                        suffixIcon: courseSearchController.text.trim().isEmpty
                                            ? null
                                            : IconButton(
                                                tooltip: 'Clear search',
                                                onPressed: saving
                                                    ? null
                                                    : () => setDialogState(() {
                                                          courseSearchController.clear();
                                                          selectedCourse = _bestCourseForExcel(group.course, courses);
                                                        }),
                                                icon: const Icon(Icons.clear_rounded, size: 18),
                                              ),
                                      ),
                                    ),
                                    SizedBox(height: _s(8)),
                                    DropdownButtonFormField<String>(
                                      value: dropdownCourseValue,
                                      isExpanded: true,
                                      style: profileFieldStyle,
                                      decoration: InputDecoration(
                                        labelText: 'Course',
                                        helperText: filteredCourses.isEmpty ? 'No course matched your search.' : '${filteredCourses.length} course option(s)',
                                      ),
                                      items: filteredCourses
                                          .map((course) => DropdownMenuItem(
                                                value: course.id,
                                                child: Text(course.displayLabel, overflow: TextOverflow.ellipsis, style: profileFieldStyle),
                                              ))
                                          .toList(),
                                      onChanged: saving
                                          ? null
                                          : (courseId) => setDialogState(() {
                                                selectedCourse = _courseById(courses, courseId);
                                              }),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(_s(16), _s(8), _s(16), _s(12)),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
                      child: Row(
                        children: [
                          Expanded(
                            child: saving
                                ? const Text('Saving profile...', style: TextStyle(fontSize: _kBodyFontSize, color: Color(0xFF64748B), fontWeight: FontWeight.w700))
                                : const SizedBox.shrink(),
                          ),
                          TextButton(
                            onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                            style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800)),
                            child: const Text('Cancel'),
                          ),
                          SizedBox(width: _s(8)),
                          FilledButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    final studentId = studentIdController.text.trim();
                                    final firstName = firstNameController.text.trim();
                                    final lastName = lastNameController.text.trim();
                                    if (studentId.isEmpty || firstName.isEmpty || lastName.isEmpty) {
                                      setState(() => _status = 'Student ID, first name, and last name are required.');
                                      return;
                                    }
                                    setDialogState(() => saving = true);
                                    Navigator.of(dialogContext).pop();
                                    await _createStudentProfileFromGroup(
                                      group,
                                      studentId: studentId,
                                      firstName: firstName,
                                      middleName: middleNameController.text.trim(),
                                      lastName: lastName,
                                      yearLevel: selectedYear,
                                      course: selectedCourse?.code ?? group.course,
                                      courseId: selectedCourse?.id ?? '',
                                      gender: selectedGender,
                                      birthDate: _formatDateIso(selectedBirthDate),
                                    );
                                  },
                            style: FilledButton.styleFrom(textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800)),
                            icon: saving ? SizedBox(width: _s(14), height: _s(14), child: const CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 17),
                            label: Text(saving ? 'Saving...' : 'Save profile'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      studentIdController.dispose();
      lastNameController.dispose();
      firstNameController.dispose();
      middleNameController.dispose();
      courseSearchController.dispose();
    });
  }

  void _openStudentDetails(_StudentGradeGroup group) {
    final visual = group.visual;
    final studentMissing = group.rows.any((row) => row.studentFound == false);
    final canCreate = studentMissing && group.studentId.trim().isNotEmpty && group.firstName.trim().isNotEmpty && group.lastName.trim().isNotEmpty;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _ModernDialogScaffold(
          title: group.studentName,
          subtitle: studentMissing ? 'Review UNO details and create the student profile if needed.' : 'Student profile matched in SMS.',
          icon: studentMissing ? Icons.person_add_alt_1_rounded : Icons.person_rounded,
          iconColor: visual.color,
          width: 720,
          maxHeightFactor: 0.88,
          onClose: () => Navigator.of(dialogContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: _s(8),
                runSpacing: _s(8),
                children: [
                  _DetailPill(label: 'Student ID', value: group.studentId.isEmpty ? '-' : group.studentId, color: const Color(0xFF2563EB)),
                  _DetailPill(label: 'Course', value: group.course.isEmpty ? '-' : group.course, color: const Color(0xFF334155)),
                  _DetailPill(label: 'Year', value: group.yearLevel.isEmpty ? '-' : group.yearLevel, color: const Color(0xFF334155)),
                  _DetailPill(label: 'Birthdate', value: group.birthDate.isEmpty ? '-' : group.birthDate, color: const Color(0xFF334155)),
                  _DetailPill(label: 'Subjects', value: group.rows.length.toString(), color: visual.color),
                ],
              ),
              SizedBox(height: _s(12)),
              Container(
                padding: EdgeInsets.all(_s(12)),
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(_s(14)),
                  border: Border.all(color: visual.border),
                ),
                child: Text(
                  studentMissing
                      ? (canCreate
                          ? 'This student was not found in the student records. You can create a student profile from the UNO row details, then run Check again.'
                          : 'This student was not found. Open the profile form and complete any missing Student ID, first name, or last name before saving.')
                      : 'Student was matched in the student records. Tap a subject cell to inspect grade and subject details.',
                  style: TextStyle(color: visual.color, fontWeight: FontWeight.w800, fontSize: _kBodyFontSize),
                ),
              ),
              SizedBox(height: _s(12)),
              _sectionLabel('UNO row details', Icons.assignment_ind_rounded),
              Table(
                border: const TableBorder(
                  horizontalInside: BorderSide(color: Color(0xFFE2E8F0)),
                  verticalInside: BorderSide(color: Color(0xFFE2E8F0)),
                  top: BorderSide(color: Color(0xFFE2E8F0)),
                  bottom: BorderSide(color: Color(0xFFE2E8F0)),
                  left: BorderSide(color: Color(0xFFE2E8F0)),
                  right: BorderSide(color: Color(0xFFE2E8F0)),
                ),
                columnWidths: const {0: FixedColumnWidth(120), 1: FlexColumnWidth()},
                children: [
                  _detailRow('Last name', group.lastName),
                  _detailRow('First name', group.firstName),
                  _detailRow('Middle name', group.middleName),
                  _detailRow('Birthdate', group.birthDate),
                  _detailRow('UNO row', group.excelRowNumber.toString()),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
            if (studentMissing)
              FilledButton.icon(
                onPressed: _isBusy
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        _openStudentProfileForm(group);
                      },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Create student profile'),
              ),
          ],
        );
      },
    );
  }

  TableRow _detailRow(String label, String value) {
    return TableRow(
      children: [
        _TinyHeader(label),
        _TinyCell(value),
      ],
    );
  }

  Future<void> _createStudentProfileFromGroup(
    _StudentGradeGroup group, {
    String? studentId,
    String? firstName,
    String? middleName,
    String? lastName,
    String? yearLevel,
    String? course,
    String courseId = '',
    String gender = '',
    String birthDate = '',
  }) async {
    final finalStudentId = studentId?.trim().isNotEmpty == true ? studentId!.trim() : group.studentId.trim();
    final finalFirstName = firstName?.trim().isNotEmpty == true ? firstName!.trim() : group.firstName.trim();
    final finalMiddleName = middleName ?? group.middleName;
    final finalLastName = lastName?.trim().isNotEmpty == true ? lastName!.trim() : group.lastName.trim();
    final finalYearLevel = _normalizeYearLevelLabel(yearLevel ?? group.yearLevel);
    final finalCourse = course?.trim().isNotEmpty == true ? course!.trim() : group.course.trim();

    if (finalStudentId.isEmpty || finalFirstName.isEmpty || finalLastName.isEmpty) {
      setState(() => _status = 'Cannot create student profile: Student ID, first name, and last name are required.');
      return;
    }

    setState(() {
      _isBusy = true;
      _operationLabel = 'Creating student profile';
      _operationDone = 0;
      _operationTotal = 0;
      _status = 'Creating $finalLastName, $finalFirstName in the student records...';
    });

    try {
      final result = await _api.createStudentProfile(
        studentId: finalStudentId,
        firstName: finalFirstName,
        middleName: finalMiddleName,
        lastName: finalLastName,
        courseId: courseId,
        course: finalCourse,
        yearLevel: finalYearLevel,
        gender: gender,
        birthDate: birthDate,
      );

      final courseCode = result.student['course_code']?.toString() ?? group.course;
      for (final row in _rows) {
        if (_rowGroupKey(row) == group.key) {
          row.studentFound = true;
          if (courseCode.trim().isNotEmpty) row.databaseCourse = courseCode;
          row.message = '${result.message} Run Check again to refresh grade matching.';
        }
      }

      setState(() {
        _refreshDerivedData(resetPage: false);
        _status = result.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Create student profile failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _operationLabel = '';
          _operationDone = 0;
          _operationTotal = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) return _buildLoginScaffold();

    final groups = _visibleGroups;

    return Scaffold(
      bottomNavigationBar: _rows.isEmpty || groups.isEmpty ? null : _buildStickyHorizontalScrollBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(_s(14), _s(14), _s(14), _rows.isEmpty ? _s(20) : _s(64)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  SizedBox(height: _s(9)),
                  _buildSetupPanel(),
                  SizedBox(height: _s(9)),
                  _buildDataWorkspace(groups),
                  SizedBox(height: _s(20)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginScaffold() {
    final failed = _status.toLowerCase().contains('failed') ||
        _status.toLowerCase().contains('invalid') ||
        _status.toLowerCase().contains('required');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_s(18)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _s(460)),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(_s(20)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: _s(44),
                            height: _s(40),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF14B8A6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(_s(16)),
                            ),
                            child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 21),
                          ),
                          SizedBox(width: _s(12)),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('UNO to SMS Grade Checker', style: TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900)),
                                SizedBox(height: 2),
                                Text('Login using your SMS user account.', style: TextStyle(fontSize: _kBodyFontSize, color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: _s(18)),
                      TextField(
                        controller: _usernameController,
                        enabled: !_loggingIn,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_rounded, size: 18),
                        ),
                      ),
                      SizedBox(height: _s(10)),
                      TextField(
                        controller: _passwordController,
                        enabled: !_loggingIn,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _loggingIn ? null : _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_rounded, size: 18),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                            onPressed: _loggingIn ? null : () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                          ),
                        ),
                      ),
                      SizedBox(height: _s(12)),
                      FilledButton.icon(
                        onPressed: _loggingIn ? null : _login,
                        icon: _loggingIn
                            ? SizedBox(width: _s(16), height: _s(16), child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.login_rounded, size: 18),
                        label: Text(_loggingIn ? 'Signing in...' : 'Login'),
                        style: FilledButton.styleFrom(
                          minimumSize: Size.fromHeight(_s(42)),
                          textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(10))),
                        ),
                      ),
                      SizedBox(height: _s(12)),
                      Container(
                        padding: EdgeInsets.all(_s(10)),
                        decoration: BoxDecoration(
                          color: failed ? const Color(0xFFFEF2F2) : const Color(0xFFEEF6FF),
                          borderRadius: BorderRadius.circular(_s(12)),
                          border: Border.all(color: failed ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          _status,
                          style: TextStyle(
                            fontSize: _kBodyFontSize,
                            color: failed ? const Color(0xFF991B1B) : const Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                      SizedBox(height: _s(10)),
                      TextButton.icon(
                        onPressed: _loggingIn ? null : _openConnectionSettings,
                        icon: const Icon(Icons.settings_rounded, size: 17),
                        label: const Text('Connection settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: _s(42),
          height: _s(36),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF14B8A6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(_s(16)),
          ),
          child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 20),
        ),
        SizedBox(width: _s(12)),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UNO to SMS Grade Checker', style: TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900)),
              SizedBox(height: 2),
              Text(
                'Cross-check legacy UNO promotional-list grades against current SMS grade records.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: _kBodyFontSize),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _s(300)),
          child: SizedBox(
            height: _s(36),
            child: _SoftPill(
              icon: Icons.calendar_month_rounded,
              label: _selectedPeriod?.label ?? (_loadingPeriods ? 'Loading academic years...' : 'No academic year selected'),
            ),
          ),
        ),
        SizedBox(width: _s(8)),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _s(220)),
          child: SizedBox(
            height: _s(36),
            child: _SoftPill(
              icon: Icons.person_rounded,
              label: _authDisplayName.isNotEmpty ? _authDisplayName : _authUsername,
            ),
          ),
        ),
        SizedBox(width: _s(8)),
        SizedBox(
          height: _s(36),
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: _s(14)),
              textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
        SizedBox(width: _s(8)),
        SizedBox(
          height: _s(36),
          child: OutlinedButton.icon(
            onPressed: _openConnectionSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Connection'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: _s(14)),
              textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSetupPanel() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(_s(9)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UNO import check setup', style: TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900)),
                      SizedBox(height: 3),
                      Text('Select the SMS academic year, upload the UNO promotional list, then run the comparison.', style: TextStyle(color: Color(0xFF64748B), fontSize: _kBodyFontSize)),
                    ],
                  ),
                ),
                if (_fileName.isNotEmpty) _SoftPill(icon: Icons.insert_drive_file_rounded, label: _fileName),
              ],
            ),
            SizedBox(height: _s(10)),
            LayoutBuilder(
              builder: (context, constraints) {
                final controlHeight = _s(42);
                final buttonStyle = OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: _s(12)),
                  textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800),
                  foregroundColor: const Color(0xFF445487),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(10))),
                );
                Widget uploadButton({double? width}) => SizedBox(
                      width: width,
                      height: controlHeight,
                      child: FilledButton.icon(
                        onPressed: _isBusy ? null : _pickExcel,
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: const Text('Upload UNO', maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: _s(12)),
                          textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(10))),
                        ),
                      ),
                    );
                Widget checkButton({double? width}) => SizedBox(
                      width: width,
                      height: controlHeight,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _checkDatabase,
                        icon: const Icon(Icons.manage_search_rounded, size: 16),
                        label: const Text('Check', maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: buttonStyle,
                      ),
                    );
                Widget exportButton({double? width}) => SizedBox(
                      width: width,
                      height: controlHeight,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy || _rows.isEmpty ? null : _exportExcel,
                        icon: const Icon(Icons.file_download_rounded, size: 16),
                        label: const Text('Export Report', maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: buttonStyle,
                      ),
                    );

                if (constraints.maxWidth < _s(900)) {
                  final stackAcademicAndCheck = constraints.maxWidth < _s(520);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (stackAcademicAndCheck) ...[
                        SizedBox(height: controlHeight, child: _buildPeriodSelector()),
                        SizedBox(height: _s(8)),
                        checkButton(),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(child: SizedBox(height: controlHeight, child: _buildPeriodSelector())),
                            SizedBox(width: _s(8)),
                            SizedBox(width: _s(104), child: checkButton()),
                          ],
                        ),
                      ],
                      SizedBox(height: _s(8)),
                      Row(
                        children: [
                          Expanded(child: uploadButton()),
                          SizedBox(width: _s(8)),
                          Expanded(child: exportButton()),
                        ],
                      ),
                    ],
                  );
                }

                final uploadWidth = constraints.maxWidth < _s(1120) ? _s(168) : _s(178);
                final checkWidth = constraints.maxWidth < _s(1120) ? _s(96) : _s(104);
                final exportWidth = constraints.maxWidth < _s(1120) ? _s(138) : _s(150);
                final rightActionWidth = uploadWidth + exportWidth + _s(16);
                final periodWidth = math
                    .min(_s(500), math.max(_s(330), constraints.maxWidth - rightActionWidth - checkWidth - _s(48)))
                    .toDouble();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: periodWidth, height: controlHeight, child: _buildPeriodSelector()),
                    SizedBox(width: _s(8)),
                    checkButton(width: checkWidth),
                    const Spacer(),
                    uploadButton(width: uploadWidth),
                    SizedBox(width: _s(8)),
                    exportButton(width: exportWidth),
                  ],
                );
              },
            ),
            SizedBox(height: _s(9)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SizedBox(height: 54, child: _buildProgressPanel())),
                SizedBox(width: _s(10)),
                Expanded(child: SizedBox(height: 54, child: _buildStatusPanel())),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return DropdownButtonFormField<String>(
      value: _selectedPeriod?.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Academic Year',
        hintText: _loadingPeriods ? 'Loading academic years...' : 'Select academic year',
        prefixIcon: const Icon(Icons.event_note_rounded, size: 18),
        suffixIcon: _loadingPeriods
            ? Padding(
                padding: EdgeInsets.all(_s(12)),
                child: SizedBox(width: _s(15), height: _s(15), child: const CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                tooltip: 'Refresh periods',
                onPressed: _isBusy ? null : _loadPeriods,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
      ),
      items: _periods
          .map((period) => DropdownMenuItem<String>(
                value: period.id,
                child: Text(period.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: _kBodyFontSize)),
              ))
          .toList(),
      onChanged: _isBusy
          ? null
          : (id) {
              GradePeriod? match;
              for (final period in _periods) {
                if (period.id == id) {
                  match = period;
                  break;
                }
              }
              setState(() {
                _selectedPeriod = match;
                _rows = [];
                _allGroups = [];
                _visibleGroups = [];
                _fileName = '';
                _interpretation = null;
                _refreshDerivedData(resetPage: true);
                _status = match == null ? 'Select an academic year, then upload the UNO promotional list.' : 'Selected ${match.label}. Upload UNO promotional list to begin.';
              });
            },
    );
  }

  Widget _buildProgressPanel() {
    final label = _hasProgress
        ? (_operationLabel.contains('•') || _operationTotal <= 0 ? _operationLabel : '$_operationLabel • $_operationDone / $_operationTotal')
        : (_fileName.isEmpty ? 'No file uploaded yet' : _fileName);

    return Container(
      padding: EdgeInsets.all(_s(9)),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(_s(14)),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, size: 17, color: Color(0xFF2563EB)),
              SizedBox(width: _s(7)),
              Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: _kBodyFontSize))),
            ],
          ),
          SizedBox(height: _s(8)),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(minHeight: _s(7), value: _progressValue, backgroundColor: const Color(0xFFE2E8F0)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    final failed = _status.toLowerCase().contains('failed') ||
        _status.toLowerCase().contains('unable') ||
        _status.toLowerCase().contains('error');

    return Container(
      padding: EdgeInsets.all(_s(9)),
      decoration: BoxDecoration(
        color: failed ? const Color(0xFFFEF2F2) : const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(_s(14)),
        border: Border.all(color: failed ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: failed ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8), size: 18),
          SizedBox(width: _s(7)),
          Expanded(child: Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: failed ? const Color(0xFF991B1B) : const Color(0xFF1E3A8A), fontSize: _kBodyFontSize))),
        ],
      ),
    );
  }

  Widget _buildDataWorkspace(List<_StudentGradeGroup> groups) {
    final pageCount = _pageCount(groups.length);
    final safePageIndex = groups.isEmpty ? 0 : _pageIndex.clamp(0, pageCount - 1).toInt();
    final start = groups.isEmpty ? 0 : safePageIndex * _pageSize;
    final end = math.min(start + _pageSize, groups.length);
    final pagedGroups = groups.isEmpty ? <_StudentGradeGroup>[] : groups.sublist(start, end);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(_s(9)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMetrics(),
                SizedBox(height: _s(10)),
                _buildToolbar(groups.length),
                SizedBox(height: _s(8)),
                _buildPaginationBar(totalStudents: groups.length, pageCount: pageCount, safePageIndex: safePageIndex, start: start, end: end),
                SizedBox(height: _s(8)),
                _buildLegend(),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildResultsArea(pagedGroups),
          if (_rows.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: EdgeInsets.all(_s(9)),
              child: _buildBottomControls(totalStudents: groups.length, pageCount: pageCount, safePageIndex: safePageIndex, start: start, end: end),
            ),
            if (_interpretation != null)
              Padding(
                padding: EdgeInsets.fromLTRB(_s(9), 0, _s(9), _s(9)),
                child: _InterpretationCard(text: _interpretation!),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    final cards = [
      _MetricCard(label: 'Students', value: _studentCount.toString(), icon: Icons.groups_rounded),
      _MetricCard(label: 'Subject records', value: _rows.length.toString(), icon: Icons.table_rows_rounded),
      _MetricCard(label: 'Checked', value: _checkedCount.toString(), icon: Icons.checklist_rounded),
      _MetricCard(label: 'Existing', value: _existingCount.toString(), icon: Icons.verified_rounded),
      _MetricCard(label: 'Missing', value: _missingCount.toString(), icon: Icons.remove_circle_outline_rounded),
      _MetricCard(label: 'Diffs', value: (_gradeDiffCount + _unitsDiffCount).toString(), icon: Icons.compare_arrows_rounded),
      _MetricCard(label: 'Duplicate SMS', value: _duplicateGradeCount.toString(), icon: Icons.control_point_duplicate_rounded),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _s(1040)) {
          final itemWidth = math.max(_s(170), (constraints.maxWidth - _s(16)) / 3).toDouble();
          return Wrap(
            spacing: _s(8),
            runSpacing: _s(8),
            children: [for (final card in cards) SizedBox(width: itemWidth, child: card)],
          );
        }
        return Row(
          children: List.generate(cards.length, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == cards.length - 1 ? 0 : _s(8)),
                child: cards[index],
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildToolbar(int visibleStudentCount) {
    final controlHeight = _s(44);
    const toolbarTextStyle = TextStyle(
      fontSize: _kBodyFontSize,
      fontWeight: FontWeight.w800,
      color: Color(0xFF334155),
    );
    final filterWidth = math
        .min(_s(230), math.max(_s(118), _s(68) + (_filter.length * _s(8))))
        .toDouble();
    final filter = SizedBox(
      width: filterWidth,
      height: controlHeight,
      child: DropdownButtonFormField<String>(
        value: _filter,
        isDense: true,
        isExpanded: true,
        iconSize: 16,
        style: toolbarTextStyle,
        selectedItemBuilder: (context) => _filterOptions
            .map((value) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: toolbarTextStyle),
                ))
            .toList(),
        decoration: InputDecoration(
          hintText: 'Filter',
          hintStyle: toolbarTextStyle.copyWith(color: const Color(0xFF64748B)),
          prefixIcon: const Icon(Icons.filter_alt_rounded, size: 17),
          prefixIconConstraints: BoxConstraints(minWidth: _s(32), minHeight: controlHeight),
          contentPadding: EdgeInsets.symmetric(horizontal: _s(8), vertical: 0),
        ),
        items: _filterOptions
            .map((value) => DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: toolbarTextStyle),
                ))
            .toList(),
        onChanged: (value) => setState(() {
          _filter = value ?? 'All';
          _applyFilterNoSetState(resetPage: true);
        }),
      ),
    );
    final search = SizedBox(
      height: controlHeight,
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() => _applyFilterNoSetState(resetPage: true)),
        decoration: InputDecoration(
          hintText: 'Search student, ID, subject, course, grade, or status',
          suffixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIconConstraints: BoxConstraints(minWidth: _s(40), minHeight: controlHeight),
          contentPadding: EdgeInsets.only(left: _s(12), right: _s(8), top: 0, bottom: 0),
        ),
      ),
    );
    final countPill = SizedBox(
      height: controlHeight,
      child: _SoftPill(icon: Icons.visibility_rounded, label: '$visibleStudentCount students'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _s(760)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [Expanded(child: filter), SizedBox(width: _s(8)), SizedBox(width: _s(144), child: countPill)]),
              SizedBox(height: _s(8)),
              search,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            filter,
            SizedBox(width: _s(8)),
            Expanded(child: search),
            SizedBox(width: _s(8)),
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: _s(118), maxWidth: _s(154)),
              child: countPill,
            ),
          ],
        );
      },
    );
  }

  Widget _buildPaginationBar({
    required int totalStudents,
    required int pageCount,
    required int safePageIndex,
    required int start,
    required int end,
  }) {
    final showingStart = totalStudents == 0 ? 0 : start + 1;
    final showingEnd = totalStudents == 0 ? 0 : end;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _s(9), vertical: _s(6)),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(_s(10)),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final left = SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_rounded, size: 15, color: Color(0xFF2563EB)),
                SizedBox(width: _s(6)),
                Flexible(
                  child: Text(
                    'Showing $showingStart-$showingEnd of $totalStudents students',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: _kTableFontSize),
                  ),
                ),
              ],
            ),
          );
          final right = SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildRowsPerPageSelector(),
                SizedBox(width: _s(6)),
                _PagerButtons(totalStudents: totalStudents, pageCount: pageCount, safePageIndex: safePageIndex, onPrevious: () => setState(() => _pageIndex = safePageIndex - 1), onNext: () => setState(() => _pageIndex = safePageIndex + 1)),
              ],
            ),
          );
          if (constraints.maxWidth < _s(900)) {
            return Wrap(spacing: _s(8), runSpacing: _s(6), crossAxisAlignment: WrapCrossAlignment.center, children: [left, right]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: left)),
              SizedBox(width: _s(8)),
              right,
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomControls({
    required int totalStudents,
    required int pageCount,
    required int safePageIndex,
    required int start,
    required int end,
  }) {
    final showingStart = totalStudents == 0 ? 0 : start + 1;
    final showingEnd = totalStudents == 0 ? 0 : end;
    final pageTools = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Showing $showingStart-$showingEnd of $totalStudents students', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: _kTableFontSize)),
        SizedBox(width: _s(10)),
        _buildRowsPerPageSelector(),
        SizedBox(width: _s(8)),
        _PagerButtons(totalStudents: totalStudents, pageCount: pageCount, safePageIndex: safePageIndex, onPrevious: () => setState(() => _pageIndex = safePageIndex - 1), onNext: () => setState(() => _pageIndex = safePageIndex + 1)),
      ],
    );
    final interpretationButton = OutlinedButton.icon(
      onPressed: _rows.isEmpty ? null : _generateInterpretation,
      icon: const Icon(Icons.psychology_alt_rounded, size: 16),
      label: const Text('Generate overall interpretation'),
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(fontSize: _kBodyFontSize, fontWeight: FontWeight.w800),
        padding: EdgeInsets.symmetric(horizontal: _s(13), vertical: _s(10)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(10))),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _s(980)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: pageTools),
              SizedBox(height: _s(8)),
              Align(alignment: Alignment.centerRight, child: interpretationButton),
            ],
          );
        }
        return SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: pageTools)),
              SizedBox(width: _s(12)),
              interpretationButton,
            ],
          ),
        );
      },
    );
  }

  Widget _buildRowsPerPageSelector({bool compact = false}) {
    const labelStyle = TextStyle(
      color: Color(0xFF64748B),
      fontWeight: FontWeight.w900,
      fontSize: _kTableFontSize,
      height: 1.0,
    );
    const valueStyle = TextStyle(
      color: Color(0xFF334155),
      fontWeight: FontWeight.w800,
      fontSize: _kTableFontSize,
      height: 1.0,
    );

    return SizedBox(
      height: 34,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!compact) const Text('Rows/page', style: labelStyle),
          if (!compact) SizedBox(width: _s(6)),
          Container(
            width: 68,
            height: 34,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: _s(7)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_s(10)),
              border: Border.all(color: const Color(0xFFD9E2F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _pageSize,
                isExpanded: true,
                isDense: true,
                iconSize: 14,
                style: valueStyle,
                alignment: AlignmentDirectional.center,
                selectedItemBuilder: (context) => const [
                  Center(child: Text('50', style: valueStyle, textAlign: TextAlign.center)),
                  Center(child: Text('100', style: valueStyle, textAlign: TextAlign.center)),
                  Center(child: Text('150', style: valueStyle, textAlign: TextAlign.center)),
                  Center(child: Text('250', style: valueStyle, textAlign: TextAlign.center)),
                ],
                items: const [
                  DropdownMenuItem(value: 50, alignment: AlignmentDirectional.center, child: Text('50', style: valueStyle, textAlign: TextAlign.center)),
                  DropdownMenuItem(value: 100, alignment: AlignmentDirectional.center, child: Text('100', style: valueStyle, textAlign: TextAlign.center)),
                  DropdownMenuItem(value: 150, alignment: AlignmentDirectional.center, child: Text('150', style: valueStyle, textAlign: TextAlign.center)),
                  DropdownMenuItem(value: 250, alignment: AlignmentDirectional.center, child: Text('250', style: valueStyle, textAlign: TextAlign.center)),
                ],
                onChanged: (value) => setState(() {
                  _pageSize = value ?? 50;
                  _pageIndex = 0;
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final items = [
      _LegendItem('Exists', _StatusVisual.exists.color),
      _LegendItem('Missing grade', _StatusVisual.missing.color),
      _LegendItem('Grade differs', _StatusVisual.gradeDiff.color),
      _LegendItem('Units differ', _StatusVisual.unitsDiff.color),
      _LegendItem('Student not found', _StatusVisual.studentMissing.color),
      _LegendItem('Subject not found', _StatusVisual.subjectMissing.color),
      _LegendItem('Duplicate SMS grades', _StatusVisual.duplicate.color),
      _LegendItem('Unchecked', _StatusVisual.unchecked.color),
    ];
    return Wrap(spacing: _s(10), runSpacing: _s(7), children: items);
  }

  Widget _buildResultsArea(List<_StudentGradeGroup> groups) {
    if (_rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: _s(60)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: _s(74),
              height: _s(74),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(_s(22))),
              child: const Icon(Icons.upload_file_rounded, size: 34, color: Color(0xFF2563EB)),
            ),
            SizedBox(height: _s(9)),
            const Text('No UNO rows loaded yet', style: TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900)),
            SizedBox(height: _s(4)),
            const Text('Upload the UNO promotional list to preview and check grades.', style: TextStyle(color: Color(0xFF64748B), fontSize: _kBodyFontSize)),
          ],
        ),
      );
    }

    if (groups.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: _s(50)),
        child: const Center(child: Text('No students match the selected filter/search.')),
      );
    }

    return SingleChildScrollView(
      controller: _horizontalController,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.all(_s(8)),
      child: RepaintBoundary(child: _StudentGradeTable(groups: groups, onSubjectTap: _openSubjectDetails, onStudentTap: _handleStudentTap)),
    );
  }

  Widget _buildStickyHorizontalScrollBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: _s(20),
        padding: EdgeInsets.symmetric(horizontal: _s(10), vertical: _s(2)),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, -2))],
        ),
        child: AnimatedBuilder(
          animation: _horizontalController,
          builder: (context, _) {
            final position = _horizontalController.hasClients ? _horizontalController.position : null;
            final max = position == null ? 0.0 : math.max(0.0, _safeScrollMetric(position.maxScrollExtent));
            final viewport = position == null ? 1.0 : math.max(1.0, _safeScrollMetric(position.viewportDimension, fallback: 1.0));
            final offset = position == null ? 0.0 : _safeScrollMetric(position.pixels).clamp(0.0, max).toDouble();
            final canScroll = max > 0.5;

            void jumpTo(double next) {
              if (!_horizontalController.hasClients || !canScroll) return;
              _horizontalController.jumpTo(next.clamp(0.0, max).toDouble());
            }

            return Row(
              children: [
                IconButton(
                  tooltip: 'Scroll left',
                  onPressed: !canScroll || offset <= 0 ? null : () => jumpTo(offset - 420),
                  icon: const Icon(Icons.keyboard_arrow_left_rounded, size: 15),
                  constraints: BoxConstraints.tightFor(width: _s(18), height: _s(18)),
                  padding: EdgeInsets.zero,
                ),
                Expanded(
                  child: _RoundedHorizontalScrollControl(
                    offset: offset,
                    max: max,
                    viewport: viewport,
                    onChanged: jumpTo,
                  ),
                ),
                IconButton(
                  tooltip: 'Scroll right',
                  onPressed: !canScroll || offset >= max ? null : () => jumpTo(offset + 420),
                  icon: const Icon(Icons.keyboard_arrow_right_rounded, size: 15),
                  constraints: BoxConstraints.tightFor(width: _s(18), height: _s(18)),
                  padding: EdgeInsets.zero,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}



class _ModernDialogScaffold extends StatelessWidget {
  const _ModernDialogScaffold({
    required this.title,
    required this.child,
    required this.actions,
    required this.onClose,
    this.subtitle = '',
    this.icon = Icons.info_outline_rounded,
    this.iconColor = const Color(0xFF2563EB),
    this.width = 720,
    this.maxHeightFactor = 0.90,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback onClose;
  final double width;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: _s(22), vertical: _s(18)),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(_s(18)), bottomRight: Radius.circular(_s(18))),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _s(width), maxHeight: MediaQuery.of(context).size.height * maxHeightFactor),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(_s(18), _s(16), _s(14), _s(12)),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Container(
                    width: _s(38),
                    height: _s(38),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(_s(13)),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  SizedBox(width: _s(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: _kBodyFontSize, color: Color(0xFF64748B))),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_s(18)),
                child: child,
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(_s(18), _s(10), _s(18), _s(14)),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))) ,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) SizedBox(width: _s(8)),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundedHorizontalScrollControl extends StatelessWidget {
  const _RoundedHorizontalScrollControl({
    required this.offset,
    required this.max,
    required this.viewport,
    required this.onChanged,
  });

  final double offset;
  final double max;
  final double viewport;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = math.max(1.0, constraints.maxWidth);
        final canScroll = max > 0.5;
        final totalContentWidth = math.max(viewport + max, 1.0);
        final visibleRatio = viewport <= 0 ? 0.25 : (viewport / totalContentWidth).clamp(0.12, 1.0).toDouble();
        final thumbWidth = canScroll ? math.max(_s(36), trackWidth * visibleRatio) : trackWidth;
        final travel = math.max(0.0, trackWidth - thumbWidth);
        final thumbLeft = canScroll && max > 0 ? (offset / max).clamp(0.0, 1.0).toDouble() * travel : 0.0;

        double offsetFromLocalDx(double dx) {
          if (!canScroll || travel <= 0) return 0;
          final ratio = ((dx - (thumbWidth / 2)) / travel).clamp(0.0, 1.0).toDouble();
          return ratio * max;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: canScroll ? (details) => onChanged(offsetFromLocalDx(details.localPosition.dx)) : null,
          onHorizontalDragUpdate: canScroll
              ? (details) {
                  if (travel <= 0) return;
                  onChanged(offset + (details.delta.dx / travel) * max);
                }
              : null,
          child: SizedBox(
            height: _s(6),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: _s(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Positioned(
                  left: thumbLeft,
                  child: Container(
                    width: thumbWidth,
                    height: _s(6),
                    decoration: BoxDecoration(
                      color: canScroll ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(_s(3)),
                      boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 1))],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StudentGradeGroup {
  _StudentGradeGroup({
    required this.key,
    required this.studentId,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.studentName,
    required this.course,
    required this.yearLevel,
    required this.birthDate,
    required this.excelRowNumber,
    required this.rows,
  });

  final String key;
  final String studentId;
  final String lastName;
  final String firstName;
  final String middleName;
  final String studentName;
  final String course;
  final String yearLevel;
  final String birthDate;
  final int excelRowNumber;
  final List<GradeRow> rows;

  GradeRow? rowForSubjectNo(int subjectNo) {
    for (final row in rows) {
      if (row.subjectNo == subjectNo) return row;
    }
    return null;
  }

  int get existing => rows.where((row) => row.existsInDatabase).length;
  int get missing => rows.where((row) => !row.existsInDatabase && row.studentFound == true && row.subjectFound == true).length;
  int get gradeDiff => rows.where((row) => row.gradeMatches == false).length;
  int get unitsDiff => rows.where((row) => row.unitsMatch == false).length;
  int get duplicateGrades => rows.where((row) => row.databaseMatches.length > 1).length;

  _StatusVisual get visual {
    if (rows.any((row) => row.studentFound == false)) return _StatusVisual.studentMissing;
    if (rows.any((row) => row.subjectFound == false)) return _StatusVisual.subjectMissing;
    if (rows.any((row) => !row.existsInDatabase && row.studentFound == true && row.subjectFound == true)) return _StatusVisual.missing;
    if (rows.any((row) => row.gradeMatches == false)) return _StatusVisual.gradeDiff;
    if (rows.any((row) => row.unitsMatch == false)) return _StatusVisual.unitsDiff;
    if (rows.any((row) => row.databaseMatches.length > 1)) return _StatusVisual.duplicate;
    if (rows.any((row) => !row.existsInDatabase && row.studentFound == null && row.subjectFound == null)) return _StatusVisual.unchecked;
    return _StatusVisual.exists;
  }

  Map<String, dynamic> toExportJson() {
    final subjects = <String, dynamic>{};
    for (var i = 1; i <= 10; i++) {
      final row = rowForSubjectNo(i);
      if (row != null) subjects['$i'] = row.toExportJson();
    }
    return {
      'student_id': studentId,
      'last_name': lastName,
      'first_name': firstName,
      'middle_name': middleName,
      'student_name': studentName,
      'course': course,
      'year_level': yearLevel,
      'birthdate': birthDate,
      'excel_row_number': excelRowNumber,
      'subjects': subjects,
    };
  }
}

class _StudentGradeTable extends StatelessWidget {
  const _StudentGradeTable({required this.groups, required this.onSubjectTap, required this.onStudentTap});

  final List<_StudentGradeGroup> groups;
  final void Function(GradeRow row) onSubjectTap;
  final void Function(_StudentGradeGroup group) onStudentTap;

  static double get tableWidth => _s(260) + _s(176) + (_s(150) * 10);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tableWidth,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: const TableBorder(
          horizontalInside: BorderSide(color: Color(0xFFE2E8F0)),
          verticalInside: BorderSide(color: Color(0xFFE2E8F0)),
          top: BorderSide(color: Color(0xFFE2E8F0)),
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
          left: BorderSide(color: Color(0xFFE2E8F0)),
          right: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        columnWidths: _columnWidths(),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
            children: [
              _headerCell('Student'),
              _headerCell('Course / Year'),
              for (var i = 1; i <= 10; i++) _headerCell('Subject $i'),
            ],
          ),
          for (var groupIndex = 0; groupIndex < groups.length; groupIndex++)
            TableRow(
              decoration: BoxDecoration(color: groupIndex.isEven ? Colors.white : const Color(0xFFFBFDFF)),
              children: [
                _studentCell(groups[groupIndex], onStudentTap),
                _courseCell(groups[groupIndex]),
                for (var i = 1; i <= 10; i++) _subjectCell(groups[groupIndex].rowForSubjectNo(i), onSubjectTap),
              ],
            ),
        ],
      ),
    );
  }

  static Map<int, TableColumnWidth> _columnWidths() {
    return {
      0: FixedColumnWidth(_s(260)),
      1: FixedColumnWidth(_s(176)),
      for (var i = 2; i <= 11; i++) i: FixedColumnWidth(_s(150)),
    };
  }

  static Widget _headerCell(String label) {
    return Container(
      height: _s(34),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: _s(8)),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: _kBodyFontSize)),
    );
  }

  static Widget _studentCell(_StudentGradeGroup group, void Function(_StudentGradeGroup group) onStudentTap) {
    final visual = group.visual;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onStudentTap(group),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: _s(_kDataRowHeight),
          padding: EdgeInsets.all(_s(8)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _s(5),
                height: double.infinity,
                decoration: BoxDecoration(color: visual.color, borderRadius: BorderRadius.circular(99)),
              ),
              SizedBox(width: _s(9)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.studentName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: _kTableFontSize)),
                    SizedBox(height: _s(3)),
                    Text('ID: ${group.studentId.isEmpty ? 'N/A' : group.studentId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: _kTableFontSize, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Wrap(
                      spacing: _s(5),
                      runSpacing: _s(5),
                      children: [
                        _SmallBadge(label: '${group.rows.length} subj'),
                        _SmallBadge(label: '${group.existing} existing'),
                        if (group.missing > 0) _SmallBadge(label: '${group.missing} missing'),
                        if (group.gradeDiff + group.unitsDiff > 0) _SmallBadge(label: '${group.gradeDiff + group.unitsDiff} diff'),
                        if (group.duplicateGrades > 0) _SmallBadge(label: '${group.duplicateGrades} dup'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _courseCell(_StudentGradeGroup group) {
    return Container(
      height: _s(_kDataRowHeight),
      padding: EdgeInsets.all(_s(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Course', style: TextStyle(fontSize: _kTableFontSize, color: Color(0xFF94A3B8), fontWeight: FontWeight.w900)),
          SizedBox(height: _s(2)),
          Expanded(
            child: Text(
              group.course.isEmpty ? '-' : group.course,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: _kTableFontSize),
            ),
          ),
          SizedBox(height: _s(6)),
          const Text('Year', style: TextStyle(fontSize: _kTableFontSize, color: Color(0xFF94A3B8), fontWeight: FontWeight.w900)),
          SizedBox(height: _s(2)),
          Text(group.yearLevel.isEmpty ? '-' : group.yearLevel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475569), fontSize: _kTableFontSize)),
        ],
      ),
    );
  }

  static Widget _subjectCell(GradeRow? row, void Function(GradeRow row) onSubjectTap) {
    if (row == null) {
      return Container(
        height: _s(_kDataRowHeight),
        padding: EdgeInsets.all(_s(6)),
        alignment: Alignment.center,
        child: Container(
          height: double.infinity,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(_s(9)),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Text('-', style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w900)),
        ),
      );
    }

    final visual = _visualForRow(row);
    final description = row.excelSubjectDescription.trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSubjectTap(row),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: _s(_kDataRowHeight),
          padding: EdgeInsets.all(_s(5)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: visual.background,
              borderRadius: BorderRadius.circular(_s(9)),
              border: Border.all(color: visual.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(_s(6)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: _s(6.5), height: _s(6.5), decoration: BoxDecoration(color: visual.color, shape: BoxShape.circle)),
                      SizedBox(width: _s(5)),
                      Expanded(child: Text(row.subjectCode, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: _kTableFontSize))),
                      if (row.otherPeriodMatches.isNotEmpty)
                        const Icon(Icons.history_rounded, color: Color(0xFF475569), size: 12),
                      if (row.databaseMatches.length > 1)
                        Icon(Icons.control_point_duplicate_rounded, color: _StatusVisual.duplicate.color, size: 13),
                    ],
                  ),
                  SizedBox(height: _s(2)),
                  SizedBox(
                    height: _s(40),
                    child: Text(
                      description.isEmpty ? 'No UNO description' : description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _kTableFontSize,
                        color: description.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _SubjectLine(label: 'G', excel: row.excelGrade, db: row.databaseGrade, warn: row.gradeMatches == false),
                  SizedBox(height: _s(1)),
                  _SubjectLine(label: 'U', excel: row.units, db: row.databaseCredits ?? row.subjectUnits, warn: row.unitsMatch == false),
                  SizedBox(height: _s(2)),
                  Text(row.statusLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: _kTableFontSize, fontWeight: FontWeight.w900, color: visual.color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectLine extends StatelessWidget {
  const _SubjectLine({required this.label, required this.excel, required this.db, required this.warn});

  final String label;
  final String excel;
  final String? db;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final dbValue = db == null || db!.trim().isEmpty ? '-' : db!.trim();
    final excelValue = excel.trim().isEmpty ? '-' : excel.trim();
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: _kTableFontSize, color: Color(0xFF334155)),
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          TextSpan(text: excelValue, style: const TextStyle(fontWeight: FontWeight.w900)),
          const TextSpan(text: ' / '),
          TextSpan(text: dbValue, style: TextStyle(fontWeight: FontWeight.w900, color: warn ? const Color(0xFFB45309) : const Color(0xFF334155))),
        ],
      ),
    );
  }
}

class _PagerButtons extends StatelessWidget {
  const _PagerButtons({required this.totalStudents, required this.pageCount, required this.safePageIndex, required this.onPrevious, required this.onNext});

  final int totalStudents;
  final int pageCount;
  final int safePageIndex;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: 'Previous page',
          onPressed: safePageIndex <= 0 ? null : onPrevious,
          icon: const Icon(Icons.chevron_left_rounded, size: 14),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
        ),
        SizedBox(width: _s(4)),
        Text('Page ${totalStudents == 0 ? 0 : safePageIndex + 1} of ${totalStudents == 0 ? 0 : pageCount}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: _kTableFontSize)),
        SizedBox(width: _s(4)),
        IconButton.filledTonal(
          tooltip: 'Next page',
          onPressed: safePageIndex >= pageCount - 1 || totalStudents == 0 ? null : onNext,
          icon: const Icon(Icons.chevron_right_rounded, size: 14),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}


class _SubjectCatalogTable extends StatelessWidget {
  const _SubjectCatalogTable({required this.subjects});

  final List<SubjectCatalogRecord> subjects;

  @override
  Widget build(BuildContext context) {
    return Table(
      border: const TableBorder(
        horizontalInside: BorderSide(color: Color(0xFFE2E8F0)),
        verticalInside: BorderSide(color: Color(0xFFE2E8F0)),
        top: BorderSide(color: Color(0xFFE2E8F0)),
        bottom: BorderSide(color: Color(0xFFE2E8F0)),
        left: BorderSide(color: Color(0xFFE2E8F0)),
        right: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      columnWidths: const {
        0: FixedColumnWidth(70),
        1: FixedColumnWidth(110),
        2: FlexColumnWidth(),
        3: FixedColumnWidth(70),
      },
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            _TinyHeader('ID'),
            _TinyHeader('Code'),
            _TinyHeader('Description'),
            _TinyHeader('Units'),
          ],
        ),
        for (final subject in subjects)
          TableRow(
            children: [
              _TinyCell(subject.subjectId),
              _TinyCell(subject.subjectCode),
              _TinyCell(subject.subjectDescription),
              _TinyCell(subject.subjectUnits),
            ],
          ),
      ],
    );
  }
}

class _DatabaseMatchesTable extends StatelessWidget {
  const _DatabaseMatchesTable({required this.matches});

  final List<DatabaseGradeRecord> matches;

  @override
  Widget build(BuildContext context) {
    return Table(
      border: const TableBorder(
        horizontalInside: BorderSide(color: Color(0xFFE2E8F0)),
        verticalInside: BorderSide(color: Color(0xFFE2E8F0)),
        top: BorderSide(color: Color(0xFFE2E8F0)),
        bottom: BorderSide(color: Color(0xFFE2E8F0)),
        left: BorderSide(color: Color(0xFFE2E8F0)),
        right: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      columnWidths: const {
        0: FixedColumnWidth(75),
        1: FixedColumnWidth(130),
        2: FixedColumnWidth(70),
        3: FixedColumnWidth(70),
        4: FlexColumnWidth(),
        5: FixedColumnWidth(80),
        6: FixedColumnWidth(80),
      },
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            _TinyHeader('Ref'),
            _TinyHeader('Academic year'),
            _TinyHeader('Grade'),
            _TinyHeader('Credits'),
            _TinyHeader('Description'),
            _TinyHeader('Course'),
            _TinyHeader('Status'),
          ],
        ),
        for (final match in matches)
          TableRow(
            children: [
              _TinyCell(match.reference),
              _TinyCell(match.periodLabel.isNotEmpty ? match.periodLabel : match.periodId),
              _TinyCell(match.grade),
              _TinyCell(match.credits.isNotEmpty ? match.credits : match.subjectUnits),
              _TinyCell(match.subjectDescription),
              _TinyCell(match.courseCode),
              _TinyCell(match.gradeStatus),
            ],
          ),
      ],
    );
  }
}

class _TinyHeader extends StatelessWidget {
  const _TinyHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(_s(7)),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: _kTableFontSize)),
    );
  }
}

class _TinyCell extends StatelessWidget {
  const _TinyCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(_s(7)),
      child: Text(text.isEmpty ? '-' : text, style: const TextStyle(fontSize: _kTableFontSize)),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _s(10), vertical: _s(7)),
      decoration: BoxDecoration(color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.35))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: _kTableFontSize)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontSize: _kTableFontSize)),
        ],
      ),
    );
  }
}

class _InterpretationCard extends StatelessWidget {
  const _InterpretationCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(_s(12)),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(_s(14)),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology_alt_rounded, color: Color(0xFF1D4ED8), size: 18),
              SizedBox(width: 8),
              Text('Overall interpretation', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A))),
            ],
          ),
          SizedBox(height: _s(8)),
          Text(text, style: const TextStyle(color: Color(0xFF1E3A8A), height: 1.35, fontSize: _kBodyFontSize)),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Padding(
        padding: EdgeInsets.symmetric(vertical: _s(10)),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      ),
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(10)))),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(_s(8)),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(_s(15)),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: _s(29),
            height: _s(29),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(_s(11))),
            child: Icon(icon, size: 15, color: const Color(0xFF2563EB)),
          ),
          SizedBox(width: _s(8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: _kTableFontSize)),
                SizedBox(height: _s(1)),
                Text(value, style: const TextStyle(fontSize: _kHeaderFontSize, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _s(9), vertical: _s(6)),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: _s(9), height: _s(9), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          SizedBox(width: _s(6)),
          Text(label, style: const TextStyle(fontSize: _kTableFontSize, fontWeight: FontWeight.w900, color: Color(0xFF334155))),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _s(6), vertical: _s(3)),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Text(label, style: const TextStyle(fontSize: _kTableFontSize, fontWeight: FontWeight.w900, color: Color(0xFF475569))),
    );
  }
}

class _SoftPill extends StatelessWidget {
  const _SoftPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: _s(400)),
      padding: EdgeInsets.symmetric(horizontal: _s(10), vertical: 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2563EB)),
          SizedBox(width: _s(6)),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: _kTableFontSize))),
        ],
      ),
    );
  }
}

class _StatusVisual {
  const _StatusVisual({required this.label, required this.color, required this.background, required this.border});

  final String label;
  final Color color;
  final Color background;
  final Color border;

  static const exists = _StatusVisual(label: 'Exists', color: Color(0xFF16A34A), background: Color(0xFFECFDF5), border: Color(0xFF86EFAC));
  static const missing = _StatusVisual(label: 'Missing grade', color: Color(0xFFDC2626), background: Color(0xFFFEF2F2), border: Color(0xFFFECACA));
  static const gradeDiff = _StatusVisual(label: 'Grade differs', color: Color(0xFFD97706), background: Color(0xFFFFFBEB), border: Color(0xFFFCD34D));
  static const unitsDiff = _StatusVisual(label: 'Units differ', color: Color(0xFF0891B2), background: Color(0xFFECFEFF), border: Color(0xFF67E8F9));
  static const studentMissing = _StatusVisual(label: 'Student not found', color: Color(0xFFBE123C), background: Color(0xFFFFF1F2), border: Color(0xFFFDA4AF));
  static const subjectMissing = _StatusVisual(label: 'Subject not found', color: Color(0xFFC2410C), background: Color(0xFFFFF7ED), border: Color(0xFFFDBA74));
  static const duplicate = _StatusVisual(label: 'Duplicate SMS grades', color: Color(0xFF7C3AED), background: Color(0xFFF5F3FF), border: Color(0xFFC4B5FD));
  static const unchecked = _StatusVisual(label: 'Unchecked', color: Color(0xFF64748B), background: Color(0xFFF1F5F9), border: Color(0xFFCBD5E1));
}

_StatusVisual _visualForRow(GradeRow row) {
  if (row.studentFound == false) return _StatusVisual.studentMissing;
  if (row.subjectFound == false) return _StatusVisual.subjectMissing;
  if (!row.existsInDatabase && row.studentFound == null && row.subjectFound == null) return _StatusVisual.unchecked;
  if (!row.existsInDatabase && row.studentFound == true && row.subjectFound == true) return _StatusVisual.missing;
  if (row.gradeMatches == false) return _StatusVisual.gradeDiff;
  if (row.unitsMatch == false) return _StatusVisual.unitsDiff;
  if (row.databaseMatches.length > 1) return _StatusVisual.duplicate;
  return _StatusVisual.exists;
}
