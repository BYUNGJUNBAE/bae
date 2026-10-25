import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const LaptopRemoteApp());

class LaptopRemoteApp extends StatelessWidget {
  const LaptopRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '노트북 리모컨',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class Settings {
  String host = '';
  String token = '';
  String mac = '';
  String broadcast = '255.255.255.255';
  int port = 8765;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    host = p.getString('host') ?? '';
    token = p.getString('token') ?? '';
    mac = p.getString('mac') ?? '';
    broadcast = p.getString('broadcast') ?? '255.255.255.255';
    port = p.getInt('port') ?? 8765;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('host', host);
    await p.setString('token', token);
    await p.setString('mac', mac);
    await p.setString('broadcast', broadcast);
    await p.setInt('port', port);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final settings = Settings();
  String status = '확인 중...';
  bool online = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    settings.load().then((_) => _refresh());
  }

  Uri _uri(String path) =>
      Uri.parse('http://${settings.host}:${settings.port}$path');

  Map<String, String> get _headers => {'X-Token': settings.token};

  Future<void> _refresh() async {
    if (settings.host.isEmpty) {
      setState(() {
        online = false;
        status = '설정에서 노트북 주소를 입력하세요';
      });
      return;
    }
    try {
      final r = await http
          .get(_uri('/status'), headers: _headers)
          .timeout(const Duration(seconds: 4));
      final ok = r.statusCode == 200;
      if (ok) await _learnWiredInfo(jsonDecode(r.body) as Map<String, dynamic>);
      setState(() {
        online = ok;
        status = ok
            ? '켜짐 (${jsonDecode(r.body)['host']})'
            : '인증 실패 (토큰 확인)';
      });
    } catch (_) {
      setState(() {
        online = false;
        status = '응답 없음 (꺼짐/절전 또는 연결 불가)';
      });
    }
  }

  // 에이전트가 알려준 유선 MAC/브로드캐스트를 저장해 두면 꺼진 뒤에도 켜기에 쓸 수 있다
  Future<void> _learnWiredInfo(Map<String, dynamic> body) async {
    final mac = body['mac'] as String?;
    final bc = body['broadcast'] as String?;
    if (mac == null || mac.isEmpty) return;
    if (mac == settings.mac && (bc == null || bc == settings.broadcast)) return;
    settings.mac = mac;
    if (bc != null && bc.isNotEmpty) settings.broadcast = bc;
    await settings.save();
  }

  Future<void> _send(String action, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$label 하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('확인')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      final r = await http
          .post(_uri('/$action'), headers: _headers)
          .timeout(const Duration(seconds: 6));
      _toast(r.statusCode == 200 ? '$label 명령 전송됨' : '실패 (${r.statusCode})');
    } catch (e) {
      _toast('전송 실패: 노트북에 연결할 수 없습니다');
    }
    setState(() => busy = false);
    await Future.delayed(const Duration(seconds: 3));
    _refresh();
  }

  Future<void> _wake() async {
    final mac = settings.mac.replaceAll(RegExp(r'[:\-\s]'), '');
    if (!RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(mac)) {
      _toast('설정에서 MAC 주소를 확인하세요');
      return;
    }
    final bytes = <int>[
      ...List.filled(6, 0xFF),
      ...List.generate(6, (i) => int.parse(mac.substring(i * 2, i * 2 + 2), radix: 16)),
    ];
    final packet = [...bytes.sublist(0, 6), for (var i = 0; i < 16; i++) ...bytes.sublist(6)];
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final targets = {settings.broadcast, '255.255.255.255'};
      for (final t in targets) {
        for (final port in [9, 7]) {
          socket.send(packet, InternetAddress(t), port);
        }
      }
      socket.close();
      _toast('깨우기 신호 전송됨 (집 공유기 안에서만 도달)');
    } catch (e) {
      _toast('신호 전송 실패');
    }
    await Future.delayed(const Duration(seconds: 8));
    _refresh();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(settings: settings)),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('노트북 리모컨'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.circle, color: online ? Colors.green : cs.outline),
              title: Text(status),
            ),
          ),
          const SizedBox(height: 16),
          _btn(Icons.power_settings_new, '켜기 (Wake-on-LAN)', _wake, busy: busy, primary: true),
          _btn(Icons.stop_circle_outlined, '완전 종료', () => _send('shutdown', '완전 종료'), busy: busy),
          _btn(Icons.bedtime_outlined, '최대 절전', () => _send('hibernate', '최대 절전'), busy: busy),
          _btn(Icons.nightlight_outlined, '절전', () => _send('sleep', '절전'), busy: busy),
          _btn(Icons.restart_alt, '재시작', () => _send('restart', '재시작'), busy: busy),
          _btn(Icons.cancel_outlined, '종료/재시작 취소', () => _send('cancel', '취소'), busy: busy),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {required bool busy, bool primary = false}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(icon), const SizedBox(width: 8), Text(label)],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 56,
        child: primary
            ? FilledButton(onPressed: busy ? null : onTap, child: child)
            : OutlinedButton(onPressed: busy ? null : onTap, child: child),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final Settings settings;
  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final host = TextEditingController(text: widget.settings.host);
  late final port = TextEditingController(text: widget.settings.port.toString());
  late final token = TextEditingController(text: widget.settings.token);
  late final mac = TextEditingController(text: widget.settings.mac);
  late final broadcast = TextEditingController(text: widget.settings.broadcast);

  Future<void> _save() async {
    final s = widget.settings;
    s.host = host.text.trim();
    s.port = int.tryParse(port.text.trim()) ?? 8765;
    s.token = token.text.trim();
    s.mac = mac.text.trim();
    s.broadcast = broadcast.text.trim();
    await s.save();
    if (mounted) Navigator.pop(context);
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('노트북 주소', host, hint: 'Tailscale IP 예: 100.x.x.x'),
          _field('포트', port),
          _field('토큰', token, obscure: true),
          _field('노트북 MAC 주소', mac, hint: 'AA:BB:CC:DD:EE:FF'),
          _field('브로드캐스트 주소', broadcast, hint: '예: 192.168.0.255'),
          FilledButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
    );
  }
}
