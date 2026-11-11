import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

part 'native_modules.dart';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _bg = Color(0xFF0D111A);
const _card = Color(0xFF191F2C);
const _red = Color(0xFFE9474B);
const _muted = Color(0xFFA5B0C2);
const _green = Color(0xFF4BD5A2);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HrmsApp());
}

String _str(Object? v, [String fallback = '—']) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return {};
}

List<Map<String, dynamic>> _items(Object? response) {
  final data = response is Map ? response['data'] : response;
  if (data is! List) return [];
  return data.map((e) => _map(e)).toList();
}

String _humanError(Object e) => e.toString().replaceFirst('Exception: ', '');

class Api {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final http.Client _client = http.Client();
  String baseUrl = 'https://myhrms.rconsoft.com/api/mobile/v1';
  String token = '';

  Future<void> restore() async {
    baseUrl = await _storage.read(key: 'api_base_url') ?? baseUrl;
    token = await _storage.read(key: 'api_token') ?? '';
  }

  Future<void> saveLogin(String url, String value) async {
    baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    token = value;
    await _storage.write(key: 'api_base_url', value: baseUrl);
    await _storage.write(key: 'api_token', value: token);
  }

  Future<void> clear() async {
    token = '';
    await _storage.delete(key: 'api_token');
  }

  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    if (!baseUrl.startsWith('https://')) {
      throw Exception('HTTPS server URL is required.');
    }
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    if (data != null) headers['Content-Type'] = 'application/json';
    http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await _client.post(uri, headers: headers, body: jsonEncode(data ?? {}))
              .timeout(const Duration(seconds: 25));
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: headers).timeout(const Duration(seconds: 25));
          break;
        case 'PATCH':
          response = await _client.patch(uri, headers: headers, body: jsonEncode(data ?? {}))
              .timeout(const Duration(seconds: 25));
          break;
        default:
          response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 25));
          break;
      }
    } on TimeoutException {
      throw Exception('Connection timed out. Check internet and Laravel API.');
    } catch (e) {
      throw Exception('Unable to connect to server: $e');
    }
    Map<String, dynamic> json = {};
    try {
      json = _map(jsonDecode(response.body));
    } catch (_) {
      if (response.statusCode == 404) {
        throw Exception('API route missing (HTTP 404). Upload the Laravel API files first.');
      }
      throw Exception('Server returned HTTP ${response.statusCode}. Check Laravel logs.');
    }
    if (response.statusCode >= 400) {
      String message = _str(json['message'], 'HTTP ${response.statusCode}');
      if (json['errors'] is Map) {
        final first = (json['errors'] as Map).values.firstOrNull;
        if (first is List && first.isNotEmpty) message = '$message\n${first.first}';
      }
      throw Exception(message);
    }
    return json;
  }

  void dispose() => _client.close();
}

