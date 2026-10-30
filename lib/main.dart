import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SurgicalLogbookApp());
}

const Color kGoldColor = Color(0xFFD4AF37);
const Color kDarkBg = Color(0xFF121212);
const Color kCardBg = Color(0xFF1E1E1E);

class SurgicalLogbookApp extends StatelessWidget {
  const SurgicalLogbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Surgical e-Logbook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
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

// --- Database Helper ---
class LogbookDatabase {
  static final LogbookDatabase instance = LogbookDatabase._init();
  static Database? _database;
  LogbookDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'surgical_elogbook_v2.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            patientId TEXT NOT NULL,
            age INTEGER NOT NULL,
            sex TEXT NOT NULL,
            hospital TEXT NOT NULL,
            consultant TEXT NOT NULL,
            category TEXT NOT NULL,
            procedureName TEXT NOT NULL,
            urgency TEXT NOT NULL,
            role TEXT NOT NULL,
            complications TEXT NOT NULL,
            notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<int> insertCase(Map<String, dynamic> row) async {
    final db = await instance.database;
    final cleanRow = Map<String, dynamic>.from(row)..remove('id');
    return await db.insert('operations', cleanRow);
  }

  Future<int> updateCase(int id, Map<String, dynamic> row) async {
    final db = await instance.database;
    final cleanRow = Map<String, dynamic>.from(row)..remove('id');
    return await db.update('operations', cleanRow,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List>> fetchAllCases() async {
    final db = await instance.database;
    return await db.query('operations', orderBy: 'date DESC, id DESC');
  }

  Future<int> deleteCase(int id) async {
    final db = await instance.database;
    return await db.delete('operations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future> loadSettings() async {
    final db = await instance.database;
    final rows = await db.query('settings');
    final Map<String, String> map = {};
    for (var r in rows) {
      map[r['key'] as String] = r['value'] as String;
    }
    return map;
  }
}

// --- Categorized General Surgery Procedures ---
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
    'Hartmann\'s Procedure',
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

// --- Main Screen ---
class LogbookHomeScreen extends StatefulWidget {
  const LogbookHomeScreen({super.key});

  @override
  State<LogbookHomeScreen> createState() => _LogbookHomeScreenState();
}

class _LogbookHomeScreenState extends State<LogbookHomeScreen> {
  List> _cases = [];
  String _selectedRoleFilter = 'ALL';
  String _searchQuery = '';

  // Active Screen Date Filter (YYYY-MM-DD)
  String? _screenStartDate;
  String? _screenEndDate;

  String _traineeName = 'Dr. Surgeon';
  String _traineeGrade = 'General Surgery Resident';
  String _defaultHospital = 'Teaching Hospital';
  String _defaultConsultant = 'Consultant Surgeon';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final settings = await LogbookDatabase.instance.loadSettings();
    final data = await LogbookDatabase.instance.fetchAllCases();
    setState(() {
      _traineeName = settings['traineeName'] ?? 'Dr. Surgeon';
      _traineeGrade = settings['traineeGrade'] ?? 'General Surgery Resident';
      _defaultHospital = settings['defaultHospital'] ?? 'Teaching Hospital';
      _defaultConsultant = settings['defaultConsultant'] ?? 'Consultant Surgeon';
      _cases = data;
    });
  }

  Future<void> _refreshCases() async {
    final data = await LogbookDatabase.instance.fetchAllCases();
    setState(() => _cases = data);
  }

  // Helper to check if a case date falls within [fromDate, toDate] inclusive
  bool _isDateInRange(String caseDate, String? fromDate, String? toDate) {
    if (fromDate != null && caseDate.compareTo(fromDate) < 0) return false;
    if (toDate != null && caseDate.compareTo(toDate) > 0) return false;
    return true;
  }

  List> _getCasesForRange(
      String? fromDate, String? toDate) {
    return _cases
        .where((c) => _isDateInRange(c['date'] as String, fromDate, toDate))
        .toList();
  }

  // Cases filtered by the active screen date range
  List> get _dateFilteredCases =>
      _getCasesForRange(_screenStartDate, _screenEndDate);

  // Cases displayed in the list (after applying role & search filters)
  List> get _filteredCases {
    return _dateFilteredCases.where((c) {
      final matchesRole =
          _selectedRoleFilter == 'ALL' || c['role'] == _selectedRoleFilter;
      final q = _searchQuery.toLowerCase();
      final matchesSearch =
          c['procedureName'].toString().toLowerCase().contains(q) ||
              c['patientId'].toString().toLowerCase().contains(q) ||
              c['category'].toString().toLowerCase().contains(q) ||
              c['consultant'].toString().toLowerCase().contains(q);
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

  // --- Date Range Picker Dialog for Export & Filtering ---
  void _showDateRangeDialog({required String mode}) {
    // mode: 'pdf', 'csv', or 'screen_filter'
    String? tempFrom = _screenStartDate;
    String? tempTo = _screenEndDate;
    String activePreset =
        (tempFrom == null && tempTo == null) ? 'all' : 'custom';

    void applyPreset(
        String preset, void Function(void Function()) setDialogState) {
      final now = DateTime.now();
      final fmt = DateFormat('yyyy-MM-dd');
      setDialogState(() {
        activePreset = preset;
        if (preset == 'all') {
          tempFrom = null;
          tempTo = null;
        } else if (preset == 'month') {
          tempFrom = fmt.format(DateTime(now.year, now.month, 1));
          tempTo = fmt.format(now);
        } else if (preset == '3months') {
          tempFrom = fmt.format(DateTime(now.year, now.month - 3, now.day));
          tempTo = fmt.format(now);
        } else if (preset == '6months') {
          tempFrom = fmt.format(DateTime(now.year, now.month - 6, now.day));
          tempTo = fmt.format(now);
        } else if (preset == 'year') {
          tempFrom = fmt.format(DateTime(now.year, 1, 1));
          tempTo = fmt.format(now);
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
                      : 'فلترة السجل حسب التاريخ',
              style: const TextStyle(color: kGoldColor, fontSize: 17),
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
                                tempFrom =
                                    DateFormat('yyyy-MM-dd').format(picked);
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
                                tempTo =
                                    DateFormat('yyyy-MM-dd').format(picked);
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
                      color: kGoldColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kGoldColor.withOpacity(0.4)),
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
                          _exportConsolidationPdf(
                              fromDate: tempFrom, toDate: tempTo);
                        } else if (mode == 'csv') {
                          _exportCsv(fromDate: tempFrom, toDate: tempTo);
                        }
                      },
                child: Text(
                  mode == 'pdf'
                      ? 'توليد PDF'
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

  // --- 1. JSON Backup Export ---
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
      final dir = await getTemporaryDirectory();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = File('${dir.path}/elogbook_backup_$dateStr.json');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Surgical e-Logbook Full Backup ($dateStr)',
      );
    } catch (e) {
      _showSnack('Error exporting backup: $e');
    }
  }

  // --- 2. JSON Backup Restore ---
  Future<void> _importJsonBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);

      if (data['settings'] != null && data['settings'] is Map) {
        final Map<String, dynamic> s = data['settings'];
        for (var entry in s.entries) {
          await LogbookDatabase.instance
              .saveSetting(entry.key, entry.value.toString());
        }
      }

      int importedCount = 0;
      if (data['operations'] != null && data['operations'] is List) {
        final List ops = data['operations'];
        final existing = await LogbookDatabase.instance.fetchAllCases();

        for (var item in ops) {
          final map = Map<String, dynamic>.from(item);
          final isDuplicate = existing.any((e) =>
              e['date'] == map['date'] &&
              e['patientId'] == map['patientId'] &&
              e['procedureName'] == map['procedureName']);

          if (!isDuplicate) {
            await LogbookDatabase.instance.insertCase({
              'date': map['date'] ??
                  DateFormat('yyyy-MM-dd').format(DateTime.now()),
              'patientId': map['patientId'] ?? 'Unknown',
              'age': map['age'] ?? 0,
              'sex': map['sex'] ?? 'M',
              'hospital': map['hospital'] ?? _defaultHospital,
              'consultant': map['consultant'] ?? _defaultConsultant,
              'category': map['category'] ?? 'General',
              'procedureName': map['procedureName'] ?? 'Operation',
              'urgency': map['urgency'] ?? 'Elective',
              'role': map['role'] ?? 'P',
              'complications': map['complications'] ?? 'None',
              'notes': map['notes'] ?? '',
            });
            importedCount++;
          }
        }
      }

      await _initData();
      _showSnack('تم استيراد $importedCount عملية بنجاح');
    } catch (e) {
      _showSnack('فشل استيراد الملف: تأكد من صحة صيغة JSON');
    }
  }

  // --- 3. CSV Export (Supports Date Range) ---
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

      for (var c in targetCases) {
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

      final dir = await getTemporaryDirectory();
      final rangeTag = (fromDate != null || toDate != null)
          ? '${fromDate ?? "Start"}_to_${toDate ?? "Now"}'
          : DateFormat('yyyyMMdd').format(DateTime.now());
      final file = File('${dir.path}/surgical_logbook_$rangeTag.csv');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Surgical e-Logbook CSV ($rangeTag)',
      );
    } catch (e) {
      _showSnack('Error exporting CSV: $e');
    }
  }

