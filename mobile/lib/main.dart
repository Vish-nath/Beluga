import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';

import 'local_database.dart';
import 'reminder_notifications.dart';

// ════════════════════════════════════════════════════════════
// MAIN ENTRY POINT
// ════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderNotifications.initialize();
  runApp(const BelugaApp());
}

// ════════════════════════════════════════════════════════════
// APP ROOT
// ════════════════════════════════════════════════════════════

class BelugaApp extends StatefulWidget {
  const BelugaApp({super.key});

  @override
  State<BelugaApp> createState() => _BelugaAppState();
}

class _BelugaAppState extends State<BelugaApp> {
  bool _isDarkMode = false;

  void _toggleTheme() => setState(() => _isDarkMode = !_isDarkMode);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beluga Health',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: AppEntry(isDarkMode: _isDarkMode, onToggleTheme: _toggleTheme),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final seed = const Color(0xff176b55);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
        primary: isDark ? const Color(0xff22a07d) : seed,
      ),
      scaffoldBackgroundColor: isDark ? const Color(0xff121412) : const Color(0xfff5f5ef),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xff121412) : const Color(0xfff5f5ef),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xff1c201e) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: isDark ? const Color(0xff2a322e) : const Color(0xffe4e9e2)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xff1c201e) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? const Color(0xff2a322e) : const Color(0xffdfe5df)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? const Color(0xff2a322e) : const Color(0xffdfe5df)),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// APP ENTRY – ONBOARDING vs HOME
// ════════════════════════════════════════════════════════════

