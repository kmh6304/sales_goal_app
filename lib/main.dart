import 'dart:async';
import 'dart:convert';

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
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
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
    final sign = carry > 0 ? '+' : '-';

    return '($status $sign${money(carry)})';
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

      final savedSelectedDates =
          await prefs.getStringList(
        selectedSalesDatesKey,
      );

      if (savedSelectedDates != null) {
        selectedSalesDates
          ..clear()
          ..addAll(savedSelectedDates);
      }
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
                                suffixStyle: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
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
                        child:
                            GridView.builder(
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

    // 선택 날짜 합계
    final selectedTotal =
        calculateSelectedDatesTotal();

    return Scaffold(
      backgroundColor: const Color(0xFF6B6B6B),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            final windowWidth = isWide
                ? constraints.maxWidth * 0.82
                : constraints.maxWidth * 0.92;
            final windowHeight = constraints.maxHeight * 0.92;

            return Center(
              child: SizedBox(
                width: windowWidth,
                height: windowHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7E7E7),
                    border: Border.all(
                      color: const Color(0xFF303030),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 14,
                        offset: Offset(5, 6),
                      ),
                    ],
                  ),
                  child: ClipRect(
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      children: [
                        // 레트로 윈도우 제목 표시줄
                      Container(
                        height: 48,
                        padding: const EdgeInsets.only(left: 12, right: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1238A8),
                          border: Border(
                            bottom: BorderSide(
                              color: Color(0xFF0B2370),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '매출관리',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: changeGoal,
                              tooltip: '목표 설정',
                              icon: const Icon(
                                Icons.settings,
                                color: Colors.white,
                                size: 19,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 34,
                              ),
                            ),
                            _windowButton(Icons.remove),
                            _windowButton(Icons.crop_square),
                            _windowButton(Icons.close),
                          ],
                        ),
                      ),

                      // 실제 앱 내용
                      Expanded(
                        child: ClipRect(
                          child: GestureDetector(
                            // 화면 다른 곳을 터치하면 숫자 키보드 닫기
                            onTap: dismissKeyboard,
                            behavior: HitTestBehavior.translucent,
                            child: ScrollConfiguration(
                              behavior: const ScrollBehavior().copyWith(
                                overscroll: false,
                                scrollbars: true,
                              ),
                              child: SingleChildScrollView(
                                clipBehavior: Clip.hardEdge,
                                physics: const ClampingScrollPhysics(),
                                padding: const EdgeInsets.all(16),
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
                          color:
                              Colors.blue.shade50,
                          borderRadius:
                              BorderRadius.circular(
                            16,
                          ),
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
                          fontWeight: FontWeight.bold,
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
                                suffixStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                border: const OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
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
                                backgroundColor: const Color(0xFF1238A8),
                                foregroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              child: const Text(
                                '저장',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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

                      if (selectedSalesDates
                          .isNotEmpty) ...[
                        Text(
                          selectedDatesText,
                          textAlign:
                              TextAlign.center,
                          style:
                              const TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          money(selectedTotal),
                          textAlign:
                              TextAlign.center,
                          style:
                              const TextStyle(
                            fontSize: 28,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ] else
                        const Text(
                          '아직 선택한 날짜가 없어.',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),

                      const SizedBox(height: 14),

                      FilledButton.icon(
                        onPressed: selectSalesDates,
                        icon: const Icon(
                          Icons.date_range,
                          color: Colors.white,
                        ),
                        label: const Text(
                          '날짜 선택',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
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

                      const SizedBox(height: 12),

                      Text(
                        money(calculateAllTotal()),
                        textAlign:
                            TextAlign.center,
                        style:
                            const TextStyle(
                          fontSize: 28,
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
                            ),
                          ),
                        ),
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
    );
  }

  Widget _windowButton(IconData icon) {
    final isMinimize = icon == Icons.remove;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: SizedBox(
        width: 40,
        height: 34,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFD8D8D8),
            border: Border.all(
              color: const Color(0xFF303030),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF7A7A7A),
                offset: Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: null,
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, isMinimize ? 4 : 0),
                  child: Icon(
                    icon,
                    color: Colors.black,
                    size: 26,
                    weight: 900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // 카드
  // =====================================================

  Widget _card({
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFD0D0D0),
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