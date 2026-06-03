import 'package:flutter/foundation.dart';

@immutable
class TelemostRoom {
  const TelemostRoom._({
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

  factory TelemostRoom.parse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Telemost room URL is required.');
    }

    final urlMatch = _urlPattern.firstMatch(trimmed);
    final id = urlMatch?.group(1) ?? trimmed;
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException(
        'Expected a Yandex Telemost URL like https://telemost.yandex.ru/j/...',
      );
    }

    return TelemostRoom._(
      id: id,
      url: 'https://telemost.yandex.ru/j/$id',
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
  const TunnelSettings({
    required this.telemostRoom,
    required this.vlessEndpoint,
    this.socksHost = '127.0.0.1',
    this.socksPort = 1080,
  });

  final TelemostRoom telemostRoom;
  final VlessRealityEndpoint vlessEndpoint;
  final String socksHost;
  final int socksPort;

  factory TunnelSettings.parse({
    required String telemostRoom,
    required String vlessUri,
  }) {
    return TunnelSettings(
      telemostRoom: TelemostRoom.parse(telemostRoom),
      vlessEndpoint: VlessRealityEndpoint.parse(vlessUri),
    );
  }

  Map<String, Object> toPlatformArgs() {
    return <String, Object>{
      'telemostRoomId': telemostRoom.id,
      'telemostRoomUrl': telemostRoom.url,
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
}
