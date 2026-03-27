// lib/main.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RRPalette {
  static const Color bg = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF0F1620);

  // Default theme: dark muted Blue -> Red
  static const Color blue = Color(0xFF0D2B45);
  static const Color red = Color(0xFF4B0D1F);

  static const Color keep = Color(0xFF1E4F7A);
  static const Color delete = Color(0xFF7A1E2C);
  static const Color share = Color(0xFF3A3D44);

  // Light grey theme gradient
  static const Color greyLight = Color(0xFFB8BCC6);
  static const Color greyDark = Color(0xFF2A2D33);

  // Dark grey theme gradient
  static const Color darkGreyA = Color(0xFF2B2F36);
  static const Color darkGreyB = Color(0xFF111318);

  // Black theme gradient
  static const Color blackA = Color(0xFF000000);
  static const Color blackB = Color(0xFF050607);
}

enum RRThemeMode {
  blueRed,
  lightGrey,
  darkGrey,
  black,
}

const String _kPrefsThemeMode = 'rr_theme_mode';

class RRThemeController extends ChangeNotifier {
  RRThemeController(this.mode);
  RRThemeMode mode;

  void setMode(RRThemeMode m) {
    if (mode == m) return;
    mode = m;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString(_kPrefsThemeMode, mode.name));
  }
}

class RRTheme extends InheritedNotifier<RRThemeController> {
  const RRTheme({
    super.key,
    required RRThemeController controller,
    required Widget child,
  }) : super(notifier: controller, child: child);

  static RRThemeController of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<RRTheme>();
    assert(w != null, 'RRTheme not found in widget tree');
    return w!.notifier!;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final themeStr = prefs.getString(_kPrefsThemeMode);
  final themeMode = RRThemeMode.values
          .cast<RRThemeMode?>()
          .firstWhere((m) => m?.name == themeStr, orElse: () => RRThemeMode.blueRed) ??
      RRThemeMode.blueRed;

  try {
    await MobileAds.instance.initialize();
  } catch (_) {}

  runApp(RetroRelicsApp(themeController: RRThemeController(themeMode)));
}

class RetroRelicsApp extends StatelessWidget {
  const RetroRelicsApp({super.key, required this.themeController});
  final RRThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return RRTheme(
      controller: themeController,
      child: MaterialApp(
        title: 'Retro Relics',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: RRPalette.bg,
          colorScheme: const ColorScheme.dark(
            primary: RRPalette.keep,
            surface: RRPalette.surface,
          ),
          textTheme: const TextTheme(
            headlineSmall: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        home: const _PermissionGate(),
      ),
    );
  }
}