class HrmsApp extends StatelessWidget {
  const HrmsApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RCONSOFT HRMS',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(seedColor: _red, brightness: Brightness.dark),
        appBarTheme: const AppBarTheme(backgroundColor: _bg, foregroundColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: _card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF303746))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _red, width: 1.5)),
        ),
        cardTheme: CardThemeData(color: _card, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
            minimumSize: const Size(100, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
        navigationBarTheme: const NavigationBarThemeData(backgroundColor: _card),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final Api api = Api();
  bool restoring = true;
  bool loggedIn = false;
  bool busy = false;
  int tab = 0;
  int refreshEpoch = 0;
  String? error;
  Map<String, dynamic> user = {};
  Map<String, dynamic> subscription = {};

  bool get isSuper => user['role'] == 'super_admin';
  bool get isManager => ['company_admin', 'admin', 'manager', 'hr'].contains(user['role']);
  bool get canRequestPlan => ['company_admin', 'admin'].contains(user['role']);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      await api.restore();
      if (api.token.isNotEmpty) {
        final response = await api.call('/me');
        user = _map(response['user']);
        subscription = _map(response['subscription']);
        loggedIn = true;
      }
    } catch (_) {
      await api.clear();
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  Future<void> _login(String server, String email, String password) async {
    final url = server.trim().replaceAll(RegExp(r'/+$'), '');
    if (!url.startsWith('https://')) {
      setState(() => error = 'Server must use HTTPS.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      api.baseUrl = url;
      final result = await api.call('/login', method: 'POST', data: {
        'email': email.trim(), 'password': password, 'device_name': 'RCONSOFT HRMS Android',
      });
      final token = _str(result['token'], '');
      if (token.isEmpty) throw Exception('Login succeeded but no API token was returned.');
      await api.saveLogin(url, token);
      if (!mounted) return;
      setState(() {
        user = _map(result['user']);
        subscription = _map(result['subscription']);
        tab = 0; loggedIn = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = _humanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _logout() async {
    try { await api.call('/logout', method: 'POST'); } catch (_) {}
    await api.clear();
    if (mounted) setState(() { loggedIn = false; tab = 0; user = {}; subscription = {}; error = null; });
  }

  void _message(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!loggedIn) return _LoginView(busy: busy, error: error, server: api.baseUrl, onSubmit: _login);
    if (user['must_change_password'] == true) {
      return Scaffold(appBar:AppBar(title:const Text('Set a new password')),
        body:_PasswordPage(api:api,onMessage:_message,onChanged:()async {
          try{final r=await api.call('/me');if(mounted)setState(()=>user=_map(r['user']));}
          catch(e){_message(_humanError(e));}
        }));
    }
    final sections = isSuper
        ? <_Section>[
            const _Section('Overview', Icons.dashboard_rounded),
            const _Section('Tenants', Icons.apartment_rounded),
            const _Section('Approvals', Icons.verified_user_rounded),
            const _Section('Account', Icons.person_rounded),
          ]
        : <_Section>[
            const _Section('Overview', Icons.dashboard_rounded),
            const _Section('Leads', Icons.groups_rounded),
            const _Section('Tasks', Icons.check_circle_outline_rounded),
            const _Section('More', Icons.grid_view_rounded),
          ];
    final pages = isSuper
        ? <Widget>[
            _DashboardPage(api: api, superAdmin: true),
            _TenantsPage(api: api, onMessage: _message),
            _ApprovalsPage(api: api, onMessage: _message),
            ListView(padding:const EdgeInsets.all(18),children:[
              const _Title('Platform Account'),const SizedBox(height:14),
              _AccountPage(user:user,subscription:subscription,onLogout:_logout,embedded:true),
              const SizedBox(height:12),
              _MenuTile(icon:Icons.manage_accounts,label:'Edit profile',onTap:()=>_openNative(context,
                _ProfileSettings(api:api,onMessage:_message),'My profile')),
              _MenuTile(icon:Icons.lock_reset,label:'Change password',onTap:()=>_openNative(context,
                _PasswordPage(api:api,onMessage:_message),'Change password')),
            ]),
          ]
        : <Widget>[
            _DashboardPage(api: api, superAdmin: false),
            isManager ? _LeadsPage(api: api, onMessage: _message)
                : _ListPage(api: api, title: 'My attendance', endpoint: '/attendance', icon: Icons.schedule,
                    itemBuilder: (item, reload) => _AttendanceTile(item: item)),
            _TasksPage(api: api, isManager: isManager, onMessage: _message),
            _MorePage(api: api, user: user, subscription: subscription,
                isManager: isManager, canRequestPlan: canRequestPlan, onLogout: _logout, onMessage: _message),
          ];
    final width = MediaQuery.sizeOf(context).width;
    final nav = NavigationBar(
      height: 70,
      selectedIndex: tab,
      onDestinationSelected: (index) => setState(() => tab = index),
      destinations: sections.map((e) => NavigationDestination(icon: Icon(e.icon), label: e.label)).toList(),
    );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(children: [
          const _Logo(size: 32),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RCONSOFT', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
            Text(isSuper ? 'Super Admin Console' : _str(user['company_name'], 'HRMS & CRM'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _muted)),
          ])),
        ]),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: () => setState(() => refreshEpoch++), icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: width >= 800 ? null : nav,
      body: width >= 800
          ? Row(children: [
              NavigationRail(
                extended: width >= 1100,
                backgroundColor: _card,
                destinations: sections.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.label))).toList(),
                selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i),
              ),
              Expanded(child: KeyedSubtree(key: ValueKey('page-$tab-$refreshEpoch'), child: pages[tab])),
            ])
          : KeyedSubtree(key: ValueKey('page-$tab-$refreshEpoch'), child: pages[tab]),
    );
  }
}

class _Section {
  final String label;
  final IconData icon;
  const _Section(this.label, this.icon);
}

class _Logo extends StatelessWidget {
  final double size;
  const _Logo({this.size = 70});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(size * .28),
        boxShadow: const [BoxShadow(color: Color(0x33E9474B), blurRadius: 26, offset: Offset(0, 7))]),
    alignment: Alignment.center,
    child: Text('R', style: TextStyle(fontSize: size * .58, color: Colors.white, fontWeight: FontWeight.w900)),
  );
}

class _LoginView extends StatefulWidget {
  final bool busy;
  final String? error;
  final String server;
  final Future<void> Function(String, String, String) onSubmit;
  const _LoginView({required this.busy, required this.error, required this.server, required this.onSubmit});
  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  late final TextEditingController server = TextEditingController(text: widget.server);
  final email = TextEditingController();
  final password = TextEditingController();
  bool showPassword = false;
  bool showServer = false;
  @override
  void dispose() { server.dispose(); email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _Logo()), const SizedBox(height: 22),
          const Text('Your workspace,\nwherever you work.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 9),
          const Text('HRMS + CRM  •  Secure multi-tenant access', textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 30),
          _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Welcome back', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Use the same login as your Laravel HRMS website.', style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 20),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.alternate_email))),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: !showPassword, autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(onPressed: () => setState(() => showPassword = !showPassword),
                        icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility)))),
            if (showServer) ...[
              const SizedBox(height: 12),
              TextField(controller: server, keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'HTTPS API base URL', prefixIcon: Icon(Icons.dns_outlined))),
            ],
            Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => setState(() => showServer = !showServer),
                  child: Text(showServer ? 'Hide server settings' : 'API server settings')),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 8),
              Text(widget.error!, style: const TextStyle(color: Color(0xFFFF8585), fontSize: 13)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: widget.busy ? null : () => widget.onSubmit(server.text, email.text, password.text),
                icon: widget.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login), label: const Text('Sign in securely')),
          ])),
          const SizedBox(height: 22),
          const Text('Your company data remains on its own MySQL database.\nOnly HTTPS API requests are sent by the app.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 11, height: 1.5)),
        ],
      )),
    ))));
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(17)});
  @override
  Widget build(BuildContext context) => Container(padding: padding,
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A3140), width: .7)), child: child);
}

