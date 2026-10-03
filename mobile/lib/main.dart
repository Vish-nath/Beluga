import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'reminder_notifications.dart';

const defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api',
);
const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

String get platformDefaultApiBaseUrl {
  if (configuredApiBaseUrl.isNotEmpty) return configuredApiBaseUrl;
  return defaultTargetPlatform == TargetPlatform.macOS
      ? 'http://127.0.0.1:8000/api'
      : defaultApiBaseUrl;
}

const secureStorage = FlutterSecureStorage();

class HealthApi {
  HealthApi(this.token, {this.baseUrl});

  final String? token;
  final String? baseUrl;

  String get activeBaseUrl => (baseUrl != null && baseUrl!.trim().isNotEmpty)
      ? baseUrl!.trim().replaceAll(RegExp(r'/+$'), '')
      : platformDefaultApiBaseUrl;

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$activeBaseUrl$cleanPath');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    late http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await http
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 15));
          break;
        case 'PUT':
          response = await http
              .put(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 15));
          break;
        case 'DELETE':
          response = await http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
          break;
        default:
          response =
              await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
          break;
      }
    } catch (e) {
      throw Exception(
        'Could not connect to server at $activeBaseUrl. Please check your network or server URL.',
      );
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

  Future<Map<String, dynamic>> signInWithGoogle(String idToken) async =>
      Map<String, dynamic>.from(await request('/auth/google', method: 'POST', body: {
        'id_token': idToken,
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderNotifications.initialize();
  runApp(const BelugaApp());
}

class BelugaApp extends StatefulWidget {
  const BelugaApp({super.key});

  @override
  State<BelugaApp> createState() => _BelugaAppState();
}

class _BelugaAppState extends State<BelugaApp> {
  String? _token;
  Map<String, dynamic>? _user;
  String _baseUrl = platformDefaultApiBaseUrl;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _loadConfigAndRestoreSession();
  }

  Future<void> _loadConfigAndRestoreSession() async {
    final savedUrl = await secureStorage.read(key: 'custom_api_base_url');
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      _baseUrl = savedUrl.trim();
    }
    final token = await secureStorage.read(key: 'access_token');
    if (token != null) {
      try {
        final result = await HealthApi(token, baseUrl: _baseUrl).request('/me');
        _token = token;
        _user = Map<String, dynamic>.from(result['user']);
      } catch (_) {
        await secureStorage.delete(key: 'access_token');
      }
    }
    if (mounted) setState(() => _checkingSession = false);
  }

  Future<void> _updateBaseUrl(String newUrl) async {
    await secureStorage.write(key: 'custom_api_base_url', value: newUrl.trim());
    setState(() => _baseUrl = newUrl.trim());
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
      await HealthApi(_token, baseUrl: _baseUrl).request('/logout', method: 'POST');
    } catch (_) {}
    await secureStorage.delete(key: 'access_token');
    if (mounted) {
      setState(() {
        _token = null;
        _user = null;
      });
    }
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
          primary: const Color(0xff176b55),
          surface: const Color(0xfff7f8f3),
        ),
        scaffoldBackgroundColor: const Color(0xfff5f5ef),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfff5f5ef),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xffe4e9e2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xffdfe5df)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xffdfe5df)),
          ),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        child: _checkingSession
            ? const Scaffold(
                key: ValueKey('session-loading'),
                body: Center(child: CircularProgressIndicator()),
              )
            : _token == null
              ? AuthScreen(
                  key: const ValueKey('sign-in'),
                  baseUrl: _baseUrl,
                  onUpdateBaseUrl: _updateBaseUrl,
                  onAuthenticated: _acceptSession,
                )
              : HealthHome(
                  key: const ValueKey('signed-in'),
                  token: _token!,
                  baseUrl: _baseUrl,
                  user: _user!,
                  onSignOut: _signOut,
                  onUpdateBaseUrl: _updateBaseUrl,
                ),
      ),
    );
  }
}

// ==========================================
// SERVER CONFIGURATION DIALOG
// ==========================================

class ServerConfigDialog extends StatefulWidget {
  const ServerConfigDialog({
    required this.currentUrl,
    required this.onSave,
    super.key,
  });

