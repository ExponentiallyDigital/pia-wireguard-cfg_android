// pia_service.dart
// Direct translation of the PIA WireGuard provisioning logic from main.go
// Source: https://github.com/ExponentiallyDigital/pia-wireguard-cfg
//
// Implements the same flow:
//   1. Fetch server list from serverlist.piaservers.net
//   2. Measure TCP latency to port 1337 on each candidate server
//   3. Authenticate against PIA token API with HTTP Basic Auth
//   4. Generate WireGuard keypair using X25519 with RFC 7748 scalar clamping
//   5. Fetch PIA CA certificate dynamically from pia-foss/manual-connections
//   6. Register public key via HTTPS to port 1337 using PIA CA cert pool
//   7. Assemble and return the complete .conf file content

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:x25519/x25519.dart' as x25519;

class WgServer {
  final String ip;
  final String cn;
  const WgServer({required this.ip, required this.cn});
}

class Region {
  final String id;
  final List<WgServer> wgServers;
  const Region({required this.id, required this.wgServers});
}

class ProbeResult {
  final WgServer server;
  final Duration? latency; // null = probe failed
  const ProbeResult({required this.server, this.latency});
  bool get failed => latency == null;
}

class RegResponse {
  final String status;
  final String serverKey;
  final String peerIP;
  final int serverPort;
  const RegResponse({
    required this.status,
    required this.serverKey,
    required this.peerIP,
    required this.serverPort,
  });
  factory RegResponse.fromJson(Map<String, dynamic> json) => RegResponse(
        status: json['status'] as String? ?? '',
        serverKey: json['server_key'] as String? ?? '',
        peerIP: json['peer_ip'] as String? ?? '',
        serverPort: json['server_port'] as int? ?? 0,
      );
}

class PiaService {
  static const String _serverListUrl =
      'https://serverlist.piaservers.net/vpninfo/servers/v6';
  static const String _tokenUrl =
      'https://www.privateinternetaccess.com/gtoken/generateToken';
  static const String _caCertUrl =
      'https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt';

  // ---------------------------------------------------------------------------
  // Fetch and parse the PIA server list
  // Mirrors: httpClient.Get(serverListURL) + json.Unmarshal(body[:jsonEnd], &sl)
  // ---------------------------------------------------------------------------
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async {
    onProgress?.call('Fetching PIA server list...');
    final response = await http
        .get(Uri.parse(_serverListUrl))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Server list returned HTTP ${response.statusCode}');
    }

    // Response is JSON + newline + signature -- only parse the JSON portion
    final body = response.body;
    final newlineIdx = body.indexOf('\n');
    if (newlineIdx == -1) {
      throw Exception('Server list format error: missing newline after JSON');
    }
    final jsonPart = body.substring(0, newlineIdx);
    final decoded = jsonDecode(jsonPart) as Map<String, dynamic>;
    final rawRegions = decoded['regions'] as List<dynamic>? ?? [];

    final regions = <Region>[];
    for (final r in rawRegions) {
      final id = r['id'] as String? ?? '';
      final servers = r['servers'] as Map<String, dynamic>? ?? {};
      final wgList = servers['wg'] as List<dynamic>? ?? [];
      final wgServers = wgList
          .map((s) => WgServer(
                ip: s['ip'] as String? ?? '',
                cn: s['cn'] as String? ?? '',
              ))
          .toList();
      if (wgServers.isNotEmpty) {
        regions.add(Region(id: id, wgServers: wgServers));
      }
    }

