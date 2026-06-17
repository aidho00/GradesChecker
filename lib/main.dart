import 'dart:async';
import 'dart:collection';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'models/grade_period.dart';
import 'models/grade_row.dart';
import 'services/grade_check_api.dart';

const double _uiScale = 0.78;
double _s(num value) => value * _uiScale;

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
          labelStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
          floatingLabelStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w800),
          hintStyle: const TextStyle(fontSize: 12.0, color: Color(0xFF64748B)),
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
    _loadPeriods();
  }

  @override
  void dispose() {
    _apiController.dispose();
    _searchController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  GradeCheckApi get _api => GradeCheckApi(endpointUrl: _apiController.text.trim());

  bool get _hasProgress => _isBusy && _operationLabel.trim().isNotEmpty;
  double? get _progressValue {
    if (!_hasProgress || _operationTotal <= 0) return null;
    return (_operationDone / _operationTotal).clamp(0, 1).toDouble();
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
      'Duplicate DB grades' => group.rows.any((row) => row.databaseMatches.length > 1),
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

  List<_StudentGradeGroup> _groupByStudent(List<GradeRow> source) {
    final map = LinkedHashMap<String, _StudentGradeGroup>();
    for (final row in source) {
      final key = row.studentId.trim().isNotEmpty
          ? row.studentId.trim()
          : '${row.lastName}|${row.firstName}|${row.middleName}';
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

  Future<void> _loadPeriods() async {
    setState(() {
      _loadingPeriods = true;
      _status = 'Loading academic years from Database...';
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
            ? 'No academic years found in tbl_period. Import the database data first.'
            : 'Select an academic year, then upload the UNO promotional list.';
      });
    } catch (error) {
      setState(() {
        _status = 'Unable to load academic years. Check Apache/Database and Connection settings. $error';
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
            _operationLabel = 'Uploading Excel • ${_formatBytes(uploaded)} / ${_formatBytes(total)}';
            _status = 'Uploading ${file.name}... ${_formatBytes(uploaded)} of ${_formatBytes(total)}';
          });
        },
        onPhase: (phase) {
          if (!mounted) return;
          setState(() {
            _operationLabel = phase;
            _operationDone = 0;
            _operationTotal = 0;
            _status = phase == 'Decoding parsed Excel response'
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
      setState(() => _status = 'Excel upload/parsing failed: $error');
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
      setState(() => _status = 'Please upload and parse an Excel file first.');
      return;
    }

    final liveRows = List<GradeRow>.from(_rows);
    setState(() {
      _rows = liveRows;
      _isBusy = true;
      _operationLabel = 'Checking database in batches';
      _operationDone = 0;
      _operationTotal = liveRows.length;
      _interpretation = null;
      _status = 'Checking database in smaller batches to keep the browser responsive... 0 / ${liveRows.length}';
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
            _status = 'Checking database in smaller batches... $checked / $total';
          });
        },
      );

      setState(() {
        _rows = checkedRows;
        _refreshDerivedData(resetPage: false);
        _status = 'Done. Existing: $_existingCount, Missing: $_missingCount, Grade differs: $_gradeDiffCount, Units differ: $_unitsDiffCount, Duplicate DB grades: $_duplicateGradeCount.';
      });
    } catch (error) {
      setState(() => _status = 'Database check failed: $error');
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
      _operationLabel = 'Generating formatted Excel export';
      _operationDone = 0;
      _operationTotal = _studentCount;
      _status = 'Generating formatted Excel-compatible export on the PHP API...';
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
      return 'No UNO promotional-list data has been loaded yet. Upload the file and run the database check first.';
    }

    final total = _rows.length;
    final issueCount = _missingCount + _gradeDiffCount + _unitsDiffCount + _studentMissingCount + _subjectMissingCount;
    final existingPct = total == 0 ? 0.0 : (_existingCount / total) * 100;
    final issuePct = total == 0 ? 0.0 : (issueCount / total) * 100;
    final duplicateText = _duplicateGradeCount > 0
        ? ' There are also $_duplicateGradeCount subject entries with more than one matching grade record in the database; tap the subject cells to inspect all DB grades.'
        : '';

    final overall = issueCount == 0 && _checkedCount == total
        ? 'Overall, the uploaded Excel file is consistent with the selected database period.'
        : issuePct <= 5 && _checkedCount == total
            ? 'Overall, the uploaded Excel file is mostly consistent with the selected database period, with only a small number of records requiring review.'
            : 'Overall, the uploaded Excel file still needs review before it can be considered fully matched with the selected database period.';

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
        return AlertDialog(
          title: const Text('Connection settings'),
          content: SizedBox(
            width: _s(560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Change this only when Apache is running on another port, folder, or server IP.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                SizedBox(height: _s(10)),
                TextField(
                  controller: _apiController,
                  enabled: !_isBusy,
                  decoration: const InputDecoration(
                    labelText: 'API endpoint',
                    prefixIcon: Icon(Icons.link_rounded),
                    hintText: 'http://localhost/grades_checker_api/check_grades.php',
                  ),
                ),
              ],
            ),
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
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Save & reload periods'),
            ),
          ],
        );
      },
    );
  }

  void _openSubjectDetails(GradeRow row) {
    final visual = _visualForRow(row);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          titlePadding: EdgeInsets.fromLTRB(_s(20), _s(16), _s(20), _s(8)),
          contentPadding: EdgeInsets.fromLTRB(_s(20), 0, _s(20), _s(14)),
          title: Row(
            children: [
              Container(width: _s(10), height: _s(10), decoration: BoxDecoration(color: visual.color, shape: BoxShape.circle)),
              SizedBox(width: _s(10)),
              Expanded(child: Text(row.subjectCode.isEmpty ? 'Subject details' : row.subjectCode, style: const TextStyle(fontWeight: FontWeight.w900))),
            ],
          ),
          content: SizedBox(
            width: _s(780),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(row.subjectDescription?.trim().isNotEmpty == true ? row.subjectDescription! : 'No subject description returned yet.', style: const TextStyle(color: Color(0xFF475569))),
                  SizedBox(height: _s(12)),
                  Wrap(
                    spacing: _s(8),
                    runSpacing: _s(8),
                    children: [
                      _DetailPill(label: 'Status', value: row.statusLabel, color: visual.color),
                      _DetailPill(label: 'Excel grade', value: row.excelGrade.isEmpty ? '-' : row.excelGrade, color: const Color(0xFF2563EB)),
                      _DetailPill(label: 'Excel units', value: row.units.isEmpty ? '-' : row.units, color: const Color(0xFF2563EB)),
                      _DetailPill(label: 'DB grade', value: row.databaseGrade?.trim().isNotEmpty == true ? row.databaseGrade! : '-', color: const Color(0xFF334155)),
                      _DetailPill(label: 'DB units', value: row.databaseCredits?.trim().isNotEmpty == true ? row.databaseCredits! : '-', color: const Color(0xFF334155)),
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
                      child: Text(row.message!, style: TextStyle(color: visual.color, fontWeight: FontWeight.w800)),
                    ),
                  SizedBox(height: _s(14)),
                  Text('Selected-period grade records (${row.databaseMatches.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  SizedBox(height: _s(8)),
                  if (row.databaseMatches.isEmpty)
                    const Text('No database grade record returned for this subject and selected period.', style: TextStyle(color: Color(0xFF64748B)))
                  else
                    _DatabaseMatchesTable(matches: row.databaseMatches),
                  SizedBox(height: _s(16)),
                  Text('Other-period grade records (${row.otherPeriodMatches.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  SizedBox(height: _s(8)),
                  if (row.otherPeriodMatches.isEmpty)
                    const Text('No grade record found for this same student and subject in other academic periods.', style: TextStyle(color: Color(0xFF64748B)))
                  else
                    _DatabaseMatchesTable(matches: row.otherPeriodMatches),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _visibleGroups;

    return Scaffold(
      bottomNavigationBar: _rows.isEmpty ? null : _buildStickyHorizontalScrollBar(),
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
              Text('UNO to SMS Grade Checker', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              SizedBox(height: 2),
              Text(
                'Cross-check legacy UNO promotional-list grades against current SMS Database grade records.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
        if (_selectedPeriod != null) ...[
          SizedBox(
            height: _s(36),
            child: _SoftPill(icon: Icons.calendar_month_rounded, label: _selectedPeriod!.label),
          ),
          SizedBox(width: _s(8)),
        ],
        SizedBox(
          height: _s(36),
          child: OutlinedButton.icon(
            onPressed: _openConnectionSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Connection'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: _s(14)),
              textStyle: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w800),
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
                      Text('UNO import check setup', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      SizedBox(height: 3),
                      Text('Select the SMS academic year, upload the UNO promotional list, then run the comparison.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(10))),
                );
                Widget uploadButton({double? width}) => SizedBox(
                      width: width,
                      height: controlHeight,
                      child: FilledButton.icon(
                        onPressed: _isBusy ? null : _pickExcel,
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Upload Excel', maxLines: 1)),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: _s(12)),
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
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Check', maxLines: 1)),
                        style: buttonStyle,
                      ),
                    );
                Widget exportButton({double? width}) => SizedBox(
                      width: width,
                      height: controlHeight,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy || _rows.isEmpty ? null : _exportExcel,
                        icon: const Icon(Icons.file_download_rounded, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Export Excel', maxLines: 1)),
                        style: buttonStyle,
                      ),
                    );

                if (constraints.maxWidth < _s(900)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: controlHeight, child: _buildPeriodSelector()),
                      SizedBox(height: _s(8)),
                      Row(
                        children: [
                          Expanded(child: uploadButton()),
                          SizedBox(width: _s(8)),
                          Expanded(child: checkButton()),
                          SizedBox(width: _s(8)),
                          Expanded(child: exportButton()),
                        ],
                      ),
                    ],
                  );
                }

                final uploadWidth = constraints.maxWidth < _s(1120) ? _s(126) : _s(142);
                final checkWidth = constraints.maxWidth < _s(1120) ? _s(92) : _s(104);
                final exportWidth = constraints.maxWidth < _s(1120) ? _s(130) : _s(146);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: SizedBox(height: controlHeight, child: _buildPeriodSelector())),
                    SizedBox(width: _s(8)),
                    uploadButton(width: uploadWidth),
                    SizedBox(width: _s(8)),
                    checkButton(width: checkWidth),
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
                child: Text(period.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
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
              Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
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
          Expanded(child: Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: failed ? const Color(0xFF991B1B) : const Color(0xFF1E3A8A), fontSize: 12))),
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
      _MetricCard(label: 'Duplicate DB', value: _duplicateGradeCount.toString(), icon: Icons.control_point_duplicate_rounded),
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
    final filter = SizedBox(
      width: _s(118),
      height: controlHeight,
      child: DropdownButtonFormField<String>(
        value: _filter,
        isDense: true,
        isExpanded: true,
        iconSize: 16,
        decoration: InputDecoration(
          hintText: 'Filter',
          prefixIcon: const Icon(Icons.filter_alt_rounded, size: 17),
          prefixIconConstraints: BoxConstraints(minWidth: _s(32), minHeight: controlHeight),
          contentPadding: EdgeInsets.symmetric(horizontal: _s(8), vertical: 0),
        ),
        items: const [
          DropdownMenuItem(value: 'All', child: Text('All')),
          DropdownMenuItem(value: 'Existing', child: Text('Existing')),
          DropdownMenuItem(value: 'Missing', child: Text('Missing')),
          DropdownMenuItem(value: 'Grade differs', child: Text('Grade differs')),
          DropdownMenuItem(value: 'Units differ', child: Text('Units differ')),
          DropdownMenuItem(value: 'Student not found', child: Text('Student not found')),
          DropdownMenuItem(value: 'Subject not found', child: Text('Subject not found')),
          DropdownMenuItem(value: 'Duplicate DB grades', child: Text('Duplicate DB grades')),
        ],
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
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: 11.0),
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
        Text('Showing $showingStart-$showingEnd of $totalStudents students', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: 11.3)),
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
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _s(980)) {
          return Wrap(spacing: _s(12), runSpacing: _s(8), crossAxisAlignment: WrapCrossAlignment.center, children: [pageTools, interpretationButton]);
        }
        return Row(children: [Flexible(child: pageTools), const Spacer(), interpretationButton]);
      },
    );
  }

  Widget _buildRowsPerPageSelector({bool compact = false}) {
    const labelStyle = TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900, fontSize: 11.0, height: 1.0);
    const valueStyle = TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w800, fontSize: 11.0, height: 1.0);
    return SizedBox(
      height: 34,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!compact) const Text('Rows/page', style: labelStyle),
          if (!compact) SizedBox(width: _s(6)),
          SizedBox(
            width: 68,
            height: 34,
            child: DropdownButtonFormField<int>(
              value: _pageSize,
              isDense: true,
              isExpanded: true,
              iconSize: 14,
              style: valueStyle,
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: _s(8), vertical: 0),
                isDense: true,
              ),
              selectedItemBuilder: (context) => const [
                Center(child: Text('50', style: valueStyle, textAlign: TextAlign.center)),
                Center(child: Text('100', style: valueStyle, textAlign: TextAlign.center)),
                Center(child: Text('150', style: valueStyle, textAlign: TextAlign.center)),
                Center(child: Text('250', style: valueStyle, textAlign: TextAlign.center)),
              ],
              items: const [
                DropdownMenuItem(value: 50, child: Center(child: Text('50', style: valueStyle, textAlign: TextAlign.center))),
                DropdownMenuItem(value: 100, child: Center(child: Text('100', style: valueStyle, textAlign: TextAlign.center))),
                DropdownMenuItem(value: 150, child: Center(child: Text('150', style: valueStyle, textAlign: TextAlign.center))),
                DropdownMenuItem(value: 250, child: Center(child: Text('250', style: valueStyle, textAlign: TextAlign.center))),
              ],
              onChanged: (value) => setState(() {
                _pageSize = value ?? 50;
                _pageIndex = 0;
              }),
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
      _LegendItem('Duplicate DB grades', _StatusVisual.duplicate.color),
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
            const Text('No Excel rows loaded yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            SizedBox(height: _s(4)),
            const Text('Upload the UNO promotional list to preview and check grades.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
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

    return Scrollbar(
      controller: _horizontalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.all(_s(8)),
        child: RepaintBoundary(child: _StudentGradeTable(groups: groups, onSubjectTap: _openSubjectDetails)),
      ),
    );
  }

  Widget _buildStickyHorizontalScrollBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: _s(40),
        padding: EdgeInsets.symmetric(horizontal: _s(12), vertical: _s(4)),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, -3))],
        ),
        child: AnimatedBuilder(
          animation: _horizontalController,
          builder: (context, _) {
            final hasClients = _horizontalController.hasClients;
            final max = hasClients ? math.max(0.0, _horizontalController.position.maxScrollExtent) : 0.0;
            final offset = hasClients ? _horizontalController.offset.clamp(0.0, max).toDouble() : 0.0;
            final canScroll = max > 0.5;

            void jumpTo(double next) {
              if (!hasClients || !canScroll) return;
              _horizontalController.jumpTo(next.clamp(0.0, max).toDouble());
            }

            return Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, size: 16, color: Color(0xFF2563EB)),
                SizedBox(width: _s(6)),
                const Text('Horizontal', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF334155))),
                SizedBox(width: _s(8)),
                IconButton(
                  tooltip: 'Scroll left',
                  onPressed: !canScroll || offset <= 0 ? null : () => jumpTo(offset - 420),
                  icon: const Icon(Icons.keyboard_arrow_left_rounded, size: 18),
                  constraints: BoxConstraints.tightFor(width: _s(28), height: _s(28)),
                  padding: EdgeInsets.zero,
                ),
                Expanded(
                  child: Slider(
                    value: canScroll ? offset : 0,
                    min: 0,
                    max: canScroll ? max : 1,
                    onChanged: canScroll ? jumpTo : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Scroll right',
                  onPressed: !canScroll || offset >= max ? null : () => jumpTo(offset + 420),
                  icon: const Icon(Icons.keyboard_arrow_right_rounded, size: 18),
                  constraints: BoxConstraints.tightFor(width: _s(28), height: _s(28)),
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
      'excel_row_number': excelRowNumber,
      'subjects': subjects,
    };
  }
}

