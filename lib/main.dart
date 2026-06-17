import 'dart:collection';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models/grade_period.dart';
import 'models/grade_row.dart';
import 'services/excel_parser.dart';
import 'services/grade_check_api.dart';

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
      title: 'Grades Checker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F6FB),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE5EAF3)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E2F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E2F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: seed, width: 1.4),
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

  List<GradePeriod> _periods = [];
  GradePeriod? _selectedPeriod;
  List<GradeRow> _rows = [];
  String _fileName = '';
  String _status = 'Start by choosing a period, then upload the HEMIS Excel file.';
  String _filter = 'All';
  bool _isBusy = false;
  bool _loadingPeriods = false;
  int _operationDone = 0;
  int _operationTotal = 0;
  String _operationLabel = '';

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  @override
  void dispose() {
    _apiController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  GradeCheckApi get _api => GradeCheckApi(endpointUrl: _apiController.text.trim());

  List<GradeRow> get _visibleRows {
    final query = _searchController.text.trim().toLowerCase();
    return _rows.where((row) {
      if (!_passesFilter(row)) return false;
      if (query.isEmpty) return true;
      final combined = [
        row.studentId,
        row.studentName,
        row.firstName,
        row.lastName,
        row.middleName,
        row.subjectCode,
        row.subjectDescription ?? '',
        row.course,
        row.databaseCourse ?? '',
        row.excelGrade,
        row.databaseGrade ?? '',
      ].join(' ').toLowerCase();
      return combined.contains(query);
    }).toList(growable: false);
  }

  List<_StudentGradeGroup> get _visibleStudentGroups => _groupByStudent(_visibleRows);

  int get _existingCount => _rows.where((row) => row.existsInDatabase).length;
  int get _missingCount => _rows.where((row) => !row.existsInDatabase && row.studentFound == true && row.subjectFound == true).length;
  int get _gradeDiffCount => _rows.where((row) => row.gradeMatches == false).length;
  int get _unitsDiffCount => _rows.where((row) => row.unitsMatch == false).length;
  int get _studentMissingCount => _rows.where((row) => row.studentFound == false).length;
  int get _subjectMissingCount => _rows.where((row) => row.subjectFound == false).length;
  int get _checkedCount => _rows.where((row) => row.studentFound != null || row.subjectFound != null || row.existsInDatabase).length;
  int get _studentCount => _groupByStudent(_rows).length;

  bool get _hasProgress => _isBusy && _operationLabel.trim().isNotEmpty;
  double? get _progressValue {
    if (!_hasProgress || _operationTotal <= 0) return null;
    return (_operationDone / _operationTotal).clamp(0, 1).toDouble();
  }

  bool _passesFilter(GradeRow row) {
    return switch (_filter) {
      'Existing' => row.existsInDatabase && row.gradeMatches != false && row.unitsMatch != false,
      'Missing' => !row.existsInDatabase && row.studentFound == true && row.subjectFound == true,
      'Grade differs' => row.gradeMatches == false,
      'Units differ' => row.unitsMatch == false,
      'Student not found' => row.studentFound == false,
      'Subject not found' => row.subjectFound == false,
      _ => true,
    };
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

  Future<void> _loadPeriods() async {
    setState(() {
      _loadingPeriods = true;
      _status = 'Loading academic periods from MySQL...';
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
            ? 'No periods found in tbl_period. Import the database data first.'
            : 'Loaded ${periods.length} periods. Select one, then upload Excel.';
      });
    } catch (error) {
      setState(() {
        _status = 'Unable to load periods. Check Apache/MySQL and Connection settings. $error';
      });
    } finally {
      if (mounted) setState(() => _loadingPeriods = false);
    }
  }

  Future<void> _pickExcel() async {
    if (_selectedPeriod == null) {
      setState(() => _status = 'Please select a period first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _operationLabel = 'Waiting for file selection';
      _operationDone = 0;
      _operationTotal = 0;
      _status = 'Choose the HEMIS promotional list Excel file.';
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        allowMultiple: false,
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) {
        setState(() {
          _status = 'File selection cancelled.';
          _operationLabel = '';
        });
        return;
      }

      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('No file bytes were returned. On Flutter Web, use withData: true.');
      }

      await _loadExcelBytes(bytes, file.name);
    } catch (error) {
      setState(() => _status = 'Excel parsing failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _operationLabel = '';
        });
      }
    }
  }

  Future<void> _loadExcelBytes(Uint8List bytes, String fileName) async {
    final period = _selectedPeriod!;
    final parsedRows = await HemisExcelParser.parsePromotionalListAsync(
      bytes: bytes,
      schoolYear: period.name,
      semester: period.semester,
      periodId: period.id,
      onProgress: (phase, processed, total) {
        if (!mounted) return;
        setState(() {
          _operationLabel = phase;
          _operationDone = processed;
          _operationTotal = total;
          _status = total > 0 ? '$phase... $processed / $total' : '$phase...';
        });
      },
    );

    setState(() {
      _rows = parsedRows;
      _fileName = fileName;
      _status = 'Parsed ${parsedRows.length} subject-grade records across $_studentCount students from $fileName.';
      _filter = 'All';
      _operationDone = parsedRows.length;
      _operationTotal = parsedRows.length;
    });
  }

  Future<void> _checkDatabase() async {
    if (_selectedPeriod == null) {
      setState(() => _status = 'Please select a period first.');
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
      _status = 'Checking database in batches... 0 / ${liveRows.length}';
    });

    try {
      final checkedRows = await _api.checkRows(
        rows: liveRows,
        periodId: _selectedPeriod!.id,
        chunkSize: 500,
        onChunkChecked: (startIndex, checkedChunk) {
          if (!mounted) return;
          for (var i = 0; i < checkedChunk.length; i++) {
            final target = startIndex + i;
            if (target >= 0 && target < liveRows.length) liveRows[target] = checkedChunk[i];
          }
          setState(() => _rows = List<GradeRow>.from(liveRows));
        },
        onProgress: (checked, total) {
          if (!mounted) return;
          setState(() {
            _operationDone = checked;
            _operationTotal = total;
            _status = 'Checking database in batches... $checked / $total';
          });
        },
      );

      setState(() {
        _rows = checkedRows;
        _status = 'Done. Existing: $_existingCount, Missing: $_missingCount, Grade differs: $_gradeDiffCount, Units differ: $_unitsDiffCount.';
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

  void _openConnectionSettings() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Connection settings'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Change this only when Apache is running on another port, folder, or server IP.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
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

  @override
  Widget build(BuildContext context) {
    final groups = _visibleStudentGroups;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildSetupPanel(),
                  const SizedBox(height: 18),
                  _buildDataWorkspace(groups),
                  const SizedBox(height: 28),
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
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF14B8A6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.fact_check_rounded, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grades Checker', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              SizedBox(height: 3),
              Text(
                'Excel-to-MySQL cross-check table: one student per row, Subject 1 to Subject 10 across the row.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        if (_selectedPeriod != null) ...[
          _SoftPill(icon: Icons.calendar_month_rounded, label: _selectedPeriod!.label),
          const SizedBox(width: 10),
        ],
        OutlinedButton.icon(
          onPressed: _openConnectionSettings,
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Connection'),
        ),
      ],
    );
  }

  Widget _buildSetupPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check setup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('Select the academic period, upload the Excel file, then run the database check.', style: TextStyle(color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                if (_fileName.isNotEmpty) _SoftPill(icon: Icons.insert_drive_file_rounded, label: _fileName),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildPeriodSelector()),
                const SizedBox(width: 12),
                SizedBox(width: 170, child: _PrimaryActionButton(label: 'Upload Excel', icon: Icons.upload_file_rounded, onPressed: _isBusy ? null : _pickExcel)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: FilledButton.tonalIcon(
                    onPressed: _isBusy ? null : _checkDatabase,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 13), child: Text('Check DB')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildProgressPanel()),
                const SizedBox(width: 12),
                Expanded(child: _buildStatusPanel()),
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
        labelText: 'Academic period',
        prefixIcon: const Icon(Icons.event_note_rounded),
        suffixIcon: _loadingPeriods
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                tooltip: 'Refresh periods',
                onPressed: _isBusy ? null : _loadPeriods,
                icon: const Icon(Icons.refresh_rounded),
              ),
      ),
      items: _periods
          .map((period) => DropdownMenuItem<String>(
                value: period.id,
                child: Text(period.label, overflow: TextOverflow.ellipsis),
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
                _fileName = '';
                _status = match == null ? 'Select a period, then upload Excel.' : 'Selected ${match.label}. Upload Excel to begin.';
              });
            },
    );
  }

  Widget _buildProgressPanel() {
    final label = _hasProgress
        ? (_operationTotal > 0 ? '$_operationLabel • $_operationDone / $_operationTotal' : _operationLabel)
        : (_fileName.isEmpty ? 'No file uploaded yet' : _fileName);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(minHeight: 8, value: _progressValue, backgroundColor: const Color(0xFFE2E8F0)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: failed ? const Color(0xFFFEF2F2) : const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: failed ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: failed ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_status, style: TextStyle(color: failed ? const Color(0xFF991B1B) : const Color(0xFF1E3A8A)))),
        ],
      ),
    );
  }

  Widget _buildDataWorkspace(List<_StudentGradeGroup> groups) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMetrics(),
                const SizedBox(height: 16),
                _buildToolbar(groups.length),
                const SizedBox(height: 14),
                _buildLegend(),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildResultsArea(groups),
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
    ];

    return Row(
      children: List.generate(cards.length, (index) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == cards.length - 1 ? 0 : 10),
            child: cards[index],
          ),
        );
      }),
    );
  }

  Widget _buildToolbar(int visibleStudentCount) {
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            value: _filter,
            decoration: const InputDecoration(labelText: 'Filter', prefixIcon: Icon(Icons.filter_alt_rounded)),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(value: 'Existing', child: Text('Existing')),
              DropdownMenuItem(value: 'Missing', child: Text('Missing')),
              DropdownMenuItem(value: 'Grade differs', child: Text('Grade differs')),
              DropdownMenuItem(value: 'Units differ', child: Text('Units differ')),
              DropdownMenuItem(value: 'Student not found', child: Text('Student not found')),
              DropdownMenuItem(value: 'Subject not found', child: Text('Subject not found')),
            ],
            onChanged: (value) => setState(() => _filter = value ?? 'All'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Search student, ID, subject, course, or grade', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        const SizedBox(width: 12),
        _SoftPill(icon: Icons.visibility_rounded, label: '$visibleStudentCount student rows'),
      ],
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
      _LegendItem('Unchecked', _StatusVisual.unchecked.color),
    ];
    return Wrap(spacing: 12, runSpacing: 8, children: items);
  }

  Widget _buildResultsArea(List<_StudentGradeGroup> groups) {
    if (_rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 70),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(24)),
              child: const Icon(Icons.upload_file_rounded, size: 38, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 14),
            const Text('No Excel rows loaded yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Upload the HEMIS promotional list to preview and check grades.', style: TextStyle(color: Color(0xFF64748B))),
          ],
        ),
      );
    }

    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: Text('No students match the selected filter/search.')),
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(14),
        child: _StudentGradeTable(groups: groups),
      ),
    );
  }
}