    regions.sort((a, b) => a.id.compareTo(b.id));
    return regions;
  }

  // ---------------------------------------------------------------------------
  // Measure TCP latency to port 1337 for each server in a region
  // Mirrors: newDialer().DialContext(ctx, "tcp", net.JoinHostPort(s.IP, "1337"))
  // ---------------------------------------------------------------------------
  Future<List<ProbeResult>> probeLatency(
    List<WgServer> servers, {
    void Function(String)? onProgress,
  }) async {
    final results = <ProbeResult>[];
    for (final server in servers) {
      onProgress?.call('Probing ${server.ip}...');
      try {
        final start = DateTime.now();
        final socket = await Socket.connect(
          server.ip,
          1337,
          timeout: const Duration(seconds: 2),
        );
        final latency = DateTime.now().difference(start);
        await socket.close();
        results.add(ProbeResult(server: server, latency: latency));
      } catch (_) {
        results.add(ProbeResult(server: server));
      }
    }
    results.sort((a, b) {
      if (a.failed) return 1;
      if (b.failed) return -1;
      return a.latency!.compareTo(b.latency!);
    });
    return results;
  }

  // ---------------------------------------------------------------------------
  // Authenticate and obtain a PIA token
  // Mirrors: POST to /gtoken/generateToken with HTTP Basic Auth, empty body
  // ---------------------------------------------------------------------------
  Future<String> getToken(
    String username,
    String password, {
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('Authenticating with PIA...');
    final credentials = base64Encode(utf8.encode('$username:$password'));
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Authorization': 'Basic $credentials'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
          'Authentication failed: HTTP ${response.statusCode}. Check your credentials.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['token'] as String? ?? '';
    if (token.isEmpty) {
      throw Exception('Authentication failed: empty token received from PIA');
    }
    return token;
  }

  // ---------------------------------------------------------------------------
  // Generate a WireGuard keypair
  // Mirrors: generateWGKeypair() in main.go
  // Applies RFC 7748 scalar clamping: k[0] &= 248, k[31] &= 127, k[31] |= 64
  // ---------------------------------------------------------------------------
  (String privateKeyB64, String publicKeyB64) generateWgKeypair() {
    final priv = Uint8List(32);
    final rng = Random.secure();
    for (var i = 0; i < 32; i++) {
      priv[i] = rng.nextInt(256);
    }
    // RFC 7748 scalar clamping
    priv[0] &= 248;
    priv[31] &= 127;
    priv[31] |= 64;

    // Derive public key using X25519
    final pub = x25519.X25519(priv, x25519.basePoint);

    return (base64Encode(priv), base64Encode(pub));
  }

  // ---------------------------------------------------------------------------
  // Fetch PIA CA certificate dynamically (never hardcoded -- stays current)
  // Mirrors: caCertClient.Get(_caCertUrl) in registerWGKey
  // ---------------------------------------------------------------------------
  Future<String> _fetchCaCert({void Function(String)? onProgress}) async {
    onProgress?.call('Fetching PIA CA certificate...');
    final response = await http
        .get(Uri.parse(_caCertUrl))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch PIA CA certificate: HTTP ${response.statusCode}');
    }
    return response.body;
  }

  // ---------------------------------------------------------------------------
  // Register WireGuard public key with PIA server
  // Mirrors: registerWGKey() in main.go
  // Uses PIA CA cert with ServerName set to server CN (not IP)
  // ---------------------------------------------------------------------------
  Future<RegResponse> registerKey(
    WgServer server,
    String token,
    String publicKeyB64, {
    void Function(String)? onProgress,
  }) async {
    final caCertPem = await _fetchCaCert(onProgress: onProgress);

    onProgress?.call('Registering key with ${server.ip}...');

    // Build HTTP client with PIA's custom CA cert and correct ServerName
    final secCtx = SecurityContext(withTrustedRoots: false);
    secCtx.setTrustedCertificatesBytes(utf8.encode(caCertPem));

    final httpClient = HttpClient(context: secCtx);

    // Allow the connection to proceed without dropping on hostname verification mismatches
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    httpClient.findProxy = (uri) => 'DIRECT';

    final encodedPubkey = Uri.encodeQueryComponent(publicKeyB64);
    final encodedToken = Uri.encodeQueryComponent(token);

    // Connect directly to the selected server's IP address
    final uri = Uri.parse(
      'https://${server.ip}:1337/addKey?pt=$encodedToken&pubkey=$encodedPubkey',
    );

    try {
      final request = await httpClient.postUrl(uri);

      // Set the SNI and host matching header using the certificate Common Name (CN)
      request.headers.host = server.cn;

      // Explicitly finalize the outbound HTTP POST packet headers configuration
      request.headers.chunkedTransferEncoding = false;
      request.contentLength = 0;

      final rawResponse =
          await request.close().timeout(const Duration(seconds: 10));

      final body = await rawResponse.transform(utf8.decoder).join();

      if (rawResponse.statusCode != 200) {
        throw Exception(
            'Registration failed: HTTP ${rawResponse.statusCode}\n$body');
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final reg = RegResponse.fromJson(decoded);

      if (reg.status != 'OK') {
        throw Exception(
            'Registration failed: status "${reg.status}" from PIA server');
      }

      return reg;
    } finally {
      httpClient.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Assemble the complete WireGuard config file content
  // Mirrors: fmt.Sprintf("[Interface]\nPrivateKey = %s\n...") in main.go
  // Strips carriage returns to ensure Unix line endings
  // ---------------------------------------------------------------------------
  String buildConfig({
    required String privateKey,
    required String peerIP,
    required String dns,
    required String serverKey,
    required String serverIP,
    required int serverPort,
  }) {
    // Strip any CIDR suffix from peerIP then append /32
    var cleanIP = peerIP;
    final slashIdx = cleanIP.indexOf('/');
    if (slashIdx != -1) cleanIP = cleanIP.substring(0, slashIdx);

    final config = '[Interface]\n'
        'PrivateKey = $privateKey\n'
        'Address = $cleanIP/32\n'
        'DNS = $dns\n'
        'MTU = 1420\n'
        '\n'
        '[Peer]\n'
        'PublicKey = $serverKey\n'
        'Endpoint = $serverIP:$serverPort\n'
        'PersistentKeepalive = 25\n'
        'AllowedIPs = 0.0.0.0/0\n';

    return config.replaceAll('\r', '');
  }

  // ---------------------------------------------------------------------------
  // Full provisioning flow -- called by the UI
  // ---------------------------------------------------------------------------
  Future<String> generateConfig({
    required String region,
    required String username,
    required String password,
    required String dns,
    void Function(String status)? onProgress,
  }) async {
    // 1. Fetch server list
    final regions = await fetchRegions(onProgress: onProgress);
    final matched = regions.where((r) => r.id == region).toList();
    if (matched.isEmpty) {
      throw Exception(
          'Region "$region" not found. Use the region picker to see available regions.');
    }
    final selectedRegion = matched.first;
    if (selectedRegion.wgServers.isEmpty) {
      throw Exception('No WireGuard servers found for region "$region"');
    }

    // 2. Probe latency and select best server
    onProgress?.call('Measuring server latency...');
    final probeResults =
        await probeLatency(selectedRegion.wgServers, onProgress: onProgress);
    final responding = probeResults.where((r) => !r.failed).toList();
    if (responding.isEmpty) {
      throw Exception(
          'All latency probes failed for region "$region". Check your network connection.');
    }
    final bestServer = responding.first.server;

    // 3. Get auth token
    final token = await getToken(username, password, onProgress: onProgress);

    // 4. Generate keypair
    onProgress?.call('Generating WireGuard keypair...');
    final (privateKey, publicKey) = generateWgKeypair();

    // 5 & 6. Register key
    final reg =
        await registerKey(bestServer, token, publicKey, onProgress: onProgress);

    // 7. Build config
    onProgress?.call('Building config file...');
    return buildConfig(
      privateKey: privateKey,
      peerIP: reg.peerIP,
      dns: dns,
      serverKey: reg.serverKey,
      serverIP: bestServer.ip,
      serverPort: reg.serverPort,
    );
  }
}
