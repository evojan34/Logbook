import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SurgicalLogbookApp());
}

class SurgicalLogbookApp extends StatelessWidget {
  const SurgicalLogbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);
    const darkBg = Color(0xFF121212);
    const cardBg = Color(0xFF1E1E1E);

    return MaterialApp(
      title: 'Surgical e-Logbook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: darkBg,
        primaryColor: goldColor,
        colorScheme: const ColorScheme.dark(
          primary: goldColor,
          secondary: goldColor,
          surface: cardBg,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: cardBg,
          foregroundColor: goldColor,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: goldColor.withOpacity(0.25)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: goldColor,
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
    final path = p.join(dbPath, 'surgical_elogbook.db');
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
            procedureName TEXT NOT NULL,
            urgency TEXT NOT NULL,
            role TEXT NOT NULL,
            complications TEXT NOT NULL,
            notes TEXT
          )
        ''');
      },
    );
    return _database!;
  }

  Future<int> insertCase(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('operations', row);
  }

  Future<List>> fetchAllCases() async {
    final db = await instance.database;
    return await db.query('operations', orderBy: 'date DESC, id DESC');
  }

  Future<int> deleteCase(int id) async {
    final db = await instance.database;
    return await db.delete('operations', where: 'id = ?', whereArgs: [id]);
  }
}

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

  final List<String> _commonProcedures = [
    'Open Appendicectomy',
    'Laparoscopic Appendicectomy',
    'Laparoscopic Cholecystectomy',
    'Open Cholecystectomy',
    'Inguinal Hernia Repair (Mesh)',
    'Paraumbilical / Umbilical Hernia Repair',
    'Incisional Hernia Repair',
    'Exploratory Laparotomy',
    'Thyroidectomy (Total / Subtotal)',
    'Modified Radical Mastectomy / Lumpectomy',
    'Haemorrhoidectomy',
    'Fistulotomy / Perianal Abscess Drainage',
    'Pilonidal Sinus Excision',
    'Chest Tube (ICTD) Insertion',
    'Wound Debridement & Suturing',
    'Other (Custom)',
  ];

  @override
  void initState() {
    super.initState();
    _refreshCases();
  }

  Future<void> _refreshCases() async {
    final data = await LogbookDatabase.instance.fetchAllCases();
    setState(() {
      _cases = data;
    });
  }

  List> get _filteredCases {
    return _cases.where((c) {
      final matchesRole =
          _selectedRoleFilter == 'ALL' || c['role'] == _selectedRoleFilter;
      final matchesSearch = c['procedureName']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          c['patientId']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      return matchesRole && matchesSearch;
    }).toList();
  }

  int _countByRole(String role) =>
      _cases.where((c) => c['role'] == role).length;

  // --- PDF Consolidation Report Generator ---
  Future<void> _exportConsolidationPdf() async {
    final pdf = pw.Document();

    // Group cases by procedure name for the summary table
    final Map<String, Map<String, int>> summary = {};
    for (var c in _cases) {
      final proc = c['procedureName'] as String;
      final role = c['role'] as String;
      summary.putIfAbsent(
          proc, () => {'P': 0, 'S-TS': 0, 'S-TU': 0, 'A': 0, 'T': 0, 'Total': 0});
      summary[proc]![role] = (summary[proc]![role] ?? 0) + 1;
      summary[proc]!['Total'] = (summary[proc]!['Total'] ?? 0) + 1;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('PAN-SURGICAL ELECTRONIC LOGBOOK',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Procedure Consolidation Sheet (General Surgery)',
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
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
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.center,
          ),
          pw.SizedBox(height: 20),
          pw.Text(
              'Total Logged Cases: ${_cases.length}  |  Performed (P): ${_countByRole('P')}  |  Supervised (S-TS/S-TU): ${_countByRole('S-TS') + _countByRole('S-TU')}  |  Assisted (A): ${_countByRole('A')}',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 24),
          pw.Text('Detailed Operative Log',
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
              'Complications'
            ],
            data: _cases
                .map((c) => [
                      c['date'],
                      c['patientId'],
                      '${c['age']}/${c['sex']}',
                      c['procedureName'],
                      c['urgency'],
                      c['role'],
                      c['complications'],
                    ])
                .toList(),
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Trainee Signature: ______________________'),
              pw.Text('Supervisor Signature: ______________________'),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // --- Add Operation Modal ---
  void _showAddCaseSheet() {
    final patientIdCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final hospitalCtrl = TextEditingController(text: 'Teaching Hospital');
    final customProcCtrl = TextEditingController();
    final complicationsCtrl = TextEditingController(text: 'None');
    final notesCtrl = TextEditingController();

    String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String selectedSex = 'M';
    String selectedProcedure = _commonProcedures.first;
    String selectedUrgency = 'Elective';
    String selectedRole = 'P';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
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
                const Text(
                  'Log New Operation (إضافة عملية)',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD4AF37)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: patientIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Patient ID / MRN',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                    DropdownButton<String>(
                      value: selectedSex,
                      items: const [
                        DropdownMenuItem(value: 'M', child: Text('Male')),
                        DropdownMenuItem(value: 'F', child: Text('Female')),
                      ],
                      onChanged: (val) =>
                          setModalState(() => selectedSex = val!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hospitalCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hospital (المستشفى)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedProcedure,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Procedure (نوع العملية)',
                    border: OutlineInputBorder(),
                  ),
                  items: _commonProcedures
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) =>
                      setModalState(() => selectedProcedure = val!),
                ),
                if (selectedProcedure == 'Other (Custom)') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customProcCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Enter Procedure Name in English',
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
                              value: 'T', child: Text('T (Training)')),
                        ],
                        onChanged: (val) =>
                            setModalState(() => selectedRole = val!),
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
                  decoration: const InputDecoration(
                    labelText: 'Operative Notes (ملاحظات)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final finalProcedure =
                        selectedProcedure == 'Other (Custom)'
                            ? customProcCtrl.text.trim()
                            : selectedProcedure;
                    if (patientIdCtrl.text.isEmpty || finalProcedure.isEmpty) {
                      return;
                    }
                    await LogbookDatabase.instance.insertCase({
                      'date': selectedDate,
                      'patientId': patientIdCtrl.text.trim(),
                      'age': int.tryParse(ageCtrl.text.trim()) ?? 0,
                      'sex': selectedSex,
                      'hospital': hospitalCtrl.text.trim(),
                      'procedureName': finalProcedure,
                      'urgency': selectedUrgency,
                      'role': selectedRole,
                      'complications': complicationsCtrl.text.trim(),
                      'notes': notesCtrl.text.trim(),
                    });
                    if (mounted) Navigator.pop(ctx);
                    _refreshCases();
                  },
                  child: const Text('Save Operation (حفظ العملية)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
          color: isSelected ? const Color(0xFFD4AF37) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.black : const Color(0xFFD4AF37),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surgical e-Logbook'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export Consolidation PDF',
            onPressed: _cases.isEmpty ? null : _exportConsolidationPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatChip('Total', _cases.length, 'ALL'),
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
                hintText: 'Search procedure or Patient ID...',
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
                    child: Text('No operations logged yet. Tap + to add.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredCases.length,
                    itemBuilder: (ctx, i) {
                      final c = _filteredCases[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            c['procedureName'],
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37)),
                          ),
                          subtitle: Text(
                            'Date: ${c['date']} | Pt: ${c['patientId']} (${c['age']}${c['sex']})\nCEPOD: ${c['urgency']} | Hospital: ${c['hospital']}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFD4AF37).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  c['role'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFD4AF37)),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () async {
                                  await LogbookDatabase.instance
                                      .deleteCase(c['id']);
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
        onPressed: _showAddCaseSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}
