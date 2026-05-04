import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

final _log = Logger('DriveClient');

class DriveClient {
  DriveClient._();

  static final _clientId = ClientId(
    const String.fromEnvironment('GOOGLE_CLIENT_ID'),
    const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
  );

  static const _scopes = [drive.DriveApi.driveAppdataScope];

  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'drive_access_token';
  static const _refreshTokenKey = 'drive_refresh_token';
  static const _tokenExpiryKey = 'drive_token_expiry';
  static const _emailKey = 'drive_email';

  static AccessCredentials? _credentials;
  static http.Client? _httpClient;

  /// Opens browser for Google Sign-In using manual code flow.
  /// Returns email on success, null on failure.
  static Future<String?> signIn(BuildContext context) async {
    try {
      final client = http.Client();

      final credentials = await obtainAccessCredentialsViaUserConsentManual(
        _clientId,
        _scopes,
        client,
        (url) async {
          // 1. Open browser
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          // 2. Ask user to paste the code shown by Google
          if (!context.mounted) return '';
          final code = await _showCodeDialog(context);
          return code ?? '';
        },
      );

      _credentials = credentials;
      _httpClient = authenticatedClient(client, credentials);

      final email = credentials.idToken != null
          ? _extractEmail(credentials.idToken!)
          : 'Connected';

      await Future.wait([
        _storage.write(
          key: _accessTokenKey,
          value: credentials.accessToken.data,
        ),
        _storage.write(
          key: _refreshTokenKey,
          value: credentials.refreshToken ?? '',
        ),
        _storage.write(
          key: _tokenExpiryKey,
          value: credentials.accessToken.expiry.toIso8601String(),
        ),
        _storage.write(key: _emailKey, value: email),
      ]);

      _log.info('signIn: success, email=$email');
      return email;
    } catch (e, st) {
      _log.warning('signIn failed: $e', e, st);
      return null;
    }
  }

  /// Shows a dialog asking the user to paste the auth code from the browser.
  static Future<String?> _showCodeDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter authorization code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'After approving access in the browser, '
              'Google will show you an authorization code. '
              'Copy and paste it here.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Authorization code',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  /// Restores session from stored tokens. Returns email or null.
  static Future<String?> restoreSession() async {
    try {
      final accessToken = await _storage.read(key: _accessTokenKey);
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      final expiryStr = await _storage.read(key: _tokenExpiryKey);
      final email = await _storage.read(key: _emailKey);

      if (accessToken == null || accessToken.isEmpty) return null;

      final expiry = expiryStr != null
          ? DateTime.tryParse(expiryStr) ?? DateTime.now()
          : DateTime.now();

      _credentials = AccessCredentials(
        AccessToken('Bearer', accessToken, expiry.toUtc()),
        refreshToken?.isNotEmpty == true ? refreshToken : null,
        _scopes,
      );

      final baseClient = http.Client();

      if (_credentials!.accessToken.hasExpired) {
        if (refreshToken == null || refreshToken.isEmpty) {
          await signOut();
          return null;
        }
        try {
          _credentials = await refreshCredentials(
            _clientId,
            _credentials!,
            baseClient,
          );
          await Future.wait([
            _storage.write(
              key: _accessTokenKey,
              value: _credentials!.accessToken.data,
            ),
            _storage.write(
              key: _tokenExpiryKey,
              value: _credentials!.accessToken.expiry.toIso8601String(),
            ),
          ]);
        } catch (e) {
          _log.warning('restoreSession: refresh failed: $e');
          await signOut();
          return null;
        }
      }

      _httpClient = authenticatedClient(baseClient, _credentials!);
      _log.info('restoreSession: success, email=$email');
      return email;
    } catch (e, st) {
      _log.warning('restoreSession failed: $e', e, st);
      return null;
    }
  }

  static Future<void> signOut() async {
    _credentials = null;
    _httpClient?.close();
    _httpClient = null;
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _tokenExpiryKey),
      _storage.delete(key: _emailKey),
    ]);
    _log.info('signOut: done');
  }

  static Future<drive.DriveApi?> getDriveApi() async {
    if (_httpClient == null) {
      final email = await restoreSession();
      if (email == null) return null;
    }
    return drive.DriveApi(_httpClient!);
  }

  static bool get isSignedIn => _httpClient != null;
  static Future<String?> getSavedEmail() => _storage.read(key: _emailKey);

  static String _extractEmail(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return 'Connected';
      final payload = parts[1];
      final padded = payload.padRight(
        payload.length + (4 - payload.length % 4) % 4,
        '=',
      );
      final decoded = String.fromCharCodes(base64Url.decode(padded));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return json['email'] as String? ?? 'Connected';
    } catch (e) {
      return 'Connected';
    }
  }
}