class _Title extends StatelessWidget {
  final String text;
  final String? subtitle;
  const _Title(this.text, {this.subtitle});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(text, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
    if (subtitle != null) ...[const SizedBox(height: 4),
      Text(subtitle!, style: const TextStyle(color: _muted, fontSize: 12))],
  ]);
}

class _DashboardPage extends StatefulWidget {
  final Api api;
  final bool superAdmin;
  const _DashboardPage({required this.api, required this.superAdmin});
  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  Map<String, dynamic> data = {};
  String? error;
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.api.call(widget.superAdmin ? '/super-admin/dashboard' : '/dashboard');
      if (mounted) setState(() => data = result);
    } catch (e) { if (mounted) setState(() => error = _humanError(e)); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    final summary = _map(data['summary']);
    final keys = summary.entries.toList();
    return RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 36), children: [
      _Title(widget.superAdmin ? 'Platform overview' : 'Workspace overview',
          subtitle: widget.superAdmin ? 'Manage all your customer workspaces' : 'Live information from your company database'),
      const SizedBox(height: 22),
      if (loading) const LinearProgressIndicator(minHeight: 3),
      if (error != null) _ErrorPanel(error: error!, retry: load),
      if (!loading && error == null) ...[
        LayoutBuilder(builder: (context, constraints) {
          final cols = constraints.maxWidth < 440 ? 2 : (constraints.maxWidth < 800 ? 3 : 4);
          return GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: keys.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 12,
                mainAxisSpacing: 12, childAspectRatio: 1.38),
            itemBuilder: (context, i) {
              final item = keys[i];
              final icons = [Icons.people_alt_rounded, Icons.query_stats, Icons.task_alt, Icons.wallet_outlined,
                Icons.event_available, Icons.trending_up];
              return _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(icons[i % icons.length], color: i.isEven ? _red : _green, size: 22),
                Text(_str(item.value, '0'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                Text(item.key.replaceAll('_',' ').toUpperCase(), style: const TextStyle(fontSize: 10, color: _muted, letterSpacing: .7)),
              ]));
            },
          );
        }),
        const SizedBox(height: 24),
        if (!widget.superAdmin) ...[
          const Text('Recent work', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._items(data['recent_tasks']).take(4).map((task) => Padding(
            padding: const EdgeInsets.only(bottom: 9), child: _Panel(child: Row(children: [
              const Icon(Icons.check_circle_outline, color: _red), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_str(task['title']), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_str(task['status']), style: const TextStyle(color: _muted, fontSize: 12)),
              ])),
            ])),
          )),
          if (_items(data['recent_tasks']).isEmpty)
            const _Panel(child: Text('No recent tasks yet.', style: TextStyle(color: _muted))),
        ],
      ],
    ]));
  }
}

class _ErrorPanel extends StatelessWidget {
  final String error;
  final Future<void> Function() retry;
  const _ErrorPanel({required this.error, required this.retry});
  @override
  Widget build(BuildContext context) => _Panel(child: Column(children: [
    const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF8585), size: 35),
    const SizedBox(height: 10), Text(error, textAlign: TextAlign.center),
    const SizedBox(height: 10), TextButton(onPressed: retry, child: const Text('Retry')),
  ]));
}

typedef _TileBuilder = Widget Function(Map<String, dynamic> item, Future<void> Function() reload);

class _ListPage extends StatefulWidget {
  final Api api;
  final String title;
  final String endpoint;
  final IconData icon;
  final _TileBuilder itemBuilder;
  final Widget? header;
  const _ListPage({super.key, required this.api, required this.title, required this.endpoint,
    required this.icon, required this.itemBuilder, this.header});
  @override
  State<_ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<_ListPage> {
  List<Map<String,dynamic>> items = [];
  bool loading = true;
  String? error;
  int page=1; int lastPage=1;
  bool loadingMore=false;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() {loading = true; error = null;page=1;});
    try {
      final data = await widget.api.call(widget.endpoint);
      if (mounted) setState(() {
        items = _items(data);
        page = int.tryParse(_str(data['current_page'],'1'))??1;
        lastPage = int.tryParse(_str(data['last_page'],'1'))??1;
      });
    } catch (e) { if (mounted) setState(() => error = _humanError(e)); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> loadMore()async {
    if(loadingMore||page>=lastPage)return;
    setState(()=>loadingMore=true);
    try{
      final next=page+1;
      final sep=widget.endpoint.contains('?')?'&':'?';
      final data=await widget.api.call('${widget.endpoint}${sep}page=$next');
      if(mounted)setState((){
        items.addAll(_items(data));
        page=next;
      });
    }catch(e){if(mounted)setState(()=>error=_humanError(e));}
    finally{if(mounted)setState(()=>loadingMore=false);}
  }
  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: load,
    child: ListView(padding: const EdgeInsets.fromLTRB(18,18,18,40), children: [
      _Title(widget.title, subtitle: '${items.length} records shown • Pull to refresh'),
      if (widget.header != null) ...[const SizedBox(height: 14), widget.header!],
      const SizedBox(height: 18),
      if (loading) const LinearProgressIndicator(),
      if (error != null) _ErrorPanel(error: error!, retry: load),
      if (!loading && items.isEmpty && error == null)
        _Panel(child: Row(children: [Icon(widget.icon, color: _muted), const SizedBox(width: 12),
          const Expanded(child: Text('No records yet.', style: TextStyle(color: _muted)))])),
      ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 10),
          child: widget.itemBuilder(item, load))),
      if(page<lastPage)Padding(padding:const EdgeInsets.only(top:12),child:
        OutlinedButton.icon(onPressed:loadingMore?null:loadMore,
          icon:loadingMore?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):
            const Icon(Icons.expand_more),label:Text('Load more • Page $page/$lastPage'))),
    ]));
}

