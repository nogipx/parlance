import 'dart:io';

import 'package:parlance_mcp/io.dart';

/// The native launcher owns the listeners, certificates and saved preference.
final class ConsoleWifi {
  ConsoleWifi(this.directory);

  final Directory directory;
  File get _preference => File('${directory.path}/console-wifi-enabled');
  CollectorLan? _lan;
  bool _enabled = false;
  String? _error;

  Map<String, Object?> get status => {
    'enabled': _enabled,
    'android': _lan?.android.toString(),
    'ios': _lan?.ios?.toString(),
    'error': _error,
  };

  Future<void> restore() async {
    if (await _preference.exists()) {
      _enabled = true;
      await setEnabled(true);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _error = null;
    try {
      if (enabled) {
        if (_lan != null) return;
        final address = await _wifiAddress();
        SecurityContext? tls;
        try {
          tls = await _certificate(address.address);
        } on Object catch (e) {
          _error = 'iPhone TLS unavailable. $e';
        }
        _lan = await CollectorLan.start(address, tls: tls);
        await _preference.create();
      } else {
        if (await _preference.exists()) await _preference.delete();
        await close();
      }
      _enabled = enabled;
    } on Object catch (e) {
      await close();
      _error = e.toString();
    }
  }

  Future<void> close() async {
    final lan = _lan;
    _lan = null;
    await lan?.close();
  }

  Future<InternetAddress> _wifiAddress() async {
    final ports = await Process.run('/usr/sbin/networksetup', [
      '-listallhardwareports',
    ]);
    final interfaces = RegExp(r'Hardware Port: (.+)\nDevice: (\S+)')
        .allMatches(ports.stdout as String)
        .toList();
    for (final port in [
      ...interfaces.where((p) => p[1] == 'Wi-Fi'),
      ...interfaces.where((p) => p[1] != 'Wi-Fi' && p[1]!.contains('Ethernet')),
    ]) {
      final result = await Process.run('/usr/sbin/ipconfig', [
        'getifaddr',
        port[2]!,
      ]);
      final address = InternetAddress.tryParse(result.stdout.toString().trim());
      if (address != null && address.type == InternetAddressType.IPv4) {
        return address;
      }
    }
    throw StateError('Connect the Mac to Wi-Fi or Ethernet and try again.');
  }

  Future<SecurityContext> _certificate(String ip) async {
    final temp = await directory.createTemp('wifi-tls-');
    try {
      final certificate = '${temp.path}/cert.pem';
      final key = '${temp.path}/key.pem';
      final result = await Process.run('mkcert', [
        '-cert-file',
        certificate,
        '-key-file',
        key,
        ip,
      ]);
      if (result.exitCode != 0) throw StateError('mkcert: ${result.stderr}');
      return SecurityContext()
        ..useCertificateChain(certificate)
        ..usePrivateKey(key);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
