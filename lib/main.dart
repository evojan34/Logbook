import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SurgicalLogbookApp());
}

const Color kGoldColor = Color(0xFFD4AF37);
const Color kGoldBorder = Color(0x40D4AF37);
const Color kGoldSubtle = Color(0x26D4AF37);
const Color kDarkBg = Color(0xFF121212);
const Color kCardBg = Color(0xFF1E1E1E);

String formatDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String formatStamp(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  final h = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$y$m${day}_$h$min';
}

class SurgicalLogbookApp extends StatelessWidget {
  const SurgicalLogbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Surgical e-Logbook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDarkBg,
        primaryColor: kGoldColor,
        colorScheme: const ColorScheme.dark(
          primary: kGoldColor,
          secondary: kGoldColor,
          surface: kCardBg,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kCardBg,
          foregroundColor: kGoldColor,
          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kGoldColor,
          foregroundColor: Colors.black,
        ),
      ),
      home: const LogbookHomeScreen(),
    );
  }
}

class LogbookDatabase {
  static final LogbookDatabase instance = LogbookDatabase._init();
  LogbookDatabase._init();

  Map<String, dynamic>? _cache;

  Future<Directory> getStorageDir() async {
    try {
      final baseDir = Directory('${Directory.systemTemp.parent.path}/files');
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      return baseDir;
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  Future<File> _getDbFile() async {
    final dir = await getStorageDir();
    return File('${dir.path}/surgical_elogbook_v2.json');
  }

  Future> _loadDb() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _getDbFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          _cache = decoded;
          _cache!['operations'] ??= <dynamic>[];
          _cache!['settings'] ??= <String, dynamic>{};
          return _cache!;
        }
      }
    } catch (_) {}
    _cache = {
      'nextId': 1,
      'operations': <dynamic>[],
      'settings': <String, dynamic>{},
    };
    return _cache!;
  }

  Future<void> _saveDb() async {
    if (_cache == null) return;
    final file = await _getDbFile();
    await file.writeAsString(jsonEncode(_cache));
  }

  Future<int> insertCase(Map<String, dynamic> row) async {
    final db = await _loadDb();
    final int nextId = (db['nextId'] as int? ?? 1);
    final newRow = Map<String, dynamic>.from(row);
    newRow['id'] = nextId;
    (db['operations'] as List<dynamic>).add(newRow);
    db['nextId'] = nextId + 1;
    await _saveDb();
    return nextId;
  }

  Future<void> updateCase(int id, Map<String, dynamic> row) async {
    final db = await _loadDb();
    final List<dynamic> ops = db['operations'] as List<dynamic>;
    for (int i = 0; i < ops.length; i++) {
      final item = Map<String, dynamic>.from(ops[i] as Map);
      if (item['id'] == id) {
        final updated = Map<String, dynamic>.from(row);
        updated['id'] = id;
        ops[i] = updated;
        break;
      }
    }
    await _saveDb();
  }

  Future<List>> fetchAllCases() async {
    final db = await _loadDb();
    final List<dynamic> ops = db['operations'] as List<dynamic>;
    final List> result =
        ops.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    result.sort((a, b) {
      final c = (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? '');
      if (c != 0) return c;
      return (b['id'] as int? ?? 0).compareTo(a['id'] as int? ?? 0);
    });
    return result;
  }

  Future<void> deleteCase(int id) async {
    final db = await _loadDb();
    final List<dynamic> ops = db['operations'] as List<dynamic>;
    ops.removeWhere((e) => (e as Map)['id'] == id);
    await _saveDb();
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await _loadDb();
    final Map<String, dynamic> settings =
        Map<String, dynamic>.from(db['settings'] as Map);
    settings[key] = value;
    db['settings'] = settings;
    await _saveDb();
  }

  Future> loadSettings() async {
    final db = await _loadDb();
    final Map<String, dynamic> s = Map<String, dynamic>.from(db['settings'] as Map);
    final Map<String, String> result = {};
    for (final entry in s.entries) {
      result[entry.key.toString()] = entry.value.toString();
    }
    return result;
  }
}

class PurePdfGenerator {
  static String _cleanAscii(String input) {
    final ascii = input.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    return ascii
        .replaceAll('\\', '\\\\')
        .replaceAll('(', '\\(')
        .replaceAll(')', '\\)');
  }