class _StudentGradeGroup {
  _StudentGradeGroup({
    required this.key,
    required this.studentId,
    required this.studentName,
    required this.course,
    required this.yearLevel,
    required this.excelRowNumber,
    required this.rows,
  });

  final String key;
  final String studentId;
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

  _StatusVisual get visual {
    if (rows.any((row) => row.studentFound == false)) return _StatusVisual.studentMissing;
    if (rows.any((row) => row.subjectFound == false)) return _StatusVisual.subjectMissing;
    if (rows.any((row) => !row.existsInDatabase && row.studentFound == true && row.subjectFound == true)) return _StatusVisual.missing;
    if (rows.any((row) => row.gradeMatches == false)) return _StatusVisual.gradeDiff;
    if (rows.any((row) => row.unitsMatch == false)) return _StatusVisual.unitsDiff;
    if (rows.any((row) => !row.existsInDatabase && row.studentFound == null && row.subjectFound == null)) return _StatusVisual.unchecked;
    return _StatusVisual.exists;
  }
}

class _StudentGradeTable extends StatelessWidget {
  const _StudentGradeTable({required this.groups});

  final List<_StudentGradeGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Table(
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
              for (var i = 1; i <= 10; i++) _subjectCell(groups[groupIndex].rowForSubjectNo(i)),
            ],
          ),
      ],
    );
  }

  static Map<int, TableColumnWidth> _columnWidths() {
    return {
      0: const FixedColumnWidth(330),
      1: const FixedColumnWidth(160),
      for (var i = 2; i <= 11; i++) i: const FixedColumnWidth(190),
    };
  }

  static Widget _headerCell(String label) {
    return Container(
      height: 46,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155))),
    );
  }

  static Widget _studentCell(_StudentGradeGroup group) {
    final visual = group.visual;
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 7, height: 70, decoration: BoxDecoration(color: visual.color, borderRadius: BorderRadius.circular(99))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.studentName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 4),
                Text('ID: ${group.studentId.isEmpty ? 'N/A' : group.studentId}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _SmallBadge(label: '${group.rows.length} subj'),
                    _SmallBadge(label: '${group.existing} existing'),
                    if (group.missing > 0) _SmallBadge(label: '${group.missing} missing'),
                    if (group.gradeDiff + group.unitsDiff > 0) _SmallBadge(label: '${group.gradeDiff + group.unitsDiff} diff'),
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
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Course', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(group.course.isEmpty ? '-' : group.course, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('Year', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(group.yearLevel.isEmpty ? '-' : group.yearLevel, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475569))),
        ],
      ),
    );
  }

  static Widget _subjectCell(GradeRow? row) {
    if (row == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: const Text('-', style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w800)),
      );
    }

    final visual = _visualForRow(row);
    return Tooltip(
      message: row.message ?? row.statusLabel,
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: visual.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: visual.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: visual.color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(row.subjectCode, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
                ],
              ),
              const SizedBox(height: 6),
              _SubjectLine(label: 'Grade', excel: row.excelGrade, db: row.databaseGrade, warn: row.gradeMatches == false),
              const SizedBox(height: 3),
              _SubjectLine(label: 'Units', excel: row.units, db: row.databaseCredits ?? row.subjectUnits, warn: row.unitsMatch == false),
              const SizedBox(height: 5),
              Text(row.statusLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: visual.color)),
            ],
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
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155)),
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
          TextSpan(text: excelValue, style: const TextStyle(fontWeight: FontWeight.w900)),
          const TextSpan(text: ' / '),
          TextSpan(text: dbValue, style: TextStyle(fontWeight: FontWeight.w900, color: warn ? const Color(0xFFB45309) : const Color(0xFF334155))),
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
      icon: Icon(icon),
      label: Padding(padding: const EdgeInsets.symmetric(vertical: 13), child: Text(label)),
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, size: 20, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
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
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF2563EB)),
          const SizedBox(width: 7),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF334155)))),
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
  static const unchecked = _StatusVisual(label: 'Unchecked', color: Color(0xFF64748B), background: Color(0xFFF1F5F9), border: Color(0xFFCBD5E1));
}

_StatusVisual _visualForRow(GradeRow row) {
  if (row.studentFound == false) return _StatusVisual.studentMissing;
  if (row.subjectFound == false) return _StatusVisual.subjectMissing;
  if (!row.existsInDatabase && row.studentFound == null && row.subjectFound == null) return _StatusVisual.unchecked;
  if (!row.existsInDatabase && row.studentFound == true && row.subjectFound == true) return _StatusVisual.missing;
  if (row.gradeMatches == false) return _StatusVisual.gradeDiff;
  if (row.unitsMatch == false) return _StatusVisual.unitsDiff;
  return _StatusVisual.exists;
}
