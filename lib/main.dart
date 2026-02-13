import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await MobileAds.instance.initialize();
  } catch (_) {}

  runApp(const RetroRelicsApp());
}

class RetroRelicsApp extends StatelessWidget {
  const RetroRelicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Retro Relics",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE6C47C),
          surface: Color(0xFF0F1620),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      home: const _PermissionGate(),
    );
  }
}

/// ------------------------------
/// Permission Gate
/// ------------------------------
class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate>
    with WidgetsBindingObserver {
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
          (p) => (p?.name ?? "").toLowerCase().contains("recent"),
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
      return const _Shell(child: Center(child: CircularProgressIndicator()));
    }

    if (_hasError) {
      return _Shell(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.photo_library_outlined, size: 44),
              const SizedBox(height: 14),
              Text("Gallery access",
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(
                "No photo access.\n\nOpen Settings and allow FULL access to Photos & Videos.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.75)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: PhotoManager.openSetting,
                  child: const Text("Open Settings"),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _init,
                  child: const Text("Try again"),
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

/// ------------------------------
/// Viewer Screen (MVP)
/// ------------------------------
class RetroRelicsViewer extends StatefulWidget {
  const RetroRelicsViewer({super.key});

  @override
  State<RetroRelicsViewer> createState() => _RetroRelicsViewerState();
}

class _RetroRelicsViewerState extends State<RetroRelicsViewer>
    with WidgetsBindingObserver {
  int _credits = 15;

  final Random _rng = Random();
  List<AssetEntity> _assets = [];
  AssetEntity? _current;
  final Set<String> _seen = <String>{};

  bool _busy = false;
  String? _toast;

  RewardedAd? _rewardedAd;
  bool _rewardedLoading = false;

  static const _kPrefsCredits = "rr_credits";
  static const _kPrefsCurrentId = "rr_current_id";
  static const _kPrefsSeen = "rr_seen_ids";

  // Swipe state
  double _dragDx = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreState().then((_) {
      _loadAssets();
    });
    _loadRewarded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistState();
    }
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    _credits = prefs.getInt(_kPrefsCredits) ?? 15;

    final seen = prefs.getStringList(_kPrefsSeen) ?? const <String>[];
    _seen
      ..clear()
      ..addAll(seen.take(500));
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefsCredits, _credits);
    await prefs.setStringList(_kPrefsSeen, _seen.take(500).toList());

    final currentId = _current?.id;
    if (currentId != null) {
      await prefs.setString(_kPrefsCurrentId, currentId);
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
          (p) => (p?.name ?? "").toLowerCase().contains("recent"),
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
          _toast = "No photos found.";
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
        _showToast("No photos in Recent.");
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
          setState(() => _current = match);
          return;
        }
      }

      _nextRandom();
    } catch (_) {
      setState(() {
        _busy = false;
        _toast = "Failed to load photos.";
      });
    }
  }

  void _nextRandom() {
    if (_assets.isEmpty) {
      setState(() {
        _current = null;
        _toast = "No photos available.";
      });
      return;
    }

    if (_seen.length >= max(1, (_assets.length * 0.85).floor())) {
      _seen.clear();
    }

    AssetEntity pick;
    int tries = 0;
    do {
      pick = _assets[_rng.nextInt(_assets.length)];
      tries++;
    } while (_seen.contains(pick.id) && tries < 40);

    _seen.add(pick.id);

    setState(() {
      _current = pick;
      _toast = null;
      _dragDx = 0.0;
    });

    _persistState();
  }

  void _consumeCreditOrGate(Future<void> Function() action) async {
    if (_busy) return;

    if (_credits > 0) {
      setState(() => _credits--);
      _persistState();
      await action();
      return;
    }

    _showRewardGate();
  }

  Future<void> _onKeep() async {
    _consumeCreditOrGate(() async => _nextRandom());
  }

  Future<void> _onShare() async {
    _consumeCreditOrGate(() async {
      final asset = _current;
      if (asset == null) return;

      setState(() => _busy = true);
      try {
        final file = await asset.file;
        if (file == null) {
          _showToast("Can't access this item (cloud-only / restriction).");
          return;
        }
        await Share.shareXFiles([XFile(file.path)]);
      } catch (_) {
        _showToast("Sharing failed.");
      } finally {
        setState(() => _busy = false);
      }
    });
  }

  Future<void> _onDelete() async {
    _consumeCreditOrGate(() async {
      final asset = _current;
      if (asset == null) return;

      setState(() => _busy = true);
      try {
        final deletedIds = await PhotoManager.editor.deleteWithIds([asset.id]);
        final deleted = deletedIds.isNotEmpty;

        if (deleted) {
          _assets.removeWhere((a) => a.id == asset.id);
          _seen.remove(asset.id);
          _showToast("Deleted.");
          _nextRandom();
        } else {
          _showToast("Delete canceled or not allowed.");
        }
      } catch (_) {
        _showToast("Delete failed (OS restriction/permission).");
      } finally {
        setState(() => _busy = false);
      }
    });
  }

  void _loadRewarded() {
    if (_rewardedLoading) return;

    setState(() => _rewardedLoading = true);

    RewardedAd.load(
      adUnitId: _AdIds.rewardedAndroidTest,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewarded();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _rewardedAd = null;
              _showToast("Ad failed to show. Try again.");
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
      _showToast("Ad not ready yet. Please try again.");
      _loadRewarded();
      return;
    }

    Navigator.of(context).pop();

    ad.show(
      onUserEarnedReward: (_, __) {
        setState(() => _credits = 5);
        _persistState();
        _showToast("Unlocked 5 more.");
      },
    );
  }

  void _showRewardGate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1620),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          // ✅ FIX: push buttons above system nav bar
          padding: EdgeInsets.fromLTRB(18, 16, 18, 24 + bottom + 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Text("Unlock more",
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                "Watch a short video to unlock 5 more relics.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.75)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _rewardedLoading ? null : _showRewarded,
                  child: Text(_rewardedLoading ? "Loading..." : "Watch Ad"),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Not now"),
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

  // -------------------------
  // Swipe gestures
  // -------------------------
  void _onPanUpdate(DragUpdateDetails d) {
    if (_busy || _current == null) return;
    setState(() => _dragDx += d.delta.dx);
  }

  Future<void> _onPanEnd(DragEndDetails d) async {
    if (_busy || _current == null) return;

    // threshold based on screen width
    final w = MediaQuery.of(context).size.width;
    final threshold = w * 0.22;

    if (_dragDx <= -threshold) {
      // swipe left -> delete
      setState(() => _dragDx = -w); // animate out visually
      await _onDelete();
      return;
    }

    if (_dragDx >= threshold) {
      // swipe right -> keep
      setState(() => _dragDx = w); // animate out visually
      await _onKeep();
      return;
    }

    // snap back
    setState(() => _dragDx = 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final asset = _current;

    return _Shell(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            children: [
              _TopBar(
                credits: _credits,
                onReload: _busy ? null : _loadAssets,
              ),
              const SizedBox(height: 10),

              // ✅ FIX: Give the image more vertical space.
              // Buttons are still there, but image area is bigger now.
              Expanded(
                flex: 13,
                child: GestureDetector(
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    transform: Matrix4.translationValues(_dragDx, 0, 0),
                    child: _MediaCard(asset: asset, busy: _busy),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ✅ Buttons slightly higher & tighter spacing
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ActionRow(
                      enabled: !_busy && asset != null,
                      onDelete: _onDelete,
                      onShare: _onShare,
                      onKeep: _onKeep,
                    ),
                    if (_toast != null) ...[
                      const SizedBox(height: 10),
                      _Toast(text: _toast!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  final Widget child;
  const _Shell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1.2,
            center: Alignment(-0.6, -0.8),
            colors: [
              Color(0xFF132031),
              Color(0xFF0B0F14),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final int credits;
  final VoidCallback? onReload;

  const _TopBar({required this.credits, required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFE6C47C)),
        const SizedBox(width: 8),
        Text("Retro Relics", style: Theme.of(context).textTheme.headlineSmall),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 16, color: Colors.white.withOpacity(0.85)),
              const SizedBox(width: 6),
              Text(
                "$credits",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          onPressed: onReload,
          icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.85)),
        ),
      ],
    );
  }
}

class _MediaCard extends StatelessWidget {
  final AssetEntity? asset;
  final bool busy;

  const _MediaCard({required this.asset, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1620),
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
              child: Text(
                "Loading...",
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            )
          else
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = max(200, c.maxWidth.floor());
                  final h = max(200, c.maxHeight.floor());

                  // ✅ FIX: keep aspect ratio, no distortion
                  // Image will fit inside frame (letterbox if needed).
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
          if (busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.25),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final bool enabled;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onKeep;

  const _ActionRow({
    required this.enabled,
    required this.onDelete,
    required this.onShare,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      required Color borderColor,
    }) {
      return Expanded(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: borderColor.withOpacity(enabled ? 0.35 : 0.15),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: Colors.white.withOpacity(enabled ? 0.9 : 0.5)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withOpacity(enabled ? 0.9 : 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(
          icon: Icons.delete_outline,
          label: "Delete",
          onTap: onDelete,
          borderColor: const Color(0xFFE85D5D),
        ),
        const SizedBox(width: 10),
        pill(
          icon: Icons.ios_share,
          label: "Share",
          onTap: onShare,
          borderColor: const Color(0xFF58A6FF),
        ),
        const SizedBox(width: 10),
        pill(
          icon: Icons.favorite_border,
          label: "Keep",
          onTap: onKeep,
          borderColor: const Color(0xFFE6C47C),
        ),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  final String text;
  const _Toast({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
      ),
    );
  }
}

class _AdIds {
  static const String rewardedAndroidTest =
      "ca-app-pub-3940256099942544/5224354917";
}
