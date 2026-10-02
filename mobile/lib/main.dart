import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api',
);

const secureStorage = FlutterSecureStorage();

class HealthApi {
  HealthApi(this.token, {this.baseUrl});

  final String? token;
  final String? baseUrl;

  String get activeBaseUrl => (baseUrl != null && baseUrl!.trim().isNotEmpty)
      ? baseUrl!.trim().replaceAll(RegExp(r'/+$'), '')
      : defaultApiBaseUrl;

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

  Future<Map<String, dynamic>> googleAuth({
    String? idToken,
    String? email,
    String? name,
  }) async =>
      Map<String, dynamic>.from(await request('/auth/google', method: 'POST', body: {
        if (idToken != null) 'id_token': idToken,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
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
  String _baseUrl = defaultApiBaseUrl;
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
      home: _checkingSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _token == null
              ? AuthScreen(
                  baseUrl: _baseUrl,
                  onUpdateBaseUrl: _updateBaseUrl,
                  onAuthenticated: _acceptSession,
                )
              : HealthHome(
                  token: _token!,
                  baseUrl: _baseUrl,
                  user: _user!,
                  onSignOut: _signOut,
                  onUpdateBaseUrl: _updateBaseUrl,
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
                  label: const Text('Localhost', style: TextStyle(fontSize: 11)),
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
    super.key,
  });

  final String baseUrl;
  final ValueChanged<String> onUpdateBaseUrl;
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
      final api = HealthApi(null, baseUrl: widget.baseUrl);
      final result = _register
          ? await api.register(
              _name.text.trim(),
              _email.text.trim(),
              _password.text,
            )
          : await api.signIn(_email.text.trim(), _password.text);
      widget.onAuthenticated(result);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogleDialog() async {
    final googleEmail = TextEditingController(text: _email.text);
    final googleName = TextEditingController(text: _name.text);
    final formKey = GlobalKey<FormState>();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_circle, color: Color(0xff4285F4)),
            SizedBox(width: 8),
            Text('Sign in with Google'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter your Gmail ID to sign in or create your account instantly:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: googleEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Gmail address',
                  hintText: 'username@gmail.com',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Enter your Gmail ID.';
                  }
                  if (!val.contains('@')) return 'Enter a valid email address.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: googleName,
                decoration: const InputDecoration(
                  labelText: 'Full name (optional)',
                  hintText: 'e.g. John Doe',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (accepted != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = HealthApi(null, baseUrl: widget.baseUrl);
      final result = await api.googleAuth(
        email: googleEmail.text.trim(),
        name: googleName.text.trim().isNotEmpty ? googleName.text.trim() : null,
      );
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
                        Text(
                          _register
                              ? 'Create your account with your Gmail ID'
                              : 'Sign in with your Gmail ID & password',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        if (_register) ...[
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Full name'),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter your name.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Gmail / Email ID',
                            hintText: 'you@gmail.com',
                          ),
                          validator: (value) => value == null || !value.contains('@')
                              ? 'Enter a valid Gmail or email address.'
                              : null,
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
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_register ? 'Create account' : 'Sign in'),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _signInWithGoogleDialog,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          icon: Image.network(
                            'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                            height: 20,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.account_circle, color: Color(0xff4285F4)),
                          ),
                          label: const Text(
                            'Continue with Google',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _register = !_register;
                                    _error = null;
                                  }),
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

  final _pages = const ['Patients', 'Overview', 'Health log', 'Reminders', 'Profile'];
  final _icons = const [
    Icons.people_alt_outlined,
    Icons.home_outlined,
    Icons.monitor_heart_outlined,
    Icons.notifications_outlined,
    Icons.person_outline,
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
      _ => ProfilePage(
          api: _api,
          baseUrl: widget.baseUrl,
          onUpdateBaseUrl: widget.onUpdateBaseUrl,
        ),
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
              duration: const Duration(milliseconds: 250),
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
      setState(() => _reminders = widget.api.request('/reminders'));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _complete(int id) async {
    try {
      await widget.api.request('/reminders/$id/complete', method: 'POST');
      setState(() => _reminders = widget.api.request('/reminders'));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _delete(int id) async {
    try {
      await widget.api.request('/reminders/$id', method: 'DELETE');
      setState(() => _reminders = widget.api.request('/reminders'));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
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
                child: FilledButton.icon(
                  onPressed: _addReminder,
                  icon: const Icon(Icons.add),
                  label: const Text('Add reminder'),
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
        },
      );
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
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
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