class AppEntry extends StatefulWidget {
  const AppEntry({required this.isDarkMode, required this.onToggleTheme, super.key});
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _loading = true;
  bool _needsOnboarding = true;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      final profile = await LocalDatabase.instance.getProfile();
      final complete = LocalDatabase.instance.isProfileComplete(profile);
      if (mounted) setState(() { _needsOnboarding = !complete; _loading = false; });
    } catch (e) {
      if (kDebugMode) print('Profile check error: $e');
      if (mounted) setState(() { _needsOnboarding = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      child: _needsOnboarding
          ? OnboardingScreen(
              key: const ValueKey('onboarding'),
              isDarkMode: widget.isDarkMode,
              onToggleTheme: widget.onToggleTheme,
              onComplete: () => setState(() => _needsOnboarding = false),
            )
          : HealthHome(
              key: const ValueKey('home'),
              isDarkMode: widget.isDarkMode,
              onToggleTheme: widget.onToggleTheme,
              onReset: () => setState(() => _needsOnboarding = true),
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ONBOARDING SCREEN
// ════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.onComplete,
    super.key,
  });
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _breakfastTime = TextEditingController(text: '08:00');
  final _lunchTime = TextEditingController(text: '13:00');
  final _dinnerTime = TextEditingController(text: '20:00');
  bool _busy = false;
  int _step = 0;

  Future<void> _finish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final db = LocalDatabase.instance;

      // Save profile
      await db.saveProfile({
        'name': _name.text.trim(),
        'age': int.tryParse(_age.text.trim()),
      });

      // Add default meal schedules
      final meals = [
        {'meal_name': 'Breakfast', 'scheduled_time': _breakfastTime.text.trim()},
        {'meal_name': 'Lunch', 'scheduled_time': _lunchTime.text.trim()},
        {'meal_name': 'Dinner', 'scheduled_time': _dinnerTime.text.trim()},
      ];
      for (final meal in meals) {
        await db.addMealSchedule(meal);
      }

      // Request notification permission and schedule
      await ReminderNotifications.requestPermission();
      await _syncNotifications();

      widget.onComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AnimatedBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: FrostedGlassCard(
                  child: Form(
                    key: _formKey,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _AnimatedThemeSwitch(isDarkMode: widget.isDarkMode, onToggle: widget.onToggleTheme),
                              const Icon(Icons.monitor_heart_outlined, size: 42, color: Color(0xff176b55)),
                              const SizedBox(width: 40),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Welcome to Beluga',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your offline nursing assistant.\nAll data stays on this device.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
                          ),
                          const SizedBox(height: 24),

                          // Step 0: Name & Age
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Please enter your name.' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _age,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake_outlined)),
                          ),

                          const SizedBox(height: 20),
                          Text('Meal schedule', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Set your usual meal times. You can change these later.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                          const SizedBox(height: 12),
                          _TimeField(controller: _breakfastTime, label: 'Breakfast time'),
                          const SizedBox(height: 10),
                          _TimeField(controller: _lunchTime, label: 'Lunch time'),
                          const SizedBox(height: 10),
                          _TimeField(controller: _dinnerTime, label: 'Dinner time'),

                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _busy ? null : _finish,
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: _busy
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Get started'),
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _busy ? null : _importData,
                            icon: const Icon(Icons.file_upload_outlined, size: 18),
                            label: const Text('Import existing data'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return;
      final String content;
      if (kIsWeb) {
        final bytes = result.files.single.bytes;
        if (bytes == null) return;
        content = utf8.decode(bytes);
      } else {
        final path = result.files.single.path;
        if (path == null) return;
        content = await XFile(path).readAsString();
      }
      await LocalDatabase.instance.importAllData(content);
      await _syncNotifications();
      widget.onComplete();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

// ════════════════════════════════════════════════════════════
// HOME – THREE-TAB NAVIGATION
// ════════════════════════════════════════════════════════════

class HealthHome extends StatefulWidget {
  const HealthHome({
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.onReset,
    super.key,
  });
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onReset;

  @override
  State<HealthHome> createState() => _HealthHomeState();
}

class _HealthHomeState extends State<HealthHome> {
  int _selected = 0;
  StreamSubscription<NotificationResponse>? _notifSub;

  @override
  void initState() {
    super.initState();
    _notifSub = reminderNotificationActions.stream.listen(_handleNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final response = ReminderNotifications.takeLaunchResponse();
      if (response != null) _handleNotification(response);
    });
    _syncNotifications();
  }

  Future<void> _handleNotification(NotificationResponse response) async {
    if (response.payload == null) return;
    try {
      final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
      final kind = payload['kind'];
      final name = payload['name']?.toString() ?? '';
      final time = payload['time']?.toString() ?? '';
      final db = LocalDatabase.instance;

      if (kind == 'medication' && response.actionId == 'mark_complete') {
        await db.recordMedicationTaken(name, time);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medication recorded ✓')));
      } else if (kind == 'meal' && response.actionId == 'mark_complete') {
        await db.recordMealTaken(name);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meal recorded ✓')));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  static const _tabs = ['Home', 'Calendar', 'Settings'];
  static const _icons = [Icons.home_outlined, Icons.calendar_month_outlined, Icons.settings_outlined];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final page = switch (_selected) {
      0 => HomePage(onNavigate: (i) => setState(() => _selected = i)),
      1 => const CalendarPage(),
      2 => SettingsPage(
          isDarkMode: widget.isDarkMode,
          onToggleTheme: widget.onToggleTheme,
          onReset: widget.onReset,
        ),
      _ => const SizedBox.shrink(),
    };

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(_tabs[_selected], style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          _AnimatedThemeSwitch(isDarkMode: widget.isDarkMode, onToggle: widget.onToggleTheme),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: NavigationRail(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.7),
                  selectedIndex: _selected,
                  onDestinationSelected: (v) => setState(() => _selected = v),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (var i = 0; i < _tabs.length; i++)
                      NavigationRailDestination(icon: Icon(_icons[i]), label: Text(_tabs[i])),
                  ],
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0.02, 0), end: Offset.zero)
                      .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(_selected), child: page),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: NavigationBar(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.7),
                  selectedIndex: _selected,
                  onDestinationSelected: (v) => setState(() => _selected = v),
                  destinations: [
                    for (var i = 0; i < _tabs.length; i++)
                      NavigationDestination(icon: Icon(_icons[i]), label: _tabs[i]),
                  ],
                ),
              ),
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// HOME PAGE
// ════════════════════════════════════════════════════════════

class HomePage extends StatefulWidget {
  const HomePage({required this.onNavigate, super.key});
  final ValueChanged<int> onNavigate;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _db = LocalDatabase.instance;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _meals = [];
  List<Map<String, dynamic>> _meds = [];
  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _db.getProfile();
    final meals = await _db.getMealSchedules();
    final meds = await _db.getMedications();
    final appointments = await _db.getAppointments();
    if (mounted) setState(() { _profile = profile; _meals = meals; _meds = meds; _appointments = appointments; });
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) return const Center(child: CircularProgressIndicator());
    final name = _profile!['name'] ?? '';
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Hello, $name 👋', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(today, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 20),

          // Meal schedule card
          _SectionHeader(icon: Icons.restaurant_outlined, title: 'Today\'s meals', count: _meals.length),
          const SizedBox(height: 8),
          if (_meals.isEmpty)
            const _EmptyHint(text: 'No meals scheduled. Add your meal times in Settings.')
          else
            ..._meals.map((m) => _ScheduleCard(
              icon: Icons.restaurant,
              title: m['meal_name'] ?? 'Meal',
              time: m['scheduled_time'] ?? '',
              color: const Color(0xffe8f5e9),
              onDone: () async {
                await _db.recordMealTaken(m['meal_name'] ?? 'Meal');
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meal recorded ✓')));
              },
            )),

          const SizedBox(height: 20),
          _SectionHeader(icon: Icons.medication_outlined, title: 'Medications', count: _meds.length),
          const SizedBox(height: 8),
          if (_meds.isEmpty)
            const _EmptyHint(text: 'No medications added. Tap the + button below to add.')
          else
            ..._meds.map((m) {
              final timing = m['timing'] == 'before_meal' ? 'Before meal' : m['timing'] == 'after_meal' ? 'After meal' : 'As scheduled';
              return _ScheduleCard(
                icon: Icons.medication,
                title: m['name'] ?? 'Medicine',
                time: '${m['scheduled_time'] ?? ''} · $timing',
                subtitle: m['prescribed_dose'] ?? '',
                color: const Color(0xffe3f2fd),
                onDone: () async {
                  await _db.recordMedicationTaken(m['name'] ?? 'Medicine', m['scheduled_time'] ?? '');
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medication recorded ✓')));
                },
              );
            }),

          const SizedBox(height: 20),
          _SectionHeader(icon: Icons.event_outlined, title: 'Upcoming appointments', count: _appointments.where((a) => a['completed'] != 1).length),
          const SizedBox(height: 8),
          if (_appointments.where((a) => a['completed'] != 1).isEmpty)
            const _EmptyHint(text: 'No upcoming appointments.')
          else
            ..._appointments.where((a) => a['completed'] != 1).take(3).map((a) => _ScheduleCard(
              icon: Icons.local_hospital_outlined,
              title: '${a['doctor_name']} (${a['specialty'] ?? ''})',
              time: '${a['appointment_date']} at ${a['appointment_time']}',
              color: const Color(0xfffff3e0),
              onDone: () async {
                await _db.completeAppointment(a['id'] as int);
                await _db.recordHealthCheckup(a['doctor_name'] ?? '', a['appointment_date'] ?? '');
                _load();
              },
            )),

          const SizedBox(height: 24),
          // Quick-add buttons
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _QuickAction(icon: Icons.medication_outlined, label: 'Add medication', onTap: () => _addMedication(context)),
              _QuickAction(icon: Icons.event_outlined, label: 'Add appointment', onTap: () => _addAppointment(context)),
              _QuickAction(icon: Icons.restaurant_outlined, label: 'Edit meals', onTap: () => _editMeals(context)),
            ],
          ),

          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'All your data is stored offline on this device. When you uninstall the app, all data is erased for your privacy.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMedication(BuildContext ctx) async {
    final result = await showDialog<bool>(context: ctx, builder: (_) => const _MedicationDialog());
    if (result == true) { _load(); await _syncNotifications(); }
  }

  Future<void> _addAppointment(BuildContext ctx) async {
    final result = await showDialog<bool>(context: ctx, builder: (_) => const _AppointmentDialog());
    if (result == true) { _load(); await _syncNotifications(); }
  }

  Future<void> _editMeals(BuildContext ctx) async {
    await showDialog(context: ctx, builder: (_) => _MealScheduleDialog(meals: _meals));
    _load();
    await _syncNotifications();
  }
}