  final String currentUrl;
  final ValueChanged<String> onSave;

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentUrl);
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final cleanUrl = _controller.text.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await http
          .get(Uri.parse('$cleanUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        setState(() {
          _testSuccess = true;
          _testResult = 'Connected successfully to Beluga Server!';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testResult = 'Server responded with code ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Connection failed: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.dns_outlined, color: Color(0xff176b55)),
          SizedBox(width: 8),
          Text('Server Connection'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the address of your PC server or public tunnel:',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'http://192.168.1.15:8000/api',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text('Emulator', style: TextStyle(fontSize: 11)),
                  onPressed: () => _controller.text = 'http://10.0.2.2:8000/api',
                ),
                ActionChip(
                    label: Text(
                      defaultTargetPlatform == TargetPlatform.macOS ? 'This Mac' : 'Localhost',
                      style: const TextStyle(fontSize: 11),
                    ),
                  onPressed: () => _controller.text = 'http://127.0.0.1:8000/api',
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: const Text('Test Connection'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _testSuccess ? const Color(0xffe8f5e9) : const Color(0xffffebee),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _testSuccess ? const Color(0xff2e7d32) : const Color(0xffc62828),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_controller.text.trim());
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ==========================================
// AUTH SCREEN (GMAIL ID, PASSWORD & GOOGLE)
// ==========================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.baseUrl,
    required this.onUpdateBaseUrl,
    required this.onAuthenticated,
    this.initialRegister = false,
    super.key,
  });

  final String baseUrl;
  final ValueChanged<String> onUpdateBaseUrl;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  final bool initialRegister;

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

  @override
  void initState() {
    super.initState();
    _register = widget.initialRegister;
  }

  Future<void> _signInWithGoogle() async {
    if (googleServerClientId.isEmpty) {
      setState(() => _error = 'Google sign-in is not configured for this build.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final google = GoogleSignIn(
        scopes: const ['email'],
        serverClientId: googleServerClientId,
      );
      final account = await google.signIn();
      if (account == null) return;
      final idToken = (await account.authentication).idToken;
      if (idToken == null) throw Exception('Google did not return a verified sign-in token.');
      final result = await HealthApi(null, baseUrl: widget.baseUrl).signInWithGoogle(idToken);
      if (_register) Navigator.of(context).pop();
      widget.onAuthenticated(result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = HealthApi(null, baseUrl: widget.baseUrl);
      final result = _register
          ? await api.register(
              _name.text.trim(),
              _email.text.trim(),
              _password.text,
            )
          : await api.signIn(_email.text.trim(), _password.text);
          if (_register) Navigator.of(context).pop();
      widget.onAuthenticated(result);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openServerConfig() {
    showDialog(
      context: context,
      builder: (context) => ServerConfigDialog(
        currentUrl: widget.baseUrl,
        onSave: widget.onUpdateBaseUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_register)
                              IconButton(
                                tooltip: 'Back to sign in',
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back),
                              )
                            else
                              const SizedBox(width: 32),
                            const Icon(
                              Icons.monitor_heart_outlined,
                              size: 40,
                              color: Color(0xff176b55),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined, size: 20),
                              tooltip: 'Configure Server Address',
                              onPressed: _openServerConfig,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Beluga Health',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.12),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Text(
                            _register
                                ? 'Create your account with email and password'
                                : 'Sign in with email and password',
                            key: ValueKey(_register),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOutCubic,
                          child: Column(
                            key: ValueKey(_register),
                            children: _register
                                ? [
                                    TextFormField(
                                      controller: _name,
                                      decoration: const InputDecoration(labelText: 'Full name'),
                                      validator: (value) => value == null || value.trim().isEmpty
                                          ? 'Enter your name.'
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                  ]
                                : const [],
                          ),
                        ),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            hintText: 'you@gmail.com',
                          ),
                          validator: (value) => value == null || !value.contains('@')
                              ? 'Enter a valid email address.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The app administrator can view account health records. Do not enter real health data in this prototype.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 11),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Password'),
                          validator: (value) => value == null || value.length < 8
                              ? 'Use at least 8 characters.'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xffffebee),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _busy
                                ? const SizedBox(
                                    key: ValueKey('busy'),
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _register ? 'Create account' : 'Sign in',
                                    key: ValueKey(_register),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (googleServerClientId.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _signInWithGoogle,
                            icon: const Icon(Icons.account_circle_outlined),
                            label: const Text('Continue with Google'),
                          ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  if (_register) {
                                    Navigator.of(context).maybePop();
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    PageRouteBuilder<void>(
                                      transitionDuration: const Duration(milliseconds: 280),
                                      pageBuilder: (context, animation, secondaryAnimation) =>
                                          AuthScreen(
                                        baseUrl: widget.baseUrl,
                                        onUpdateBaseUrl: widget.onUpdateBaseUrl,
                                        onAuthenticated: widget.onAuthenticated,
                                        initialRegister: true,
                                      ),
                                      transitionsBuilder:
                                          (context, animation, secondaryAnimation, child) =>
                                              FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0.04, 0),
                                            end: Offset.zero,
                                          ).animate(CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          )),
                                          child: child,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          child: Text(
                            _register
                                ? 'Already have an account? Sign in'
                                : 'New here? Create an account',
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _openServerConfig,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xfff0f4f2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.wifi_outlined, size: 14, color: Color(0xff176b55)),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Server: ${widget.baseUrl}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xff176b55)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
    );
  }
}

// ==========================================
// HOME NAVIGATION CONTAINER
// ==========================================

class HealthHome extends StatefulWidget {
  const HealthHome({
    required this.token,
    required this.baseUrl,
    required this.user,
    required this.onSignOut,
    required this.onUpdateBaseUrl,
    super.key,
  });

  final String token;
  final String baseUrl;
  final Map<String, dynamic> user;
  final VoidCallback onSignOut;
  final ValueChanged<String> onUpdateBaseUrl;

  @override
  State<HealthHome> createState() => _HealthHomeState();
}

class _HealthHomeState extends State<HealthHome> {
  int _selected = 0;
  late final HealthApi _api = HealthApi(widget.token, baseUrl: widget.baseUrl);
  StreamSubscription<NotificationResponse>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _notificationSubscription = reminderNotificationActions.stream.listen(
      _handleNotificationResponse,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final response = ReminderNotifications.takeLaunchResponse();
      if (response != null) _handleNotificationResponse(response);
    });
    _syncDeviceReminders();
  }

  Future<void> _syncDeviceReminders() async {
    try {
      final results = await Future.wait([
        _api.request('/me'),
        _api.request('/reminders'),
      ]);
      final profile = Map<String, dynamic>.from(results[0]['profile'] ?? {});
      final prescriptions = List<Map<String, dynamic>>.from(
        (profile['prescriptions'] as List? ?? []).map(Map<String, dynamic>.from),
      );
      final reminders = List<Map<String, dynamic>>.from(
        (results[1] as List).map(Map<String, dynamic>.from),
      );
      await ReminderNotifications.sync(prescriptions: prescriptions, reminders: reminders);
    } catch (_) {}
  }

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    if (response.actionId != 'mark_complete' || response.payload == null) return;
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(response.payload!) as Map);
      if (payload['kind'] == 'reminder') {
        await _api.request('/reminders/${payload['id']}/complete', method: 'POST');
      } else if (payload['kind'] == 'prescription') {
        await _api.request(
          '/prescription-completions',
          method: 'POST',
          body: {
            'prescription_id': payload['id'],
            'scheduled_time': payload['time'],
            'completed_on': DateTime.now().toIso8601String().substring(0, 10),
          },
        );
      } else {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder marked complete.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  List<String> get _pages => [
        'Patients',
        'Overview',
        'Health log',
        'Reminders',
        'Profile',
        if (widget.user['is_admin'] == true) 'Admin',
      ];

  List<IconData> get _icons => [
    Icons.people_alt_outlined,
    Icons.home_outlined,
    Icons.monitor_heart_outlined,
    Icons.notifications_outlined,
    Icons.person_outline,
    if (widget.user['is_admin'] == true) Icons.admin_panel_settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final page = switch (_selected) {
      0 => PatientsPage(api: _api),
      1 => OverviewPage(
          api: _api,
          user: widget.user,
          onNavigate: (index) => setState(() => _selected = index),
        ),
      2 => MeasurementPage(api: _api),
      3 => RemindersPage(api: _api),
      4 => ProfilePage(
          api: _api,
          baseUrl: widget.baseUrl,
          onUpdateBaseUrl: widget.onUpdateBaseUrl,
        ),
      5 when widget.user['is_admin'] == true => AdminPage(api: _api),
      _ => const SizedBox.shrink(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pages[_selected],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: widget.onSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _selected,
              onDestinationSelected: (value) => setState(() => _selected = value),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (var i = 0; i < _pages.length; i++)
                  NavigationRailDestination(
                    icon: Icon(_icons[i]),
                    label: Text(_pages[i]),
                  ),
              ],
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              reverseDuration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
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
              destinations: [
                for (var i = 0; i < _pages.length; i++)
                  NavigationDestination(
                    icon: Icon(_icons[i]),
                    label: _pages[i],
                  ),
              ],
            ),
    );
  }
}

