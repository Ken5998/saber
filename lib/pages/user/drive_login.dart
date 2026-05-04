import 'package:flutter/material.dart';
import 'package:saber/data/googledrive/drive_client.dart';
import 'package:saber/data/googledrive/drive_syncer.dart';
import 'package:saber/data/prefs.dart';

class DriveLoginPage extends StatefulWidget {
  const DriveLoginPage({super.key});

  @override
  State<DriveLoginPage> createState() => _DriveLoginPageState();
}

class _DriveLoginPageState extends State<DriveLoginPage> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = await DriveClient.signIn(context);

    if (!mounted) return;

    if (email == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in cancelled or failed. Please try again.';
      });
      return;
    }

    stows.driveLoggedIn = true;
    stows.driveEmail.value = email;

    setState(() => _loading = false);

    // Start sync in background
    DriveSyncer.sync();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Google Drive')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.cloud_outlined, size: 80, color: colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'Sync your notes with Google Drive',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your notes will be saved to a private app folder '
              'in your Google Drive. Only this app can access it.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : _signIn,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_loading ? 'Signing in…' : 'Sign in with Google'),
            ),
          ],
        ),
      ),
    );
  }
}