// ════════════════════════════════════════════════════════════
// CALENDAR PAGE
// ════════════════════════════════════════════════════════════

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _db = LocalDatabase.instance;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<String, List<Map<String, dynamic>>> _events = {};

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final events = await _db.getCalendarEventsGrouped();
    if (mounted) setState(() => _events = events);
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = day.toIso8601String().substring(0, 10);
    return _events[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = _selectedDay.toIso8601String().substring(0, 10);
    final dayEvents = _events[selectedKey] ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FrostedGlassCard(
          padding: const EdgeInsets.all(12),
          child: TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selected, focused) {
              setState(() { _selectedDay = selected; _focusedDay = focused; });
            },
            eventLoader: _getEventsForDay,
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
              markerSize: 6,
              markersMaxCount: 3,
            ),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          DateFormat('MMMM d, yyyy').format(_selectedDay),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (dayEvents.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('No events recorded for this day.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
            ),
          )
        else
          ...dayEvents.map((e) {
            final type = e['event_type'] ?? '';
            final icon = type == 'medication' ? Icons.medication : type == 'meal' ? Icons.restaurant : Icons.local_hospital;
            final color = type == 'medication' ? const Color(0xffe3f2fd) : type == 'meal' ? const Color(0xffe8f5e9) : const Color(0xfffff3e0);
            return Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: color, child: Icon(icon, size: 20, color: const Color(0xff176b55))),
                title: Text(e['title'] ?? ''),
                subtitle: e['description'] != null && (e['description'] as String).isNotEmpty ? Text(e['description']) : null,
                trailing: e['completed'] == 1 ? const Icon(Icons.check_circle, color: Color(0xff176b55)) : null,
              ),
            );
          }),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// SETTINGS PAGE