class _CompanyTile extends StatelessWidget {
  final Map<String,dynamic> item;
  const _CompanyTile({required this.item});
  @override
  Widget build(BuildContext context) => _Panel(child: Row(children: [
    const CircleAvatar(backgroundColor: Color(0x33E9474B), child: Icon(Icons.apartment, color: _red)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_str(item['name']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      Text(_str(item['slug']), style: const TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 4),
      Text(item['database_ready_at'] == null ? 'Database pending initialization' : 'Database ready',
          style: TextStyle(fontSize: 11, color: item['database_ready_at'] == null ? Colors.orange : _green)),
    ])),
    Icon(item['is_active'] == true ? Icons.check_circle : Icons.pause_circle,
        color: item['is_active'] == true ? _green : Colors.orange),
  ]));
}

class _LeadsPage extends StatefulWidget {
  final Api api;
  final void Function(String) onMessage;
  const _LeadsPage({required this.api, required this.onMessage});
  @override
  State<_LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<_LeadsPage> {
  final key = GlobalKey<_ListPageState>();
  @override
  Widget build(BuildContext context) => Stack(children: [
    _ListPage(key: key, api: widget.api, title: 'CRM leads', endpoint: '/leads', icon: Icons.groups,
        itemBuilder: (item, reload) => _Panel(child: InkWell(
          onTap: () => _editLead(item, reload),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(_str(item['name']),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              _Chip(label: _str(item['stage']))]),
            const SizedBox(height: 5),
            Text(_str(item['company_name']), style: const TextStyle(color: _muted)),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.phone_outlined, size: 14, color: _muted),
              const SizedBox(width: 4), Expanded(child: Text(_str(item['phone']), style: const TextStyle(fontSize: 12))),
              const Icon(Icons.currency_rupee, size: 14, color: _red),
              Text(_str(item['value'],'0'), style: const TextStyle(fontWeight: FontWeight.bold))]),
          ]),
        ))),
    Positioned(right: 18, bottom: 18, child: FloatingActionButton.extended(
      heroTag: 'lead_add', backgroundColor: _red, foregroundColor: Colors.white,
      onPressed: () => _editLead(null, () => key.currentState?.load() ?? Future<void>.value()),
      label: const Text('New lead'), icon: const Icon(Icons.add))),
  ]);

  Future<void> _editLead(Map<String,dynamic>? item, Future<void> Function() reload) async {
    final name=TextEditingController(text: _str(item?['name'],''));
    final company=TextEditingController(text: _str(item?['company_name'],''));
    final phone=TextEditingController(text: _str(item?['phone'],''));
    final email=TextEditingController(text: _str(item?['email'],''));
    final value=TextEditingController(text: _str(item?['value'],'0'));
    final notes=TextEditingController(text: _str(item?['notes'],''));
    final source=TextEditingController(text:_str(item?['source'],''));
    final followup=TextEditingController(text:_str(item?['next_follow_up'],'').split('T').first);
    final assigned=TextEditingController(text:_str(item?['assigned_to'],''));
    final due=TextEditingController(text:_str(item?['due_date'],'').split('T').first);
    String stage = _str(item?['stage'], 'New');
    const stages = ['New','Contacted','Qualified','Proposal','Negotiation','Won','Lost'];
    if (!stages.contains(stage)) stage = 'New';
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: _card,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => Padding(
        padding: EdgeInsets.only(left: 18,right: 18,top: 20,bottom: MediaQuery.viewInsetsOf(ctx).bottom+22),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(item==null?'New CRM lead':'Edit CRM lead', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 17),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Client name *')),
          const SizedBox(height: 9), TextField(controller: company, decoration: const InputDecoration(labelText: 'Company')),
          const SizedBox(height: 9), TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 9), TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 9), TextField(controller: value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Deal value (₹)')),
          const SizedBox(height: 9), TextField(controller:source,decoration:const InputDecoration(labelText:'Lead source')),
          const SizedBox(height: 9), TextField(controller:assigned,decoration:const InputDecoration(labelText:'Assigned to')),
          const SizedBox(height: 9), TextField(controller:followup,decoration:const InputDecoration(labelText:'Next follow-up YYYY-MM-DD')),
          const SizedBox(height: 9), TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(value: stage, decoration: const InputDecoration(labelText: 'Stage'),
            items: stages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => redraw(() => stage=v??'New')),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () async {
            if(name.text.trim().isEmpty) {widget.onMessage('Client name required');return;}
            try {
              await widget.api.call(item==null?'/leads':'/leads/${item['id']}',method:item==null?'POST':'PATCH', data:{
                'name':name.text.trim(),'company_name':company.text.trim(),
                'phone':phone.text.trim().isEmpty?null:phone.text.trim(),
                'email':email.text.trim().isEmpty?null:email.text.trim(),
                'value':double.tryParse(value.text)??0,'stage':stage,
                'source':source.text.trim().isEmpty?null:source.text.trim(),
                'assigned_to':assigned.text.trim().isEmpty?null:assigned.text.trim(),
                'next_follow_up':followup.text.trim().isEmpty?null:followup.text.trim(),
                'notes':notes.text.trim().isEmpty?null:notes.text.trim(),
              });
              if(ctx.mounted) Navigator.pop(ctx);
              await reload();widget.onMessage('Lead saved');
            } catch(e) {widget.onMessage(_humanError(e));}
          }, child: const Text('Save lead'))),
          if(item!=null)...[const SizedBox(height:10),
            OutlinedButton.icon(onPressed:()async{
              if(!await _confirmAction(ctx,'Delete CRM lead','This permanently deletes this lead.'))return;
              try{await widget.api.call('/leads/${item['id']}',method:'DELETE');
                if(ctx.mounted)Navigator.pop(ctx);await reload();widget.onMessage('Lead deleted');}
              catch(e){widget.onMessage(_humanError(e));}
            },icon:const Icon(Icons.delete_outline),label:const Text('Delete lead'))],
        ])),
      )));
    name.dispose(); company.dispose(); phone.dispose(); email.dispose(); value.dispose(); notes.dispose();source.dispose();followup.dispose();assigned.dispose();
  }
}

