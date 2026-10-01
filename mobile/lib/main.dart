import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api',
);

const secureStorage = FlutterSecureStorage();

class HealthApi {
  HealthApi(this.token);

  final String? token;

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    late http.Response response;
    switch (method) {
      case 'POST':
        response = await http.post(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'PUT':
        response = await http.put(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        response = await http.get(uri, headers: headers);
        break;
    }

    if (response.statusCode == 204) return null;
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw Exception(detail ?? 'Request failed (${response.statusCode}).');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async =>
      Map<String, dynamic>.from(await request('/login', method: 'POST', body: {
        'email': email,
        'password': password,
      }));

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
  ) async =>
      Map<String, dynamic>.from(await request('/register', method: 'POST', body: {
        'name': name,
        'email': email,
        'password': password,
      }));
}

void main() => runApp(const BelugaApp());

class BelugaApp extends StatefulWidget {
  const BelugaApp({super.key});

  @override
  State<BelugaApp> createState() => _BelugaAppState();
}

class _BelugaAppState extends State<BelugaApp> {
  String? _token;
  Map<String, dynamic>? _user;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await secureStorage.read(key: 'access_token');
    if (token != null) {
      try {
        final result = await HealthApi(token).request('/me');
        _token = token;
        _user = Map<String, dynamic>.from(result['user']);
      } catch (_) {
        await secureStorage.delete(key: 'access_token');
      }
    }
    if (mounted) setState(() => _checkingSession = false);
  }

  Future<void> _acceptSession(Map<String, dynamic> result) async {
    await secureStorage.write(key: 'access_token', value: result['access_token']);
    setState(() {
      _token = result['access_token'];
      _user = Map<String, dynamic>.from(result['user']);
    });
  }

  Future<void> _signOut() async {
    try {
      await HealthApi(_token).request('/logout', method: 'POST');
    } catch (_) {
      // Clear the local session even if the server is temporarily unavailable.
    }
    await secureStorage.delete(key: 'access_token');
    if (mounted) setState(() {
      _token = null;
      _user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beluga Health',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff176b55),
          surface: const Color(0xfff7f8f3),
        ),
        scaffoldBackgroundColor: const Color(0xfff5f5ef),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfff5f5ef),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xffe4e9e2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xffdfe5df)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xffdfe5df)),
          ),
        ),
      ),
      home: _checkingSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _token == null
              ? AuthScreen(onAuthenticated: _acceptSession)
              : HealthHome(token: _token!, user: _user!, onSignOut: _signOut),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.onAuthenticated, super.key});

  final ValueChanged<Map<String, dynamic>> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = HealthApi(null);
      final result = _register
          ? await api.register(_name.text.trim(), _email.text.trim(), _password.text)
          : await api.signIn(_email.text.trim(), _password.text);
      widget.onAuthenticated(result);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 24 * (1 - value)),
                  child: child,
                ),
              ),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.monitor_heart_outlined, size: 38, color: Color(0xff176b55)),
                      const SizedBox(height: 12),
                      Text('Beluga Health', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 5),
                      Text(_register ? 'Create your personal account' : 'Sign in to your health space', textAlign: TextAlign.center),
                      const SizedBox(height: 22),
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Full name'),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Enter your name.' : null,
                        ),
                        const SizedBox(height: 13),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email address'),
                        validator: (value) => value == null || !value.contains('@') ? 'Enter a valid email address.' : null,
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (value) => value == null || value.length < 8 ? 'Use at least 8 characters.' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_register ? 'Create account' : 'Sign in'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }),
                        child: Text(_register ? 'Already have an account? Sign in' : 'New here? Create an account'),
                      ),
                      const SizedBox(height: 8),
                      const Text('Educational tracking only. This app does not diagnose or prescribe.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
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
}

class HealthHome extends StatefulWidget {
  const HealthHome({required this.token, required this.user, required this.onSignOut, super.key});

  final String token;
  final Map<String, dynamic> user;
  final VoidCallback onSignOut;

  @override
  State<HealthHome> createState() => _HealthHomeState();
}

