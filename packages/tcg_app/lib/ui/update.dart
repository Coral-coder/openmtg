import 'package:flutter/material.dart';

import '../app/updater.dart';
import '../theme/theme.dart';

/// Offers a newer GitHub release and shows the download; see [Updater].
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.release});
  final ReleaseInfo release;

  /// Shows the prompt for [release] on top of whatever is on screen.
  static Future<void> show(BuildContext context, ReleaseInfo release) =>
      showDialog(context: context, barrierDismissible: false, builder: (_) => UpdateDialog(release: release));

  @override
  Widget build(BuildContext context) {
    final u = Updater.shared;
    final t = GameTheme.of(context);
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(t.radius)),
            child: ThemedPanel(
              title: 'New build available',
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${release.label} is on GitHub Releases. You have ${u.installedVersion} (build ${u.installedCode}).', style: t.body),
                if (release.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(release.notes, style: t.small, maxLines: 6, overflow: TextOverflow.ellipsis),
                ],
                if (u.downloading) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: u.progress, minHeight: 10, backgroundColor: t.muted.withValues(alpha: 0.3), color: t.accent),
                  ),
                  const SizedBox(height: 6),
                  Text('Downloading ${(u.progress * 100).round()}%', style: t.small),
                ] else if (u.downloaded != null) ...[
                  const SizedBox(height: 8),
                  Text('Downloaded and ready to install.', style: t.small.copyWith(color: t.ok)),
                ],
                if (u.error != null) ...[
                  const SizedBox(height: 10),
                  Text(u.error!, style: t.small.copyWith(color: t.danger)),
                ],
                if (!u.downloading) ...[
                  const SizedBox(height: 16),
                  ThemedButton(
                    u.downloaded != null ? 'Install' : 'Download & install',
                    icon: Icons.system_update,
                    onPressed: () async {
                      final ok = await u.downloadAndInstall(release: release);
                      if (ok && context.mounted) Navigator.pop(context);
                    },
                  ),
                  if (u.error != null && u.error!.contains('different key')) ...[
                    const SizedBox(height: 8),
                    ThemedButton('Open installer anyway', outlined: true, color: t.danger, onPressed: u.installAnyway),
                  ],
                  const SizedBox(height: 8),
                  ThemedButton('Later', outlined: true, color: t.muted, onPressed: () => Navigator.pop(context)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Checks GitHub on launch and whenever the app returns to the foreground, and shows
/// [UpdateDialog] when a newer build exists. Wrap the first screen with it; it draws nothing.
/// Does nothing off Android (iOS builds come through TestFlight).
class UpdateCheck extends StatefulWidget {
  const UpdateCheck({super.key, required this.child});
  final Widget child;
  @override
  State<UpdateCheck> createState() => _UpdateCheckState();
}

class _UpdateCheckState extends State<UpdateCheck> with WidgetsBindingObserver {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final u = Updater.shared;
    if (!u.supported) return;
    final already = u.available;
    final release = await u.checkAutomatically();
    // Prompt once per build found; a resume that finds the same build stays quiet.
    if (release == null || !mounted || _showing || (already != null && already.versionCode == release.versionCode)) return;
    _showing = true;
    await UpdateDialog.show(context, release);
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