  static Uint8List generateReportPdf({
    required String traineeName,
    required String traineeGrade,
    required String hospital,
    required String consultant,
    required String periodText,
    required Map<String, Map<String, int>> summary,
    required List> cases,
  }) {
    final List<String> lines = [];
    lines.add('PAN-SURGICAL ELECTRONIC LOGBOOK - CONSOLIDATION REPORT');
    lines.add('Surgeon / Trainee: $traineeName ($traineeGrade)');
    lines.add('Institution: $hospital   |   Supervisor: $consultant');
    lines.add('Period: $periodText   |   Printed: ${formatDate(DateTime.now())}');
    lines.add('=' * 85);
    lines.add('1. PROCEDURE CONSOLIDATION SUMMARY');
    lines.add('-' * 85);
    final hdr = 'Procedure Name'.padRight(42) +
        'P'.padLeft(5) +
        'S-TS'.padLeft(6) +
        'S-TU'.padLeft(6) +
        'A'.padLeft(5) +
        'T'.padLeft(5) +
        'Total'.padLeft(7);
    lines.add(hdr);
    lines.add('-' * 85);

    for (final entry in summary.entries) {
      final name = entry.key.length > 40
          ? entry.key.substring(0, 40).padRight(42)
          : entry.key.padRight(42);
      final v = entry.value;
      final pStr = (v['P'] ?? 0).toString().padLeft(5);
      final stsStr = (v['S-TS'] ?? 0).toString().padLeft(6);
      final stuStr = (v['S-TU'] ?? 0).toString().padLeft(6);
      final aStr = (v['A'] ?? 0).toString().padLeft(5);
      final tStr = (v['T'] ?? 0).toString().padLeft(5);
      final totStr = (v['Total'] ?? 0).toString().padLeft(7);
      lines.add('$name$pStr$stsStr$stuStr$aStr$tStr$totStr');
    }

    int countRole(String r) => cases.where((c) => c['role'] == r).length;
    lines.add('-' * 85);
    lines.add(
        'TOTAL: ${cases.length} | P: ${countRole("P")} | S-TS: ${countRole("S-TS")} | S-TU: ${countRole("S-TU")} | A: ${countRole("A")} | T: ${countRole("T")}');
    lines.add('=' * 85);
    lines.add('');
    lines.add('2. DETAILED OPERATIVE LOGBOOK RECORD');
    lines.add('-' * 85);
    final dtlHdr = 'Date'.padRight(12) +
        'Pt ID'.padRight(11) +
        'Age/S'.padRight(8) +
        'Procedure'.padRight(33) +
        'CEPOD'.padRight(11) +
        'Role'.padRight(6);
    lines.add(dtlHdr);
    lines.add('-' * 85);

    for (final c in cases) {
      final date = (c['date']?.toString() ?? '').padRight(12);
      final pt = (c['patientId']?.toString() ?? '');
      final ptPad = (pt.length > 9 ? pt.substring(0, 9) : pt).padRight(11);
      final ageSex = '${c['age']}/${c['sex']}'.padRight(8);
      final proc = (c['procedureName']?.toString() ?? '');
      final procPad =
          (proc.length > 30 ? proc.substring(0, 30) : proc).padRight(33);
      final urg = (c['urgency']?.toString() ?? '');
      final urgPad = (urg.length > 9 ? urg.substring(0, 9) : urg).padRight(11);
      final role = (c['role']?.toString() ?? '').padRight(6);
      lines.add('$date$ptPad$ageSex$procPad$urgPad$role');
    }

    lines.add('');
    lines.add('-' * 85);
    lines.add(
        'Trainee Signature: ___________________    Consultant Signature: ___________________');

    const int linesPerPage = 52;
    final List<List<String>> pages = [];
    for (int i = 0; i < lines.length; i += linesPerPage) {
      final end = (i + linesPerPage < lines.length) ? i + linesPerPage : lines.length;
      pages.add(lines.sublist(i, end));
    }
    if (pages.isEmpty) pages.add(['Empty Logbook']);

    final List<String> objects = [];
    objects.add('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    final List<String> pageRefs = [];
    for (int i = 0; i < pages.length; i++) {
      final pageObjNum = 4 + (i * 2);
      pageRefs.add('$pageObjNum 0 R');
    }
    objects.add(
        '2 0 obj\n<< /Type /Pages /Kids [${pageRefs.join(' ')}] /Count ${pages.length} >>\nendobj\n');
    objects.add(
        '3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n');

    for (int i = 0; i < pages.length; i++) {
      final pageObjNum = 4 + (i * 2);
      final contentObjNum = pageObjNum + 1;

      final sb = StringBuffer();
      sb.writeln('BT');
      sb.writeln('/F1 8.5 Tf');
      int y = 800;
      for (final line in pages[i]) {
        final safe = _cleanAscii(line);
        sb.writeln('1 0 0 1 30 $y Tm ($safe) Tj');
        y -= 14;
      }
      sb.writeln('ET');
      final streamContent = sb.toString();

      objects.add(
          '$pageObjNum 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents $contentObjNum 0 R >>\nendobj\n');
      objects.add(
          '$contentObjNum 0 obj\n<< /Length ${streamContent.length} >>\nstream\n$streamContent\nendstream\nendobj\n');
    }

    final pdfBuffer = StringBuffer();
    pdfBuffer.write('%PDF-1.4\n');
    final List<int> offsets = [];
    for (final obj in objects) {
      offsets.add(pdfBuffer.toString().length);
      pdfBuffer.write(obj);
    }
    final xrefOffset = pdfBuffer.toString().length;
    pdfBuffer.write('xref\n0 ${objects.length + 1}\n');
    pdfBuffer.write('0000000000 65535 f \n');
    for (final offset in offsets) {
      pdfBuffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    pdfBuffer.write(
        'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n');

    return Uint8List.fromList(utf8.encode(pdfBuffer.toString()));
  }
}

final Map<String, List<String>> kSurgicalProcedures = {
  'Appendix & Diagnostic': [
    'Open Appendicectomy',
    'Laparoscopic Appendicectomy',
    'Diagnostic Laparoscopy',
    'Exploratory Laparotomy',
  ],
  'Hepatobiliary & Spleen': [
    'Laparoscopic Cholecystectomy',
    'Open Cholecystectomy',
    'CBD Exploration',
    'Hydatid Cyst Liver Excision / Derotation',
    'Splenectomy (Trauma / Elective)',
  ],
  'Hernia & Abdominal Wall': [
    'Inguinal Hernia Repair (Lichtenstein Mesh)',
    'Herniotomy (Pediatric / Indirect)',
    'Paraumbilical / Umbilical Hernia Repair',
    'Epigastric Hernia Repair',
    'Incisional Hernia Repair',
    'Femoral Hernia Repair',
  ],
  'Upper & Lower GI': [
    'Perforated Duodenal Ulcer (Graham Patch) Repair',
    'Small Bowel Resection & Anastomosis',
    'Adhesiolysis (Intestinal Obstruction)',
    'Right / Left Hemicolectomy',
    'Hartmann Procedure',
    'Colostomy / Ileostomy Creation or Closure',
  ],
  'Coloproctology & Perianal': [
    'Haemorrhoidectomy (Milligan-Morgan / Stapled)',
    'Lateral Internal Sphincterotomy (Anal Fissure)',
    'Fistulotomy / Fistulectomy / Seton Placement',
    'Perianal / Ischiorectal Abscess Drainage',
    'Pilonidal Sinus Excision (Open / Flap)',
  ],
  'Endocrine & Breast': [
    'Total Thyroidectomy',
    'Hemithyroidectomy / Lobectomy',
    'Modified Radical Mastectomy (MRM)',
    'Breast Lumpectomy / Wide Local Excision',
    'Breast Abscess Incision & Drainage',
  ],
  'Trauma, Vascular & Minor': [
    'Chest Tube (ICTD) Insertion',
    'Central Venous Catheter (CVC) Insertion',
    'Below / Above Knee Amputation (BKA / AKA)',
    'Ray / Toe Amputation (Diabetic Foot)',
    'Wound Debridement & Primary Suturing',
    'Sebaceous Cyst / Lipoma Excision',
    'Ingrowing Toenail (Wedge Resection)',
    'Other (Custom Procedure)',
  ],
};

class LogbookHomeScreen extends StatefulWidget {
  const LogbookHomeScreen({super.key});

  @override
  State<LogbookHomeScreen> createState() => _LogbookHomeScreenState();
}

class _LogbookHomeScreenState extends State<LogbookHomeScreen> {
  int _currentTabIndex = 0;
  List> _cases = [];
  String _selectedRoleFilter = 'ALL';
  String _searchQuery = '';

  String? _screenStartDate;
  String? _screenEndDate;

  String _traineeName = 'Dr. Surgeon';
  String _traineeGrade = 'General Surgery Resident';
  String _defaultHospital = 'Teaching Hospital';
  String _defaultConsultant = 'Consultant Surgeon';
  int _targetCasesGoal = 200;
  String _pinCode = '';
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _initData(checkPinOnStart: true);
  }

  Future<void> _initData({bool checkPinOnStart = false}) async {
    final settings = await LogbookDatabase.instance.loadSettings();
    final data = await LogbookDatabase.instance.fetchAllCases();
    final savedPin = settings['pinCode'] ?? '';
    setState(() {
      _traineeName = settings['traineeName'] ?? 'Dr. Surgeon';
      _traineeGrade = settings['traineeGrade'] ?? 'General Surgery Resident';
      _defaultHospital = settings['defaultHospital'] ?? 'Teaching Hospital';
      _defaultConsultant = settings['defaultConsultant'] ?? 'Consultant Surgeon';
      _targetCasesGoal =
          int.tryParse(settings['targetCasesGoal'] ?? '200') ?? 200;
      _pinCode = savedPin;
      if (checkPinOnStart && savedPin.isNotEmpty) {
        _isLocked = true;
      }
      _cases = data;
    });
  }

  Future<void> _refreshCases() async {
    final data = await LogbookDatabase.instance.fetchAllCases();
    setState(() => _cases = data);
  }

  bool _isDateInRange(String caseDate, String? fromDate, String? toDate) {
    if (fromDate != null && caseDate.compareTo(fromDate) < 0) return false;
    if (toDate != null && caseDate.compareTo(toDate) > 0) return false;
    return true;
  }

  List> _getCasesForRange(
      String? fromDate, String? toDate) {
    return _cases
        .where((c) => _isDateInRange(c['date']?.toString() ?? '', fromDate, toDate))
        .toList();
  }

  List> get _dateFilteredCases =>
      _getCasesForRange(_screenStartDate, _screenEndDate);

  List> get _filteredCases {
    return _dateFilteredCases.where((c) {
      final role = c['role']?.toString() ?? '';
      final matchesRole =
          _selectedRoleFilter == 'ALL' || role == _selectedRoleFilter;
      final q = _searchQuery.toLowerCase();
      final matchesSearch =
          (c['procedureName']?.toString() ?? '').toLowerCase().contains(q) ||
              (c['patientId']?.toString() ?? '').toLowerCase().contains(q) ||
              (c['category']?.toString() ?? '').toLowerCase().contains(q) ||
              (c['consultant']?.toString() ?? '').toLowerCase().contains(q);
      return matchesRole && matchesSearch;
    }).toList();
  }

  int _countByRole(String role) =>
      _dateFilteredCases.where((c) => c['role'] == role).length;

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kCardBg),
    );
  }

  Future<String> _saveExportFile(String fileName, Uint8List bytes) async {
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final f = File('${downloadDir.path}/$fileName');
        await f.writeAsBytes(bytes);
        return f.path;
      }
    } catch (_) {}
    final localDir = await LogbookDatabase.instance.getStorageDir();
    final f = File('${localDir.path}/$fileName');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: kCardBg,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _showDateRangeDialog({required String mode}) {
    String? tempFrom = _screenStartDate;
    String? tempTo = _screenEndDate;
    String activePreset =
        (tempFrom == null && tempTo == null) ? 'all' : 'custom';

    void applyPreset(
        String preset, void Function(void Function()) setDialogState) {
      final now = DateTime.now();
      setDialogState(() {
        activePreset = preset;
        if (preset == 'all') {
          tempFrom = null;
          tempTo = null;
        } else if (preset == 'month') {
          tempFrom = formatDate(DateTime(now.year, now.month, 1));
          tempTo = formatDate(now);
        } else if (preset == '3months') {
          tempFrom = formatDate(DateTime(now.year, now.month - 3, now.day));
          tempTo = formatDate(now);
        } else if (preset == '6months') {
          tempFrom = formatDate(DateTime(now.year, now.month - 6, now.day));
          tempTo = formatDate(now);
        } else if (preset == 'year') {
          tempFrom = formatDate(DateTime(now.year, 1, 1));
          tempTo = formatDate(now);
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final matchingCases = _getCasesForRange(tempFrom, tempTo);

          return AlertDialog(
            backgroundColor: kCardBg,
            title: Text(
              mode == 'pdf'
                  ? 'تحديد فترة تقرير الـ PDF'
                  : mode == 'csv'
                      ? 'تحديد فترة ملف الإكسل (CSV)'
                      : 'فلترة السجل والإحصائيات بالتاريخ',
              style: const TextStyle(color: kGoldColor, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اختيار سريع للفترة التدريبية:',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _presetChip('كل السجل', 'all', activePreset,
                          (p) => applyPreset(p, setDialogState)),
                      _presetChip('هذا الشهر', 'month', activePreset,
                          (p) => applyPreset(p, setDialogState)),
                      _presetChip('آخر 3 أشهر', '3months', activePreset,
                          (p) => applyPreset(p, setDialogState)),
                      _presetChip('كورس 6 أشهر', '6months', activePreset,
                          (p) => applyPreset(p, setDialogState)),
                      _presetChip('هذه السنة', 'year', activePreset,
                          (p) => applyPreset(p, setDialogState)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'أو تحديد تاريخ مخصص (من - إلى):',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: tempFrom != null
                                  ? (DateTime.tryParse(tempFrom!) ??
                                      DateTime.now())
                                  : DateTime.now(),
                              firstDate: DateTime(2015),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                activePreset = 'custom';
                                tempFrom = formatDate(picked);
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'من تاريخ (From)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(
                              tempFrom ?? 'البداية',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: tempTo != null
                                  ? (DateTime.tryParse(tempTo!) ??
                                      DateTime.now())
                                  : DateTime.now(),
                              firstDate: DateTime(2015),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                activePreset = 'custom';
                                tempTo = formatDate(picked);
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'إلى تاريخ (To)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(
                              tempTo ?? 'اليوم',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kGoldSubtle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kGoldBorder),
                    ),
                    child: Text(
                      'العمليات المشمولة في هذه الفترة: ${matchingCases.length} عملية',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: kGoldColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGoldColor,
                  foregroundColor: Colors.black,
                ),
                onPressed: matchingCases.isEmpty && mode != 'screen_filter'
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        if (mode == 'screen_filter') {
                          setState(() {
                            _screenStartDate = tempFrom;
                            _screenEndDate = tempTo;
                          });
                        } else if (mode == 'pdf') {
                          _openConsolidationReportScreen(
                              fromDate: tempFrom, toDate: tempTo);
                        } else if (mode == 'csv') {
                          _exportCsv(fromDate: tempFrom, toDate: tempTo);
                        }
                      },
                child: Text(
                  mode == 'pdf'
                      ? 'معاينة وحفظ PDF'
                      : mode == 'csv'
                          ? 'تصدير CSV'
                          : 'تطبيق الفلتر',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _presetChip(
      String label, String key, String activeKey, Function(String) onSelect) {
    final isSelected = key == activeKey;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      selectedColor: kGoldColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.black : Colors.white,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => onSelect(key),
    );
  }

  Future<void> _exportJsonBackup() async {
    try {
      final settings = await LogbookDatabase.instance.loadSettings();
      final backupData = {
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': settings,
        'operations': _cases,
      };
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      await Clipboard.setData(ClipboardData(text: jsonString));

      final stamp = formatStamp(DateTime.now());
      final savedPath = await _saveExportFile(
        'elogbook_backup_$stamp.json',
        Uint8List.fromList(utf8.encode(jsonString)),
      );
      _showSnack('تم حفظ النسخة الاحتياطية ونسخها للحافظة:\n$savedPath');
    } catch (_) {
      _showSnack('تم نسخ النسخة الاحتياطية للحافظة');
    }
  }

  Future<void> _showRestoreBackupDialog() async {
    final textCtrl = TextEditingController();
    final storageDir = await LogbookDatabase.instance.getStorageDir();
    final List<File> localBackups = storageDir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.json') &&
            !f.path.endsWith('surgical_elogbook_v2.json'))
        .toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardBg,
        title: const Text(
          'استعادة نسخة احتياطية (Restore)',
          style: TextStyle(color: kGoldColor, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (localBackups.isNotEmpty) ...[
                const Text(
                  'نسخ احتياطية محفوظة في الهاتف:',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 6),
                ...localBackups.reversed.take(3).map(
                      (file) => Card(
                        color: kDarkBg,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.restore_page,
                              color: kGoldColor),
                          title: Text(
                            file.path.split('/').last,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () async {
                            final content = await file.readAsString();
                            if (mounted) Navigator.pop(ctx);
                            await _processJsonRestore(content);
                          },
                        ),
                      ),
                    ),
                const Divider(height: 20),
              ],
              const Text(
                'أو الصق محتوى ملف النسخة الاحتياطية (JSON):',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.content_paste, color: kGoldColor),
                label: const Text('لصق تلقائي من الحافظة (Paste)',
                    style: TextStyle(color: kGoldColor)),
                onPressed: () async {
                  final clip = await Clipboard.getData(Clipboard.kTextPlain);
                  if (clip?.text != null) {
                    textCtrl.text = clip!.text!;
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: textCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '{"version": 2, "operations": [...]}',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kGoldColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final content = textCtrl.text.trim();
              if (content.isEmpty) return;
              Navigator.pop(ctx);
              await _processJsonRestore(content);
            },
            child: const Text('استعادة الآن',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _processJsonRestore(String content) async {
    try {
      final Map<String, dynamic> data = jsonDecode(content);

      if (data['settings'] != null && data['settings'] is Map) {
        final Map<String, dynamic> s =
            Map<String, dynamic>.from(data['settings']);
        for (final entry in s.entries) {
          await LogbookDatabase.instance
              .saveSetting(entry.key, entry.value.toString());
        }
      }

      int importedCount = 0;
      if (data['operations'] != null && data['operations'] is List) {
        final List<dynamic> ops = data['operations'];
        final existing = await LogbookDatabase.instance.fetchAllCases();

        for (final item in ops) {
          final map = Map<String, dynamic>.from(item);
          final isDuplicate = existing.any((e) =>
              e['date'] == map['date'] &&
              e['patientId'] == map['patientId'] &&
              e['procedureName'] == map['procedureName']);

          if (!isDuplicate) {
            await LogbookDatabase.instance.insertCase({
              'date': map['date']?.toString() ?? formatDate(DateTime.now()),
              'patientId': map['patientId']?.toString() ?? 'Unknown',
              'age': int.tryParse(map['age']?.toString() ?? '0') ?? 0,
              'sex': map['sex']?.toString() ?? 'M',
              'hospital': map['hospital']?.toString() ?? _defaultHospital,
              'consultant': map['consultant']?.toString() ?? _defaultConsultant,
              'category':
                  map['category']?.toString() ?? 'Appendix & Diagnostic',
              'procedureName': map['procedureName']?.toString() ?? 'Operation',
              'urgency': map['urgency']?.toString() ?? 'Elective',
              'role': map['role']?.toString() ?? 'P',
              'complications': map['complications']?.toString() ?? 'None',
              'notes': map['notes']?.toString() ?? '',
            });
            importedCount++;
          }
        }
      }

      await _initData();
      _showSnack('تم استيراد $importedCount عملية بنجاح');
    } catch (_) {
      _showSnack('فشل الاستيراد: تأكد من صحة نص JSON');
    }
  }

  Future<void> _exportCsv({String? fromDate, String? toDate}) async {
    try {
      final targetCases = _getCasesForRange(fromDate, toDate);
      final buffer = StringBuffer();
      buffer.writeln(
          'Date,Patient_ID,Age,Sex,Hospital,Consultant,Category,Procedure,CEPOD_Urgency,Role,Complications,Notes');

      String esc(dynamic val) {
        final s = (val ?? '').toString().replaceAll('"', '""');
        return '"$s"';
      }

      for (final c in targetCases) {
        buffer.writeln([
          esc(c['date']),
          esc(c['patientId']),
          esc(c['age']),
          esc(c['sex']),
          esc(c['hospital']),
          esc(c['consultant']),
          esc(c['category']),
          esc(c['procedureName']),
          esc(c['urgency']),
          esc(c['role']),
          esc(c['complications']),
          esc(c['notes']),
        ].join(','));
      }

      final csvText = buffer.toString();
      await Clipboard.setData(ClipboardData(text: csvText));

      final rangeTag = (fromDate != null || toDate != null)
          ? '${fromDate ?? "Start"}_to_${toDate ?? "Now"}'
          : formatDate(DateTime.now());
      final savedPath = await _saveExportFile(
        'surgical_logbook_$rangeTag.csv',
        Uint8List.fromList(utf8.encode(csvText)),
      );

      _showSnack('تم حفظ ملف الإكسل CSV ونسخه للحافظة:\n$savedPath');
    } catch (e) {
      _showSnack('Error exporting CSV: $e');
    }
  }

  void _openConsolidationReportScreen({String? fromDate, String? toDate}) {
    final targetCases = _getCasesForRange(fromDate, toDate);
    if (targetCases.isEmpty) {
      _showSnack('لا توجد عمليات مسجلة في هذه الفترة');
      return;
    }

    final periodText = (fromDate == null && toDate == null)
        ? 'All Recorded Operations (Complete Logbook)'
        : 'From: ${fromDate ?? "Beginning"}   To: ${toDate ?? formatDate(DateTime.now())}';

    final Map<String, Map<String, int>> summary = {};
    for (final c in targetCases) {
      final proc = c['procedureName']?.toString() ?? 'Operation';
      final role = c['role']?.toString() ?? 'P';
      summary.putIfAbsent(proc,
          () => {'P': 0, 'S-TS': 0, 'S-TU': 0, 'A': 0, 'T': 0, 'Total': 0});
      summary[proc]![role] = (summary[proc]![role] ?? 0) + 1;
      summary[proc]!['Total'] = (summary[proc]!['Total'] ?? 0) + 1;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsolidationReportScreen(
          traineeName: _traineeName,
          traineeGrade: _traineeGrade,
          hospital: _defaultHospital,
          consultant: _defaultConsultant,
          periodText: periodText,
          summary: summary,
          cases: targetCases,
          onSavePdf: (bytes) => _saveExportFile(
            'Surgical_Logbook_${formatStamp(DateTime.now())}.pdf',
            bytes,
          ),
        ),
      ),
    );
  }

  void _showProfileDialog() {
    final nameCtrl = TextEditingController(text: _traineeName);
    final gradeCtrl = TextEditingController(text: _traineeGrade);
    final hospCtrl = TextEditingController(text: _defaultHospital);
    final consCtrl = TextEditingController(text: _defaultConsultant);
    final goalCtrl = TextEditingController(text: _targetCasesGoal.toString());
    final pinCtrl = TextEditingController(text: _pinCode);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardBg,
        title: const Text('بيانات الطبيب والإعدادات',
            style: TextStyle(color: kGoldColor, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Surgeon / Trainee Name (الاسم بالإنكليزية)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: gradeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Grade / Specialty (الدرجة العلمية)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hospCtrl,
                decoration: const InputDecoration(
                    labelText: 'Default Hospital (المستشفى الافتراضي)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: consCtrl,
                decoration: const InputDecoration(
                    labelText: 'Default Consultant (المشرف الافتراضي)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: goalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Target Operations Goal (الهدف التدريبي)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN Lock (رمز قفل التطبيق - اتركه فارغاً للإلغاء)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kGoldColor, foregroundColor: Colors.black),
            onPressed: () async {
              await LogbookDatabase.instance
                  .saveSetting('traineeName', nameCtrl.text.trim());
              await LogbookDatabase.instance
                  .saveSetting('traineeGrade', gradeCtrl.text.trim());
              await LogbookDatabase.instance
                  .saveSetting('defaultHospital', hospCtrl.text.trim());
              await LogbookDatabase.instance
                  .saveSetting('defaultConsultant', consCtrl.text.trim());
              await LogbookDatabase.instance
                  .saveSetting('targetCasesGoal', goalCtrl.text.trim());
              await LogbookDatabase.instance
                  .saveSetting('pinCode', pinCtrl.text.trim());
              if (mounted) Navigator.pop(ctx);
              _initData();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showCaseSheet({Map<String, dynamic>? existingCase}) {
    final int? editingId = existingCase?['id'] as int?;
    final bool isEdit = editingId != null;

    final patientIdCtrl = TextEditingController(
        text: existingCase?['patientId']?.toString() ?? '');
    final ageCtrl = TextEditingController(
        text:
            existingCase != null ? (existingCase['age']?.toString() ?? '') : '');
    final hospitalCtrl = TextEditingController(
        text: existingCase?['hospital']?.toString() ?? _defaultHospital);
    final consultantCtrl = TextEditingController(
        text: existingCase?['consultant']?.toString() ?? _defaultConsultant);
    final customProcCtrl = TextEditingController();
    final complicationsCtrl = TextEditingController(
        text: existingCase?['complications']?.toString() ?? 'None');
    final notesCtrl =
        TextEditingController(text: existingCase?['notes']?.toString() ?? '');

    String selectedDate =
        existingCase?['date']?.toString() ?? formatDate(DateTime.now());
    String selectedSex = existingCase?['sex']?.toString() ?? 'M';
    String selectedCategory = existingCase?['category']?.toString() ??
        kSurgicalProcedures.keys.first;
    if (!kSurgicalProcedures.containsKey(selectedCategory)) {
      selectedCategory = kSurgicalProcedures.keys.first;
    }

    List<String> currentCategoryProcs = kSurgicalProcedures[selectedCategory]!;
    String selectedProcedure = existingCase?['procedureName']?.toString() ??
        currentCategoryProcs.first;
    if (!currentCategoryProcs.contains(selectedProcedure)) {
      selectedCategory = 'Trauma, Vascular & Minor';
      currentCategoryProcs = kSurgicalProcedures[selectedCategory]!;
      selectedProcedure = 'Other (Custom Procedure)';
      customProcCtrl.text = existingCase?['procedureName']?.toString() ?? '';
    }

    String selectedUrgency = existingCase?['urgency']?.toString() ?? 'Elective';
    String selectedRole = existingCase?['role']?.toString() ?? 'P';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEdit
                      ? 'Edit Operation (تعديل العملية)'
                      : 'Log New Operation (إضافة عملية)',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: kGoldColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.tryParse(selectedDate) ??
                                DateTime.now(),
                            firstDate: DateTime(2015),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setModalState(() {
                              selectedDate = formatDate(picked);
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date (التاريخ)',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(selectedDate),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: patientIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Patient ID / MRN',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Age (العمر)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown(
                        label: 'Sex (الجنس)',
                        value: selectedSex,
                        items: const [
                          DropdownMenuItem(
                              value: 'M', child: Text('Male (ذكر)')),
                          DropdownMenuItem(
                              value: 'F', child: Text('Female (أنثى)')),
                        ],
                        onChanged: (val) =>
                            setModalState(() => selectedSex = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Subspecialty Category (التصنيف الجراحي)',
                  value: selectedCategory,
                  items: kSurgicalProcedures.keys
                      .map((cat) =>
                          DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (val) {
                    setModalState(() {
                      selectedCategory = val!;
                      selectedProcedure =
                          kSurgicalProcedures[selectedCategory]!.first;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Procedure (نوع العملية)',
                  value: selectedProcedure,
                  items: kSurgicalProcedures[selectedCategory]!
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) =>
                      setModalState(() => selectedProcedure = val!),
                ),
                if (selectedProcedure == 'Other (Custom Procedure)') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customProcCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Enter Custom Procedure Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        label: 'CEPOD Urgency',
                        value: selectedUrgency,
                        items: ['Elective', 'Scheduled', 'Urgent', 'Emergency']
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (val) =>
                            setModalState(() => selectedUrgency = val!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown(
                        label: 'Supervision Role',
                        value: selectedRole,
                        items: const [
                          DropdownMenuItem(
                              value: 'P', child: Text('P (Performed)')),
                          DropdownMenuItem(
                              value: 'S-TS', child: Text('S-TS (Scrubbed)')),
                          DropdownMenuItem(
                              value: 'S-TU', child: Text('S-TU (Unscrubbed)')),
                          DropdownMenuItem(
                              value: 'A', child: Text('A (Assisted)')),
                          DropdownMenuItem(
                              value: 'T', child: Text('T (Training Junior)')),
                        ],
                        onChanged: (val) =>
                            setModalState(() => selectedRole = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: hospitalCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Hospital (المستشفى)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: consultantCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Consultant (المشرف)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: complicationsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Complications (المضاعفات)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Operative Findings & Notes (ملاحظات العملية)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGoldColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final finalProcedure =
                        selectedProcedure == 'Other (Custom Procedure)'
                            ? customProcCtrl.text.trim()
                            : selectedProcedure;
                    if (patientIdCtrl.text.trim().isEmpty ||
                        finalProcedure.isEmpty) {
                      return;
                    }
                    final row = {
                      'date': selectedDate,
                      'patientId': patientIdCtrl.text.trim(),
                      'age': int.tryParse(ageCtrl.text.trim()) ?? 0,
                      'sex': selectedSex,
                      'hospital': hospitalCtrl.text.trim(),
                      'consultant': consultantCtrl.text.trim(),
                      'category': selectedCategory,
                      'procedureName': finalProcedure,
                      'urgency': selectedUrgency,
                      'role': selectedRole,
                      'complications': complicationsCtrl.text.trim(),
                      'notes': notesCtrl.text.trim(),
                    };

                    if (editingId != null) {
                      await LogbookDatabase.instance.updateCase(editingId, row);
                    } else {
                      await LogbookDatabase.instance.insertCase(row);
                    }
                    if (mounted) Navigator.pop(ctx);
                    _refreshCases();
                  },
                  child: Text(
                    isEdit
                        ? 'Update Operation (حفظ التعديلات)'
                        : 'Save Operation (حفظ العملية)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsDashboard() {
    final list = _dateFilteredCases;
    final total = list.length;

    final pCount = _countByRole('P');
    final stsCount = _countByRole('S-TS');
    final stuCount = _countByRole('S-TU');
    final tCount = _countByRole('T');
    final aCount = _countByRole('A');

    final operatingCount = pCount + stsCount + stuCount + tCount;
    final independenceRatio = total == 0 ? 0.0 : operatingCount / total;
    final goalProgress = _targetCasesGoal <= 0
        ? 0.0
        : (total / _targetCasesGoal).clamp(0.0, 1.0);

    int countUrgency(String u) => list.where((c) => c['urgency'] == u).length;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          color: kCardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kGoldBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'التقدم نحو الهدف التدريبي (Target Goal)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kGoldColor,
                          fontSize: 15),
                    ),
                    Text(
                      '$total / $_targetCasesGoal',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: goalProgress,
                    minHeight: 10,
                    backgroundColor: Colors.white12,
                    color: kGoldColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'نسبة إنجاز الهدف المحدد: ${(goalProgress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: kCardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kGoldBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مؤشر الاستقلالية الجراحية (Operating vs Assisted)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kGoldColor,
                      fontSize: 15),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'جراح رئيسي / بإشراف: $operatingCount (${(independenceRatio * 100).toStringAsFixed(1)}%)',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.greenAccent),
                    ),
                    Text(
                      'مساعد (A): $aCount',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.orangeAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: independenceRatio,
                    minHeight: 10,
                    backgroundColor: const Color(0x46FFAB40),
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: kCardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kGoldBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'توزيع الحالات حسب درجة الاستعجال (CEPOD)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kGoldColor,
                      fontSize: 15),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _urgencyBox('Elective', countUrgency('Elective')),
                    _urgencyBox('Scheduled', countUrgency('Scheduled')),
                    _urgencyBox('Urgent', countUrgency('Urgent')),
                    _urgencyBox('Emergency', countUrgency('Emergency')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: kCardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kGoldBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تفصيل العمليات حسب التخصص الجراحي الفرعي',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kGoldColor,
                      fontSize: 15),
                ),
                const SizedBox(height: 12),
                ...kSurgicalProcedures.keys.map((category) {
                  final catCases =
                      list.where((c) => c['category'] == category).toList();
                  final catTotal = catCases.length;
                  final catOperating =
                      catCases.where((c) => c['role'] != 'A').length;
                  final catAssisted =
                      catCases.where((c) => c['role'] == 'A').length;
                  final ratio = total == 0 ? 0.0 : catTotal / total;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                category,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            Text(
                              'المجموع: $catTotal  (منفذ: $catOperating | مساعد: $catAssisted)',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 6,
                            backgroundColor: Colors.white10,
                            color: kGoldColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _urgencyBox(String label, int count) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: kGoldColor),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }

  Widget _buildStatChip(String label, int count, String roleKey) {
    final isSelected = _selectedRoleFilter == roleKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedRoleFilter = roleKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kGoldColor : kCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kGoldBorder),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.black : kGoldColor,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.black87 : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockScreen() {
    final pinInputCtrl = TextEditingController();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: kGoldColor),
              const SizedBox(height: 16),
              const Text(
                'Surgical e-Logbook Locked',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: kGoldColor),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinInputCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'أدخل رمز القفل (PIN)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (val) {
                  if (val.trim() == _pinCode) {
                    setState(() => _isLocked = false);
                  } else {
                    _showSnack('رمز القفل غير صحيح');
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGoldColor,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () {
                  if (pinInputCtrl.text.trim() == _pinCode) {
                    setState(() => _isLocked = false);
                  } else {
                    _showSnack('رمز القفل غير صحيح');
                  }
                },
                child: const Text('فتح السجل الجراحي',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return _buildLockScreen();
    }

    final hasDateFilter = _screenStartDate != null || _screenEndDate != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Surgical e-Logbook', style: TextStyle(fontSize: 18)),
            Text(
              _traineeName,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.date_range,
              color: hasDateFilter ? Colors.amberAccent : kGoldColor,
            ),
            tooltip: 'فلترة السجل بالتاريخ',
            onPressed: () => _showDateRangeDialog(mode: 'screen_filter'),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Consolidation PDF Report',
            onPressed: _cases.isEmpty
                ? null
                : () => _showDateRangeDialog(mode: 'pdf'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: kCardBg,
            onSelected: (value) {
              if (value == 'profile') _showProfileDialog();
              if (value == 'export_json') _exportJsonBackup();
              if (value == 'import_json') _showRestoreBackupDialog();
              if (value == 'export_csv') _showDateRangeDialog(mode: 'csv');
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.badge_outlined, color: kGoldColor),
                  title: Text('بيانات الطبيب والهدف وقفل PIN'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart_outlined, color: kGoldColor),
                  title: Text('تصدير جدول إكسل (CSV لفترة محددة)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_json',
                child: ListTile(
                  leading: Icon(Icons.cloud_upload_outlined, color: kGoldColor),
                  title: Text('تصدير نسخة احتياطية شاملة (JSON)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import_json',
                child: ListTile(
                  leading:
                      Icon(Icons.cloud_download_outlined, color: kGoldColor),
                  title: Text('استعادة نسخة احتياطية (JSON)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (hasDateFilter)
            Container(
              margin: const EdgeInsets.only(left: 12, right: 12, top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kGoldSubtle,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kGoldColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الفترة المعروضة: ${_screenStartDate ?? "البداية"} ← ${_screenEndDate ?? "اليوم"}',
                    style: const TextStyle(
                        color: kGoldColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                  InkWell(
                    onTap: () => setState(() {
                      _screenStartDate = null;
                      _screenEndDate = null;
                    }),
                    child: const Icon(Icons.close, size: 18, color: kGoldColor),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatChip('Total', _dateFilteredCases.length, 'ALL'),
                _buildStatChip('P', _countByRole('P'), 'P'),
                _buildStatChip('S-TS', _countByRole('S-TS'), 'S-TS'),
                _buildStatChip('S-TU', _countByRole('S-TU'), 'S-TU'),
                _buildStatChip('A', _countByRole('A'), 'A'),
                _buildStatChip('T', _countByRole('T'), 'T'),
              ],
            ),
          ),
          Expanded(
            child: _currentTabIndex == 1
                ? _buildAnalyticsDashboard()
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText:
                                'Search procedure, category, or Patient ID...',
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _filteredCases.isEmpty
                            ? const Center(
                                child: Text(
                                    'No operations found in the selected period.'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _filteredCases.length,
                                itemBuilder: (ctx, i) {
                                  final c = _filteredCases[i];
                                  return Card(
                                    color: kCardBg,
                                    margin: const EdgeInsets.only(bottom: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side:
                                          const BorderSide(color: kGoldBorder),
                                    ),
                                    child: ListTile(
                                      onTap: () =>
                                          _showCaseSheet(existingCase: c),
                                      title: Text(
                                        c['procedureName']?.toString() ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: kGoldColor),
                                      ),
                                      subtitle: Text(
                                        'Date: ${c['date']} | Pt: ${c['patientId']} (${c['age']}${c['sex']}) | CEPOD: ${c['urgency']}\nSupervisor: ${c['consultant']} | Hosp: ${c['hospital']}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: kGoldSubtle,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              c['role']?.toString() ?? '',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: kGoldColor),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.redAccent),
                                            onPressed: () async {
                                              await LogbookDatabase.instance
                                                  .deleteCase(c['id'] as int);
                                              _refreshCases();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        backgroundColor: kCardBg,
        selectedItemColor: kGoldColor,
        unselectedItemColor: Colors.white54,
        onTap: (idx) => setState(() => _currentTabIndex = idx),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Operations Log (السجل)',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: 'Analytics (الإحصائيات)',
          ),
        ],
      ),
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton(
              onPressed: () => _showCaseSheet(),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class ConsolidationReportScreen extends StatelessWidget {
  final String traineeName;
  final String traineeGrade;
  final String hospital;
  final String consultant;
  final String periodText;
  final Map<String, Map<String, int>> summary;
  final List> cases;
  final Future<String> Function(Uint8List bytes) onSavePdf;

  const ConsolidationReportScreen({
    super.key,
    required this.traineeName,
    required this.traineeGrade,
    required this.hospital,
    required this.consultant,
    required this.periodText,
    required this.summary,
    required this.cases,
    required this.onSavePdf,
  });

  int _countRole(String r) => cases.where((c) => c['role'] == r).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Consolidation Sheet Preview'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download, color: kGoldColor),
            label: const Text('حفظ PDF',
                style:
                    TextStyle(color: kGoldColor, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final bytes = PurePdfGenerator.generateReportPdf(
                traineeName: traineeName,
                traineeGrade: traineeGrade,
                hospital: hospital,
                consultant: consultant,
                periodText: periodText,
                summary: summary,
                cases: cases,
              );
              final path = await onSavePdf(bytes);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم حفظ ملف الـ PDF في:\n$path'),
                    backgroundColor: kCardBg,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black87, fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'PAN-SURGICAL ELECTRONIC LOGBOOK',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
              ),
              const SizedBox(height: 4),
              Text('Surgeon / Trainee: $traineeName ($traineeGrade)'),
              Text('Institution: $hospital   |   Consultant: $consultant'),
              Text(
                'Logbook Period: $periodText',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Divider(color: Colors.black, thickness: 1.5, height: 20),
              const Text(
                '1. Procedure Consolidation Summary',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
              ),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: Colors.black54),
                columnWidths: const {
                  0: FlexColumnWidth(3.5),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.2),
                  3: FlexColumnWidth(1.2),
                  4: FlexColumnWidth(1),
                  5: FlexColumnWidth(1),
                  6: FlexColumnWidth(1.2),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFE0E0E0)),
                    children: [
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Procedure',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('P',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('S-TS',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('S-TU',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('A',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('T',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Total',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  ...summary.entries.map(
                    (e) => TableRow(
                      children: [
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(e.key)),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${e.value['P']}',
                                textAlign: TextAlign.center)),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${e.value['S-TS']}',
                                textAlign: TextAlign.center)),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${e.value['S-TU']}',
                                textAlign: TextAlign.center)),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${e.value['A']}',
                                textAlign: TextAlign.center)),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${e.value['T']}',
                                textAlign: TextAlign.center)),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${e.value['Total']}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.black)),
                child: Text(
                  'Period Total: ${cases.length}  |  Performed (P): ${_countRole('P')}  |  Supervised: ${_countRole('S-TS') + _countRole('S-TU')}  |  Assisted (A): ${_countRole('A')}  |  Training (T): ${_countRole('T')}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '2. Detailed Operative Logbook Record',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
              ),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: Colors.black54),
                columnWidths: const {
                  0: FlexColumnWidth(1.6),
                  1: FlexColumnWidth(1.3),
                  2: FlexColumnWidth(1.0),
                  3: FlexColumnWidth(2.8),
                  4: FlexColumnWidth(1.4),
                  5: FlexColumnWidth(1.0),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFE0E0E0)),
                    children: [
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Date',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 10))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Pt ID',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 10))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Age/S',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 10))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Procedure',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 10))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('CEPOD',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 10))),
                      Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Role',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 10))),
                    ],
                  ),
                  ...cases.map(
                    (c) => TableRow(
                      children: [
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${c['date']}',
                                style: const TextStyle(fontSize: 10))),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${c['patientId']}',
                                style: const TextStyle(fontSize: 10))),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${c['age']}/${c['sex']}',
                                style: const TextStyle(fontSize: 10))),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${c['procedureName']}',
                                style: const TextStyle(fontSize: 10))),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${c['urgency']}',
                                style: const TextStyle(fontSize: 10))),
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${c['role']}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                transformAlignment: Alignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Trainee Signature: ____________________'),
                      const SizedBox(height: 4),
                      Text(traineeName),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Consultant Signature: ____________________'),
                      const SizedBox(height: 4),
                      Text(consultant),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