// ════════════════════════════════════════════════════════════

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.onReset,
    super.key,
  });
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onReset;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _db = LocalDatabase.instance;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _db.getProfile();
    if (mounted) setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Profile section
        if (_profile != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xffe2ede7),
                        child: Text(
                          (_profile!['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xff176b55)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_profile!['name'] ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            if (_profile!['age'] != null) Text('Age: ${_profile!['age']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editProfile(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 12),
        Text('Schedule management', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _SettingsTile(icon: Icons.restaurant_outlined, title: 'Meal times', subtitle: 'Customize your meal schedule', onTap: () => _editMealSchedule(context)),
        _SettingsTile(icon: Icons.medication_outlined, title: 'Medications', subtitle: 'Manage your prescriptions', onTap: () => _manageMedications(context)),
        _SettingsTile(icon: Icons.event_outlined, title: 'Doctor appointments', subtitle: 'Schedule health checkups', onTap: () => _manageAppointments(context)),

        const SizedBox(height: 16),
        Text('Data & Privacy', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _SettingsTile(icon: Icons.file_download_outlined, title: 'Export data', subtitle: 'Save all your data as a JSON file', onTap: () => _exportData(context)),
        _SettingsTile(icon: Icons.file_upload_outlined, title: 'Import data', subtitle: 'Restore data from a backup file', onTap: () => _importData(context)),
        _SettingsTile(
          icon: Icons.delete_forever_outlined,
          title: 'Delete all data',
          subtitle: 'Erase everything and start fresh',
          color: Colors.red,
          onTap: () => _deleteAllData(context),
        ),

        const SizedBox(height: 16),
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            secondary: Icon(widget.isDarkMode ? Icons.dark_mode : Icons.light_mode),
            title: const Text('Dark mode'),
            value: widget.isDarkMode,
            onChanged: (_) => widget.onToggleTheme(),
          ),
        ),

        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xff176b55)),
                const SizedBox(height: 8),
                Text(
                  'Privacy first — all data is stored locally on your device.\nNo accounts, no servers, no tracking.\nUninstalling the app permanently erases all data.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editProfile(BuildContext ctx) async {
    final result = await showDialog<bool>(context: ctx, builder: (_) => _ProfileEditDialog(profile: _profile!));
    if (result == true) _load();
  }

  Future<void> _editMealSchedule(BuildContext ctx) async {
    final meals = await _db.getMealSchedules();
    if (!ctx.mounted) return;
    await showDialog(context: ctx, builder: (_) => _MealScheduleDialog(meals: meals));
    await _syncNotifications();
  }

  Future<void> _manageMedications(BuildContext ctx) async {
    await Navigator.push(ctx, MaterialPageRoute(builder: (_) => const _MedicationsListPage()));
    await _syncNotifications();
  }

  Future<void> _manageAppointments(BuildContext ctx) async {
    await Navigator.push(ctx, MaterialPageRoute(builder: (_) => const _AppointmentsListPage()));
    await _syncNotifications();
  }

  Future<void> _exportData(BuildContext ctx) async {
    try {
      final json = await _db.exportAllData();
      final date = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'beluga_backup_$date.json';
      final bytes = Uint8List.fromList(utf8.encode(json));
      if (ctx.mounted) {
        await Share.shareXFiles([
          XFile.fromData(bytes, name: filename, mimeType: 'application/json'),
        ], text: 'Beluga Health backup');
      }
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _importData(BuildContext ctx) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return;
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (ctx) => AlertDialog(
          title: const Text('Import data?'),
          content: const Text('This will replace ALL current data with the imported file. This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
          ],
        ),
      );
      if (confirmed != true) return;
      final String content;
      if (kIsWeb) {
        final bytes = result.files.single.bytes;
        if (bytes == null) return;
        content = utf8.decode(bytes);
      } else {
        final path = result.files.single.path;
        if (path == null) return;
        content = await XFile(path).readAsString();
      }
      await _db.importAllData(content);
      await _syncNotifications();
      _load();
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Data imported successfully ✓')));
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _deleteAllData(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text('This will permanently erase ALL your data including profile, meals, medications, appointments, and calendar history. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteAllData();
      widget.onReset();
    }
  }
}

// ════════════════════════════════════════════════════════════
// DIALOG: MEDICATION ADD
// ════════════════════════════════════════════════════════════

class _MedicationDialog extends StatefulWidget {
  const _MedicationDialog({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_MedicationDialog> createState() => _MedicationDialogState();
}

class _MedicationDialogState extends State<_MedicationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _dose = TextEditingController(text: widget.existing?['prescribed_dose'] ?? '');
  late final _quantity = TextEditingController(text: widget.existing?['quantity'] ?? '');
  late final _time = TextEditingController(text: widget.existing?['scheduled_time'] ?? '08:00');
  late final _instructions = TextEditingController(text: widget.existing?['instructions'] ?? '');
  late String _timing = widget.existing?['timing'] ?? 'before_meal';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final data = {
      'name': _name.text.trim(),
      'prescribed_dose': _dose.text.trim(),
      'quantity': _quantity.text.trim(),
      'scheduled_time': _time.text.trim(),
      'instructions': _instructions.text.trim(),
      'timing': _timing,
    };
    if (widget.existing != null) {
      await LocalDatabase.instance.updateMedication(widget.existing!['id'] as int, data);
    } else {
      await LocalDatabase.instance.addMedication(data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit medication' : 'Add medication'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Medicine name *'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 10),
                TextFormField(controller: _dose, decoration: const InputDecoration(labelText: 'Prescribed dose')),
                const SizedBox(height: 10),
                TextFormField(controller: _quantity, decoration: const InputDecoration(labelText: 'Quantity per intake')),
                const SizedBox(height: 10),
                _TimeField(controller: _time, label: 'Scheduled time'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _timing,
                  decoration: const InputDecoration(labelText: 'When to take'),
                  items: const [
                    DropdownMenuItem(value: 'before_meal', child: Text('Before meal')),
                    DropdownMenuItem(value: 'after_meal', child: Text('After meal')),
                    DropdownMenuItem(value: 'custom', child: Text('As scheduled')),
                  ],
                  onChanged: (v) => setState(() => _timing = v ?? 'before_meal'),
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _instructions, maxLines: 2, decoration: const InputDecoration(labelText: 'Doctor\'s instructions')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// DIALOG: APPOINTMENT ADD
// ════════════════════════════════════════════════════════════

class _AppointmentDialog extends StatefulWidget {
  const _AppointmentDialog({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<_AppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _doctor = TextEditingController(text: widget.existing?['doctor_name'] ?? '');
  late final _specialty = TextEditingController(text: widget.existing?['specialty'] ?? '');
  late final _date = TextEditingController(text: widget.existing?['appointment_date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
  late final _time = TextEditingController(text: widget.existing?['appointment_time'] ?? '10:00');
  late final _location = TextEditingController(text: widget.existing?['location'] ?? '');
  late final _notes = TextEditingController(text: widget.existing?['notes'] ?? '');

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final data = {
      'doctor_name': _doctor.text.trim(),
      'specialty': _specialty.text.trim(),
      'appointment_date': _date.text.trim(),
      'appointment_time': _time.text.trim(),
      'location': _location.text.trim(),
      'notes': _notes.text.trim(),
    };
    if (widget.existing != null) {
      await LocalDatabase.instance.updateAppointment(widget.existing!['id'] as int, data);
    } else {
      await LocalDatabase.instance.addAppointment(data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit appointment' : 'Schedule appointment'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: _doctor, decoration: const InputDecoration(labelText: 'Doctor name *'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 10),
                TextFormField(controller: _specialty, decoration: const InputDecoration(labelText: 'Specialty')),
                const SizedBox(height: 10),
                TextFormField(controller: _date, decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD) *'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 10),
                _TimeField(controller: _time, label: 'Time'),
                const SizedBox(height: 10),
                TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
                const SizedBox(height: 10),
                TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// DIALOG: MEAL SCHEDULE EDIT
// ════════════════════════════════════════════════════════════

class _MealScheduleDialog extends StatefulWidget {
  const _MealScheduleDialog({required this.meals});
  final List<Map<String, dynamic>> meals;

  @override
  State<_MealScheduleDialog> createState() => _MealScheduleDialogState();
}

class _MealScheduleDialogState extends State<_MealScheduleDialog> {
  late List<Map<String, dynamic>> _meals = List.from(widget.meals);
  final _db = LocalDatabase.instance;

  Future<void> _addMeal() async {
    final name = TextEditingController();
    final time = TextEditingController(text: '12:00');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add meal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Meal name')),
            const SizedBox(height: 10),
            _TimeField(controller: time, label: 'Time'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (name.text.trim().isNotEmpty) Navigator.pop(ctx, true);
          }, child: const Text('Add')),
        ],
      ),
    );
    if (result == true) {
      await _db.addMealSchedule({'meal_name': name.text.trim(), 'scheduled_time': time.text.trim()});
      final meals = await _db.getMealSchedules();
      setState(() => _meals = meals);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Meal schedule'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_meals.isEmpty) const Text('No meals configured.'),
            ..._meals.map((m) => ListTile(
              title: Text(m['meal_name'] ?? ''),
              subtitle: Text(m['scheduled_time'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await _db.deleteMealSchedule(m['id'] as int);
                  final meals = await _db.getMealSchedules();
                  setState(() => _meals = meals);
                },
              ),
            )),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _addMeal, icon: const Icon(Icons.add), label: const Text('Add meal')),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// DIALOG: PROFILE EDIT
// ════════════════════════════════════════════════════════════

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late final _name = TextEditingController(text: widget.profile['name'] ?? '');
  late final _age = TextEditingController(text: widget.profile['age']?.toString() ?? '');
  late final _location = TextEditingController(text: widget.profile['location'] ?? '');
  late final _conditions = TextEditingController(text: widget.profile['conditions'] ?? '');
  late final _appetite = TextEditingController(text: widget.profile['appetite'] ?? '');
  late final _routine = TextEditingController(text: widget.profile['daily_routine'] ?? '');
  late String _gender = widget.profile['gender'] ?? '';
  late String _blood = widget.profile['blood_type'] ?? '';

  Future<void> _save() async {
    await LocalDatabase.instance.saveProfile({
      'name': _name.text.trim(),
      'age': int.tryParse(_age.text.trim()),
      'gender': _gender,
      'blood_type': _blood,
      'location': _location.text.trim(),
      'conditions': _conditions.text.trim(),
      'appetite': _appetite.text.trim(),
      'daily_routine': _routine.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: _age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _gender.isEmpty ? '' : _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Prefer not to say')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _gender = v ?? ''),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _blood.isEmpty ? '' : _blood,
                decoration: const InputDecoration(labelText: 'Blood type'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Unknown')),
                  for (final v in ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'])
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (v) => setState(() => _blood = v ?? ''),
              ),
              const SizedBox(height: 10),
              TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
              const SizedBox(height: 10),
              TextField(controller: _conditions, maxLines: 2, decoration: const InputDecoration(labelText: 'Health conditions')),
              const SizedBox(height: 10),
              TextField(controller: _appetite, decoration: const InputDecoration(labelText: 'Appetite / diet notes')),
              const SizedBox(height: 10),
              TextField(controller: _routine, maxLines: 2, decoration: const InputDecoration(labelText: 'Daily routine')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// FULL-PAGE: MEDICATIONS LIST
// ════════════════════════════════════════════════════════════

class _MedicationsListPage extends StatefulWidget {
  const _MedicationsListPage();

  @override
  State<_MedicationsListPage> createState() => _MedicationsListPageState();
}

class _MedicationsListPageState extends State<_MedicationsListPage> {
  List<Map<String, dynamic>> _meds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final meds = await LocalDatabase.instance.getMedications();
    if (mounted) setState(() => _meds = meds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await showDialog<bool>(context: context, builder: (_) => const _MedicationDialog());
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _meds.isEmpty
          ? const Center(child: Text('No medications added yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _meds.length,
              itemBuilder: (ctx, i) {
                final m = _meds[i];
                final timing = m['timing'] == 'before_meal' ? 'Before meal' : m['timing'] == 'after_meal' ? 'After meal' : 'As scheduled';
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.medication, color: Color(0xff176b55)),
                    title: Text(m['name'] ?? ''),
                    subtitle: Text('${m['scheduled_time']} · $timing\n${m['prescribed_dose'] ?? ''}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'edit') {
                          final result = await showDialog<bool>(context: ctx, builder: (_) => _MedicationDialog(existing: m));
                          if (result == true) _load();
                        } else if (action == 'delete') {
                          await LocalDatabase.instance.deleteMedication(m['id'] as int);
                          _load();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// FULL-PAGE: APPOINTMENTS LIST
// ════════════════════════════════════════════════════════════

class _AppointmentsListPage extends StatefulWidget {
  const _AppointmentsListPage();

  @override
  State<_AppointmentsListPage> createState() => _AppointmentsListPageState();
}

class _AppointmentsListPageState extends State<_AppointmentsListPage> {
  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appts = await LocalDatabase.instance.getAppointments();
    if (mounted) setState(() => _appointments = appts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor Appointments')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await showDialog<bool>(context: context, builder: (_) => const _AppointmentDialog());
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _appointments.isEmpty
          ? const Center(child: Text('No appointments scheduled.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _appointments.length,
              itemBuilder: (ctx, i) {
                final a = _appointments[i];
                final completed = a['completed'] == 1;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      completed ? Icons.check_circle : Icons.event,
                      color: completed ? const Color(0xff176b55) : Colors.orange,
                    ),
                    title: Text(a['doctor_name'] ?? ''),
                    subtitle: Text('${a['specialty'] ?? ''}\n${a['appointment_date']} at ${a['appointment_time']}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'complete') {
                          await LocalDatabase.instance.completeAppointment(a['id'] as int);
                          await LocalDatabase.instance.recordHealthCheckup(a['doctor_name'] ?? '', a['appointment_date'] ?? '');
                          _load();
                        } else if (action == 'edit') {
                          final result = await showDialog<bool>(context: ctx, builder: (_) => _AppointmentDialog(existing: a));
                          if (result == true) _load();
                        } else if (action == 'delete') {
                          await LocalDatabase.instance.deleteAppointment(a['id'] as int);
                          _load();
                        }
                      },
                      itemBuilder: (_) => [
                        if (!completed) const PopupMenuItem(value: 'complete', child: Text('Mark complete')),
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SHARED UTILITY WIDGETS
// ════════════════════════════════════════════════════════════

/// Sync all notifications from local DB
Future<void> _syncNotifications() async {
  final db = LocalDatabase.instance;
  final meals = await db.getMealSchedules();
  final meds = await db.getMedications();
  final appts = await db.getAppointments();
  await ReminderNotifications.syncFromLocal(meals: meals, medications: meds, appointments: appts);
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:MM (24h)',
        suffixIcon: IconButton(
          icon: const Icon(Icons.access_time),
          onPressed: () async {
            final parts = controller.text.split(':');
            final initial = TimeOfDay(
              hour: int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 8,
              minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
            );
            final picked = await showTimePicker(context: context, initialTime: initial);
            if (picked != null) {
              controller.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
            }
          },
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return null;
        return RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v) ? null : 'Use HH:MM format';
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, required this.count});
  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xff176b55)),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xffe8f5e9), borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xff176b55))),
        ),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.icon, required this.title, required this.time, required this.color, this.subtitle, this.onDone});
  final IconData icon;
  final String title;
  final String time;
  final String? subtitle;
  final Color color;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: Icon(icon, size: 20, color: const Color(0xff176b55))),
        title: Text(title),
        subtitle: Text([time, if (subtitle != null && subtitle!.isNotEmpty) subtitle!].join('\n')),
        trailing: onDone != null
            ? IconButton(icon: const Icon(Icons.check_circle_outline), tooltip: 'Mark done', onPressed: onDone)
            : null,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.color});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color ?? const Color(0xff176b55)),
        title: Text(title, style: TextStyle(color: color)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _AnimatedThemeSwitch extends StatelessWidget {
  const _AnimatedThemeSwitch({required this.isDarkMode, required this.onToggle});
  final bool isDarkMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onToggle,
      tooltip: isDarkMode ? 'Light mode' : 'Dark mode',
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: Icon(
          isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(isDarkMode),
          color: isDarkMode ? Colors.amberAccent : const Color(0xff176b55),
        ),
      ),
    );
  }
}

class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground({required this.child});
  final Widget child;

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1.0 + _ctrl.value * 0.4, -1.0),
            end: Alignment(1.0, 1.0 - _ctrl.value * 0.4),
            colors: isDark
                ? const [Color(0xff121412), Color(0xff16221d), Color(0xff0f1a16), Color(0xff0a0e0c)]
                : const [Color(0xfff7f8f4), Color(0xffe6f2ee), Color(0xffeff7f4), Color(0xfff5f7f3)],
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class FrostedGlassCard extends StatelessWidget {
  const FrostedGlassCard({required this.child, this.padding = const EdgeInsets.all(24), super.key});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff1c201e).withOpacity(0.72) : Colors.white.withOpacity(0.78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.85),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.08), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