class _TasksPage extends StatefulWidget {
  final Api api;
  final bool isManager;
  final void Function(String) onMessage;
  const _TasksPage({required this.api, required this.isManager, required this.onMessage});
  @override
  State<_TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<_TasksPage> {
  final key=GlobalKey<_ListPageState>();
  @override
  Widget build(BuildContext context) => Stack(children: [
    _ListPage(key:key, api:widget.api,title: widget.isManager?'Team tasks':'My tasks',endpoint:'/tasks',icon:Icons.checklist,
      itemBuilder: (item,reload) => _Panel(child: InkWell(onTap: () => _editTask(item,reload), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,children: [
          Row(children: [Expanded(child: Text(_str(item['title']),style: const TextStyle(fontSize:15,fontWeight:FontWeight.w800))),
            _Chip(label:_str(item['priority']))]),
          const SizedBox(height:6),
          Text(_str(item['description']), maxLines:2,overflow:TextOverflow.ellipsis,style: const TextStyle(color:_muted,fontSize:12)),
          const SizedBox(height:12),
          Row(children: [const Icon(Icons.event,size:15,color:_muted), const SizedBox(width:5),
            Expanded(child:Text(_str(item['due_date']),style: const TextStyle(color:_muted,fontSize:12))),
            _Chip(label:_str(item['status']))]),
        ]))),
    ),
    if(widget.isManager) Positioned(right:18,bottom:18,child:FloatingActionButton.extended(
      heroTag:'task_add',onPressed:()=>_editTask(null,()=>key.currentState?.load()??Future<void>.value()),
      backgroundColor:_red,foregroundColor:Colors.white,icon:const Icon(Icons.add),label:const Text('New task'))),
  ]);

  Future<void> _editTask(Map<String,dynamic>? item, Future<void> Function() reload) async {
    final title=TextEditingController(text:_str(item?['title'],''));
    final description=TextEditingController(text:_str(item?['description'],''));
    final assigned=TextEditingController(text:_str(item?['assigned_to'],''));
    String status=_str(item?['status'],'Open'),priority=_str(item?['priority'],'Medium');
    const statuses=['Open','In Progress','Blocked','Completed'];
    const priorities=['Low','Medium','High','Urgent'];
    if(!statuses.contains(status))status='Open';
    if(!priorities.contains(priority))priority='Medium';
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:_card,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,redraw)=>Padding(
      padding:EdgeInsets.only(left:18,right:18,top:18,bottom:MediaQuery.viewInsetsOf(ctx).bottom+20),
      child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(item==null?'Create task':'Update task',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
        const SizedBox(height:16),
        if(widget.isManager) ...[
          TextField(controller:title,decoration:const InputDecoration(labelText:'Task title *')),
          const SizedBox(height:10),
          TextField(controller:description,maxLines:2,decoration:const InputDecoration(labelText:'Description')),
          const SizedBox(height:10),
          TextField(controller:assigned,decoration:const InputDecoration(labelText:'Assigned to (employee code or name)')),
          const SizedBox(height:10),TextField(controller:due,decoration:const InputDecoration(labelText:'Due date YYYY-MM-DD')),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(value:priority,decoration:const InputDecoration(labelText:'Priority'),
            items:priorities.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
            onChanged:(v)=>redraw(()=>priority=v??'Medium')),
          const SizedBox(height:10),
        ],
        DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Status'),
          items:statuses.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
          onChanged:(v)=>redraw(()=>status=v??'Open')),
        const SizedBox(height:16),
        SizedBox(width:double.infinity,child:FilledButton(onPressed:() async {
          try {
            final path = widget.isManager
                ? (item==null?'/tasks':'/tasks/${item['id']}')
                : '/tasks/${item?['id']}/my-status';
            await widget.api.call(path, method:widget.isManager?(item==null?'POST':'PATCH'):'PATCH',
              data:widget.isManager?{'title':title.text.trim(),'description':description.text.trim(),
                'assigned_to':assigned.text.trim(),'due_date':due.text.trim().isEmpty?null:due.text.trim(),'priority':priority,'status':status}
                :{'status':status});
            if(ctx.mounted)Navigator.pop(ctx);
            await reload();widget.onMessage('Task updated');
          }catch(e){widget.onMessage(_humanError(e));}
        },child:const Text('Save task'))),
        if(widget.isManager&&item!=null)...[const SizedBox(height:10),
          OutlinedButton.icon(onPressed:()async{
            if(!await _confirmAction(ctx,'Delete task','This permanently deletes the task.'))return;
            try{await widget.api.call('/tasks/${item['id']}',method:'DELETE');
              if(ctx.mounted)Navigator.pop(ctx);await reload();widget.onMessage('Task deleted');}
            catch(e){widget.onMessage(_humanError(e));}
          },icon:const Icon(Icons.delete_outline),label:const Text('Delete Task'))],
      ])),
    )));
    title.dispose();description.dispose();assigned.dispose();due.dispose();
  }
}