class _HealthHomeState extends State<HealthHome> {
  int _selected = 0;
  late final HealthApi _api = HealthApi(widget.token);

  final _pages = const ['Overview', 'Health log', 'Reminders', 'Profile'];
  final _icons = const [Icons.home_outlined, Icons.monitor_heart_outlined, Icons.notifications_outlined, Icons.person_outline];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final page = switch (_selected) {
      0 => OverviewPage(api: _api, user: widget.user, onNavigate: (index) => setState(() => _selected = index)),
      1 => MeasurementPage(api: _api),
      2 => RemindersPage(api: _api),
      _ => ProfilePage(api: _api),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_pages[_selected]),
        actions: [IconButton(onPressed: widget.onSignOut, tooltip: 'Sign out', icon: const Icon(Icons.logout))],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _selected,
              onDestinationSelected: (value) => setState(() => _selected = value),
              labelType: NavigationRailLabelType.all,
              destinations: [for (var i = 0; i < _pages.length; i++) NavigationRailDestination(icon: Icon(_icons[i]), label: Text(_pages[i]))],
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              reverseDuration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
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
          : NavigationBar(
              selectedIndex: _selected,
              onDestinationSelected: (value) => setState(() => _selected = value),
              destinations: [for (var i = 0; i < _pages.length; i++) NavigationDestination(icon: Icon(_icons[i]), label: _pages[i])],
            ),
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({required this.api, required this.user, required this.onNavigate, super.key});

  final HealthApi api;
  final Map<String, dynamic> user;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: api.request('/dashboard'),
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = Map<String, dynamic>.from(snapshot.data);
        final profile = Map<String, dynamic>.from(data['profile'] ?? {});
        final latest = Map<String, dynamic>.from(data['latest_measurement'] ?? {});
        final dataset = data['dataset'] == null ? null : Map<String, dynamic>.from(data['dataset']);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Hello, ${user['name'] ?? data['name']}', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text('Your personal health check-in.'),
            const SizedBox(height: 18),
            Wrap(spacing: 12, runSpacing: 12, children: [
              AnimatedReveal(index: 0, child: MetricCard(label: 'Steps', value: latest['steps']?.toString() ?? '—', icon: Icons.directions_walk)),
              AnimatedReveal(index: 1, child: MetricCard(label: 'Active minutes', value: latest['active_minutes']?.toString() ?? '—', icon: Icons.bolt_outlined)),
              AnimatedReveal(index: 2, child: MetricCard(label: 'Sleep hours', value: latest['sleep_hours']?.toString() ?? '—', icon: Icons.bedtime_outlined)),
              AnimatedReveal(index: 3, child: MetricCard(label: 'BMI', value: profile['bmi']?.toString() ?? '—', icon: Icons.monitor_weight_outlined)),
            ]),
            const SizedBox(height: 16),
            AnimatedReveal(index: 4, child: Card(child: ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Log health measurements'),
              subtitle: const Text('Steps, sleep, glucose, or blood pressure'),
              onTap: () => onNavigate(1),
            ))),
            AnimatedReveal(index: 5, child: Card(child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Manage reminders'),
              subtitle: const Text('View and update your daily schedule'),
              onTap: () => onNavigate(2),
            ))),
            if (dataset != null)
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Sample dataset: ${dataset['record_count']} records; ${dataset['diabetes_count']} diabetes labels; ${dataset['hypertension_count']} hypertension labels. Sample counts only, not an individual prediction or local prevalence estimate.'),
              )),
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Health readings and BMI are for personal tracking and discussion with a healthcare professional. This app does not diagnose or recommend treatment.'),
            )),
          ],
        );
      },
    );
  }
}

class AnimatedReveal extends StatelessWidget {
  const AnimatedReveal({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        duration: Duration(milliseconds: 420 + (index * 70)),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: 1),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        ),
        child: child,
      );
}

class MetricCard extends StatelessWidget {
  const MetricCard({required this.label, required this.value, required this.icon, super.key});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: MediaQuery.sizeOf(context).width >= 760
        ? 220
        : (MediaQuery.sizeOf(context).width - 64) / 2,
        child: Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        )),
      );
}

