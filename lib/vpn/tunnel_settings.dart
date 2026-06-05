import 'package:flutter/foundation.dart';

@immutable
class OlcrtcRoom {
  const OlcrtcRoom._({
    required this.id,
    required this.url,
  });

  final String id;
  final String url;

  static final RegExp _urlPattern = RegExp(
    r'^https://telemost\.yandex\.(?:ru|com)/j/([A-Za-z0-9_-]+)(?:[/?#].*)?$',
    caseSensitive: false,
  );
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  factory OlcrtcRoom.parse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('olcRTC room URL or ID is required.');
    }

    final urlMatch = _urlPattern.firstMatch(trimmed);
    if (urlMatch != null) {
      final id = urlMatch.group(1)!;
      return OlcrtcRoom._(
        id: id,
        url: 'https://telemost.yandex.ru/j/$id',
      );
    }

    if (_idPattern.hasMatch(trimmed)) {
      return OlcrtcRoom._(
        id: trimmed,
        url: 'https://telemost.yandex.ru/j/$trimmed',
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      return OlcrtcRoom._(id: trimmed, url: trimmed);
    }

    if (trimmed.contains('/') && !trimmed.contains(RegExp(r'\s'))) {
      return OlcrtcRoom._(id: trimmed, url: trimmed);
    }

    throw const FormatException(
      'Expected a Telemost URL, Jitsi URL, or olcRTC room ID.',
    );
  }
}

@immutable
class VlessRealityEndpoint {
  const VlessRealityEndpoint._({
    required this.originalUri,
    required this.userId,
    required this.host,
    required this.port,
    required this.publicKey,
    required this.serverName,
    required this.shortId,
    required this.flow,
  });

  final String originalUri;
  final String userId;
  final String host;
  final int port;
  final String publicKey;
  final String serverName;
  final String shortId;
  final String flow;

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  factory VlessRealityEndpoint.parse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('VLESS Reality URI is required.');
    }

    final uri = Uri.parse(trimmed);
    if (uri.scheme.toLowerCase() != 'vless') {
      throw const FormatException('Expected a vless:// URI.');
    }
    if (!_uuidPattern.hasMatch(uri.userInfo)) {
      throw const FormatException('VLESS URI must contain a UUID user id.');
    }
    if (uri.host.isEmpty) {
      throw const FormatException('VLESS URI must contain a server host.');
    }
    if (!uri.hasPort || uri.port <= 0 || uri.port > 65535) {
      throw const FormatException('VLESS URI must contain a valid server port.');
    }

    final params = uri.queryParameters;
    if ((params['security'] ?? '').toLowerCase() != 'reality') {
      throw const FormatException(
        'VLESS URI must use security=reality.',
      );
    }

    final publicKey = params['pbk'] ?? params['publicKey'] ?? '';
    if (publicKey.isEmpty) {
      throw const FormatException('Reality public key is required.');
    }

    return VlessRealityEndpoint._(
      originalUri: trimmed,
      userId: uri.userInfo,
      host: uri.host,
      port: uri.port,
      publicKey: publicKey,
      serverName: params['sni'] ?? params['serverName'] ?? '',
      shortId: params['sid'] ?? '',
      flow: params['flow'] ?? '',
    );
  }
}

@immutable
class TunnelSettings {
  static final RegExp _olcrtcKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  const TunnelSettings({
    required this.olcrtcRoom,
    required this.vlessEndpoint,
    required this.olcrtcKey,
    this.olcrtcCarrier = 'telemost',
    this.olcrtcTransport = 'datachannel',
    this.socksHost = '127.0.0.1',
    this.socksPort = 1080,
    this.waitReadyTimeoutMillis = 60000,
  });

  final OlcrtcRoom olcrtcRoom;
  final VlessRealityEndpoint vlessEndpoint;
  final String olcrtcKey;
  final String olcrtcCarrier;
  final String olcrtcTransport;
  final String socksHost;
  final int socksPort;
  final int waitReadyTimeoutMillis;

  factory TunnelSettings.parse({
    required String olcrtcRoom,
    required String vlessUri,
    required String olcrtcKey,
    String olcrtcCarrier = 'telemost',
    String olcrtcTransport = 'datachannel',
  }) {
    final normalizedKey = _parseOlcrtcKey(olcrtcKey);
    final normalizedCarrier = _parseNonEmpty(
      olcrtcCarrier,
      'olcRTC carrier is required.',
    );
    final normalizedTransport = _parseNonEmpty(
      olcrtcTransport,
      'olcRTC transport is required.',
    );

    return TunnelSettings(
      olcrtcRoom: OlcrtcRoom.parse(olcrtcRoom),
      vlessEndpoint: VlessRealityEndpoint.parse(vlessUri),
      olcrtcKey: normalizedKey,
      olcrtcCarrier: normalizedCarrier,
      olcrtcTransport: normalizedTransport,
    );
  }

  Map<String, Object> toPlatformArgs() {
    return <String, Object>{
      'telemostRoomId': olcrtcRoom.id,
      'telemostRoomUrl': olcrtcRoom.url,
      'vlessUri': vlessEndpoint.originalUri,
      'vlessHost': vlessEndpoint.host,
      'vlessPort': vlessEndpoint.port,
      'vlessUserId': vlessEndpoint.userId,
      'realityPublicKey': vlessEndpoint.publicKey,
      'realityServerName': vlessEndpoint.serverName,
      'realityShortId': vlessEndpoint.shortId,
      'vlessFlow': vlessEndpoint.flow,
      'socksHost': socksHost,
      'socksPort': socksPort,
    };
  }

  Map<String, Object> toOlcrtcArgs({required String clientId}) {
    return <String, Object>{
      'carrier': olcrtcCarrier,
      'transport': olcrtcTransport,
      'roomId': olcrtcRoom.url,
      'telemostRoomId': olcrtcRoom.id,
      'telemostRoomUrl': olcrtcRoom.url,
      'clientId': clientId,
      'key': olcrtcKey,
      'socksHost': socksHost,
      'socksPort': socksPort,
      'waitReadyTimeoutMillis': waitReadyTimeoutMillis,
    };
  }

  static String _parseOlcrtcKey(String value) {
    final trimmed = value.trim();
    if (!_olcrtcKeyPattern.hasMatch(trimmed)) {
      throw const FormatException(
        'olcRTC key must be a 64 character hex string.',
      );
    }
    return trimmed.toLowerCase();
  }

  static String _parseNonEmpty(String value, String message) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw FormatException(message);
    }
    return trimmed;
  }
}