class _AttendanceTile extends StatelessWidget {
  final Map<String,dynamic> item;
  const _AttendanceTile({required this.item});
  @override
  Widget build(BuildContext context)=>_Panel(child:Row(children:[
    const CircleAvatar(backgroundColor:Color(0x334BD5A2),child:Icon(Icons.event_available,color:_green)),
    const SizedBox(width:10),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(_str(item['work_date']),style:const TextStyle(fontWeight:FontWeight.w700)),
      Text('In: ${_str(item['check_in'])}  |  Out: ${_str(item['check_out'])}',
        style:const TextStyle(color:_muted,fontSize:11),maxLines:2),
    ])),
    _Chip(label:_str(item['status'])),
  ]));
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});
  @override
  Widget build(BuildContext context) => Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),
    decoration:BoxDecoration(color:const Color(0x2A4BD5A2),borderRadius:BorderRadius.circular(20)),
    child:Text(label,style:const TextStyle(color:_green,fontSize:11,fontWeight:FontWeight.w700)));
}

class _MorePage extends StatelessWidget {
  final Api api;
  final Map<String,dynamic> user,subscription;
  final bool isManager,canRequestPlan;
  final Future<void> Function() onLogout;
  final void Function(String) onMessage;
  const _MorePage({required this.api,required this.user,required this.subscription,
    required this.isManager,required this.canRequestPlan,required this.onLogout,required this.onMessage});
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.fromLTRB(18,20,18,28),children:[
    const _Title('Workspace tools',subtitle:'People, attendance, leaves and billing'),
    const SizedBox(height:16),
    _Panel(child:Column(children:[
      if(isManager) _MenuTile(icon:Icons.badge_outlined,label:'Employees',onTap:()=>_open(context,
        _EmployeesPage(api:api,onMessage:onMessage))),
      if(isManager) _MenuTile(icon:Icons.cake_outlined,label:'Employee Birthdays',onTap:()=>_open(context,
        _BirthdaysPage(api:api))),
      if(isManager) _MenuTile(icon:Icons.bar_chart_outlined,label:'Reports & Export',onTap:()=>_open(context,
        _ReportsPage(api:api,onMessage:onMessage))),
      if(!isManager) _MenuTile(icon:Icons.auto_graph,label:'My Performance',onTap:()=>_open(context,
        _PerformancePage(api:api))),
      _MenuTile(icon:Icons.watch_later_outlined,label:'Attendance',onTap:()=>_open(context,
        _AttendancePage(api:api,isManager:isManager,onMessage:onMessage))),
      _MenuTile(icon:Icons.event_note_outlined,label:'Leave requests',onTap:()=>_open(context,
        _LeavePage(api:api,isManager:isManager,onMessage:onMessage))),
      _MenuTile(icon:Icons.workspace_premium_outlined,label:'Plans & subscription',onTap:()=>_open(context,
        _BillingPage(api:api,canRequest:canRequestPlan,onMessage:onMessage))),
      _MenuTile(icon:Icons.manage_accounts_outlined,label:'Edit Profile',onTap:()=>_open(context,
        _ProfileSettings(api:api,onMessage:onMessage))),
      _MenuTile(icon:Icons.lock_reset,label:'Change Password',onTap:()=>_open(context,
        _PasswordPage(api:api,onMessage:onMessage))),
    ])),
    const SizedBox(height:16),
    _AccountPage(user:user,subscription:subscription,onLogout:onLogout,embedded:true),
  ]);
  void _open(BuildContext ctx,Widget screen){Navigator.of(ctx).push(MaterialPageRoute(builder:(_)=>Scaffold(
    appBar:AppBar(title:const Text('RCONSOFT HRMS')),body:screen)));}
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuTile({required this.icon,required this.label,required this.onTap});
  @override
  Widget build(BuildContext context)=>ListTile(leading:Icon(icon,color:_red),title:Text(label),
    trailing:const Icon(Icons.chevron_right_rounded,color:_muted),onTap:onTap);
}