// ==========================================
// ADMIN ACCOUNT AND HEALTH RECORDS
// ==========================================

class AdminPage extends StatefulWidget {
  const AdminPage({required this.api, super.key});
  final HealthApi api;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late Future<dynamic> _usersFuture;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _loadUsers() {
    _usersFuture = widget.api.request('/admin/users');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load accounts: ${snapshot.error}'),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => setState(_loadUsers), child: const Text('Retry')),
              ],
            ),
          );
        }
        final users = List<Map<String, dynamic>>.from(snapshot.data ?? []);
        if (users.isEmpty) return const Center(child: Text('No accounts yet.'));
        return RefreshIndicator(
          onRefresh: () async => setState(_loadUsers),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Accounts', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Selecting an account opens its private health records.'),
              const SizedBox(height: 12),
              for (final user in users)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(user['name']?.toString() ?? 'Unnamed account'),
                    subtitle: Text(user['email']?.toString() ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminUserDetailPage(
                          api: widget.api,
                          userId: user['id'] as int,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class AdminUserDetailPage extends StatefulWidget {
  const AdminUserDetailPage({
    required this.api,
    required this.userId,
    super.key,
  });

  final HealthApi api;
  final int userId;

  @override
  State<AdminUserDetailPage> createState() => _AdminUserDetailPageState();
}

class _AdminUserDetailPageState extends State<AdminUserDetailPage> {
  late final Future<dynamic> _detailsFuture =
      widget.api.request('/admin/users/${widget.userId}');

  Widget _recordLine(String label, Object? value) {
    final text = value == null || value.toString().isEmpty ? 'Not provided' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text('$label: $text'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account records')),
      body: FutureBuilder<dynamic>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load records: ${snapshot.error}'));
          }

          final data = Map<String, dynamic>.from(snapshot.data);
          final user = Map<String, dynamic>.from(data['user']);
          final profile = data['profile'] == null
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(data['profile']);
          final measurements = List<Map<String, dynamic>>.from(data['measurements'] ?? []);
          final reminders = List<Map<String, dynamic>>.from(data['reminders'] ?? []);
          final patients = List<Map<String, dynamic>>.from(data['patients'] ?? []);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(user['name']?.toString() ?? '', style: Theme.of(context).textTheme.titleLarge),
              Text(user['email']?.toString() ?? ''),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Profile', style: Theme.of(context).textTheme.titleMedium),
                      _recordLine('Age', profile['age']),
                      _recordLine('Gender', profile['gender']),
                      _recordLine('Blood type', profile['blood_type']),
                      _recordLine('Height (cm)', profile['height_cm']),
                      _recordLine('Weight (kg)', profile['weight_kg']),
                      _recordLine('BMI', profile['bmi']),
                      _recordLine('Location', profile['location']),
                      _recordLine('Conditions', (profile['conditions'] ?? []).join(', ')),
                      _recordLine('Medications', (profile['medications'] ?? []).join(', ')),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Health log (${measurements.length})', style: Theme.of(context).textTheme.titleMedium),
                      for (final item in measurements) ...[
                        const Divider(),
                        _recordLine('Recorded', item['recorded_at']),
                        _recordLine('Steps', item['steps']),
                        _recordLine('Active minutes', item['active_minutes']),
                        _recordLine('Sleep hours', item['sleep_hours']),
                        _recordLine('Fasting glucose', item['fasting_glucose']),
                        _recordLine('Blood pressure', '${item['systolic_bp'] ?? '—'} / ${item['diastolic_bp'] ?? '—'}'),
                      ],
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reminders (${reminders.length})', style: Theme.of(context).textTheme.titleMedium),
                      for (final reminder in reminders)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(reminder['title']?.toString() ?? ''),
                          subtitle: Text('${reminder['scheduled_time'] ?? ''} · ${reminder['instruction'] ?? ''}'),
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Patient records (${patients.length})', style: Theme.of(context).textTheme.titleMedium),
                      for (final patient in patients)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(patient['name']?.toString() ?? ''),
                          subtitle: Text('${patient['patient_id'] ?? ''} · ${patient['age'] ?? ''} years'),
                          children: [
                            _recordLine('Conditions', (patient['chronic_conditions'] ?? []).join(', ')),
                            _recordLine('Allergies', (patient['allergies'] ?? []).join(', ')),
                            _recordLine('Medications', (patient['current_medications'] ?? []).join(', ')),
                            _recordLine('Notes', patient['notes']),
                            for (final visit in List<Map<String, dynamic>>.from(patient['visits'] ?? []))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Visit ${visit['visit_date'] ?? ''}'),
                                subtitle: Text([
                                  visit['chief_complaint'],
                                  visit['diagnosis'],
                                  visit['clinical_notes'],
                                  if ((visit['prescriptions'] ?? []).isNotEmpty)
                                    'Prescriptions: ${(visit['prescriptions'] as List).join(', ')}',
                                ].where((value) => value != null && value.toString().isNotEmpty).join('\n')),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==========================================
// PATIENTS MANAGEMENT PAGE
// ==========================================

class PatientsPage extends StatefulWidget {
  const PatientsPage({required this.api, super.key});
  final HealthApi api;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  final _searchController = TextEditingController();
  late Future<dynamic> _patientsFuture;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  void _loadPatients([String? query]) {
    final path = (query != null && query.trim().isNotEmpty)
        ? '/patients?q=${Uri.encodeComponent(query.trim())}'
        : '/patients';
    setState(() {
      _patientsFuture = widget.api.request(path);
    });
  }

  Future<void> _openAddPatientDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PatientFormDialog(api: widget.api),
    );
    if (result == true) {
      _loadPatients(_searchController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddPatientDialog,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Patient'),
        backgroundColor: const Color(0xff176b55),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search patients by name, ID, phone, condition...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadPatients();
                        },
                      )
                    : null,
              ),
              onChanged: (val) => _loadPatients(val),
            ),
          ),
          Expanded(
            child: FutureBuilder<dynamic>(
              future: _patientsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorPanel(message: snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = List<Map<String, dynamic>>.from(snapshot.data);
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline, size: 56, color: Colors.black38),
                          const SizedBox(height: 14),
                          Text(
                            _searchController.text.isEmpty
                                ? 'No patients in the database yet'
                                : 'No patients match your search',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add a patient to track their medical history, checkups, and vitals for future reference.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _openAddPatientDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Add First Patient'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = list[index];
                    final conditions = List<String>.from(p['chronic_conditions'] ?? []);
                    final visitCount = p['visit_count'] ?? 0;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PatientDetailPage(
                                api: widget.api,
                                patientId: p['patient_id'],
                              ),
                            ),
                          );
                          _loadPatients(_searchController.text);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xffe2ede7),
                                    foregroundColor: const Color(0xff176b55),
                                    child: Text(
                                      (p['name'] as String? ?? 'P')
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['name'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${p['patient_id']} · ${p['age']} yrs · ${p['gender']}${p['blood_group'] != '' ? ' · Blood: ${p['blood_group']}' : ''}',
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xffe8f5e9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$visitCount ${visitCount == 1 ? 'record' : 'records'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xff2e7d32),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (conditions.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: conditions.map((c) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfff5efe6),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xffe4d5c3)),
                                      ),
                                      child: Text(
                                        c,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xff8c5520),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                              if ((p['phone'] as String? ?? '').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.phone_outlined, size: 14, color: Colors.black45),
                                    const SizedBox(width: 6),
                                    Text(
                                      p['phone'],
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// PATIENT DETAIL & FUTURE REFERENCE VISITS
// ==========================================

class PatientDetailPage extends StatefulWidget {
  const PatientDetailPage({
    required this.api,
    required this.patientId,
    super.key,
  });

  final HealthApi api;
  final String patientId;

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  late Future<dynamic> _patientFuture;

  @override
  void initState() {
    super.initState();
    _loadPatient();
  }

  void _loadPatient() {
    setState(() {
      _patientFuture = widget.api.request('/patients/${widget.patientId}');
    });
  }

  Future<void> _editPatient(Map<String, dynamic> patient) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PatientFormDialog(
        api: widget.api,
        existing: patient,
      ),
    );
    if (result == true) _loadPatient();
  }

  Future<void> _deletePatient() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Patient?'),
        content: const Text(
          'Are you sure you want to delete this patient and all their past visit records? This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.api.request('/patients/${widget.patientId}', method: 'DELETE');
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _addVisit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => VisitFormDialog(
        api: widget.api,
        patientId: widget.patientId,
      ),
    );
    if (result == true) _loadPatient();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _patientFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Patient Details')),
            body: ErrorPanel(message: snapshot.error.toString()),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Patient Details')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final patient = Map<String, dynamic>.from(snapshot.data);
        final visits = List<Map<String, dynamic>>.from(patient['visits'] ?? []);
        final conditions = List<String>.from(patient['chronic_conditions'] ?? []);
        final allergies = List<String>.from(patient['allergies'] ?? []);
        final medications = List<String>.from(patient['current_medications'] ?? []);

        return Scaffold(
          appBar: AppBar(
            title: Text(patient['name'] ?? 'Patient Details'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Modify Patient Data',
                onPressed: () => _editPatient(patient),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete Patient',
                onPressed: _deletePatient,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Demographic Profile Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            patient['name'] ?? '',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xff176b55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              patient['patient_id'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _infoItem('Age', '${patient['age']} years'),
                          _infoItem('Gender', patient['gender'] ?? '—'),
                          _infoItem('Blood Group', patient['blood_group'] != '' ? patient['blood_group'] : '—'),
                          if ((patient['phone'] as String? ?? '').isNotEmpty)
                            _infoItem('Phone', patient['phone']),
                          if ((patient['email'] as String? ?? '').isNotEmpty)
                            _infoItem('Email', patient['email']),
                          if ((patient['emergency_contact'] as String? ?? '').isNotEmpty)
                            _infoItem('Emergency Contact', patient['emergency_contact']),
                        ],
                      ),
                      if (allergies.isNotEmpty) ...[
                        const Divider(height: 24),
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                            SizedBox(width: 6),
                            Text('Allergies:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: allergies.map((a) => Chip(
                            label: Text(a, style: const TextStyle(fontSize: 11, color: Colors.red)),
                            backgroundColor: const Color(0xffffebee),
                            visualDensity: VisualDensity.compact,
                          )).toList(),
                        ),
                      ],
                      if (conditions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Chronic Conditions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: conditions.map((c) => Chip(
                            label: Text(c, style: const TextStyle(fontSize: 11)),
                            backgroundColor: const Color(0xfff0f4f2),
                            visualDensity: VisualDensity.compact,
                          )).toList(),
                        ),
                      ],
                      if (medications.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Current Medications:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: medications.map((m) => Chip(
                            label: Text(m, style: const TextStyle(fontSize: 11)),
                            backgroundColor: const Color(0xffe8f0fe),
                            visualDensity: VisualDensity.compact,
                          )).toList(),
                        ),
                      ],
                      if ((patient['notes'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Clinical Notes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(patient['notes'], style: const TextStyle(color: Colors.black87, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Medical History & Records (${visits.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  FilledButton.icon(
                    onPressed: _addVisit,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Record'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff176b55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (visits.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No medical records logged for this patient yet.\nTap "Add Record" to store checkup vitals, complaints, diagnoses, and prescriptions for future reference.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                )
              else
                ...visits.map((v) => _visitCard(v)),
            ],
          ),
        );
      },
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 11)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _visitCard(Map<String, dynamic> visit) {
    final prescriptions = List<String>.from(visit['prescriptions'] ?? []);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_note_outlined, size: 18, color: Color(0xff176b55)),
                    const SizedBox(width: 8),
                    Text(
                      visit['visit_date'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                if ((visit['next_followup'] as String? ?? '').isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xffe0f2f1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Follow-up: ${visit['next_followup']}',
                      style: const TextStyle(fontSize: 11, color: Color(0xff00695c)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if ((visit['chief_complaint'] as String? ?? '').isNotEmpty)
              Text(
                'Complaint: ${visit['chief_complaint']}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            if ((visit['diagnosis'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Diagnosis: ${visit['diagnosis']}',
                  style: const TextStyle(color: Color(0xff176b55), fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(height: 10),
            // Vitals row
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                if (visit['systolic_bp'] != null && visit['diastolic_bp'] != null)
                  _vitalChip('BP', '${visit['systolic_bp']}/${visit['diastolic_bp']} mmHg'),
                if (visit['fasting_glucose'] != null)
                  _vitalChip('Glucose', '${visit['fasting_glucose']} mg/dL'),
                if (visit['heart_rate'] != null)
                  _vitalChip('Heart Rate', '${visit['heart_rate']} bpm'),
                if (visit['temperature'] != null)
                  _vitalChip('Temp', '${visit['temperature']} °C'),
                if (visit['weight_kg'] != null)
                  _vitalChip('Weight', '${visit['weight_kg']} kg'),
              ],
            ),
            if (prescriptions.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Prescriptions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              ...prescriptions.map((rx) => Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.medication_outlined, size: 14, color: Color(0xff176b55)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(rx, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
            ],
            if ((visit['clinical_notes'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                visit['clinical_notes'],
                style: const TextStyle(fontSize: 12, color: Colors.black87, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vitalChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xfff7f8f3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xffe4e9e2)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ==========================================
// PATIENT FORM (ADD & EDIT)
// ==========================================

class PatientFormDialog extends StatefulWidget {
  const PatientFormDialog({required this.api, this.existing, super.key});
  final HealthApi api;
  final Map<String, dynamic>? existing;

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _id = TextEditingController(text: widget.existing?['patient_id'] ?? '');
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _age = TextEditingController(text: widget.existing?['age']?.toString() ?? '');
  late final _phone = TextEditingController(text: widget.existing?['phone'] ?? '');
  late final _email = TextEditingController(text: widget.existing?['email'] ?? '');
  late final _address = TextEditingController(text: widget.existing?['address'] ?? '');
  late final _emergency = TextEditingController(text: widget.existing?['emergency_contact'] ?? '');
  late final _conditions = TextEditingController(
      text: (widget.existing?['chronic_conditions'] as List? ?? []).join(', '));
  late final _allergies = TextEditingController(
      text: (widget.existing?['allergies'] as List? ?? []).join(', '));
  late final _medications = TextEditingController(
      text: (widget.existing?['current_medications'] as List? ?? []).join(', '));
  late final _notes = TextEditingController(text: widget.existing?['notes'] ?? '');

  String _gender = 'Female';
  String _bloodGroup = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _gender = widget.existing!['gender'] ?? 'Female';
      _bloodGroup = widget.existing!['blood_group'] ?? '';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final payload = {
      'patient_id': _id.text.trim().isNotEmpty ? _id.text.trim() : null,
      'name': _name.text.trim(),
      'age': int.tryParse(_age.text.trim()) ?? 0,
      'gender': _gender,
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'blood_group': _bloodGroup,
      'address': _address.text.trim(),
      'emergency_contact': _emergency.text.trim(),
      'chronic_conditions': _conditions.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'allergies': _allergies.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'current_medications': _medications.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'notes': _notes.text.trim(),
    };

    try {
      if (widget.existing == null) {
        await widget.api.request('/patients', method: 'POST', body: payload);
      } else {
        await widget.api.request(
          '/patients/${widget.existing!['patient_id']}',
          method: 'PUT',
          body: payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Modify Patient Data' : 'Add New Patient'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter patient name.' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _id,
                        decoration: const InputDecoration(
                          labelText: 'Patient ID',
                          hintText: 'e.g. PAT-1001 (auto if empty)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Age *'),
                        validator: (v) => v == null || int.tryParse(v) == null ? 'Enter age.' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _gender.isNotEmpty ? _gender : 'Female',
                        decoration: const InputDecoration(labelText: 'Gender'),
                        items: const [
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Other', child: Text('Other')),
                        ],
                        onChanged: (v) => setState(() => _gender = v ?? 'Female'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _bloodGroup.isNotEmpty ? _bloodGroup : '',
                        decoration: const InputDecoration(labelText: 'Blood Group'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('Not known')),
                          DropdownMenuItem(value: 'A+', child: Text('A+')),
                          DropdownMenuItem(value: 'A-', child: Text('A-')),
                          DropdownMenuItem(value: 'B+', child: Text('B+')),
                          DropdownMenuItem(value: 'B-', child: Text('B-')),
                          DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                          DropdownMenuItem(value: 'AB-', child: Text('AB-')),
                          DropdownMenuItem(value: 'O+', child: Text('O+')),
                          DropdownMenuItem(value: 'O-', child: Text('O-')),
                        ],
                        onChanged: (v) => setState(() => _bloodGroup = v ?? ''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone Number'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _emergency,
                        decoration: const InputDecoration(labelText: 'Emergency Contact'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _conditions,
                  decoration: const InputDecoration(
                    labelText: 'Chronic Conditions (comma separated)',
                    hintText: 'Diabetes, Hypertension, Asthma',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _allergies,
                  decoration: const InputDecoration(
                    labelText: 'Allergies (comma separated)',
                    hintText: 'Penicillin, Peanuts',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _medications,
                  decoration: const InputDecoration(
                    labelText: 'Current Medications (comma separated)',
                    hintText: 'Metformin 500mg, Lisinopril 10mg',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Clinical Notes',
                    hintText: 'Patient background or general remarks',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving...' : (isEditing ? 'Save Changes' : 'Create Patient')),
        ),
      ],
    );
  }
}

// ==========================================
// VISIT / CHECKUP FORM (FUTURE REFERENCE)
// ==========================================

class VisitFormDialog extends StatefulWidget {
  const VisitFormDialog({required this.api, required this.patientId, super.key});
  final HealthApi api;
  final String patientId;

  @override
  State<VisitFormDialog> createState() => _VisitFormDialogState();
}

class _VisitFormDialogState extends State<VisitFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final _complaint = TextEditingController();
  final _diagnosis = TextEditingController();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _glucose = TextEditingController();
  final _heartRate = TextEditingController();
  final _temperature = TextEditingController();
  final _weight = TextEditingController();
  final _prescriptions = TextEditingController();
  final _notes = TextEditingController();
  final _followup = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final payload = {
      'visit_date': _date.text.trim(),
      'chief_complaint': _complaint.text.trim(),
      'diagnosis': _diagnosis.text.trim(),
      'systolic_bp': int.tryParse(_systolic.text.trim()),
      'diastolic_bp': int.tryParse(_diastolic.text.trim()),
      'fasting_glucose': double.tryParse(_glucose.text.trim()),
      'heart_rate': int.tryParse(_heartRate.text.trim()),
      'temperature': double.tryParse(_temperature.text.trim()),
      'weight_kg': double.tryParse(_weight.text.trim()),
      'prescriptions': _prescriptions.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'clinical_notes': _notes.text.trim(),
      'next_followup': _followup.text.trim().isNotEmpty ? _followup.text.trim() : null,
    };

    try {
      await widget.api.request(
        '/patients/${widget.patientId}/visits',
        method: 'POST',
        body: payload,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Medical Checkup / Record'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _date,
                        decoration: const InputDecoration(labelText: 'Visit Date (YYYY-MM-DD) *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required.' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _followup,
                        decoration: const InputDecoration(labelText: 'Next Follow-up (optional)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _complaint,
                  decoration: const InputDecoration(labelText: 'Chief Complaint / Symptoms *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _diagnosis,
                  decoration: const InputDecoration(labelText: 'Diagnosis / Assessment'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _systolic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Systolic BP (mmHg)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _diastolic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Diastolic BP (mmHg)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _glucose,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Glucose (mg/dL)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _heartRate,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Heart Rate (bpm)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _temperature,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Temperature (°C)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Weight (kg)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _prescriptions,
                  decoration: const InputDecoration(
                    labelText: 'Prescriptions (comma separated)',
                    hintText: 'e.g. Paracetamol 500mg tid, Amoxicillin 250mg',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Clinical Notes / Instructions'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving...' : 'Save Record'),
        ),
      ],
    );
  }
}

// ==========================================
// OVERVIEW PAGE
// ==========================================

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    required this.api,
    required this.user,
    required this.onNavigate,
    super.key,
  });

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
        final patientsCount = data['patients_count'] ?? 0;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Hello, ${user['name'] ?? data['name']}',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text('Clinical & Personal Health Management Space.'),
            const SizedBox(height: 18),

            // Quick patient action card
            Card(
              color: const Color(0xffe8f5e9),
              child: ListTile(
                leading: const Icon(Icons.people_alt, color: Color(0xff176b55), size: 32),
                title: Text('$patientsCount Patients in Database',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('View, modify, and track patient records & visits'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => onNavigate(0),
              ),
            ),
            const SizedBox(height: 14),
            RoutineGuide(profile: profile),
            const SizedBox(height: 14),

            Wrap(spacing: 12, runSpacing: 12, children: [
              AnimatedReveal(
                  index: 0,
                  child: MetricCard(
                      label: 'Steps',
                      value: latest['steps']?.toString() ?? '—',
                      icon: Icons.directions_walk)),
              AnimatedReveal(
                  index: 1,
                  child: MetricCard(
                      label: 'Active minutes',
                      value: latest['active_minutes']?.toString() ?? '—',
                      icon: Icons.bolt_outlined)),
              AnimatedReveal(
                  index: 2,
                  child: MetricCard(
                      label: 'Sleep hours',
                      value: latest['sleep_hours']?.toString() ?? '—',
                      icon: Icons.bedtime_outlined)),
              AnimatedReveal(
                  index: 3,
                  child: MetricCard(
                      label: 'BMI',
                      value: profile['bmi']?.toString() ?? '—',
                      icon: Icons.monitor_weight_outlined)),
            ]),
            const SizedBox(height: 16),
            AnimatedReveal(
              index: 4,
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Log personal health measurements'),
                  subtitle: const Text('Steps, sleep, glucose, or blood pressure'),
                  onTap: () => onNavigate(2),
                ),
              ),
            ),
            AnimatedReveal(
              index: 5,
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Manage daily reminders'),
                  subtitle: const Text('View and update your schedule'),
                  onTap: () => onNavigate(3),
                ),
              ),
            ),
            if (dataset != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Sample dataset: ${dataset['record_count']} records; ${dataset['diabetes_count']} diabetes labels; ${dataset['hypertension_count']} hypertension labels. Stored in local database for reference.',
                  ),
                ),
              ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Health readings and records are stored in your private local PC database for patient reference. Always consult qualified clinical specialists for medical decisions.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class RoutineGuide extends StatelessWidget {
  const RoutineGuide({required this.profile, super.key});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final routine = profile['daily_routine']?.toString().trim() ?? '';
    final appetite = profile['appetite']?.toString().trim() ?? '';
    final prescriptions = profile['prescriptions'] as List? ?? [];
    final conditions = profile['conditions'] as List? ?? [];
    final familyHistory = profile['family_history']?.toString().trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily wellness routine', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'General routine prompts only. This app does not diagnose or prescribe treatment.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Divider(height: 20),
            _routineLine(
              Icons.restaurant_outlined,
              'Meals',
              appetite.isEmpty
                  ? 'Plan regular meals that suit your appetite; ask your care team about condition-specific diet needs.'
                  : 'Appetite notes: $appetite. Follow any diet guidance from your clinician or dietitian.',
            ),
            _routineLine(
              Icons.schedule_outlined,
              'Your daily rhythm',
              routine.isEmpty
                  ? 'Add your usual routine in Account & Profile to keep your schedule notes in one place.'
                  : routine,
            ),
            _routineLine(
              Icons.medication_outlined,
              'Prescriptions',
              prescriptions.isEmpty
                  ? 'Add medicines exactly as prescribed to schedule reminders.'
                  : 'Reminders use the medicine names, quantities, and times you entered from your doctor’s instructions. Do not change a prescription based on this app.',
            ),
            if (conditions.isNotEmpty || familyHistory.isNotEmpty)
              _routineLine(
                Icons.health_and_safety_outlined,
                'Health context',
                'Your health and family-history notes are saved for reference; they are not used to generate a diagnosis or treatment plan.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _routineLine(IconData icon, String title, String message) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: const Color(0xff176b55)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(message, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
}

class AnimatedReveal extends StatelessWidget {
  const AnimatedReveal({required this.index, required this.child, super.key});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        duration: Duration(milliseconds: 300 + (index * 60)),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: 1),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
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
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}

// ==========================================
// HEALTH LOG PAGE
// ==========================================

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
      values[entry.key] = const {
        'steps',
        'active_minutes',
        'systolic_bp',
        'diastolic_bp',
      }.contains(entry.key)
          ? parsed?.toInt()
          : parsed?.toDouble();
    }
    values.removeWhere((_, value) => value == null);
    if (values.isEmpty) {
      setState(() => _message = 'Enter at least one measurement.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.request('/measurements', method: 'POST', body: values);
      for (final controller in _controllers.values) {
        controller.clear();
      }
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
          Text('Today’s Health Log', style: Theme.of(context).textTheme.headlineSmall),
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
          const Text('Enter personal measurements you have to monitor trends.'),
          if (_message != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save check-in'),
          ),
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

// ==========================================
// REMINDERS PAGE
// ==========================================

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
    _reminders = _loadAndSyncReminders();
  }

  Future<dynamic> _loadAndSyncReminders() async {
    final results = await Future.wait([
      widget.api.request('/reminders'),
      widget.api.request('/me'),
    ]);
    final profile = Map<String, dynamic>.from(results[1]['profile'] ?? {});
    await ReminderNotifications.sync(
      prescriptions: List<Map<String, dynamic>>.from(
        (profile['prescriptions'] as List? ?? []).map(Map<String, dynamic>.from),
      ),
      reminders: List<Map<String, dynamic>>.from(
        (results[0] as List).map(Map<String, dynamic>.from),
      ),
    );
    return results[0];
  }

  void _reloadReminders() {
    setState(() => _reminders = _loadAndSyncReminders());
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
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Reminder title'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Enter a title.' : null,
              ),
              TextFormField(
                controller: time,
                decoration: const InputDecoration(labelText: 'Time (HH:MM)'),
                validator: (value) => value == null ||
                        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)
                    ? 'Use 24-hour time, e.g. 08:30.'
                    : null,
              ),
              TextFormField(
                controller: instruction,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await widget.api.request(
        '/reminders',
        method: 'POST',
        body: {
          'title': title.text.trim(),
          'scheduled_time': time.text.trim(),
          'instruction': instruction.text.trim(),
        },
      );
      await ReminderNotifications.requestPermission();
      _reloadReminders();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _complete(int id) async {
    try {
      await widget.api.request('/reminders/$id/complete', method: 'POST');
      _reloadReminders();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _delete(int id) async {
    try {
      await widget.api.request('/reminders/$id', method: 'DELETE');
      _reloadReminders();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _enableNotifications() async {
    await ReminderNotifications.requestPermission();
    _reloadReminders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification permission requested.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: _reminders,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final items = List<Map<String, dynamic>>.from(snapshot.data);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _enableNotifications,
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Enable notifications'),
                    ),
                    FilledButton.icon(
                      onPressed: _addReminder,
                      icon: const Icon(Icons.add),
                      label: const Text('Add reminder'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No reminders yet. Add one to start your daily routine.'),
                  ),
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: IconButton(
                      tooltip: 'Mark complete',
                      onPressed: item['completed_today'] == 1 || item['completed_today'] == true
                          ? null
                          : () => _complete(item['id']),
                      icon: Icon(
                        item['completed_today'] == 1 || item['completed_today'] == true
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                      ),
                    ),
                    title: Text(item['title']),
                    subtitle: Text('${item['scheduled_time']}  ${item['instruction'] ?? ''}'),
                    trailing: IconButton(
                      tooltip: 'Delete reminder',
                      onPressed: () => _delete(item['id']),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Reminders are stored in your database.'),
              ),
            ],
          );
        },
      );
}

// ==========================================
// PROFILE PAGE
// ==========================================

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    required this.api,
    required this.baseUrl,
    required this.onUpdateBaseUrl,
    super.key,
  });

  final HealthApi api;
  final String baseUrl;
  final ValueChanged<String> onUpdateBaseUrl;

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

  void _openServerConfig() {
    showDialog(
      context: context,
      builder: (context) => ServerConfigDialog(
        currentUrl: widget.baseUrl,
        onSave: widget.onUpdateBaseUrl,
      ),
    );
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
          return ProfileForm(
            api: widget.api,
            user: user,
            profile: profile,
            baseUrl: widget.baseUrl,
            onOpenServerConfig: _openServerConfig,
            onSaved: () => setState(() => _profile = widget.api.request('/me')),
          );
        },
      );
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    required this.api,
    required this.user,
    required this.profile,
    required this.baseUrl,
    required this.onOpenServerConfig,
    required this.onSaved,
    super.key,
  });

  final HealthApi api;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final String baseUrl;
  final VoidCallback onOpenServerConfig;
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
  late final _conditions =
      TextEditingController(text: (widget.profile['conditions'] as List? ?? []).join(', '));
  late final _medications =
      TextEditingController(text: (widget.profile['medications'] as List? ?? []).join(', '));
  late final _appetite = TextEditingController(text: widget.profile['appetite'] ?? '');
  late final _dailyRoutine = TextEditingController(text: widget.profile['daily_routine'] ?? '');
  late final _familyHistory = TextEditingController(text: widget.profile['family_history'] ?? '');
  late List<Map<String, dynamic>> _prescriptions = List<Map<String, dynamic>>.from(
    (widget.profile['prescriptions'] as List? ?? []).map(
      (item) => Map<String, dynamic>.from(item),
    ),
  );
  late String _profileImage = widget.profile['profile_image'] ?? '';
  String _gender = '';
  String _bloodType = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _gender = widget.profile['gender'] ?? '';
    _bloodType = widget.profile['blood_type'] ?? '';
  }

  Future<void> _pickProfileImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      imageQuality: 78,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (bytes.length > 1_000_000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a smaller profile image.')),
        );
      }
      return;
    }
    setState(() => _profileImage = 'data:image/jpeg;base64,${base64Encode(bytes)}');
  }

  Future<void> _editPrescription({Map<String, dynamic>? prescription}) async {
    final name = TextEditingController(text: prescription?['name']?.toString() ?? '');
    final dose = TextEditingController(text: prescription?['prescribed_dose']?.toString() ?? '');
    final quantity = TextEditingController(text: prescription?['quantity']?.toString() ?? '');
    final times = TextEditingController(
      text: ((prescription?['intake_times'] as List?) ?? []).join(', '),
    );
    final instructions = TextEditingController(text: prescription?['instructions']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(prescription == null ? 'Add prescribed medicine' : 'Edit prescribed medicine'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Medicine name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the name from the prescription.'
                      : null,
                ),
                TextFormField(
                  controller: dose,
                  decoration: const InputDecoration(labelText: 'Doctor-prescribed dose'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the dose as written by the doctor.'
                      : null,
                ),
                TextFormField(
                  controller: quantity,
                  decoration: const InputDecoration(labelText: 'Quantity per intake'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the prescribed quantity per intake.'
                      : null,
                ),
                TextFormField(
                  controller: times,
                  decoration: const InputDecoration(
                    labelText: 'Intake times',
                    hintText: '08:00, 20:00',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Enter at least one time.';
                    final parsed = value.split(',').map((item) => item.trim());
                    return parsed.every((item) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(item))
                        ? null
                        : 'Use 24-hour times, separated by commas.';
                  },
                ),
                TextField(
                  controller: instructions,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Doctor instructions'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'id': prescription?['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
                'name': name.text.trim(),
                'prescribed_dose': dose.text.trim(),
                'quantity': quantity.text.trim(),
                'intake_times': times.text
                    .split(',')
                    .map((item) => item.trim())
                    .toList(),
                'instructions': instructions.text.trim(),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    dose.dispose();
    quantity.dispose();
    times.dispose();
    instructions.dispose();
    if (result == null || !mounted) return;
    setState(() {
      final index = _prescriptions.indexWhere((item) => item['id'] == result['id']);
      if (index == -1) {
        _prescriptions = [..._prescriptions, result];
      } else {
        _prescriptions[index] = result;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.request(
        '/profile',
        method: 'PUT',
        body: {
          'name': _name.text.trim(),
          'age': int.tryParse(_age.text),
          'gender': _gender,
          'blood_type': _bloodType,
          'height_cm': double.tryParse(_height.text),
          'weight_kg': double.tryParse(_weight.text),
          'location': _location.text.trim(),
          'conditions': _conditions.text
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
          'medications': _medications.text
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
              'appetite': _appetite.text.trim(),
              'daily_routine': _dailyRoutine.text.trim(),
              'family_history': _familyHistory.text.trim(),
              'prescriptions': _prescriptions,
              'profile_image': _profileImage,
        },
      );
      await ReminderNotifications.requestPermission();
      final reminders = await widget.api.request('/reminders');
      await ReminderNotifications.sync(prescriptions: _prescriptions, reminders: List<Map<String, dynamic>>.from(
        (reminders as List).map(Map<String, dynamic>.from),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile saved.')));
      }
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _location.dispose();
    _conditions.dispose();
    _medications.dispose();
    _appetite.dispose();
    _dailyRoutine.dispose();
    _familyHistory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundImage: _profileImage.isEmpty
                      ? null
                      : MemoryImage(base64Decode(_profileImage.split(',').last)),
                  child: _profileImage.isEmpty ? const Icon(Icons.person_outline, size: 38) : null,
                ),
                TextButton.icon(
                  onPressed: _pickProfileImage,
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Choose profile photo'),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Account & Profile', style: Theme.of(context).textTheme.headlineSmall),
              OutlinedButton.icon(
                onPressed: widget.onOpenServerConfig,
                icon: const Icon(Icons.dns, size: 16),
                label: const Text('Server Settings'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Connected to: ${widget.baseUrl}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
            enabled: false,
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email / Gmail ID'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Age'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _gender.isEmpty ? null : _gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Prefer not to say')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Non-binary', child: Text('Non-binary')),
              DropdownMenuItem(value: 'Self-describe', child: Text('Self-describe')),
            ],
            onChanged: (value) => setState(() => _gender = value ?? ''),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _bloodType.isEmpty ? null : _bloodType,
            decoration: const InputDecoration(labelText: 'Blood type'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not provided')),
              for (final value in ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() => _bloodType = value ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Height (cm)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Weight (kg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _conditions,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Personal Health Conditions (comma-separated)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _medications,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Current Medications (comma-separated)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _appetite,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Appetite and meal preferences'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dailyRoutine,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Daily routine and usual meal times'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _familyHistory,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Family health history'),
          ),
          const SizedBox(height: 20),
          Text('Doctor-prescribed medicines', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final prescription in _prescriptions)
            Card(
              child: ListTile(
                title: Text(prescription['name']?.toString() ?? ''),
                subtitle: Text([
                  if ((prescription['prescribed_dose'] ?? '').toString().isNotEmpty)
                    prescription['prescribed_dose'],
                  if ((prescription['quantity'] ?? '').toString().isNotEmpty)
                    'Quantity: ${prescription['quantity']}',
                  if ((prescription['intake_times'] as List? ?? []).isNotEmpty)
                    (prescription['intake_times'] as List).join(', '),
                  if ((prescription['instructions'] ?? '').toString().isNotEmpty)
                    prescription['instructions'],
                ].join(' · ')),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Edit prescription details',
                      onPressed: () => _editPrescription(prescription: prescription),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Remove prescription',
                      onPressed: () => setState(() => _prescriptions.remove(prescription)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _editPrescription(),
              icon: const Icon(Icons.add),
              label: const Text('Add from doctor prescription'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save profile'),
          ),
        ],
      );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: Colors.black45),
              const SizedBox(height: 12),
              const Text(
                'Could not connect to the health server.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}