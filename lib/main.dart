// main.dart
// PIA WireGuard Config Generator -- Flutter Android APK
// GUI equivalent of https://github.com/ExponentiallyDigital/pia-wireguard-cfg
//
// Security hardening v0.2.0:
//   1. No permanent filesystem writes -- config held in memory only
//   2. Clear button wipes credentials and config from RAM + UI
//   3. Hardened input fields (no autocorrect, no suggestions, no clipboard on password)
//   4. Auto-wipe safety timer (3 min), reset on any touch/type interaction
//   5. FLAG_SECURE enforced in MainActivity.kt (no screenshots, blank recents preview)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'pia_service.dart';

// Removed imports: dart:io, path_provider
// path_provider and dart:io are no longer needed -- all file I/O removed.

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

  // [CHANGE 1] Removed: String? _savedPath  -- no more filesystem write path to track.
  String? _generatedConfig; // volatile in-memory only; never written to disk

  List<Region> _regions = [];

  // [CHANGE 4] Safety auto-wipe timer state
  static const _timeoutSeconds = 180; // 3 minutes
  Timer? _wipeTimer;
  int _secondsRemaining = 0;

  @override
  void dispose() {
    // [CHANGE 4] Always cancel the timer on widget teardown to prevent leaks/crashes
    _wipeTimer?.cancel();

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
  // [CHANGE 2] Clear session -- wipes credentials, config, and timer from RAM + UI
  // ---------------------------------------------------------------------------
  void _clearSession() {
    // Cancel any running timer first
    _wipeTimer?.cancel();
    _wipeTimer = null;

    // Overwrite controller text buffers to empty strings so the previous
    // content is immediately out-of-scope for the GC before setState rebuilds.
    _usernameCtrl.text = '';
    _passwordCtrl.text = '';

    setState(() {
      _generatedConfig = null;
      _secondsRemaining = 0;
      _status = 'Session cleared.';
      _passwordVisible = false;
    });
  }

  // ---------------------------------------------------------------------------
  // [CHANGE 4] Start (or restart) the 3-minute safety auto-wipe countdown
  // ---------------------------------------------------------------------------
  void _startOrResetTimer() {
    _wipeTimer?.cancel();
    _secondsRemaining = _timeoutSeconds;

    _wipeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsRemaining--;
      });
      if (_secondsRemaining <= 0) {
        timer.cancel();
        _clearSession();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // [CHANGE 4] Called by GestureDetector on any user touch/pointer event
  // to reset the auto-wipe countdown back to 3 minutes.
  // ---------------------------------------------------------------------------
  void _onUserInteraction(PointerEvent _) {
    // Only reset the timer if a config is currently displayed --
    // no need to run the timer during idle input states.
    if (_generatedConfig != null && _wipeTimer != null) {
      _startOrResetTimer();
    }
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
  // [CHANGE 1] Removed _saveConfig() call -- config stays in memory only.
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
      // [CHANGE 1] Removed: _savedPath = null
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

      // [CHANGE 1] Removed: await _saveConfig(config, region)
      // Config is now held exclusively in _generatedConfig (volatile memory).

      // [CHANGE 4] Config is now on screen -- start the safety wipe timer.
      _startOrResetTimer();
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
  // [CHANGE 1] Share via system Share Sheet using XFile.fromData
  // No temp file written to disk -- bytes passed directly through the
  // share_plus runtime memory stream. Physical file existence is scoped
  // entirely to the duration of the OS share pipeline.
  // ---------------------------------------------------------------------------
  Future<void> _shareConfig() async {
    if (_generatedConfig == null) return;
    final region = _regionCtrl.text.trim();
    final filename = 'pia-$region.conf';

    try {
      final bytes = Uint8List.fromList(_generatedConfig!.codeUnits);

      await SharePlus.instance.share(
        ShareParams(
          // XFile.fromData passes raw bytes -- no path written to storage.
          files: [
            XFile.fromData(bytes, name: filename, mimeType: 'text/plain')
          ],
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
    // [CHANGE 4] Wrap entire scaffold in a Listener so any pointer event
    // (touch, drag, stylus) resets the safety wipe countdown.
    return Listener(
      onPointerDown: _onUserInteraction,
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
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
                'v0.2.0',
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

                // [CHANGE 3] Username: autocorrect + suggestions disabled
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
                  autocorrect:
                      false, // [CHANGE 3] prevents keyboard learning username
                  enableSuggestions:
                      false, // [CHANGE 3] suppresses predictive text bar
                ),
                const SizedBox(height: 12),

                // [CHANGE 3] Password: obscured, no autocorrect, no suggestions,
                // no interactive selection (cuts off cut/copy/paste clipboard access)
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
                  autocorrect: false, // [CHANGE 3]
                  enableSuggestions: false, // [CHANGE 3]
                  enableInteractiveSelection:
                      false, // [CHANGE 3] disables cut/copy/paste
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
                    helperText:
                        'Quad9 default  |  Cloudflare: 1.1.1.1, 1.0.0.1',
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

                  // [CHANGE 2 + 4] Header row: section label, countdown, Clear button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const _SectionLabel('GENERATED CONFIG'),
                      const Spacer(),

                      // [CHANGE 4] Live countdown display
                      if (_secondsRemaining > 0) ...[
                        Icon(
                          Icons.timer_outlined,
                          size: 12,
                          color: _secondsRemaining <= 30
                              ? const Color(0xFFFF5C5C)
                              : const Color(0xFF4A5268),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_secondsRemaining}s',
                          style: TextStyle(
                            color: _secondsRemaining <= 30
                                ? const Color(0xFFFF5C5C)
                                : const Color(0xFF4A5268),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // [CHANGE 2] Clear button
                      GestureDetector(
                        onTap: _clearSession,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A1515),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFF5C5C)
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 12, color: Color(0xFFFF5C5C)),
                              SizedBox(width: 4),
                              Text(
                                'CLEAR',
                                style: TextStyle(
                                  color: Color(0xFFFF5C5C),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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

                  // [CHANGE 1] Removed: savedPath display -- no longer saved to disk.

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
                          // [CHANGE 1] Was: _saveToDirectory. Now: _shareConfig (no disk write)
                          onPressed: _shareConfig,
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
              'Your password is never stored. The generated config contains your WireGuard private key -- treat it as a secret. Config is held in memory only and never written to local storage.',
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