class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> with WidgetsBindingObserver {
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasError) {
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });

    final ps = await PhotoManager.requestPermissionExtend();

    if (!ps.isAuth && !ps.isLimited) {
      setState(() {
        _loading = false;
        _hasError = true;
      });
      return;
    }

    final canRead = await _canReadAnyAsset();
    if (!canRead) {
      setState(() {
        _loading = false;
        _hasError = true;
      });
      return;
    }

    setState(() {
      _loading = false;
      _hasError = false;
    });
  }

  Future<bool> _canReadAnyAsset() async {
    try {
      final album = await _pickRecentAlbum();
      if (album == null) return false;

      final total = await album.assetCountAsync;
      if (total <= 0) return false;

      final list = await album.getAssetListPaged(page: 0, size: 1);
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<AssetPathEntity?> _pickRecentAlbum() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      onlyAll: false,
    );
    if (paths.isEmpty) return null;

    final recentByName = paths.cast<AssetPathEntity?>().firstWhere(
          (p) => (p?.name ?? '').toLowerCase().contains('recent'),
          orElse: () => null,
        );
    if (recentByName != null) return recentByName;

    final all = paths.cast<AssetPathEntity?>().firstWhere(
          (p) => p?.isAll == true,
          orElse: () => null,
        );
    if (all != null) return all;

    return paths.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _Shell(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: _rrLogoHeight(context),
                child: Image.asset(
                  'Logo/3.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              SizedBox(height: 18 * _rrScale(context)),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    if (_hasError) {
      return _Shell(
        child: Padding(
          padding: EdgeInsets.all(18 * _rrScale(context)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.photo_library_outlined, size: 44),
              const SizedBox(height: 14),
              Text('Gallery access', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(
                'No photo access.\n\nOpen Settings and allow FULL access to Photos & Videos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.75)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: PhotoManager.openSetting,
                  child: const Text('Open Settings'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _init,
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const RetroRelicsViewer();
  }
}

class RetroRelicsViewer extends StatefulWidget {
  const RetroRelicsViewer({super.key});

  @override
  State<RetroRelicsViewer> createState() => _RetroRelicsViewerState();
}

class _RetroRelicsViewerState extends State<RetroRelicsViewer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const int _kDailyRefillCap = 10;
  static const Duration _kDailyRefillPeriod = Duration(hours: 24);

  static const String _kPrefsCredits = 'rr_credits';
  static const String _kPrefsCurrentId = 'rr_current_id';
  static const String _kPrefsSeen = 'rr_seen_ids';
  static const String _kPrefsDeletedCount = 'rr_deleted_count';
  static const String _kPrefsKeptCount = 'rr_kept_count';
  static const String _kPrefsSavedSpace = 'rr_saved_space';
  static const String _kPrefsFirstLaunchAt = 'rr_first_launch_at';
  static const String _kPrefsLastDailyRefillAt = 'rr_last_daily_refill_at';

  int _credits = _kDailyRefillCap;

  final Random _rng = Random();
  List<AssetEntity> _assets = [];
  AssetEntity? _current;
  final Set<String> _seen = <String>{};

  bool _busy = false;
  String? _toast;

  RewardedAd? _rewardedAd;
  bool _rewardedLoading = false;

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  int _deletedCount = 0;
  int _keptCount = 0;
  int _savedSpaceBytes = 0;
  bool _showingStats = false;

  late AnimationController _fadeInController;
  late AnimationController _keepAnimController;
  late AnimationController _deleteAnimController;
  late AnimationController _shareAnimController;

  String? _currentAnimationType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fadeInController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _keepAnimController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _deleteAnimController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shareAnimController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _restoreState().then((_) => _loadAssets());
    _loadRewarded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rewardedAd?.dispose();
    _fadeInController.dispose();
    _keepAnimController.dispose();
    _deleteAnimController.dispose();
    _shareAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _persistState();
    }
    if (state == AppLifecycleState.resumed) {
      _checkDailyRefill(showToast: true);
    }
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();

    final storedCredits = prefs.getInt(_kPrefsCredits) ?? _kDailyRefillCap;
    _credits = storedCredits < 0
        ? 0
        : (storedCredits > _kDailyRefillCap ? _kDailyRefillCap : storedCredits);

    _deletedCount = prefs.getInt(_kPrefsDeletedCount) ?? 0;
    _keptCount = prefs.getInt(_kPrefsKeptCount) ?? 0;
    _savedSpaceBytes = prefs.getInt(_kPrefsSavedSpace) ?? 0;

    final seen = prefs.getStringList(_kPrefsSeen) ?? const <String>[];
    _seen
      ..clear()
      ..addAll(seen.take(500));

    await _applyDailyRefillIfDue(prefs, showToast: false);
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefsCredits, _credits);
    await prefs.setInt(_kPrefsDeletedCount, _deletedCount);
    await prefs.setInt(_kPrefsKeptCount, _keptCount);
    await prefs.setInt(_kPrefsSavedSpace, _savedSpaceBytes);
    await prefs.setStringList(_kPrefsSeen, _seen.take(500).toList());

    final currentId = _current?.id;
    if (currentId != null) {
      await prefs.setString(_kPrefsCurrentId, currentId);
    }
  }

  Future<void> _applyDailyRefillIfDue(SharedPreferences prefs, {required bool showToast}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final periodMs = _kDailyRefillPeriod.inMilliseconds;

    final first = prefs.getInt(_kPrefsFirstLaunchAt);
    if (first == null) {
      await prefs.setInt(_kPrefsFirstLaunchAt, nowMs);
      await prefs.setInt(_kPrefsLastDailyRefillAt, nowMs);
      _credits = _kDailyRefillCap;
      return;
    }

    final last = prefs.getInt(_kPrefsLastDailyRefillAt) ?? first;
    final elapsed = nowMs - last;

    if (elapsed < periodMs) return;

    final periods = elapsed ~/ periodMs;
    final newLast = last + (periods * periodMs);
    await prefs.setInt(_kPrefsLastDailyRefillAt, newLast);

    final before = _credits;
    _credits = _kDailyRefillCap;

    if (showToast && mounted && _credits != before) {
      _showToast('Daily tokens refilled to $_kDailyRefillCap.');
    }
  }

  Future<void> _checkDailyRefill({required bool showToast}) async {
    final prefs = await SharedPreferences.getInstance();
    final before = _credits;
    await _applyDailyRefillIfDue(prefs, showToast: showToast);
    if (!mounted) return;
    if (_credits != before) {
      setState(() {});
      _persistState();
    }
  }

  Future<AssetPathEntity?> _pickRecentAlbum() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      onlyAll: false,
    );
    if (paths.isEmpty) return null;

    final recentByName = paths.cast<AssetPathEntity?>().firstWhere(
          (p) => (p?.name ?? '').toLowerCase().contains('recent'),
          orElse: () => null,
        );
    if (recentByName != null) return recentByName;

    final all = paths.cast<AssetPathEntity?>().firstWhere(
          (p) => p?.isAll == true,
          orElse: () => null,
        );
    if (all != null) return all;

    return paths.first;
  }

  Future<void> _loadAssets() async {
    setState(() {
      _busy = true;
      _toast = null;
    });

    try {
      final recentAlbum = await _pickRecentAlbum();
      if (recentAlbum == null) {
        setState(() {
          _assets = [];
          _current = null;
          _toast = 'No photos found.';
          _busy = false;
        });
        return;
      }

      final total = await recentAlbum.assetCountAsync;
      final size = min(2000, max(0, total));
      final assets = await recentAlbum.getAssetListPaged(page: 0, size: size);

      setState(() {
        _assets = assets;
        _busy = false;
      });

      if (assets.isEmpty) {
        _showToast('No photos in Recent.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getString(_kPrefsCurrentId);

      if (lastId != null) {
        final match = assets.cast<AssetEntity?>().firstWhere(
              (a) => a?.id == lastId,
              orElse: () => null,
            );
        if (match != null) {
          setState(() {
            _current = match;
            _currentAnimationType = null;
            _dragOffset = Offset.zero;
          });
          _fadeInController.forward(from: 0.0);
          return;
        }
      }

      await _nextRandom(startup: true);
    } catch (_) {
      setState(() {
        _busy = false;
        _toast = 'Failed to load photos.';
      });
    }
  }

  Future<void> _nextRandom({bool startup = false}) async {
    if (_assets.isEmpty) {
      setState(() => _current = null);
      return;
    }

    for (int i = 0; i < 200; i++) {
      final a = _assets[_rng.nextInt(_assets.length)];
      if (_seen.contains(a.id)) continue;

      setState(() {
        _current = a;
        _currentAnimationType = null;
        _dragOffset = Offset.zero;
      });

      _fadeInController.forward(from: 0.0);

      _seen.add(a.id);
      if (_seen.length > 500) _seen.remove(_seen.first);
      if (!startup) _persistState();
      return;
    }

    setState(() => _seen.clear());
    await _nextRandom(startup: startup);
  }

  bool _consumeCreditOrGate() {
    if (_credits > 0) {
      setState(() => _credits = max(0, _credits - 1));
      _persistState();
      return true;
    }
    _showRewardGate();
    return false;
  }

  Future<void> _onKeep() async {
    if (_busy || _current == null) return;
    if (!_consumeCreditOrGate()) return;

    setState(() {
      _busy = true;
      _currentAnimationType = 'keep';
    });

    try {
      await _keepAnimController.forward(from: 0.0);
      _keepAnimController.reset();

      setState(() => _keptCount += 1);
      await _nextRandom();
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _currentAnimationType = null;
        _dragOffset = Offset.zero;
      });
      _persistState();
    }
  }

  Future<void> _onDelete() async {
    if (_busy || _current == null) return;
    if (!_consumeCreditOrGate()) return;

    final a = _current!;

    setState(() {
      _busy = true;
      _currentAnimationType = 'delete';
    });

    try {
      await _deleteAnimController.forward(from: 0.0);
      _deleteAnimController.reset();

      int bytes = 0;
      try {
        final file = await a.file;
        if (file != null) bytes = await file.length();
      } catch (_) {}

      if (bytes <= 0) {
        final w = a.size.width.round();
        final h = a.size.height.round();
        bytes = max(0, w * h * 4);
      }

      setState(() {
        _deletedCount += 1;
        _savedSpaceBytes += bytes;
      });

      try {
        await PhotoManager.editor.deleteWithIds([a.id]);
      } catch (_) {}

      await _nextRandom();
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _currentAnimationType = null;
        _dragOffset = Offset.zero;
      });
      _persistState();
    }
  }

  Future<void> _onShare() async {
    if (_busy || _current == null) return;
    if (!_consumeCreditOrGate()) return;

    final a = _current!;
    setState(() {
      _busy = true;
      _currentAnimationType = 'share';
    });

    try {
      await _shareAnimController.forward(from: 0.0);
      _shareAnimController.reset();

      final file = await a.file;
      if (file == null) {
        _showToast('Could not access file.');
        return;
      }

      await Share.shareXFiles([XFile(file.path)]);
      await _nextRandom();
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _currentAnimationType = null;
        _dragOffset = Offset.zero;
      });
      _persistState();
    }
  }

  void _loadRewarded() {
    if (_rewardedLoading) return;
    setState(() => _rewardedLoading = true);

    RewardedAd.load(
      adUnitId: _AdIds.rewardedAndroidTest,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd?.dispose();
          _rewardedAd = ad;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewarded();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewarded();
            },
          );

          setState(() => _rewardedLoading = false);
        },
        onAdFailedToLoad: (_) {
          _rewardedAd = null;
          setState(() => _rewardedLoading = false);
        },
      ),
    );
  }

  void _showRewarded() {
    final ad = _rewardedAd;
    if (ad == null) {
      _showToast('Ad not ready yet. Please try again.');
      _loadRewarded();
      return;
    }

    Navigator.of(context).pop();

    ad.show(
      onUserEarnedReward: (_, __) {
        setState(() => _credits = _kDailyRefillCap);
        _persistState();
        _showToast('Tokens refilled to $_kDailyRefillCap.');
      },
    );
  }

  void _showRewardGate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: RRPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        final s = _rrScale(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, (24 + bottom + 10) * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44 * s,
                height: 5 * s,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              SizedBox(height: 14 * s),
              Text(
                'Out of tokens',
                style: TextStyle(
                  fontSize: 18 * s,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10 * s),
              Text(
                'Watch a short video to refill your tokens to $_kDailyRefillCap.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 13 * s),
              ),
              SizedBox(height: 18 * s),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _rewardedLoading ? null : _showRewarded,
                  child: Text(_rewardedLoading ? 'Loading...' : 'Watch Ad'),
                ),
              ),
              SizedBox(height: 10 * s),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Not now'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showToast(String message) {
    setState(() => _toast = message);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_toast == message) setState(() => _toast = null);
    });
  }

  void _showStats() {
    if (_showingStats) return;
    setState(() => _showingStats = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showingStats = false);
    });
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: RRPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final s = _rrScale(ctx);
        final bottom = MediaQuery.of(ctx).padding.bottom;
        final theme = RRTheme.of(ctx);

        Widget themeRadio(RRThemeMode m, String label) {
          return RadioListTile<RRThemeMode>(
            value: m,
            groupValue: theme.mode,
            onChanged: (v) {
              if (v == null) return;
              theme.setMode(v);
            },
            title: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14 * s),
            ),
            activeColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(horizontal: 10 * s),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(14 * s, 14 * s, 14 * s, (bottom + 14) * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44 * s,
                height: 5 * s,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              SizedBox(height: 12 * s),
              Row(
                children: [
                  Icon(Icons.settings, size: 18 * s, color: Colors.white.withOpacity(0.9)),
                  SizedBox(width: 10 * s),
                  Text(
                    'Settings',
                    style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              SizedBox(height: 10 * s),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 6 * s, top: 6 * s, bottom: 6 * s),
                  child: Text(
                    'Theme',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13 * s,
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    themeRadio(RRThemeMode.blueRed, 'Blue → Red'),
                    themeRadio(RRThemeMode.lightGrey, 'Light Grey → Dark Grey'),
                    themeRadio(RRThemeMode.darkGrey, 'Dark Grey'),
                    themeRadio(RRThemeMode.black, 'Black'),
                  ],
                ),
              ),
              SizedBox(height: 10 * s),
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: Colors.white.withOpacity(0.05),
                leading: const Text('📊', style: TextStyle(fontSize: 18)),
                title: Text(
                  'Stats',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14 * s),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showStats();
                },
              ),
              SizedBox(height: 8 * s),
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: Colors.white.withOpacity(0.05),
                leading: Icon(Icons.privacy_tip_outlined,
                    size: 18 * s, color: Colors.white.withOpacity(0.9)),
                title: Text(
                  'Privacy Policy',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14 * s),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openPrivacyPolicy();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: RRPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final s = _rrScale(ctx);
        final bottom = MediaQuery.of(ctx).padding.bottom;

        const text = '''
Privacy Policy

Retro Relics runs entirely locally on your device.

• Photos are accessed only through your phone’s media library APIs.
• No photos are uploaded, shared, or sent to any server.
• The app does not transmit your images to the internet.

Verification tip:
You can enable Airplane Mode and use the app to confirm that photos still load and browsing still works. (Only ads may require an internet connection.)
''';

        return Padding(
          padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, (bottom + 14) * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44 * s,
                height: 5 * s,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              SizedBox(height: 12 * s),
              Row(
                children: [
                  Icon(Icons.privacy_tip_outlined,
                      size: 18 * s, color: Colors.white.withOpacity(0.9)),
                  SizedBox(width: 10 * s),
                  Text(
                    'Privacy Policy',
                    style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              SizedBox(height: 10 * s),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14 * s),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    height: 1.35,
                    fontSize: 13 * s,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: 10 * s),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onPanStart(DragStartDetails d) {
    if (_busy || _current == null) return;
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_busy || _current == null) return;
    setState(() {
      final nextDx = (_dragOffset.dx + d.delta.dx).clamp(-220.0, 220.0).toDouble();
      _dragOffset = Offset(nextDx, 0);
    });
  }

  Future<void> _onPanEnd(DragEndDetails d) async {
    if (_busy || _current == null) return;

    final w = MediaQuery.of(context).size.width;
    final threshold = w * 0.22;
    final dx = _dragOffset.dx;

    if (dx <= -threshold) {
      setState(() => _dragOffset = Offset(-w, 0));
      await _onDelete();
      if (mounted) setState(() => _isDragging = false);
      return;
    }

    if (dx >= threshold) {
      setState(() => _dragOffset = Offset(w, 0));
      await _onKeep();
      if (mounted) setState(() => _isDragging = false);
      return;
    }

    setState(() {
      _dragOffset = Offset.zero;
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final asset = _current;
    final media = MediaQuery.of(context);
    final s = _rrScale(context);

    final sidePadding =
        (media.size.width * 0.04).clamp(12.0, 22.0).toDouble();
    final topPadding = (10.0 * s).clamp(8.0, 16.0).toDouble();
    final controlToCardGap = ((24.0 * s) * 0.70).clamp(15.0, 22.0).toDouble();
    final toastGap = (12.0 * s).clamp(10.0, 18.0).toDouble();

    final topButtonSize = (48.0 * s).clamp(44.0, 58.0).toDouble();
    final tokenWidth = topButtonSize;
    final bottomButtonHeight = (56.0 * s).clamp(50.0, 68.0).toDouble();
    final bottomSafeGap = max(media.padding.bottom + (14.0 * s), 24.0 * s).toDouble();

    final largeLogoHeight =
        (_rrLogoHeight(context) * 0.98).clamp(42.0, 70.0).toDouble();
    final headerHeight = max(topButtonSize, largeLogoHeight);

    return _Shell(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(sidePadding, topPadding, sidePadding, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final toastHeight =
                  _toast == null ? 0.0 : (44.0 * s).clamp(40.0, 54.0).toDouble();
              final actionColumnHeight = bottomButtonHeight +
                  (_toast == null ? 0.0 : toastGap + toastHeight);
              final bottomContentHeight =
                  controlToCardGap + actionColumnHeight + bottomSafeGap;
              final cardHeight = max(
                constraints.maxHeight - headerHeight - controlToCardGap - bottomContentHeight,
                220.0 * s,
              );

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: headerHeight,
                    child: _TopBar(
                      credits: _credits,
                      onReload: _busy ? null : _loadAssets,
                      onOpenSettings: _openSettings,
                      buttonSize: topButtonSize,
                      tokenWidth: tokenWidth,
                      logoHeight: largeLogoHeight,
                      minGap: controlToCardGap,
                      onOpenRewards: _showRewardGate,
                    ),
                  ),
                  Positioned(
                    top: headerHeight + controlToCardGap,
                    left: 0,
                    right: 0,
                    height: cardHeight,
                    child: GestureDetector(
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: AnimatedContainer(
                        duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        transform: Matrix4.translationValues(_dragOffset.dx, 0, 0),
                        child: _MediaCard(
                          asset: asset,
                          busy: _busy,
                          fadeInController: _fadeInController,
                          keepAnimController: _keepAnimController,
                          deleteAnimController: _deleteAnimController,
                          shareAnimController: _shareAnimController,
                          animationType: _currentAnimationType,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomSafeGap,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionRow(
                          enabled: !_busy && asset != null,
                          onDelete: _onDelete,
                          onShare: _onShare,
                          onKeep: _onKeep,
                          height: bottomButtonHeight,
                        ),
                        if (_toast != null) ...[
                          SizedBox(height: toastGap),
                          _Toast(text: _toast!),
                        ],
                      ],
                    ),
                  ),
                  if (_showingStats)
                    Positioned(
                      top: headerHeight + controlToCardGap + (12 * s),
                      left: 0,
                      right: 0,
                      child: _StatsOverlay(
                        deletedCount: _deletedCount,
                        keptCount: _keptCount,
                        savedSpaceBytes: _savedSpaceBytes,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = RRTheme.of(context);

    LinearGradient gradient;
    switch (theme.mode) {
      case RRThemeMode.blueRed:
        gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RRPalette.blue, RRPalette.red, RRPalette.bg],
        );
        break;
      case RRThemeMode.lightGrey:
        gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RRPalette.greyLight, RRPalette.greyDark],
        );
        break;
      case RRThemeMode.darkGrey:
        gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RRPalette.darkGreyA, RRPalette.darkGreyB],
        );
        break;
      case RRThemeMode.black:
        gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RRPalette.blackA, RRPalette.blackB],
        );
        break;
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: child,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.credits,
    required this.onReload,
    required this.onOpenSettings,
    required this.buttonSize,
    required this.tokenWidth,
    required this.logoHeight,
    required this.minGap,
    required this.onOpenRewards,
  });

  final int credits;
  final VoidCallback? onReload;
  final VoidCallback onOpenSettings;
  final double buttonSize;
  final double tokenWidth;
  final double logoHeight;
  final double minGap;
  final VoidCallback onOpenRewards;

  @override
  Widget build(BuildContext context) {
    final rowHeight = max(buttonSize, logoHeight);
    final topOffset = (rowHeight - buttonSize) / 2;
    final horizontalLogoGap = (minGap * 0.40).clamp(6.0, 10.0).toDouble();

    return SizedBox(
      height: rowHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxLogoWidth = max(
            0.0,
            constraints.maxWidth - buttonSize - tokenWidth - (horizontalLogoGap * 2),
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Center(
                  child: GestureDetector(
                    onTap: onReload,
                    child: IgnorePointer(
                      ignoring: onReload == null,
                      child: SizedBox(
                        width: maxLogoWidth,
                        height: logoHeight,
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Image.asset(
                              'Logo/3.png',
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: topOffset,
                left: 0,
                child: _TopCircleButton(
                  size: buttonSize,
                  icon: Icons.settings,
                  onTap: onOpenSettings,
                ),
              ),
              Positioned(
                top: topOffset,
                right: 0,
                child: _TokenPill(
                  height: buttonSize,
                  width: buttonSize,
                  credits: credits,
                  onTap: onOpenRewards,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({
    required this.size,
    required this.icon,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = _rrScale(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: (16.0 * s).clamp(14.0, 20.0).toDouble(),
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ),
    );
  }
}

class _TokenPill extends StatelessWidget {
  const _TokenPill({
    required this.height,
    required this.width,
    required this.credits,
    required this.onTap,
  });

  final double height;
  final double width;
  final int credits;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = _rrScale(context);
    final iconSize = (14.5 * s).clamp(13.0, 17.0).toDouble();
    final numberSize = (8.2 * s).clamp(7.0, 10.0).toDouble();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(height / 2),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bolt, size: iconSize, color: Colors.white.withOpacity(0.9)),
              SizedBox(height: 1.5 * s),
              Text(
                '$credits',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withOpacity(0.95),
                  fontSize: numberSize,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.asset,
    required this.busy,
    required this.fadeInController,
    required this.keepAnimController,
    required this.deleteAnimController,
    required this.shareAnimController,
    this.animationType,
  });

  final AssetEntity? asset;
  final bool busy;
  final AnimationController fadeInController;
  final AnimationController keepAnimController;
  final AnimationController deleteAnimController;
  final AnimationController shareAnimController;
  final String? animationType;

  @override
  Widget build(BuildContext context) {
    final fadeAnimation = CurvedAnimation(parent: fadeInController, curve: Curves.easeOut);
    final scaleInAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: fadeInController, curve: Curves.easeOutCubic),
    );

    final keepScaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: keepAnimController, curve: Curves.easeInOut),
    );

    final deleteOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: deleteAnimController, curve: Curves.easeIn),
    );
    final deleteScaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: deleteAnimController, curve: Curves.easeIn),
    );

    final shareOffsetAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.03)).animate(
      CurvedAnimation(parent: shareAnimController, curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([
        fadeInController,
        keepAnimController,
        deleteAnimController,
        shareAnimController,
      ]),
      builder: (context, child) {
        double scale = scaleInAnimation.value;
        double opacity = fadeAnimation.value;
        Offset offset = Offset.zero;

        if (animationType == 'keep') {
          scale *= keepScaleAnimation.value;
        } else if (animationType == 'delete') {
          scale *= deleteScaleAnimation.value;
          opacity *= deleteOpacityAnimation.value;
        } else if (animationType == 'share') {
          offset = shareOffsetAnimation.value;
        }

        return Transform.translate(
          offset: offset,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: RRPalette.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Stack(
                  children: [
                    if (asset == null)
                      Center(
                        child: Text('Loading...', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                      )
                    else
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final w = max(200, c.maxWidth.floor());
                            final h = max(200, c.maxHeight.floor());
                            return AssetEntityImage(
                              asset!,
                              isOriginal: false,
                              thumbnailSize: ThumbnailSize(w, h),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            );
                          },
                        ),
                      ),
                    if (animationType == 'keep' && keepAnimController.value > 0)
                      Center(
                        child: Transform.scale(
                          scale: keepAnimController.value * 3,
                          child: Opacity(
                            opacity: 1.0 - keepAnimController.value,
                            child: const Icon(Icons.favorite, color: RRPalette.keep, size: 52),
                          ),
                        ),
                      ),
                    if (busy)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.25),
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.enabled,
    required this.onDelete,
    required this.onShare,
    required this.onKeep,
    required this.height,
  });

  final bool enabled;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onKeep;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = _rrScale(context);

    return Row(
      children: [
        Expanded(
          child: _PrimaryActionButton(
            enabled: enabled,
            label: 'Delete',
            leadingText: '🗑️',
            bgColor: RRPalette.delete,
            borderColor: RRPalette.delete,
            height: height,
            onTap: onDelete,
          ),
        ),
        SizedBox(width: 10 * s),
        Expanded(
          child: _PrimaryActionButton(
            enabled: enabled,
            label: 'Share',
            bgColor: RRPalette.share,
            borderColor: RRPalette.share,
            height: height,
            onTap: onShare,
          ),
        ),
        SizedBox(width: 10 * s),
        Expanded(
          child: _PrimaryActionButton(
            enabled: enabled,
            label: 'Keep',
            trailingText: '❤️',
            bgColor: RRPalette.keep,
            borderColor: RRPalette.keep,
            height: height,
            onTap: onKeep,
          ),
        ),
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.enabled,
    required this.label,
    required this.bgColor,
    required this.borderColor,
    required this.height,
    required this.onTap,
    this.leadingText,
    this.trailingText,
  });

  final bool enabled;
  final String label;
  final Color bgColor;
  final Color borderColor;
  final double height;
  final VoidCallback onTap;
  final String? leadingText;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final s = _rrScale(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(height / 2),
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: 14 * s),
          decoration: BoxDecoration(
            color: bgColor.withOpacity(enabled ? 0.68 : 0.22),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: borderColor.withOpacity(enabled ? 0.95 : 0.35),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: bgColor.withOpacity(enabled ? 0.22 : 0.0),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingText != null) ...[
                    Text(leadingText!, style: TextStyle(fontSize: 17 * s)),
                    SizedBox(width: 8 * s),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(enabled ? 0.95 : 0.55),
                      fontSize: 14 * s,
                    ),
                  ),
                  if (trailingText != null) ...[
                    SizedBox(width: 8 * s),
                    Text(trailingText!, style: TextStyle(fontSize: 17 * s)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _Toast extends StatelessWidget {
  const _Toast({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = _rrScale(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13 * s),
      ),
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay({
    required this.deletedCount,
    required this.keptCount,
    required this.savedSpaceBytes,
  });

  final int deletedCount;
  final int keptCount;
  final int savedSpaceBytes;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final s = _rrScale(context);

    return Container(
      padding: EdgeInsets.all(18 * s),
      decoration: BoxDecoration(
        color: RRPalette.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 24)),
              SizedBox(width: 10 * s),
              Text(
                'Statistiken',
                style: TextStyle(
                  fontSize: 20 * s,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
            ],
          ),
          SizedBox(height: 16 * s),
          _StatRow(icon: '🗑️', label: 'Gelöscht', value: '$deletedCount', color: RRPalette.delete),
          SizedBox(height: 10 * s),
          _StatRow(icon: '❤️', label: 'Behalten', value: '$keptCount', color: RRPalette.keep),
          SizedBox(height: 10 * s),
          _StatRow(icon: '💾', label: 'Gespart', value: _formatBytes(savedSpaceBytes), color: RRPalette.share),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final String icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = _rrScale(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          SizedBox(width: 10 * s),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.9),
                fontSize: 14 * s,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 16 * s,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdIds {
  static const String rewardedAndroidTest = 'ca-app-pub-3940256099942544/5224354917';
}

double _rrScale(BuildContext context) {
  final shortest = MediaQuery.of(context).size.shortestSide;
  return (shortest / 390.0).clamp(0.85, 1.20).toDouble();
}

double _rrLogoHeight(BuildContext context) {
  final h = MediaQuery.of(context).size.height;
  final s = _rrScale(context);
  final base = (h * 0.07).clamp(44.0, 72.0).toDouble();
  final factor = (s.clamp(0.95, 1.05)).toDouble();
  return base * factor;
}