class _AttendancePage extends StatefulWidget {
  final Api api;
  final bool isManager;
  final void Function(String) onMessage;
  const _AttendancePage({required this.api,required this.isManager,required this.onMessage});
  @override
  State<_AttendancePage> createState()=>_AttendancePageState();
}
class _AttendancePageState extends State<_AttendancePage> {
  final key=GlobalKey<_ListPageState>();
  @override
  Widget build(BuildContext context)=>_ListPage(key:key,api:widget.api,title:'Attendance',endpoint:'/attendance',
    icon:Icons.schedule,itemBuilder:(item,reload)=>_AttendanceTile(item:item),
    header:_Panel(child:Column(children:[
      const Text('Record today’s attendance',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:9),
      Row(children:[
        Expanded(child:FilledButton(onPressed:()=>_punch('check-in'),child:const Text('Check in'))),
        const SizedBox(width:10),
        Expanded(child:OutlinedButton(onPressed:()=>_punch('check-out'),child:const Text('Check out'))),
      ]),
      if(widget.isManager) const Padding(padding:EdgeInsets.only(top:10),child:Text(
        'Managers select an employee ID; employee logins record their own attendance.',
        style:TextStyle(color:_muted,fontSize:11))),
    ])));
  Future<void> _punch(String kind) async {
    final data=<String,dynamic>{};
    if(widget.isManager){
      final id=TextEditingController();
      final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Employee ID'),content:TextField(controller:id,keyboardType:TextInputType.number,
          decoration:const InputDecoration(labelText:'Numeric employee ID')),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,id.text),child:const Text('Continue'))]));
      id.dispose();
      final employeeId=int.tryParse(result??'');if(employeeId==null)return;
      data['employee_id']=employeeId;
    }
    try {await widget.api.call('/attendance/$kind',method:'POST',data:data);
      await key.currentState?.load();widget.onMessage(kind=='check-in'?'Checked in successfully':'Checked out successfully');
    }catch(e){widget.onMessage(_humanError(e));}
  }
}

class _LeavePage extends StatefulWidget {
  final Api api;
  final bool isManager;
  final void Function(String) onMessage;
  const _LeavePage({required this.api,required this.isManager,required this.onMessage});
  @override
  State<_LeavePage> createState()=>_LeavePageState();
}
class _LeavePageState extends State<_LeavePage>{
  final key=GlobalKey<_ListPageState>();
  @override
  Widget build(BuildContext context)=>_ListPage(key:key,api:widget.api,title:'Leave requests',endpoint:'/leaves',icon:Icons.event_busy,
    header:Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:_request,
      icon:const Icon(Icons.add),label:const Text('Apply leave'))),
    itemBuilder:(item,reload)=>_Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text(_str(item['leave_type']),style:const TextStyle(fontWeight:FontWeight.w800))),
        _Chip(label:_str(item['status']))]),
      const SizedBox(height:6),
      Text('${_str(item['start_date'])}  →  ${_str(item['end_date'])}',style:const TextStyle(color:_muted)),
      if(widget.isManager&&item['status']=='Pending') Align(alignment:Alignment.centerRight,
        child:Wrap(spacing:8,children:[
          TextButton(onPressed:()=>_review(item,'Approved',reload),child:const Text('Approve')),
          TextButton(onPressed:()=>_review(item,'Rejected',reload),child:const Text('Reject')),
        ])),
    ])));
  Future<void> _review(Map<String,dynamic> item,String status,Future<void> Function() reload) async {
    try {await widget.api.call('/leaves/${item['id']}/review',method:'PATCH',data:{'status':status});
      await reload();widget.onMessage('Leave $status');
    } catch(e){widget.onMessage(_humanError(e));}
  }
  Future<void> _request() async {
    final start=TextEditingController();final end=TextEditingController();
    final reason=TextEditingController();final employee=TextEditingController();
    String type='Casual';
    await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,redraw)=>AlertDialog(
      title:const Text('Request leave'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:type,items:const ['Annual','Sick','Casual','Unpaid','Other']
          .map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),
          onChanged:(v)=>redraw(()=>type=v??'Casual'),decoration:const InputDecoration(labelText:'Leave type')),
        const SizedBox(height:8),TextField(controller:start,decoration:const InputDecoration(labelText:'Start date YYYY-MM-DD')),
        const SizedBox(height:8),TextField(controller:end,decoration:const InputDecoration(labelText:'End date YYYY-MM-DD')),
        if(widget.isManager)...[const SizedBox(height:8),TextField(controller:employee,
            keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Employee ID *'))],
        const SizedBox(height:8),TextField(controller:reason,decoration:const InputDecoration(labelText:'Reason')),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
        FilledButton(onPressed:() async {
          final data=<String,dynamic>{'leave_type':type,'start_date':start.text.trim(),
            'end_date':end.text.trim(),'reason':reason.text.trim()};
          if(widget.isManager)data['employee_id']=int.tryParse(employee.text);
          try{await widget.api.call('/leaves',method:'POST',data:data);
            if(ctx.mounted)Navigator.pop(ctx);
            await key.currentState?.load();widget.onMessage('Leave request sent');
          }catch(e){widget.onMessage(_humanError(e));}
        },child:const Text('Submit'))],
    )));
    start.dispose();end.dispose();reason.dispose();employee.dispose();
  }
}