class MeasurementPage extends StatefulWidget {
  const MeasurementPage({required this.api, super.key});
  final HealthApi api;

  @override
  State<MeasurementPage> createState() => _MeasurementPageState();
}

class _MeasurementPageState extends State<MeasurementPage> {
  final _controllers = <String, TextEditingController>{
    'steps': TextEditingController(),
    'active_minutes': TextEditingController(),
    'sleep_hours': TextEditingController(),
    'fasting_glucose': TextEditingController(),
    'systolic_bp': TextEditingController(),
    'diastolic_bp': TextEditingController(),
  };
  bool _busy = false;
  String? _message;

  Future<void> _save() async {
    final values = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      if (entry.value.text.trim().isEmpty) continue;
        final parsed = num.tryParse(entry.value.text.trim());
        values[entry.key] = const {'steps', 'active_minutes', 'systolic_bp', 'diastolic_bp'}.contains(entry.key)
          ? parsed?.toInt()
          : parsed?.toDouble();
    }
    values.removeWhere((_, value) => value == null);
    if (values.isEmpty) {
      setState(() => _message = 'Enter at least one measurement.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      await widget.api.request('/measurements', method: 'POST', body: values);
      for (final controller in _controllers.values) { controller.clear(); }
      setState(() => _message = 'Check-in saved.');
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Today’s health', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          for (final entry in _controllers.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: entry.value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _measurementLabel(entry.key)),
              ),
            ),
          const Text('Enter only measurements you have. Readings are not a diagnosis.'),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save check-in')),
        ],
      );
}

String _measurementLabel(String key) => switch (key) {
      'steps' => 'Steps',
      'active_minutes' => 'Active minutes',
      'sleep_hours' => 'Sleep hours',
      'fasting_glucose' => 'Fasting glucose (mg/dL)',
      'systolic_bp' => 'Systolic blood pressure (mmHg)',
      _ => 'Diastolic blood pressure (mmHg)',
    };

class RemindersPage extends StatefulWidget {
  const RemindersPage({required this.api, super.key});
  final HealthApi api;

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  late Future<dynamic> _reminders;

  @override
  void initState() {
    super.initState();
    _reminders = widget.api.request('/reminders');
  }

