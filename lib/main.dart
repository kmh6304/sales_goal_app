import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SalesGoalApp());
}

class SalesGoalApp extends StatelessWidget {
  const SalesGoalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '매출관리',
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale('ko', 'KR'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        scaffoldBackgroundColor: const Color(0xFFE7E7E7),
      ),
      home: const SalesGoalHomePage(),
    );
  }
}

class SalesGoalHomePage extends StatefulWidget {
  const SalesGoalHomePage({super.key});

  @override
  State<SalesGoalHomePage> createState() =>
      _SalesGoalHomePageState();
}

class _SalesGoalHomePageState
    extends State<SalesGoalHomePage>
    with WidgetsBindingObserver {
  // =====================================================
  // 매출 입력 시작일
  // =====================================================

  static final DateTime firstInputDate =
      DateTime(2026, 9, 1);

  // =====================================================
  // 저장소
  // =====================================================

  final SharedPreferencesAsync prefs =
      SharedPreferencesAsync();

  static const String baseGoalKey = 'base_goal';
  static const String dailySalesKey = 'daily_sales';
  static const String selectedDateKey = 'selected_date';
  static const String selectedSalesDatesKey =
      'selected_sales_dates';
  static const String goalHistoryKey = 'goal_history';

  // =====================================================
  // 기본 목표금액
  // =====================================================

  int baseGoal = 800000;

  // =====================================================
  // 날짜별 목표 변경 기록
  // =====================================================

  final Map<String, int> goalHistory = {};

  // =====================================================
  // 현재 선택된 날짜
  // =====================================================

  DateTime selectedDate = DateTime.now();

  // 전체 매출 합산에서 선택한 월
  DateTime summaryMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  // =====================================================
  // 로딩 상태
  // =====================================================

  bool isLoading = true;

  // =====================================================
  // 자정 날짜 확인용 타이머
  // =====================================================

  Timer? dateCheckTimer;

  // =====================================================
  // 매출 입력
  // =====================================================

  final TextEditingController salesController =
      TextEditingController();

  // =====================================================
  // 날짜별 매출
  // =====================================================

  final Map<String, int> dailySales = {};

  // =====================================================
  // 합산을 위해 선택한 날짜들
  // =====================================================

  final Set<String> selectedSalesDates = {};

  // =====================================================
  // 날짜 KEY
  // =====================================================

  String dateKey(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // =====================================================
  // 현재 날짜 매출
  // =====================================================

  int get currentSales {
    return dailySales[dateKey(selectedDate)] ?? 0;
  }

  // =====================================================
  // 키보드 닫기
  // =====================================================

  void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // =====================================================
  // 일반 금액 표시
  // =====================================================

  String money(int value) {
    return '${value.abs().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        )}원';
  }

  // =====================================================
  // 달력용 작은 금액
  // =====================================================

  String shortMoney(int value) {
    final amount = value.abs();

    if (amount >= 100000000) {
      final eok = amount / 100000000;

      if (amount % 100000000 == 0) {
        return '${eok.toInt()}억';
      }

      return '${eok.toStringAsFixed(1)}억';
    }

    if (amount >= 10000) {
      final man = amount / 10000;

      if (amount % 10000 == 0) {
        return '${man.toInt()}만';
      }

      return '${man.toStringAsFixed(1)}만';
    }

    if (amount == 0) {
      return '';
    }

    return '$amount원';
  }

  // =====================================================
  // 이월 표시
  // =====================================================

  String carryText(int carry) {
    if (carry == 0) {
      return '';
    }

    final status = carry > 0 ? '초과' : '미달';

    return '($status ${money(carry)})';
  }

  // =====================================================
  // 현재 날짜 표시
  // =====================================================

  String get dateText {
    return '${selectedDate.month}월 '
        '${selectedDate.day}일';
  }

  String formatDate(DateTime date) {
    return '${date.month}월 ${date.day}일';
  }

  // =====================================================
  // 매출 입력창 갱신
  // =====================================================

  void loadSelectedDate() {
    salesController.text = currentSales == 0
        ? ''
        : (currentSales ~/ 10000).toString();
  }

  // =====================================================
  // 특정 날짜의 기본 목표
  // =====================================================

  int getBaseGoalForDate(DateTime date) {
    final targetKey = dateKey(date);

    int result = baseGoal;
    String? latestKey;

    for (final key in goalHistory.keys) {
      if (key.compareTo(targetKey) <= 0) {
        if (latestKey == null ||
            key.compareTo(latestKey) > 0) {
          latestKey = key;
        }
      }
    }

    if (latestKey != null) {
      result = goalHistory[latestKey] ?? baseGoal;
    }

    return result;
  }

  // =====================================================
  // 전날까지 이월 계산
  //
  // + = 초과
  // - = 미달
  //
  // 실제 목표 = 기본 목표 - 이월
  // =====================================================

  int calculateCarryBefore(
    DateTime targetDate,
  ) {
    int carry = 0;

    DateTime current = DateTime(
      firstInputDate.year,
      firstInputDate.month,
      firstInputDate.day,
    );

    final selectedDay = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );

    while (current.isBefore(selectedDay)) {
      final key = dateKey(current);

      if (dailySales.containsKey(key)) {
        final sales = dailySales[key] ?? 0;

        final dayBaseGoal =
            getBaseGoalForDate(current);

        final effectiveTarget =
            dayBaseGoal - carry;

        carry = sales - effectiveTarget;
      }

      current = current.add(
        const Duration(days: 1),
      );
    }

    return carry;
  }

  // =====================================================
  // 특정 날짜의 실제 달성 목표
  // =====================================================

  int getEffectiveTargetForDate(
    DateTime date,
  ) {
    final base = getBaseGoalForDate(date);

    final carry = calculateCarryBefore(date);

    return base - carry;
  }

  // =====================================================
  // 현재 날짜의 기본 목표
  // =====================================================

  int get currentBaseGoal {
    return getBaseGoalForDate(selectedDate);
  }

  // =====================================================
  // 현재 날짜의 실제 달성 목표
  // =====================================================

  int get todayEffectiveTarget {
    return getEffectiveTargetForDate(selectedDate);
  }

  // =====================================================
  // 선택 날짜 매출 합계
  // =====================================================

  int calculateSelectedDatesTotal() {
    int total = 0;

    for (final key in selectedSalesDates) {
      total += dailySales[key] ?? 0;
    }

    return total;
  }

  // =====================================================
  // 선택 날짜 표시
  // =====================================================

  String get selectedDatesText {
    if (selectedSalesDates.isEmpty) {
      return '';
    }

    final dates = selectedSalesDates
        .map((key) {
          final parts = key.split('-');

          return DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        })
        .toList();

    dates.sort();

    return dates.map((date) {
      return '${date.month}월 ${date.day}일';
    }).join(', ');
  }

  // =====================================================
  // 저장된 데이터 불러오기
  // =====================================================

  Future<void> loadData() async {
    try {
      final savedGoal =
          await prefs.getInt(baseGoalKey);

      if (savedGoal != null && savedGoal >= 0) {
        baseGoal = savedGoal;
      }

      final savedSales =
          await prefs.getString(dailySalesKey);

      if (savedSales != null &&
          savedSales.isNotEmpty) {
        final decoded = jsonDecode(savedSales);

        if (decoded is Map) {
          dailySales.clear();

          decoded.forEach(
            (key, value) {
              if (value is num) {
                dailySales[key.toString()] =
                    value.toInt();
              }
            },
          );
        }
      }

      final savedGoalHistory =
          await prefs.getString(goalHistoryKey);

      if (savedGoalHistory != null &&
          savedGoalHistory.isNotEmpty) {
        final decoded =
            jsonDecode(savedGoalHistory);

        if (decoded is Map) {
          goalHistory.clear();

          decoded.forEach(
            (key, value) {
              if (value is num) {
                goalHistory[key.toString()] =
                    value.toInt();
              }
            },
          );
        }
      }

      final savedDate =
          await prefs.getString(selectedDateKey);

      if (savedDate != null &&
          savedDate.isNotEmpty) {
        final parsedDate =
            DateTime.tryParse(savedDate);

        if (parsedDate != null) {
          selectedDate = parsedDate;
        }
      }

      if (selectedDate.isBefore(firstInputDate)) {
        selectedDate = firstInputDate;
      }

      // 날짜 선택은 화면에서 임시로 사용하는 상태다.
      // 이전 실행에서 저장된 날짜가 오늘 표시를 덮어쓰지 않도록
      // 앱을 열 때 선택 목록을 비운다. 매출 데이터는 변경하지 않는다.
      selectedSalesDates.clear();
      await prefs.remove(selectedSalesDatesKey);
    } catch (e) {
      // 저장 데이터 오류가 있어도
      // 기본값으로 계속 실행
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isLoading = false;
      loadSelectedDate();
    });

    checkDateChange();
    startDateWatcher();
  }

  // =====================================================
  // 자정 날짜 감시 시작
  // =====================================================

  void startDateWatcher() {
    dateCheckTimer?.cancel();

    dateCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        checkDateChange();
      },
    );
  }

  // =====================================================
  // 날짜가 바뀌었는지 확인
  // =====================================================

  void checkDateChange() {
    if (!mounted || isLoading) {
      return;
    }

    final now = DateTime.now();

    if (now.isBefore(firstInputDate)) {
      return;
    }

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    if (dateKey(today) !=
        dateKey(selectedDate)) {
      dismissKeyboard();

      setState(() {
        selectedDate = today;
        loadSelectedDate();
      });

      saveSelectedDate();
    }
  }

  // =====================================================
  // 앱이 다시 활성화되었을 때
  // =====================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      checkDateChange();
    }
  }

  // =====================================================
  // 날짜별 매출 저장
  // =====================================================

  Future<void> saveDailySales() async {
    final encoded = jsonEncode(dailySales);

    await prefs.setString(
      dailySalesKey,
      encoded,
    );
  }

  // JSON 백업 및 복원

  Future<void> exportBackup() async {
    try {
      final backupData = <String, dynamic>{
        'app': 'sales_goal_app',
        'backupVersion': 1,
        'backupDate': DateTime.now().toIso8601String(),
        'baseGoal': baseGoal,
        'dailySales': dailySales,
        'goalHistory': goalHistory,
      };

      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final fileName = '매출관리_백업_$stamp.json';
      final backupJson = const JsonEncoder.withIndent('  ').convert(backupData);

      if (Platform.isWindows) {
        // Windows: 사용자가 저장 위치(예: 바탕화면)를 직접 선택하도록 한다.
        final savedPath = await FilePicker.platform.saveFile(
          dialogTitle: '매출관리 백업 파일 저장',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(backupJson)),
        );
        if (savedPath == null) return;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('백업 파일을 저장했어: $savedPath')),
        );
      } else {
        // iPhone: 공유 메뉴에서 '파일에 저장'을 선택하면 iCloud Drive에 저장할 수 있다.
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsString(backupJson, flush: true);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            text: '매출관리 백업 파일이야. “파일에 저장”을 선택한 뒤 iCloud Drive에 저장해 줘.',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('백업 파일을 저장하지 못했어: $e')),
      );
    }
  }

  Future<void> importBackup() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) return;

      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('선택한 파일을 읽을 수 없어.');
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('백업 파일 형식이 올바르지 않아.');
      }

      if (decoded['app'] != 'sales_goal_app' ||
          decoded['backupVersion'] != 1 ||
          decoded['baseGoal'] is! num ||
          decoded['dailySales'] is! Map ||
          decoded['goalHistory'] is! Map) {
        throw const FormatException('매출관리 백업 파일이 아니거나 형식이 달라.');
      }

      final restoredBaseGoal = (decoded['baseGoal'] as num).toInt();
      final rawSales = decoded['dailySales'] as Map;
      final rawGoalHistory = decoded['goalHistory'] as Map;
      final restoredSales = <String, int>{};
      final restoredGoalHistory = <String, int>{};

      if (restoredBaseGoal < 0) {
        throw const FormatException('목표 금액이 올바르지 않아.');
      }

      for (final entry in rawSales.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (DateTime.tryParse(key) == null ||
            value is! num ||
            value < 0) {
          throw const FormatException('날짜별 매출 데이터가 올바르지 않아.');
        }
        restoredSales[key] = value.toInt();
      }

      for (final entry in rawGoalHistory.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (DateTime.tryParse(key) == null ||
            value is! num ||
            value < 0) {
          throw const FormatException('목표 변경 기록이 올바르지 않아.');
        }
        restoredGoalHistory[key] = value.toInt();
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('백업 데이터 복원'),
          content: Text(
            '백업 파일에 저장된 날짜별 매출 ${restoredSales.length}건과 '
            '목표 변경 기록 ${restoredGoalHistory.length}건을 복원할 거야.\n\n'
            '현재 앱의 매출과 목표 기록은 백업 파일의 내용으로 교체돼. '
            '복원 전에 현재 데이터도 백업했는지 확인해 줘.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('복원하기'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      await prefs.setInt(baseGoalKey, restoredBaseGoal);
      await prefs.setString(dailySalesKey, jsonEncode(restoredSales));
      await prefs.setString(goalHistoryKey, jsonEncode(restoredGoalHistory));

      if (!mounted) return;
      setState(() {
        baseGoal = restoredBaseGoal;
        dailySales
          ..clear()
          ..addAll(restoredSales);
        goalHistory
          ..clear()
          ..addAll(restoredGoalHistory);
        loadSelectedDate();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('매출 데이터 복원이 완료됐어.')),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('복원할 수 없는 파일이야: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('복원 중 문제가 발생했어: $e')),
      );
    }
  }

  // =====================================================
  // 목표 변경 기록 저장
  // =====================================================

  Future<void> saveGoalHistory() async {
    final encoded = jsonEncode(goalHistory);

    await prefs.setString(
      goalHistoryKey,
      encoded,
    );
  }

  // =====================================================
  // 현재 선택 날짜 저장
  // =====================================================

  Future<void> saveSelectedDate() async {
    await prefs.setString(
      selectedDateKey,
      selectedDate.toIso8601String(),
    );
  }

  // =====================================================
  // 선택 날짜 목록 저장
  // =====================================================

  Future<void> saveSelectedSalesDates() async {
    await prefs.setStringList(
      selectedSalesDatesKey,
      selectedSalesDates.toList(),
    );
  }

  // =====================================================
  // 일반 날짜 선택
  // =====================================================

  Future<void> selectDate() async {
    // 날짜 선택 전에 매출 입력창 포커스 제거
    dismissKeyboard();

    DateTime displayedMonth = DateTime(
      selectedDate.year,
      selectedDate.month,
      1,
    );

    if (displayedMonth.isBefore(
      DateTime(firstInputDate.year, firstInputDate.month, 1),
    )) {
      displayedMonth = DateTime(
        firstInputDate.year,
        firstInputDate.month,
        1,
      );
    }

    DateTime? result;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final firstDayOfMonth = DateTime(
              displayedMonth.year,
              displayedMonth.month,
              1,
            );

            final lastDayOfMonth = DateTime(
              displayedMonth.year,
              displayedMonth.month + 1,
              0,
            );

            final firstWeekday = firstDayOfMonth.weekday % 7;
            final totalCells =
                firstWeekday + lastDayOfMonth.day;
            final rowCount = (totalCells / 7).ceil();

            final canGoPrevious = displayedMonth.isAfter(
              DateTime(
                firstInputDate.year,
                firstInputDate.month,
                1,
              ),
            );

            return Dialog(
              backgroundColor: const Color(0xFFE6E7ED),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(36),
              ),
              child: SizedBox(
                width: 380,
                height: 510,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    14,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '날짜 선택',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${selectedDate.month}월 ${selectedDate.day}일',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: canGoPrevious
                                ? () {
                                    setDialogState(() {
                                      displayedMonth = DateTime(
                                        displayedMonth.year,
                                        displayedMonth.month - 1,
                                        1,
                                      );
                                    });
                                  }
                                : null,
                            icon: const Icon(
                              Icons.chevron_left,
                              size: 32,
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: Center(
                              child: Text(
                                '${displayedMonth.year}년 '
                                '${displayedMonth.month}월',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setDialogState(() {
                                displayedMonth = DateTime(
                                  displayedMonth.year,
                                  displayedMonth.month + 1,
                                  1,
                                );
                              });
                            },
                            icon: const Icon(
                              Icons.chevron_right,
                              size: 32,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Row(
                        children: const [
                          _WeekdayText('일'),
                          _WeekdayText('월'),
                          _WeekdayText('화'),
                          _WeekdayText('수'),
                          _WeekdayText('목'),
                          _WeekdayText('금'),
                          _WeekdayText('토'),
                        ],
                      ),

                      const SizedBox(height: 4),

                      Expanded(
                        child: GridView.builder(
                          physics:
                              const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            childAspectRatio: 0.90,
                          ),
                          itemCount: rowCount * 7,
                          itemBuilder: (context, index) {
                            final day =
                                index - firstWeekday + 1;

                            if (day < 1 ||
                                day > lastDayOfMonth.day) {
                              return const SizedBox();
                            }

                            final date = DateTime(
                              displayedMonth.year,
                              displayedMonth.month,
                              day,
                            );

                            if (date.isBefore(firstInputDate)) {
                              return const SizedBox();
                            }

                            final isSelected =
                                dateKey(date) ==
                                dateKey(selectedDate);

                            final dayColor = isSelected
                                ? Colors.white
                                : date.weekday ==
                                        DateTime.sunday
                                    ? Colors.red.shade600
                                    : date.weekday ==
                                            DateTime.saturday
                                        ? Colors.blue.shade600
                                        : Colors.black87;

                            return Padding(
                              padding:
                                  const EdgeInsets.all(2),
                              child: Material(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.transparent,
                                shape:
                                    const CircleBorder(),
                                child: InkWell(
                                  customBorder:
                                      const CircleBorder(),
                                  onTap: () {
                                    result = date;
                                    Navigator.of(
                                      dialogContext,
                                    ).pop();
                                  },
                                  child: Center(
                                    child: Text(
                                      '$day',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight:
                                            FontWeight.bold,
                                        color: dayColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    dismissKeyboard();

    if (result != null) {
      setState(() {
        selectedDate = result!;
        loadSelectedDate();
      });

      await saveSelectedDate();
    }
  }

  // =====================================================
  // 매출 저장
  // =====================================================

  Future<void> saveSales() async {
    dismissKeyboard();

    final input = int.tryParse(
          salesController.text
              .replaceAll(',', '')
              .trim(),
        ) ??
        0;

    final value = input * 10000;

    if (value < 0) {
      return;
    }

    setState(() {
      dailySales[dateKey(selectedDate)] =
          value;
    });

    await saveDailySales();
  }

  // =====================================================
  // 목표금액 설정
  // =====================================================

  void changeGoal() {
    dismissKeyboard();

    final currentGoal =
        getBaseGoalForDate(selectedDate);

    final controller =
        TextEditingController(
      text: (currentGoal ~/ 10000).toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            '${formatDate(selectedDate)}부터 '
            '기본 목표금액 설정',
          ),
          content: TextField(
            controller: controller,
            keyboardType:
                TextInputType.number,
            autofocus: true,
            decoration:
                const InputDecoration(
              hintText: '예: 80',
              suffixText: '만원',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                dismissKeyboard();

                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                final input = int.tryParse(
                  controller.text
                      .replaceAll(',', '')
                      .trim(),
                );

                final value =
                    input == null ? null : input * 10000;

                if (value != null &&
                    value >= 0) {
                  setState(() {
                    goalHistory[
                        dateKey(
                      selectedDate,
                    )] = value;
                  });

                  await saveGoalHistory();

                  dismissKeyboard();

                  if (dialogContext.mounted) {
                    Navigator.pop(
                      dialogContext,
                    );
                  }
                }
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  // =====================================================
  // 여러 날짜 선택 달력
  // =====================================================

  Future<void> selectSalesDates() async {
    // 날짜 선택 전에 기존 매출 입력창 포커스 제거
    dismissKeyboard();

    final Set<String> tempSelected =
        Set<String>.from(
      selectedSalesDates,
    );

    // 드래그 선택 시 날짜 셀의 화면 위치를 찾기 위한 키
    final Map<String, GlobalKey> calendarCellKeys = {};
    String? dragStartKey;
    bool isDragging = false;
    bool dragSelectMode = true; // true: 선택, false: 선택 해제
    Set<String> dragBaseSelection = {};

    String? dateKeyAtPosition(Offset globalPosition) {
      for (final entry in calendarCellKeys.entries) {
        final cellContext = entry.value.currentContext;
        if (cellContext == null) continue;
        final object = cellContext.findRenderObject();
        if (object is! RenderBox || !object.attached) continue;
        final topLeft = object.localToGlobal(Offset.zero);
        if ((topLeft & object.size).contains(globalPosition)) {
          return entry.key;
        }
      }
      return null;
    }

    void applyDragRange(
      void Function(void Function()) setDialogState,
      String startKey,
      String endKey,
    ) {
      final a = startKey.split('-').map(int.parse).toList();
      final b = endKey.split('-').map(int.parse).toList();
      final start = DateTime(a[0], a[1], a[2]);
      final end = DateTime(b[0], b[1], b[2]);
      if (start.year != end.year || start.month != end.month) return;

      setDialogState(() {
        tempSelected
          ..clear()
          ..addAll(dragBaseSelection);
        final first = start.isBefore(end) ? start : end;
        final last = start.isAfter(end) ? start : end;
        for (DateTime date = first;
            !date.isAfter(last);
            date = date.add(const Duration(days: 1))) {
          if (date.isBefore(firstInputDate)) continue;
          final key = dateKey(date);
          if (dragSelectMode) {
            tempSelected.add(key);
          } else {
            tempSelected.remove(key);
          }
        }
      });
    }

    DateTime displayedMonth = DateTime(
      selectedDate.year,
      selectedDate.month,
      1,
    );

    if (displayedMonth.isBefore(
      DateTime(2026, 9, 1),
    )) {
      displayedMonth =
          DateTime(2026, 9, 1);
    }

    final result =
        await showDialog<Set<String>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            final firstDayOfMonth =
                DateTime(
              displayedMonth.year,
              displayedMonth.month,
              1,
            );

            final lastDayOfMonth =
                DateTime(
              displayedMonth.year,
              displayedMonth.month + 1,
              0,
            );

            final firstWeekday =
                firstDayOfMonth.weekday % 7;

            final totalCells =
                firstWeekday +
                    lastDayOfMonth.day;

            final rowCount =
                (totalCells / 7).ceil();

            final canGoPrevious =
                displayedMonth.isAfter(
              DateTime(2026, 9, 1),
            );

            return Dialog(
              backgroundColor: const Color(0xFFE6E7ED),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(36),
              ),
              child: SizedBox(
                width: 380,
                height: 510,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    14,
                  ),
                  child: Column(
                    children: [
                      // 제목
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '매출 합산 날짜 선택',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${tempSelected.length}일 선택',
                            style: TextStyle(
                              color:
                                  Colors.blue.shade700,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // 월 이동
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed:
                                canGoPrevious
                                    ? () {
                                        setDialogState(
                                          () {
                                            calendarCellKeys.clear();
                                            dragStartKey = null;
                                            isDragging = false;
                                            displayedMonth =
                                                DateTime(
                                              displayedMonth
                                                  .year,
                                              displayedMonth
                                                      .month -
                                                  1,
                                              1,
                                            );
                                          },
                                        );
                                      }
                                    : null,
                            icon: const Icon(
                              Icons.chevron_left,
                              size: 30,
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Center(
                              child: Text(
                                '${displayedMonth.year}년 '
                                '${displayedMonth.month}월',
                                style:
                                    const TextStyle(
                                  fontSize: 20,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setDialogState(
                                () {
                                  calendarCellKeys.clear();
                                  dragStartKey = null;
                                  isDragging = false;
                                  displayedMonth =
                                      DateTime(
                                    displayedMonth.year,
                                    displayedMonth.month +
                                        1,
                                    1,
                                  );
                                },
                              );
                            },
                            icon: const Icon(
                              Icons.chevron_right,
                              size: 30,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // 요일
                      Row(
                        children: const [
                          _WeekdayText('일'),
                          _WeekdayText('월'),
                          _WeekdayText('화'),
                          _WeekdayText('수'),
                          _WeekdayText('목'),
                          _WeekdayText('금'),
                          _WeekdayText('토'),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // 날짜
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            final startKey = dragStartKey ??
                                dateKeyAtPosition(details.globalPosition);
                            if (startKey == null) return;
                            isDragging = true;
                            dragStartKey = startKey;
                            dragSelectMode = !tempSelected.contains(startKey);
                            dragBaseSelection = Set<String>.from(tempSelected);
                            final currentKey =
                                dateKeyAtPosition(details.globalPosition) ?? startKey;
                            applyDragRange(setDialogState, startKey, currentKey);
                          },
                          onPanUpdate: (details) {
                            if (!isDragging || dragStartKey == null) return;
                            final currentKey = dateKeyAtPosition(details.globalPosition);
                            if (currentKey == null) return;
                            applyDragRange(setDialogState, dragStartKey!, currentKey);
                          },
                          onPanEnd: (_) {
                            isDragging = false;
                            dragStartKey = null;
                          },
                          onPanCancel: () {
                            isDragging = false;
                            dragStartKey = null;
                          },
                          child: GridView.builder(
                          padding: EdgeInsets.zero,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            childAspectRatio: 0.82,
                          ),
                          itemCount:
                              rowCount * 7,
                          itemBuilder:
                              (context, index) {
                            final day =
                                index -
                                    firstWeekday +
                                    1;

                            if (day < 1 ||
                                day >
                                    lastDayOfMonth
                                        .day) {
                              return const SizedBox();
                            }

                            final date =
                                DateTime(
                              displayedMonth.year,
                              displayedMonth.month,
                              day,
                            );

                            if (date.isBefore(
                              firstInputDate,
                            )) {
                              return const SizedBox();
                            }

                            final key =
                                dateKey(date);
                            final cellKey = calendarCellKeys.putIfAbsent(
                              key,
                              () => GlobalKey(),
                            );

                            final isSelected =
                                tempSelected
                                    .contains(key);

                            // 이 날짜의 실제 매출
                            final daySales =
                                dailySales[key];

                            // 중요:
                            // 달력의 초록/빨강은
                            // 이월을 반영하지 않고
                            // 해당 날짜의 기본 목표와 비교
                            final dayBaseGoal =
                                getBaseGoalForDate(
                              date,
                            );

                            final bool isAchieved =
                                daySales != null &&
                                    daySales >=
                                        dayBaseGoal;

                            return Padding(
                              key: cellKey,
                              padding:
                                  const EdgeInsets.all(
                                2,
                              ),
                              child: Material(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.transparent,
                                shape:
                                    const CircleBorder(),
                                child: InkWell(
                                  customBorder:
                                      const CircleBorder(),
                                  onTap: () {
                                    // 달력 선택 중에는
                                    // 매출 입력창에 포커스하지 않음
                                    setDialogState(
                                      () {
                                        if (isSelected) {
                                          tempSelected
                                              .remove(
                                            key,
                                          );
                                        } else {
                                          tempSelected
                                              .add(
                                            key,
                                          );
                                        }
                                      },
                                    );
                                    if (!isDragging) {
                                      dragStartKey = null;
                                    }
                                  },
                                  child: Padding(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                      vertical: 2,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment
                                              .center,
                                      children: [
                                        // 날짜
                                        Text(
                                          '$day',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.white
                                                : date.weekday == DateTime.sunday
                                                    ? Colors.red.shade600
                                                    : date.weekday == DateTime.saturday
                                                        ? Colors.blue.shade600
                                                        : Colors.black87,
                                          ),
                                        ),

                                        // 매출
                                        if (daySales !=
                                                null &&
                                            daySales > 0)
                                          const SizedBox(
                                            height: 1,
                                          ),

                                        if (daySales !=
                                                null &&
                                            daySales > 0)
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment
                                                    .center,
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            children: [
                                              // 초록 / 빨강
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration:
                                                    BoxDecoration(
                                                  shape:
                                                      BoxShape
                                                          .circle,
                                                  color:
                                                      isAchieved
                                                          ? Colors
                                                              .green
                                                          : Colors
                                                              .red,
                                                ),
                                              ),

                                              const SizedBox(
                                                width: 2,
                                              ),

                                              // 매출 금액
                                              Flexible(
                                                child:
                                                    FittedBox(
                                                  fit: BoxFit
                                                      .scaleDown,
                                                  child:
                                                      Text(
                                                    shortMoney(
                                                      daySales,
                                                    ),
                                                    style:
                                                        TextStyle(
                                                      fontSize:
                                                          9,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold,
                                                      color:
                                                          isSelected
                                                              ? Colors
                                                                  .white
                                                              : Colors
                                                                  .grey
                                                                  .shade700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 선택한 날짜
                      if (tempSelected.isNotEmpty)
                        SizedBox(
                          height: 38,
                          child:
                              SingleChildScrollView(
                            scrollDirection:
                                Axis.horizontal,
                            child: Center(
                              child: Text(
                                _formatTempSelectedDates(
                                  tempSelected,
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.grey.shade700,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(
                          height: 38,
                          child: Center(
                            child: Text(
                              '날짜를 선택해줘',
                              style: TextStyle(
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 4),

                      // 취소 / 선택 완료
                      Row(
                        children: [
                          Expanded(
                            child:
                                OutlinedButton(
                              onPressed: () {
                                dismissKeyboard();

                                Navigator.of(
                                  dialogContext,
                                ).pop();
                              },
                              child:
                                  const Text(
                                '취소',
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child:
                                FilledButton(
                              onPressed:
                                  tempSelected
                                          .isEmpty
                                      ? null
                                      : () {
                                          dismissKeyboard();

                                          Navigator.of(
                                            dialogContext,
                                          ).pop(
                                            Set<String>.from(
                                              tempSelected,
                                            ),
                                          );
                                        },
                              child:
                                  const Text(
                                '선택 완료',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // 달력 닫힌 뒤에도 포커스 제거
    dismissKeyboard();

    if (result != null) {
      setState(() {
        selectedSalesDates
          ..clear()
          ..addAll(result);
      });

      await saveSelectedSalesDates();

      // 선택 날짜 합산만 변경하고
      // 현재 날짜나 매출 입력창에는 손대지 않음
      dismissKeyboard();
    }
  }

  // =====================================================
  // 선택 날짜 표시
  // =====================================================

  String _formatTempSelectedDates(
    Set<String> dates,
  ) {
    final sorted = dates
        .map((key) {
          final parts = key.split('-');

          return DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        })
        .toList()
      ..sort();

    return sorted.map((date) {
      return '${date.month}월 '
          '${date.day}일';
    }).join(', ');
  }

  // =====================================================
  // 전체 매출 합산
  // =====================================================

  int calculateAllTotal() {
    int total = 0;

    for (final value in dailySales.values) {
      total += value;
    }

    return total;
  }

  // 선택한 월의 매출만 합산한다. 날짜별 원본 데이터는 그대로 유지한다.
  int calculateMonthTotal(DateTime month) {
    final prefix = '${month.year}-'
        '${month.month.toString().padLeft(2, '0')}-';
    int total = 0;
    for (final entry in dailySales.entries) {
      if (entry.key.startsWith(prefix)) total += entry.value;
    }
    return total;
  }

  List<DateTime> get summaryMonthOptions {
    DateTime latestMonth = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      1,
    );
    for (final key in dailySales.keys) {
      final parsed = DateTime.tryParse(key);
      if (parsed == null) continue;
      final month = DateTime(parsed.year, parsed.month, 1);
      if (month.isAfter(latestMonth)) latestMonth = month;
    }

    final options = <DateTime>[];
    DateTime month = DateTime(firstInputDate.year, firstInputDate.month, 1);
    while (!month.isAfter(latestMonth)) {
      options.add(month);
      month = DateTime(month.year, month.month + 1, 1);
    }
    if (options.isEmpty) options.add(latestMonth);
    return options;
  }

  // =====================================================
  // 시작
  // =====================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    if (selectedDate.isBefore(firstInputDate)) {
      selectedDate = firstInputDate;
    }

    loadData();
  }

  // =====================================================
  // 종료
  // =====================================================

  @override
  void dispose() {
    dateCheckTimer?.cancel();

    WidgetsBinding.instance
        .removeObserver(this);

    salesController.dispose();

    super.dispose();
  }

  // =====================================================
  // 화면
  // =====================================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final sales = currentSales;

    // 현재 날짜 기본 목표
    final dayBaseGoal = currentBaseGoal;

    // 전날까지 이월
    final carry =
        calculateCarryBefore(selectedDate);

    // 오늘 실제 달성 목표
    final target =
        dayBaseGoal - carry;

    // 오늘 결과
    final difference =
        sales - target;

    // 선택 날짜 합계. 아무 날짜도 선택하지 않았으면 오늘 매출을 표시한다.
    final selectedTotal =
        calculateSelectedDatesTotal();
    final todayDate = DateTime.now();
    final todaySalesTotal =
        dailySales[dateKey(todayDate)] ?? 0;
    final displayedSalesTotal = selectedSalesDates.isNotEmpty
        ? selectedTotal
        : todaySalesTotal;
    final displayedDatesText = selectedSalesDates.isNotEmpty
        ? selectedDatesText
        : '${formatDate(todayDate)} (오늘)';

    return Scaffold(
      backgroundColor: const Color(0xFFE7E7E7),
      appBar: AppBar(
        toolbarHeight: 62,
        titleSpacing: 18,
        title: const Text(
          '매출관리',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF173EAD),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            tooltip: '설정 및 백업',
            onSelected: (value) {
              if (value == 'goal') {
                changeGoal();
              } else if (value == 'backup') {
                exportBackup();
              } else if (value == 'restore') {
                importBackup();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'goal',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 10),
                    Text('목표 설정'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'backup',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 10),
                    Text('데이터 백업'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'restore',
                child: Row(
                  children: [
                    Icon(Icons.upload),
                    SizedBox(width: 10),
                    Text('데이터 복원'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.settings, size: 25),
          ),
          const SizedBox(width: 2),
          _windowButton(Icons.remove, '최소화'),
          _windowButton(Icons.crop_square, '최대화'),
          _windowButton(Icons.close, '닫기'),
          const SizedBox(width: 7),
        ],
      ),

      body: GestureDetector(
        // 화면 다른 곳을 터치하면
        // 숫자 키보드 닫기
        onTap: dismissKeyboard,
        behavior: HitTestBehavior.translucent,

        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                // =====================================================
                // 날짜
                // =====================================================

                const Text(
                  '날짜',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 4),

                InkWell(
                  onTap: selectDate,
                  borderRadius:
                      BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        Text(
                          dateText,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.calendar_month,
                          size: 23,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // =====================================================
                // 기본 목표
                // =====================================================

                _card(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        '기본 목표금액',
                        style: TextStyle(
                          color:
                              Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        money(dayBaseGoal),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // =====================================================
                // 오늘 목표
                // =====================================================

                _card(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '오늘 목표',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        carry == 0
                            ? '오늘 목표: '
                                '${money(dayBaseGoal)}'
                            : '오늘 목표: '
                                '${money(dayBaseGoal)} '
                                '${carryText(carry)}',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 16),

                      Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.all(18),
                        decoration:
                            BoxDecoration(
                          color: const Color(0xFFE2F2FF),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              '오늘 달성 목표',
                              style: TextStyle(
                                color: Colors
                                    .grey.shade600,
                                fontSize: 14,
                              ),
                            ),

                            const SizedBox(height: 5),

                            Text(
                              money(target),
                              style: TextStyle(
                                color: Colors
                                    .blue.shade700,
                                fontSize: 30,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // =====================================================
                // 오늘 매출 입력
                // =====================================================

                _card(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '오늘 매출 입력',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller:
                                  salesController,
                              keyboardType:
                                  TextInputType.number,
                              decoration:
                                  InputDecoration(
                                hintText: '매출 금액',
                                suffixText: '만원',
                                border:
                                    OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                  borderSide: const BorderSide(
                                    color: Color(0xFF80858D),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: saveSales,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF173EAD),
                                foregroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                              ),
                              child: const Text('저장'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // =====================================================
                // 오늘 결과
                // =====================================================

                _card(
                  child: Container(
                    padding:
                        const EdgeInsets.all(18),
                    decoration:
                        BoxDecoration(
                      color: difference > 0
                          ? Colors.green.shade50
                          : difference < 0
                              ? Colors.red.shade50
                              : Colors.grey.shade100,
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        if (sales == 0)
                          const Text(
                            '매출을 입력해봐',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          )
                        else if (difference > 0)
                          Text(
                            '🟢 '
                            '${money(difference)} '
                            '초과',
                            style: TextStyle(
                              color:
                                  Colors.green.shade700,
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          )
                        else if (difference < 0)
                          Text(
                            '🔴 '
                            '${money(-difference)} '
                            '미달',
                            style: TextStyle(
                              color:
                                  Colors.red.shade700,
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          )
                        else
                          Text(
                            '🟢 목표 달성',
                            style: TextStyle(
                              color:
                                  Colors.green.shade700,
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                        if (sales > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            '오늘 매출: '
                            '${money(sales)}',
                            style:
                                const TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // =====================================================
                // 선택 날짜 매출 합산
                // =====================================================

                _card(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '📅 선택 날짜 매출 합산',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        displayedDatesText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        money(displayedSalesTotal),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 14),

                      OutlinedButton.icon(
                        onPressed:
                            selectSalesDates,
                        icon: const Icon(
                          Icons.date_range,
                        ),
                        label: const Text(
                          '날짜 선택',
                        ),
                        style:
                            OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // =====================================================
                // 전체 매출 합산
                // =====================================================

                _card(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '📊 전체 매출 합산',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          const Text(
                            '조회 월',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<DateTime>(
                              isExpanded: true,
                              value: summaryMonthOptions.contains(
                                DateTime(summaryMonth.year, summaryMonth.month, 1),
                              )
                                  ? DateTime(summaryMonth.year, summaryMonth.month, 1)
                                  : summaryMonthOptions.last,
                              items: summaryMonthOptions.map((month) {
                                return DropdownMenuItem<DateTime>(
                                  value: month,
                                  child: Text('${month.year}년 ${month.month}월'),
                                );
                              }).toList(),
                              onChanged: (month) {
                                if (month == null) return;
                                setState(() => summaryMonth = month);
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Text(
                        '${summaryMonth.year}년 ${summaryMonth.month}월 매출',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        money(calculateMonthTotal(summaryMonth)),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // 카드
  // =====================================================

  Widget _windowButton(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Tooltip(
        message: label,
        child: Container(
          width: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE3E3E3),
            border: Border.all(color: const Color(0xFF353535), width: 1.5),
            boxShadow: const [
              BoxShadow(color: Color(0xFF777777), offset: Offset(2, 2), blurRadius: 0),
            ],
          ),
          child: Icon(icon, color: Colors.black, size: 24),
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: const Color(0xFFD0D0D0),
          width: 1.2,
        ),
      ),
      child: child,
    );
  }
}

// =====================================================
// 요일 표시
// =====================================================

class _WeekdayText extends StatelessWidget {
  final String text;

  const _WeekdayText(this.text);

  @override
  Widget build(
    BuildContext context,
  ) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: text == '일'
                ? Colors.red.shade600
                : text == '토'
                    ? Colors.blue.shade600
                    : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}