class _BillingPage extends StatefulWidget {
  final Api api;
  final bool canRequest;
  final void Function(String) onMessage;
  const _BillingPage({required this.api,required this.canRequest,required this.onMessage});
  @override
  State<_BillingPage> createState()=>_BillingPageState();
}
class _BillingPageState extends State<_BillingPage>{
  Map<String,dynamic> data={};String? error;bool loading=true;
  int plan=3;
  @override
  void initState(){super.initState();load();}
  Future<void> load()async{
    setState((){loading=true;error=null;});
    try{final result=await widget.api.call('/subscription');if(mounted)setState(()=>data=result);}
    catch(e){if(mounted)setState(()=>error=_humanError(e));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override
  Widget build(BuildContext context){
    final status=_map(data['status']);
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(18),children:[      const _Title('Subscription & trial',subtitle:'Approval managed manually by RCONSOFT'),
      const SizedBox(height:16),if(loading)const LinearProgressIndicator(),
      if(error!=null)_ErrorPanel(error:error!,retry:load),
      if(!loading&&error==null)...[
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('CURRENT STATUS',style:TextStyle(color:_muted,fontSize:11)),const SizedBox(height:8),
          Text(_str(status['label']),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
          Text('Until: ${_str(status['until'])}',style:const TextStyle(color:_muted)),
        ])),
        if(widget.canRequest)...[
          const SizedBox(height:18),const Text('Choose a plan',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
          const SizedBox(height:10),
          Wrap(spacing:8,runSpacing:8,children:[3,6,9,12].map((months)=>ChoiceChip(
            label:Text('$months months'),selected:plan==months,onSelected:(_)=>setState(()=>plan=months))).toList()),
          const SizedBox(height:12),
          FilledButton(onPressed:()async{
            try{await widget.api.call('/subscription/request',method:'POST',data:{'plan_months':plan});
              widget.onMessage('Submitted for RCONSOFT approval');await load();
            }catch(e){widget.onMessage(_humanError(e));}
          },child:const Text('Submit for review')),
          const Text('No online payment is collected by this app.',style:TextStyle(color:_muted,fontSize:11)),
        ],
        const SizedBox(height:20),
        const Text('Request history',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        ..._items(data['requests']).map((r)=>Padding(padding:const EdgeInsets.only(bottom:8),
          child:_Panel(child:Row(children:[Expanded(child:Text('${_str(r['plan_months'])} months')),
            _Chip(label:_str(r['status']))])))),
        if(_items(data['requests']).isEmpty)const Text('No requests submitted.',style:TextStyle(color:_muted)),
      ],
    ]));
  }
}

class _ApprovalsPage extends StatefulWidget{
  final Api api;final void Function(String) onMessage;
  const _ApprovalsPage({required this.api,required this.onMessage});
  @override
  State<_ApprovalsPage> createState()=>_ApprovalsPageState();
}
class _ApprovalsPageState extends State<_ApprovalsPage>{
  final key=GlobalKey<_ListPageState>();
  @override
  Widget build(BuildContext context)=>_ListPage(key:key,api:widget.api,title:'Pending approvals',
    endpoint:'/super-admin/subscriptions',icon:Icons.verified_user,
    itemBuilder:(item,reload)=>_Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(_str(_map(item['company'])['name']),style:const TextStyle(fontSize:15,fontWeight:FontWeight.w800)),
      const SizedBox(height:5),Text('${_str(item['plan_months'])}-month subscription',
        style:const TextStyle(color:_muted)),
      const SizedBox(height:8),Row(children:[
        Expanded(child:OutlinedButton(onPressed:()=>_review(item,'rejected',reload),child:const Text('Reject'))),
        const SizedBox(width:10),
        Expanded(child:FilledButton(onPressed:()=>_review(item,'approved',reload),child:const Text('Approve'))),
      ]),
    ])));
  Future<void> _review(Map<String,dynamic> item,String decision,Future<void> Function() reload)async{
    final confirmation=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('${decision=='approved'?'Approve':'Reject'} subscription?'),
      content:Text('${_str(_map(item['company'])['name'])} • ${_str(item['plan_months'])} months'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]));
    if(confirmation!=true)return;
    try{await widget.api.call('/super-admin/subscriptions/${item['id']}/review',method:'POST',data:{'decision':decision});
      await reload();widget.onMessage('Subscription $decision');
    }catch(e){widget.onMessage(_humanError(e));}
  }
}

class _AccountPage extends StatelessWidget {
  final Map<String,dynamic> user,subscription;
  final Future<void> Function() onLogout;
  final bool embedded;
  const _AccountPage({required this.user,required this.subscription,required this.onLogout,this.embedded=false});
  @override
  Widget build(BuildContext context)=>embedded?_body():ListView(padding:const EdgeInsets.all(18),children:[
    const _Title('Your account'),const SizedBox(height:15),_body(),
  ]);
  Widget _body()=>_Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[const CircleAvatar(backgroundColor:Color(0x33E9474B),radius:26,
      child:Icon(Icons.person,color:_red)),const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(_str(user['name']),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:17)),
        Text(_str(user['email']),style:const TextStyle(color:_muted,fontSize:12)),
      ]))]),
    const Divider(height:28),
    Text('Role: ${_str(user['role'])}',style:const TextStyle(color:_muted)),
    Text('Company: ${_str(user['company_name'],'RCONSOFT Platform')}',style:const TextStyle(color:_muted)),
    const SizedBox(height:15),
    SizedBox(width:double.infinity,child:OutlinedButton.icon(
      onPressed:onLogout,icon:const Icon(Icons.logout),label:const Text('Sign out'))),
  ]));
}