  // --- 4. PDF Consolidation Report (Supports Date Range) ---
  Future<void> _exportConsolidationPdf(
      {String? fromDate, String? toDate}) async {
    final targetCases = _getCasesForRange(fromDate, toDate);
    if (targetCases.isEmpty) {
      _showSnack('لا توجد عمليات مسجلة في هذه الفترة');
      return;
    }

    final pdf = pw.Document();
    final periodText = (fromDate == null && toDate == null)
        ? 'All Recorded Operations (Complete Logbook)'
        : 'From: ${fromDate ?? "Beginning"}   To: ${toDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now())}';

    final Map<String, Map<String, int>> summary = {};
    for (var c in targetCases) {
      final proc = c['procedureName'] as String;
      final role = c['role'] as String;
      summary.putIfAbsent(proc,
          () => {'P': 0, 'S-TS': 0, 'S-TU': 0, 'A': 0, 'T': 0, 'Total': 0});
      summary[proc]![role] = (summary[proc]![role] ?? 0) + 1;
      summary[proc]!['Total'] = (summary[proc]!['Total'] ?? 0) + 1;
    }

    int countRoleInTarget(String r) =>
        targetCases.where((c) => c['role'] == r).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('PAN-SURGICAL ELECTRONIC LOGBOOK',
                        style: pw.TextStyle(
                            fontSize: 15, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Surgeon / Trainee: $_traineeName ($_traineeGrade)',
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Primary Institution: $_defaultHospital',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 3),
                    pw.Text('Logbook Period: $periodText',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Text(
                    'Printed: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('1. Procedure Consolidation Summary',
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Procedure Name', 'P', 'S-TS', 'S-TU', 'A', 'T', 'Total'],
            data: summary.entries
                .map((e) => [
                      e.key,
                      e.value['P'].toString(),
                      e.value['S-TS'].toString(),
                      e.value['S-TU'].toString(),
                      e.value['A'].toString(),
                      e.value['T'].toString(),
                      e.value['Total'].toString(),
                    ])
                .toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            child: pw.Text(
              'Period Total: ${targetCases.length}   |   Performed (P): ${countRoleInTarget('P')}   |   Supervised (S-TS / S-TU): ${countRoleInTarget('S-TS') + countRoleInTarget('S-TU')}   |   Assisted (A): ${countRoleInTarget('A')}   |   Training (T): ${countRoleInTarget('T')}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('2. Detailed Operative Logbook Record',
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              'Pt ID',
              'Age/Sex',
              'Procedure',
              'CEPOD',
              'Role',
              'Consultant',
              'Complications'
            ],
            data: targetCases
                .map((c) => [
                      c['date'],
                      c['patientId'],
                      '${c['age']}/${c['sex']}',
                      c['procedureName'],
                      c['urgency'],
                      c['role'],
                      c['consultant'],
                      c['complications'],
                    ])
                .toList(),
            headerStyle:
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Trainee Signature: ______________________'),
                  pw.SizedBox(height: 4),
                  pw.Text(_traineeName, style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Consultant Signature: ______________________'),
                  pw.SizedBox(height: 4),
                  pw.Text(_defaultConsultant,
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // --- 5. Trainee Profile Settings Dialog ---
  void _showProfileDialog() {
    final nameCtrl = TextEditingController(text: _traineeName);
    final gradeCtrl = TextEditingController(text: _traineeGrade);
    final hospCtrl = TextEditingController(text: _defaultHospital);
    final consCtrl = TextEditingController(text: _defaultConsultant);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardBg,
        title: const Text('بيانات الطبيب والتقرير',
            style: TextStyle(color: kGoldColor)),
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
                    labelText: 'Grade / Specialty (الدرجة)'),
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
              if (mounted) Navigator.pop(ctx);
              _initData();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // --- 6. Add / Edit Operation Sheet ---
  void _showCaseSheet({Map<String, dynamic>? existingCase}) {
    final isEdit = existingCase != null;

    final patientIdCtrl =
        TextEditingController(text: existingCase?['patientId'] ?? '');
    final ageCtrl = TextEditingController(
        text: existingCase != null ? existingCase['age'].toString() : '');
    final hospitalCtrl = TextEditingController(
        text: existingCase?['hospital'] ?? _defaultHospital);
    final consultantCtrl = TextEditingController(
        text: existingCase?['consultant'] ?? _defaultConsultant);
    final customProcCtrl = TextEditingController();
    final complicationsCtrl =
        TextEditingController(text: existingCase?['complications'] ?? 'None');
    final notesCtrl =
        TextEditingController(text: existingCase?['notes'] ?? '');

    String selectedDate = existingCase?['date'] ??
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    String selectedSex = existingCase?['sex'] ?? 'M';
    String selectedCategory =
        existingCase?['category'] ?? kSurgicalProcedures.keys.first;
    if (!kSurgicalProcedures.containsKey(selectedCategory)) {
      selectedCategory = kSurgicalProcedures.keys.first;
    }

    List<String> currentCategoryProcs = kSurgicalProcedures[selectedCategory]!;
    String selectedProcedure =
        existingCase?['procedureName'] ?? currentCategoryProcs.first;
    if (!currentCategoryProcs.contains(selectedProcedure)) {
      selectedCategory = 'Trauma, Vascular & Minor';
      currentCategoryProcs = kSurgicalProcedures[selectedCategory]!;
      selectedProcedure = 'Other (Custom Procedure)';
      customProcCtrl.text = existingCase?['procedureName'] ?? '';
    }

    String selectedUrgency = existingCase?['urgency'] ?? 'Elective';
    String selectedRole = existingCase?['role'] ?? 'P';

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
                              selectedDate =
                                  DateFormat('yyyy-MM-dd').format(picked);
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
                      child: DropdownButtonFormField<String>(
                        value: selectedSex,
                        decoration: const InputDecoration(
                          labelText: 'Sex (الجنس)',
                          border: OutlineInputBorder(),
                        ),
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
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Subspecialty Category (التصنيف الجراحي)',
                    border: OutlineInputBorder(),
                  ),
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
                DropdownButtonFormField<String>(
                  value: selectedProcedure,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Procedure (نوع العملية)',
                    border: OutlineInputBorder(),
                  ),
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
                      child: DropdownButtonFormField<String>(
                        value: selectedUrgency,
                        decoration: const InputDecoration(
                          labelText: 'CEPOD Urgency',
                          border: OutlineInputBorder(),
                        ),
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
                      child: DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Supervision Role',
                          border: OutlineInputBorder(),
                        ),
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

                    if (isEdit) {
                      await LogbookDatabase.instance
                          .updateCase(existingCase['id'] as int, row);
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

  Widget _buildStatChip(String label, int count, String roleKey) {
    final isSelected = _selectedRoleFilter == roleKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedRoleFilter = roleKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kGoldColor : kCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kGoldColor.withOpacity(0.5)),
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

  @override
  Widget build(BuildContext context) {
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
              if (value == 'import_json') _importJsonBackup();
              if (value == 'export_csv') _showDateRangeDialog(mode: 'csv');
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.badge_outlined, color: kGoldColor),
                  title: Text('بيانات الطبيب (Profile)'),
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
                color: kGoldColor.withOpacity(0.15),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search procedure, category, or Patient ID...',
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
                    child: Text('No operations found in the selected period.'))
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
                          side: BorderSide(color: kGoldColor.withOpacity(0.25)),
                        ),
                        child: ListTile(
                          onTap: () => _showCaseSheet(existingCase: c),
                          title: Text(
                            c['procedureName'],
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: kGoldColor),
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
                                  color: kGoldColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  c['role'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kGoldColor),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCaseSheet(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
