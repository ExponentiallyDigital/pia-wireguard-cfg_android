// main.dart
// PIA WireGuard Config Generator -- Flutter Android APK
// GUI equivalent of https://github.com/ExponentiallyDigital/pia-wireguard-cfg

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'pia_service.dart';

void main() {
  runApp(const PiaWgApp());
}

class PiaWgApp extends StatelessWidget {
  const PiaWgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PIA WireGuard Config',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4AA),
          secondary: Color(0xFF00A882),
          surface: Color(0xFF1A1D23),
          error: Color(0xFFFF5C5C),
          onPrimary: Color(0xFF12141A),
          onSurface: Color(0xFFE8EAF0),
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2128),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2E3240)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2E3240)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF00D4AA), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF8892A4)),
          hintStyle: const TextStyle(color: Color(0xFF4A5268)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D4AA),
            foregroundColor: const Color(0xFF12141A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _service = PiaService();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _dnsCtrl = TextEditingController(text: '9.9.9.9, 149.112.112.112');

  bool _passwordVisible = false;
  bool _loading = false;
  bool _loadingRegions = false;
  String _status = '';
  String? _generatedConfig;
  String? _savedPath;
  List<Region> _regions = [];

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _regionCtrl.dispose();
    _dnsCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  // ---------------------------------------------------------------------------
  // Load region list for the picker
  // ---------------------------------------------------------------------------
  Future<void> _loadRegions() async {
    setState(() {
      _loadingRegions = true;
      _status = 'Loading regions...';
    });
    try {
      final regions = await _service.fetchRegions(onProgress: _setStatus);
      if (!mounted) return;
      setState(() => _regions = regions);
      _showRegionPicker();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to load regions: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingRegions = false);
      }
    }
  }

  void _showRegionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1D23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) => _RegionPickerSheet(
        regions: _regions,
        onSelected: (id) {
          _regionCtrl.text = id;
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main generate flow
  // ---------------------------------------------------------------------------
  Future<void> _generate() async {
    final region = _regionCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final dns = _dnsCtrl.text.trim();

    if (region.isEmpty || username.isEmpty || password.isEmpty) {
      _showError('Region, username, and password are all required.');
      return;
    }

    setState(() {
      _loading = true;
      _generatedConfig = null;
      _savedPath = null;
      _status = 'Starting...';
    });

    try {
      final config = await _service.generateConfig(
        region: region,
        username: username,
        password: password,
        dns: dns.isEmpty ? '9.9.9.9, 149.112.112.112' : dns,
        onProgress: _setStatus,
      );

      if (!mounted) return;
      setState(() {
        _generatedConfig = config;
        _status = 'Config generated successfully.';
      });

      // Auto-save to app documents directory
      await _saveConfig(config, region);
    } catch (e) {
      if (!mounted) return;
      _showError('$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Save config file
  // ---------------------------------------------------------------------------
  Future<void> _saveConfig(String config, String region) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filename = 'pia-$region.conf';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(config, flush: true);
      if (!mounted) return;
      setState(() {
        _savedPath = file.path;
        _status = 'Saved: $filename';
      });
    } catch (e) {
      _setStatus('Config generated but could not auto-save: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Share/save config through Android's system share sheet
  // ---------------------------------------------------------------------------
  Future<void> _saveToDirectory() async {
    if (_generatedConfig == null) return;
    final region = _regionCtrl.text.trim();
    final filename = 'pia-$region.conf';

    try {
      // Use share_plus to send the file -- most reliable cross-app method on Android
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/$filename');
      await tempFile.writeAsString(_generatedConfig!, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path, mimeType: 'text/plain')],
          subject: filename,
          text: 'PIA WireGuard config for region: $region',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not share file: $e');
    }
  }

  Future<void> _copyToClipboard() async {
    if (_generatedConfig == null) return;
    await Clipboard.setData(ClipboardData(text: _generatedConfig!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Config copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF00D4AA),
      ),
    );
  }

  void _showError(String message) {
    setState(() {
      _status = message;
      _loading = false;
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D23),
        title: const Text('Error', style: TextStyle(color: Color(0xFFFF5C5C))),
        content: Text(message,
            style: const TextStyle(color: Color(0xFFE8EAF0), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00D4AA))),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D23),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF00D4AA),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'PIA WireGuard Config',
              style: TextStyle(
                color: Color(0xFFE8EAF0),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Text(
              'v0.0.3',
              style: TextStyle(
                color: Color(0xFF8892A4),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('REGION'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _regionCtrl,
                      style: const TextStyle(
                        color: Color(0xFFE8EAF0),
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Region ID',
                        hintText: 'e.g. aus_melbourne',
                        prefixIcon: Icon(Icons.language,
                            color: Color(0xFF8892A4), size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _IconButton(
                    icon: Icons.list_alt,
                    loading: _loadingRegions,
                    tooltip: 'Browse regions',
                    onTap: _loadRegions,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('CREDENTIALS'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _usernameCtrl,
                style: const TextStyle(
                  color: Color(0xFFE8EAF0),
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  labelText: 'PIA Username',
                  hintText: 'e.g. p1234567',
                  prefixIcon: Icon(Icons.person_outline,
                      color: Color(0xFF8892A4), size: 18),
                ),
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_passwordVisible,
                style: const TextStyle(
                  color: Color(0xFFE8EAF0),
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  labelText: 'PIA Password',
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: Color(0xFF8892A4), size: 18),
                  suffixIcon: GestureDetector(
                    onTap: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                    child: Icon(
                      _passwordVisible
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: const Color(0xFF8892A4),
                      size: 18,
                    ),
                  ),
                ),
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 20),
              const _SectionLabel('DNS SERVERS'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dnsCtrl,
                style: const TextStyle(
                  color: Color(0xFFE8EAF0),
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  labelText: 'DNS',
                  hintText: '9.9.9.9, 149.112.112.112',
                  prefixIcon: Icon(Icons.dns_outlined,
                      color: Color(0xFF8892A4), size: 18),
                  helperText: 'Quad9 default  |  Cloudflare: 1.1.1.1, 1.0.0.1',
                  helperStyle:
                      TextStyle(color: Color(0xFF4A5268), fontSize: 11),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _generate,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF12141A),
                          ),
                        )
                      : const Text('GENERATE CONFIG'),
                ),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 16),
                _StatusBar(
                  message: _status,
                  isError: _status.toLowerCase().contains('fail') ||
                      _status.toLowerCase().contains('error'),
                ),
              ],
              if (_generatedConfig != null) ...[
                const SizedBox(height: 24),
                const _SectionLabel('GENERATED CONFIG'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1016),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: const Color(0xFF00D4AA), width: 1),
                  ),
                  child: SelectableText(
                    _generatedConfig!,
                    style: const TextStyle(
                      color: Color(0xFF00D4AA),
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ),
                if (_savedPath != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Auto-saved: $_savedPath',
                    style: const TextStyle(
                      color: Color(0xFF4A5268),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyToClipboard,
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('COPY'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00D4AA),
                          side: const BorderSide(color: Color(0xFF00D4AA)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveToDirectory,
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text('SHARE / SAVE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00D4AA),
                          side: const BorderSide(color: Color(0xFF00D4AA)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              const _InfoCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Region picker bottom sheet
// ---------------------------------------------------------------------------
class _RegionPickerSheet extends StatefulWidget {
  final List<Region> regions;
  final void Function(String) onSelected;
  const _RegionPickerSheet({required this.regions, required this.onSelected});

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.regions
        .where((r) => r.id.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2E3240),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              style: const TextStyle(
                  color: Color(0xFFE8EAF0), fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Filter regions...',
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFF8892A4), size: 18),
                filled: true,
                fillColor: const Color(0xFF1E2128),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2E3240)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2E3240)),
                ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final region = filtered[i];
                return InkWell(
                  onTap: () => widget.onSelected(region.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.chevron_right,
                            color: Color(0xFF00D4AA), size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            region.id,
                            style: const TextStyle(
                              color: Color(0xFFE8EAF0),
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${region.wgServers.length} server${region.wgServers.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: Color(0xFF4A5268), fontSize: 11),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF4A5268),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      );
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final String tooltip;
  final VoidCallback onTap;
  const _IconButton(
      {required this.icon,
      required this.loading,
      required this.tooltip,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2128),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E3240)),
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00D4AA)),
                  )
                : Icon(icon, color: const Color(0xFF00D4AA), size: 20),
          ),
        ),
      );
}

class _StatusBar extends StatelessWidget {
  final String message;
  final bool isError;
  const _StatusBar({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isError ? const Color(0xFF2A1515) : const Color(0xFF0E1E1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isError
                ? const Color(0xFFFF5C5C).withValues(alpha: 0.4)
                : const Color(0xFF00D4AA).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              size: 14,
              color:
                  isError ? const Color(0xFFFF5C5C) : const Color(0xFF00D4AA),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? const Color(0xFFFF5C5C)
                      : const Color(0xFF00D4AA),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D23),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2E3240)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ABOUT',
              style: TextStyle(
                color: Color(0xFF4A5268),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Generates a WireGuard config for PIA VPN by authenticating with PIA\'s provisioning API, selecting the lowest-latency server, and creating a fresh keypair. Config expires every 1-2 weeks and must be regenerated.',
              style: TextStyle(
                color: Color(0xFF8892A4),
                fontSize: 12,
                height: 1.6,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Your password is never stored. The generated config contains your WireGuard private key -- treat it as a secret.',
              style: TextStyle(
                color: Color(0xFF4A5268),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}