  Future<void> _addReminder() async {
    final title = TextEditingController();
    final time = TextEditingController(text: '08:00');
    final instruction = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add reminder'),
        content: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Reminder'), validator: (value) => value == null || value.trim().isEmpty ? 'Enter a title.' : null),
          TextFormField(controller: time, decoration: const InputDecoration(labelText: 'Time (HH:MM)'), validator: (value) => value == null || !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value) ? 'Use 24-hour time, e.g. 08:30.' : null),
          TextFormField(controller: instruction, decoration: const InputDecoration(labelText: 'Note (optional)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Add')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await widget.api.request('/reminders', method: 'POST', body: {'title': title.text.trim(), 'scheduled_time': time.text.trim(), 'instruction': instruction.text.trim()});
      setState(() => _reminders = widget.api.request('/reminders'));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _complete(int id) async {
    try {
      await widget.api.request('/reminders/$id/complete', method: 'POST');
      setState(() => _reminders = widget.api.request('/reminders'));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _delete(int id) async {
    try {
      await widget.api.request('/reminders/$id', method: 'DELETE');
      setState(() => _reminders = widget.api.request('/reminders'));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: _reminders,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final items = List<Map<String, dynamic>>.from(snapshot.data);
          return ListView(padding: const EdgeInsets.all(20), children: [
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _addReminder, icon: const Icon(Icons.add), label: const Text('Add reminder'))),
            const SizedBox(height: 12),
            if (items.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No reminders yet. Add one to start your daily routine.'))),
            for (final item in items) Card(child: ListTile(
              leading: IconButton(tooltip: 'Mark complete', onPressed: item['completed_today'] == 1 || item['completed_today'] == true ? null : () => _complete(item['id']), icon: Icon(item['completed_today'] == 1 || item['completed_today'] == true ? Icons.check_circle : Icons.circle_outlined)),
              title: Text(item['title']),
              subtitle: Text('${item['scheduled_time']}  ${item['instruction'] ?? ''}'),
              trailing: IconButton(tooltip: 'Delete reminder', onPressed: () => _delete(item['id']), icon: const Icon(Icons.delete_outline)),
            )),
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('Reminders are stored in your account. Background notifications are not enabled in this version.')),
          ]);
        },
      );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.api, super.key});
  final HealthApi api;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<dynamic> _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.api.request('/me');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final result = Map<String, dynamic>.from(snapshot.data);
          final user = Map<String, dynamic>.from(result['user']);
          final profile = Map<String, dynamic>.from(result['profile'] ?? {});
          return ProfileForm(api: widget.api, user: user, profile: profile, onSaved: () => setState(() => _profile = widget.api.request('/me')));
        },
      );
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({required this.api, required this.user, required this.profile, required this.onSaved, super.key});
  final HealthApi api;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final VoidCallback onSaved;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final _name = TextEditingController(text: widget.user['name'] ?? '');
  late final _email = TextEditingController(text: widget.user['email'] ?? '');
  late final _age = TextEditingController(text: widget.profile['age']?.toString() ?? '');
  late final _height = TextEditingController(text: widget.profile['height_cm']?.toString() ?? '');
  late final _weight = TextEditingController(text: widget.profile['weight_kg']?.toString() ?? '');
  late final _location = TextEditingController(text: widget.profile['location'] ?? '');
  late final _conditions = TextEditingController(text: (widget.profile['conditions'] as List? ?? []).join(', '));
  late final _medications = TextEditingController(text: (widget.profile['medications'] as List? ?? []).join(', '));
  String _gender = '';
  String _bloodType = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _gender = widget.profile['gender'] ?? '';
    _bloodType = widget.profile['blood_type'] ?? '';
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.request('/profile', method: 'PUT', body: {
        'name': _name.text.trim(),
        'age': int.tryParse(_age.text),
        'gender': _gender,
        'blood_type': _bloodType,
        'height_cm': double.tryParse(_height.text),
        'weight_kg': double.tryParse(_weight.text),
        'location': _location.text.trim(),
        'conditions': _conditions.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(),
        'medications': _medications.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
      widget.onSaved();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        Text('Personal profile', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(enabled: false, controller: _email, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 12),
        TextField(controller: _age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _gender.isEmpty ? null : _gender, decoration: const InputDecoration(labelText: 'Gender'), items: const [DropdownMenuItem(value: '', child: Text('Prefer not to say')), DropdownMenuItem(value: 'Female', child: Text('Female')), DropdownMenuItem(value: 'Male', child: Text('Male')), DropdownMenuItem(value: 'Non-binary', child: Text('Non-binary')), DropdownMenuItem(value: 'Self-describe', child: Text('Self-describe'))], onChanged: (value) => setState(() => _gender = value ?? '')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _bloodType.isEmpty ? null : _bloodType, decoration: const InputDecoration(labelText: 'Blood type'), items: const [DropdownMenuItem(value: '', child: Text('Not provided')), for (final value in ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']) DropdownMenuItem(value: value, child: Text(value))], onChanged: (value) => setState(() => _bloodType = value ?? '')),
        const SizedBox(height: 12),
        TextField(controller: _height, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Height (cm)')),
        const SizedBox(height: 12),
        TextField(controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)')),
        const SizedBox(height: 12),
        TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
        const SizedBox(height: 12),
        TextField(controller: _conditions, maxLines: 2, decoration: const InputDecoration(labelText: 'Conditions (comma-separated)')),
        const SizedBox(height: 12),
        TextField(controller: _medications, maxLines: 2, decoration: const InputDecoration(labelText: 'Medications (comma-separated)')),
        const SizedBox(height: 8),
        const Text('Medication names are saved for reference. No interaction or dosage checks are performed.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save profile')),
      ]);
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('Could not connect to the health server.'),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}