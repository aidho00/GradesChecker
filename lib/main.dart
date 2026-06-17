import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Grades Checker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF166534)),
        useMaterial3: true,
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
  final _schoolYearController = TextEditingController(text: '2019-2020');
  final _semesterController = TextEditingController(text: '1ST SEM');
  final _periodIdController = TextEditingController();
  final _searchController = TextEditingController();

  List<GradeRow> _rows = [];
  String _fileName = '';
  String _status = 'Upload the HEMIS promotional list Excel file to begin.';
  String _filter = 'All';
  bool _isBusy = false;
  int _checkedCount = 0;

  @override
  void dispose() {
    _apiController.dispose();
    _schoolYearController.dispose();
    _semesterController.dispose();
    _periodIdController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<GradeRow> get _visibleRows {
    final query = _searchController.text.trim().toLowerCase();
    return _rows.where((row) {
      final passesFilter = switch (_filter) {
        'Existing' => row.existsInDatabase,
        'Missing' => !row.existsInDatabase && row.gradeMatches != null,
        'Grade differs' => row.gradeMatches == false,
        'Units differ' => row.hasAnyUnitsDifference,
        'Unchecked' => !row.existsInDatabase && row.gradeMatches == null,
        _ => true,
      };
      if (!passesFilter) return false;
      if (query.isEmpty) return true;
      final combined = [
        row.studentId,
        row.databaseStudentId ?? '',
        row.studentName,
        row.subjectCode,
        row.course,
        row.excelGrade,
        row.databaseGrade ?? '',
        row.units,
        row.databaseUnits ?? '',
        row.subjectUnits ?? '',
        row.message ?? '',
      ].join(' ').toLowerCase();
      return combined.contains(query);
    }).toList();
  }

  int get _existingCount => _rows.where((row) => row.existsInDatabase).length;
  int get _missingCount => _rows.where((row) => !row.existsInDatabase && row.gradeMatches != null).length;
  int get _uncheckedCount => _rows.where((row) => !row.existsInDatabase && row.gradeMatches == null).length;
  int get _diffCount => _rows.where((row) => row.gradeMatches == false).length;
  int get _unitsDiffCount => _rows.where((row) => row.hasAnyUnitsDifference).length;

  Future<void> _pickExcel() async {
    setState(() {
      _isBusy = true;
      _status = 'Reading Excel file...';
      _checkedCount = 0;
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
        });
        return;
      }

      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('No file bytes were returned. On Flutter Web, use withData: true.');
      }

      _loadExcelBytes(bytes, file.name);
    } catch (error) {
      setState(() {
        _status = 'Excel parse failed: $error';
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  void _loadExcelBytes(Uint8List bytes, String fileName) {
    final parsedRows = HemisExcelParser.parsePromotionalList(
      bytes: bytes,
      schoolYear: _schoolYearController.text.trim(),
      semester: _semesterController.text.trim(),
      periodId: _periodIdController.text.trim(),
    );

    setState(() {
      _rows = parsedRows;
      _fileName = fileName;
      _status = 'Parsed ${parsedRows.length} subject-grade rows from $fileName.';
      _filter = 'All';
      _checkedCount = 0;
    });
  }

  Future<void> _checkDatabase() async {
    if (_rows.isEmpty) {
      setState(() => _status = 'Please upload and parse an Excel file first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Checking database...';
      _checkedCount = 0;
    });

    try {
      final api = GradeCheckApi(endpointUrl: _apiController.text.trim());
      final checkedRows = await api.checkRows(
        rows: _rows,
        onProgress: (checked, total) {
          setState(() {
            _checkedCount = checked;
            _status = 'Checking database... $checked / $total';
          });
        },
      );

      setState(() {
        _rows = checkedRows;
        _status = 'Done. Existing: $_existingCount, Missing: $_missingCount, Unchecked: $_uncheckedCount, Grade differs: $_diffCount, Units differ: $_unitsDiffCount.';
      });
    } catch (error) {
      setState(() {
        _status = 'Database check failed: $error';
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleRows;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Grades Checker'),
            Text(
              'HEMIS Excel vs cfcissmsdb MySQL grades',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopPanel(),
            const SizedBox(height: 12),
            _buildSummaryBar(),
            const SizedBox(height: 12),
            Expanded(child: _buildResultsArea(visibleRows)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPanel() {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 450,
                  child: TextField(
                    controller: _apiController,
                    decoration: const InputDecoration(
                      labelText: 'API endpoint',
                      helperText: 'Works with WAMP or XAMPP. Change localhost port if needed.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _schoolYearController,
                    decoration: const InputDecoration(
                      labelText: 'Academic year',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _semesterController,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _periodIdController,
                    decoration: const InputDecoration(
                      labelText: 'Period ID',
                      helperText: 'Optional',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isBusy ? null : _pickExcel,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Excel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _isBusy ? null : _checkDatabase,
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Check Database'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fileName.isEmpty ? _status : '$_status  File: $_fileName',
                    style: TextStyle(
                      color: _status.toLowerCase().contains('failed')
                          ? Colors.red.shade700
                          : Colors.grey.shade800,
                    ),
                  ),
                ),
                if (_isBusy)
                  SizedBox(
                    width: 180,
                    child: LinearProgressIndicator(
                      value: _checkedCount > 0 && _rows.isNotEmpty
                          ? _checkedCount / _rows.length
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _MetricCard(label: 'Parsed rows', value: _rows.length.toString()),
        _MetricCard(label: 'Existing', value: _existingCount.toString()),
        _MetricCard(label: 'Missing', value: _missingCount.toString()),
        _MetricCard(label: 'Unchecked', value: _uncheckedCount.toString()),
        _MetricCard(label: 'Grade differs', value: _diffCount.toString()),
        _MetricCard(label: 'Units differ', value: _unitsDiffCount.toString()),
        SizedBox(
          width: 185,
          child: DropdownButtonFormField<String>(
            value: _filter,
            decoration: const InputDecoration(
              labelText: 'Filter',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(value: 'Existing', child: Text('Existing')),
              DropdownMenuItem(value: 'Missing', child: Text('Missing')),
              DropdownMenuItem(value: 'Unchecked', child: Text('Unchecked')),
              DropdownMenuItem(value: 'Grade differs', child: Text('Grade differs')),
              DropdownMenuItem(value: 'Units differ', child: Text('Units differ')),
            ],
            onChanged: (value) => setState(() => _filter = value ?? 'All'),
          ),
        ),
        SizedBox(
          width: 300,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search student / subject / message',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsArea(List<GradeRow> visibleRows) {
    if (_rows.isEmpty) {
      return const Card(
        elevation: 0,
        child: Center(
          child: Text('No parsed grade rows yet.'),
        ),
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1780,
          child: Column(
            children: [
              _buildTableHeader(),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: visibleRows.length,
                  itemBuilder: (context, index) => _buildTableRow(visibleRows[index], index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFF166534),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: const Row(
        children: [
          _HeaderCell('Status', width: 150),
          _HeaderCell('Excel Row', width: 80),
          _HeaderCell('Excel ID', width: 105),
          _HeaderCell('DB ID', width: 105),
          _HeaderCell('Student Name', width: 230),
          _HeaderCell('Subject', width: 105),
          _HeaderCell('Excel Units', width: 90),
          _HeaderCell('Subject Units', width: 100),
          _HeaderCell('DB Units', width: 85),
          _HeaderCell('Excel Grade', width: 95),
          _HeaderCell('DB Grade', width: 85),
          _HeaderCell('DB Period', width: 155),
          _HeaderCell('Course', width: 245),
          _HeaderCell('Message', width: 250),
        ],
      ),
    );
  }

  Widget _buildTableRow(GradeRow row, int index) {
    final bg = index.isEven ? Colors.white : const Color(0xFFF8FAFC);
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 150, child: _StatusChip(row: row)),
          _BodyCell(row.excelRowNumber.toString(), width: 80),
          _BodyCell(row.studentId, width: 105),
          _BodyCell(row.databaseStudentId ?? '', width: 105),
          _BodyCell(row.studentName, width: 230),
          _BodyCell(row.subjectCode, width: 105),
          _BodyCell(row.units, width: 90),
          _BodyCell(row.subjectUnits ?? '', width: 100),
          _BodyCell(row.databaseUnits ?? '', width: 85),
          _BodyCell(row.excelGrade, width: 95),
          _BodyCell(row.databaseGrade ?? '', width: 85),
          _BodyCell(row.periodLabel ?? row.periodId, width: 155),
          _BodyCell(row.course, width: 245),
          _BodyCell(row.message ?? '', width: 250),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(this.text, {required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.row});

  final GradeRow row;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (row.statusLabel) {
      'Exists' => ('Exists', Colors.green),
      'Grade differs' => ('Grade diff', Colors.orange),
      'Units differ' => ('Units diff', Colors.deepOrange),
      'Grade + units differ' => ('Grade+Units', Colors.red),
      'Missing' => ('Missing', Colors.red),
      _ => ('Unchecked', Colors.blueGrey),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color.shade700, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