class _StudentGradeTable extends StatelessWidget {
  const _StudentGradeTable({required this.groups, required this.onSubjectTap});

  final List<_StudentGradeGroup> groups;
  final void Function(GradeRow row) onSubjectTap;

  static double get tableWidth => _s(258) + _s(112) + (_s(145) * 10);

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
                _studentCell(groups[groupIndex]),
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
      0: FixedColumnWidth(_s(250)),
      1: FixedColumnWidth(_s(104)),
      for (var i = 2; i <= 11; i++) i: FixedColumnWidth(_s(137)),
    };
  }

  static Widget _headerCell(String label) {
    return Container(
      height: _s(34),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: _s(8)),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: 12)),
    );
  }

  static Widget _studentCell(_StudentGradeGroup group) {
    final visual = group.visual;
    return Container(
      constraints: BoxConstraints(minHeight: _s(72)),
      padding: EdgeInsets.all(_s(7)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: _s(5), height: _s(52), decoration: BoxDecoration(color: visual.color, borderRadius: BorderRadius.circular(99))),
          SizedBox(width: _s(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.studentName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
                SizedBox(height: _s(3)),
                Text('ID: ${group.studentId.isEmpty ? 'N/A' : group.studentId}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.w800)),
                SizedBox(height: _s(4)),
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
    );
  }

  static Widget _courseCell(_StudentGradeGroup group) {
    return Container(
      constraints: BoxConstraints(minHeight: _s(72)),
      padding: EdgeInsets.all(_s(7)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Course', style: TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w900)),
          SizedBox(height: _s(2)),
          Text(group.course.isEmpty ? '-' : group.course, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
          SizedBox(height: _s(8)),
          const Text('Year', style: TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w900)),
          SizedBox(height: _s(2)),
          Text(group.yearLevel.isEmpty ? '-' : group.yearLevel, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475569), fontSize: 10.5)),
        ],
      ),
    );
  }

  static Widget _subjectCell(GradeRow? row, void Function(GradeRow row) onSubjectTap) {
    if (row == null) {
      return Container(
        constraints: BoxConstraints(minHeight: _s(70)),
        padding: EdgeInsets.all(_s(6)),
        alignment: Alignment.center,
        child: const Text('-', style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w900)),
      );
    }

    final visual = _visualForRow(row);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSubjectTap(row),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          constraints: BoxConstraints(minHeight: _s(70)),
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
                      Expanded(child: Text(row.subjectCode, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5))),
                      if (row.otherPeriodMatches.isNotEmpty)
                        const Icon(Icons.history_rounded, color: Color(0xFF475569), size: 12),
                      if (row.databaseMatches.length > 1)
                        Icon(Icons.control_point_duplicate_rounded, color: _StatusVisual.duplicate.color, size: 13),
                    ],
                  ),
                  SizedBox(height: _s(3)),
                  _SubjectLine(label: 'G', excel: row.excelGrade, db: row.databaseGrade, warn: row.gradeMatches == false),
                  SizedBox(height: _s(1)),
                  _SubjectLine(label: 'U', excel: row.units, db: row.databaseCredits ?? row.subjectUnits, warn: row.unitsMatch == false),
                  SizedBox(height: _s(2)),
                  Text(row.statusLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8.6, fontWeight: FontWeight.w900, color: visual.color)),
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
        style: const TextStyle(fontSize: 9.2, color: Color(0xFF334155)),
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
        Text('Page ${totalStudents == 0 ? 0 : safePageIndex + 1} of ${totalStudents == 0 ? 0 : pageCount}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5)),
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
            _TinyHeader('Period'),
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
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5)),
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
      child: Text(text.isEmpty ? '-' : text, style: const TextStyle(fontSize: 10.5)),
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
          Text('$label: ', style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 10.5)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontSize: 10.5)),
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
          Text(text, style: const TextStyle(color: Color(0xFF1E3A8A), height: 1.35, fontSize: 12)),
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
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
                SizedBox(height: _s(1)),
                Text(value, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
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
          Text(label, style: const TextStyle(fontSize: 10.8, fontWeight: FontWeight.w900, color: Color(0xFF334155))),
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
      child: Text(label, style: const TextStyle(fontSize: 8.8, fontWeight: FontWeight.w900, color: Color(0xFF475569))),
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
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155), fontSize: 10.7))),
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
  static const duplicate = _StatusVisual(label: 'Duplicate DB grades', color: Color(0xFF7C3AED), background: Color(0xFFF5F3FF), border: Color(0xFFC4B5FD));
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
