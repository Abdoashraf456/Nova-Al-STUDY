import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovaApp());
}

const bg = Color(0xFF0A1024);
const cardColor = Color(0xFF18233F);
const violet = Color(0xFF8B78FF);
const aqua = Color(0xFF64D9F7);

const courses = [
  'مبادئ المحاسبة المالية',
  'مبادئ الاقتصاد',
  'مبادئ الإدارة',
  'لغة إنجليزية للمتخصصين',
  'رياضيات تحليل الأعمال التجارية',
  'التفكير الابتكاري',
  'إدارة رياضية',
];

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOVA AI Study',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: violet,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          filled: true,
          fillColor: cardColor,
        ),
      ),
      home: const NovaHome(),
    );
  }
}

class NovaHome extends StatefulWidget {
  const NovaHome({super.key});

  @override
  State<NovaHome> createState() => _NovaHomeState();
}

class _NovaHomeState extends State<NovaHome> {
  int tab = 0;
  int subject = 0;
  bool busy = false;

  Map<String, dynamic> data = {};

  String get course => courses[subject];

  Map<String, dynamic> get current {
    return Map<String, dynamic>.from(
      data[course] ?? {},
    );
  }

  String field(String key) => (current[key] ?? '').toString();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nova_study_data');

    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          setState(() {
            data = Map<String, dynamic>.from(decoded);
          });
        }
      } catch (_) {}
    }
  }

  Future<void> saveField(String key, String value) async {
    final item = current;
    item[key] = value;
    data[course] = item;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nova_study_data',
      jsonEncode(data),
    );

    if (mounted) setState(() {});
  }

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> editField(
    String key,
    String title, {
    String hint = '',
  }) async {
    final controller = TextEditingController(
      text: field(key),
    );

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            minLines: 5,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: hint,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              await saveField(key, controller.text);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              message('تم الحفظ بنجاح');
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    controller.dispose();
  }

  Future<void> importPdf() async {
    if (busy) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => busy = true);

      final file = result.files.first;
      final Uint8List? bytes = file.bytes;

      if (bytes == null) {
        message('تعذر قراءة الملف من الجهاز');
        return;
      }

      final document = sf.PdfDocument(inputBytes: bytes);

      String extracted = '';
      int pages = 0;

      try {
        pages = document.pages.count;
        extracted = sf.PdfTextExtractor(document).extractText();
      } finally {
        document.dispose();
      }

      if (extracted.trim().isEmpty) {
        message('الملف مصور ويحتاج OCR');
        return;
      }

      await saveField(
        'source',
        '${field('source')}\n\n=== ${file.name} | $pages pages ===\n$extracted',
      );

      await saveField('filename', file.name);

      message('تم استخراج النص من $pages صفحة بنجاح');
    } catch (e) {
      message('فشل فتح ملف PDF: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<List<String>> parseRows(String key, int count) {
    return field(key)
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.split('|').map((x) => x.trim()).toList())
        .where((row) => row.length >= count)
        .toList();
  }

  Future<void> exportPdf() async {
    if (busy) return;

    setState(() => busy = true);

    try {
      final document = pw.Document();

      final arabic = await PdfGoogleFonts.notoNaskhArabicRegular();
      final arabicBold = await PdfGoogleFonts.notoNaskhArabicBold();

      final regular = pw.TextStyle(
        font: arabic,
        fontSize: 12,
        color: PdfColors.black,
        lineSpacing: 5,
      );

      final bold = pw.TextStyle(
        font: arabicBold,
        fontSize: 13,
        color: PdfColors.black,
      );

      pw.Widget section(String title, String content) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                title,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: arabicBold,
                  fontSize: 16,
                  color: PdfColors.red800,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              content.isEmpty ? 'لم يتم إضافة محتوى لهذا القسم.' : content,
              textDirection: pw.TextDirection.rtl,
              style: regular,
            ),
          ],
        );
      }

      final terms = parseRows('terms', 2);
      final questions = parseRows('questions', 7);

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(35),
          theme: pw.ThemeData.withFont(base: arabic, bold: arabicBold),
          header: (_) => pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'NOVA AI STUDY',
              style: pw.TextStyle(
                font: arabicBold,
                fontSize: 12,
                color: PdfColors.blue800,
              ),
            ),
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'NOVA AI Study | ${context.pageNumber}',
              style: pw.TextStyle(
                font: arabic,
                fontSize: 9,
                color: PdfColors.grey,
              ),
            ),
          ),
          build: (_) => [
            pw.Center(
              child: pw.Text(
                course,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: arabicBold,
                  fontSize: 23,
                  color: PdfColors.blue900,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'شرح مبسط | عربي + English',
                textDirection: pw.TextDirection.rtl,
                style: bold,
              ),
            ),
            section('الشرح والمفاهيم', field('notes')),
            section('القوانين والقواعد', field('laws')),
            section('الكلمات المفتاحية', field('keywords')),
            if (terms.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Important Terms | المصطلحات',
                style: pw.TextStyle(
                  font: arabicBold,
                  fontSize: 17,
                  color: PdfColors.red800,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['English', 'العربي', 'Explanation'],
                data: terms
                    .map((r) => [
                          r[0],
                          r[1],
                          r.length > 2 ? r.sublist(2).join(' | ') : '',
                        ])
                    .toList(),
                headerStyle: bold,
                cellStyle: regular,
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blue100,
                ),
                cellPadding: const pw.EdgeInsets.all(6),
              ),
            ],
            if (questions.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Practice Questions | أسئلة التدريب',
                style: pw.TextStyle(
                  font: arabicBold,
                  fontSize: 17,
                  color: PdfColors.red800,
                ),
              ),
              ...questions.asMap().entries.map((entry) {
                final q = entry.value;
                final answer = int.tryParse(q[5]) ?? 1;
                final index = answer.clamp(1, 4);

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Q${entry.key + 1}. ${q[0]}',
                      style: pw.TextStyle(
                        font: arabicBold,
                        fontSize: 13,
                        color: PdfColors.red800,
                      ),
                    ),
                    for (int i = 1; i <= 4; i++)
                      pw.Text(
                        '${String.fromCharCode(64 + i)}. ${q[i]}',
                        style: regular,
                      ),
                    pw.Text(
                      'Answer: ${String.fromCharCode(64 + index)}. ${q[index]}',
                      style: bold,
                    ),
                    pw.Text(
                      'الشرح: ${q.sublist(6).join(' | ')}',
                      textDirection: pw.TextDirection.rtl,
                      style: regular,
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await document.save(),
        filename: 'nova_study_${subject + 1}.pdf',
      );

      message('تم تجهيز وتصدير ملف الـ PDF بنجاح');
    } catch (e) {
      message('فشل تصدير PDF: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget panel(Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(.06),
        ),
      ),
      child: child,
    );
  }

  Widget action(
    String title,
    IconData icon,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return panel(
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: aqua, size: 30),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget subjectPicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: DropdownButtonFormField<int>(
        value: subject,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'اختر المادة الدراسية',
          prefixIcon: Icon(Icons.school, color: aqua),
        ),
        items: List.generate(
          courses.length,
          (i) => DropdownMenuItem(
            value: i,
            child: Text(
              courses[i],
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        onChanged: (v) {
          if (v != null) setState(() => subject = v);
        },
      ),
    );
  }

  Widget homePage() {
    return Column(
      children: [
        panel(
          const Column(
            children: [
              Icon(Icons.auto_awesome, color: aqua, size: 48),
              SizedBox(height: 12),
              Text(
                'NOVA AI STUDY',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'مساعد المذاكرة الجامعية',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 5),
              Text(
                'مخصص لجامعة السويس الأهلية',
                style: TextStyle(color: aqua),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          courses.length,
          (i) => action(
            courses[i],
            Icons.menu_book_outlined,
            () => setState(() {
              subject = i;
              tab = 1;
            }),
          ),
        ),
      ],
    );
  }

  Widget studyPage() {
    return Column(
      children: [
        subjectPicker(),
        action(
          'رفع وقراءة ملف PDF للمحاضرة',
          Icons.picture_as_pdf,
          importPdf,
          subtitle: field('filename').isEmpty
              ? 'اختر محاضرة من ملفات هاتفك'
              : 'آخر ملف: ${field('filename')}',
        ),
        action(
          'عرض النصوص المستخرجة',
          Icons.article_outlined,
          () => editField('source', 'نص المحاضرات المستخرج'),
        ),
        action(
          'إضافة الشرح بالعربي والإنجليزي',
          Icons.edit_note,
          () => editField(
            'notes',
            'شرح المحاضرات',
            hint: 'اكتب عنوان الموضوع وشرحه الوافي والأمثلة...',
          ),
        ),
        action(
          'القوانين والقواعد المهمة',
          Icons.calculate,
          () => editField('laws', 'القوانين والقواعد'),
        ),
        action(
          'الكلمات والعبارات المفتاحية',
          Icons.key,
          () => editField('keywords', 'الكلمات المفتاحية'),
        ),
        action(
          'جدول المصطلحات (Glossary)',
          Icons.table_chart,
          () => editField(
            'terms',
            'المصطلحات',
            hint:
                'Assets | الأصول | موارد اقتصادية تملكها المنشأة\nLiabilities | الالتزامات | ديون والتزامات',
          ),
          subtitle: 'كل مصطلح في سطر وافصل بين الأعمدة بـ |',
        ),
        action(
          'إضافة أسئلة الامتحانات (Quiz)',
          Icons.quiz_outlined,
          () => editField(
            'questions',
            'بنك الأسئلة',
            hint:
                'What is an asset?|Cash|Loan|Expense|Loss|1|النقدية أصل لأنها مورد اقتصادي',
          ),
          subtitle: 'السؤال | 4 اختيارات | رقم الإجابة الصحيحة | الشرح',
        ),
        action(
          'تصدير مذكرة PDF ملونة ومنسقة',
          Icons.file_download_outlined,
          exportPdf,
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget termsPage() {
    final rows = parseRows('terms', 2);

    return Column(
      children: [
        subjectPicker(),
        action(
          'تعديل المصطلحات مباشرة',
          Icons.edit,
          () => editField('terms', 'جدول المصطلحات', hint: 'English | العربي | الشرح'),
        ),
        if (rows.isEmpty)
          panel(
            const Text(
              'لا توجد مصطلحات مضافة لهذه المادة بعد.',
              textAlign: TextAlign.center,
            ),
          ),
        ...rows.map(
          (row) => panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  row[0],
                  style: const TextStyle(
                    color: aqua,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  row[1],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                if (row.length > 2) ...[
                  const SizedBox(height: 7),
                  Text(row.sublist(2).join(' | ')),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget examPage() {
    final rows = parseRows('questions', 7);

    return Column(
      children: [
        subjectPicker(),
        panel(
          Column(
            children: [
              const Icon(
                Icons.fact_check,
                color: aqua,
                size: 54,
              ),
              const SizedBox(height: 12),
              const Text(
                'اختبار الميدتيرم والفاينل',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text('عدد الأسئلة المتاحة: ${rows.length}'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: rows.isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExamScreen(
                                questions: rows,
                                subject: course,
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ابدأ الامتحان الآن'),
                ),
              ),
            ],
          ),
        ),
        if (rows.isEmpty)
          const Text(
            'أضف أسئلة من صفحة المذاكرة أولاً.',
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homePage(),
      studyPage(),
      examPage(),
      termsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'NOVA AI Study',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.auto_awesome, color: aqua),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.05, .04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(tab),
                child: pages[tab],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: cardColor,
        selectedIndex: tab,
        indicatorColor: violet.withOpacity(.35),
        onDestinationSelected: (v) {
          setState(() => tab = v);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book),
            label: 'المذاكرة',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz),
            label: 'امتحانات',
          ),
          NavigationDestination(
            icon: Icon(Icons.translate),
            label: 'مصطلحات',
          ),
        ],
      ),
    );
  }
}

class ExamScreen extends StatefulWidget {
  final List<List<String>> questions;
  final String subject;

  const ExamScreen({
    super.key,
    required this.questions,
    required this.subject,
  });

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late List<List<String>> questions;
  final Map<int, int> answers = {};
  bool finished = false;

  @override
  void initState() {
    super.initState();
    questions = List<List<String>>.from(widget.questions)..shuffle();
  }

  int get score {
    int total = 0;
    for (int i = 0; i < questions.length; i++) {
      final correct = int.tryParse(questions[i][5]) ?? 0;
      if (answers[i] == correct) total++;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (finished)
            Container(
              padding: const EdgeInsets.all(22),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  const Icon(Icons.emoji_events, color: aqua, size: 50),
                  const SizedBox(height: 12),
                  Text(
                    'نتيجتك: $score / ${questions.length}',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(score / questions.length * 100).round()}%',
                    style: const TextStyle(fontSize: 22, color: aqua),
                  ),
                ],
              ),
            ),
          ...questions.asMap().entries.map((entry) {
            final index = entry.key;
            final q = entry.value;
            final correct = int.tryParse(q[5]) ?? 1;

            return Card(
              color: cardColor,
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Q${index + 1}. ${q[0]}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: aqua,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(4, (i) {
                      final value = i + 1;
                      return RadioListTile<int>(
                        dense: true,
                        title: Text(
                          '${String.fromCharCode(65 + i)}. ${q[value]}',
                        ),
                        value: value,
                        groupValue: answers[index],
                        onChanged: finished
                            ? null
                            : (v) {
                                setState(() {
                                  if (v != null) answers[index] = v;
                                });
                              },
                      );
                    }),
                    if (finished) ...[
                      const Divider(),
                      Text(
                        'الإجابة الصحيحة: ${String.fromCharCode(64 + correct.clamp(1, 4))}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'الشرح: ${q.sublist(6).join(' | ')}',
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          FilledButton.icon(
            onPressed: finished
                ? () {
                    setState(() {
                      answers.clear();
                      questions.shuffle();
                      finished = false;
                    });
                  }
                : () {
                    if (answers.length != questions.length) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('يرجى الإجابة على جميع الأسئلة أولاً'),
                        ),
                      );
                      return;
                    }
                    setState(() => finished = true);
                  },
            icon: Icon(finished ? Icons.refresh : Icons.check_circle),
            label: Text(finished ? 'إعادة الامتحان' : 'تصحيح الامتحان'),
          ),
          const SizedBox(height: 25),
        ],
      ),
    );
  }
}