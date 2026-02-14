import 'dart:math';
import 'package:flutter/services.dart';

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
      return _Shell(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 150,
                child: Image.asset(
                  'Logo/3.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _credits = 150;

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
  static const _kPrefsDeletedCount = "rr_deleted_count";
  static const _kPrefsKeptCount = "rr_kept_count";
  static const _kPrefsSavedSpace = "rr_saved_space";

  // Swipe state
  double _dragDx = 0.0;
  
  // Stats
  int _deletedCount = 0;
  int _keptCount = 0;
  int _savedSpaceBytes = 0;
  bool _showingStats = false;
  
  // Animation state
  late AnimationController _fadeInController;
  late AnimationController _keepAnimController;
  late AnimationController _deleteAnimController;
  late AnimationController _shareAnimController;
  
  String? _currentAnimationType; // 'keep', 'delete', 'share'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize animation controllers
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _keepAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _deleteAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shareAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    _restoreState().then((_) {
      _loadAssets();
    });
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistState();
    }
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    _credits = prefs.getInt(_kPrefsCredits) ?? 15;
    _deletedCount = prefs.getInt(_kPrefsDeletedCount) ?? 0;
    _keptCount = prefs.getInt(_kPrefsKeptCount) ?? 0;
    _savedSpaceBytes = prefs.getInt(_kPrefsSavedSpace) ?? 0;

    final seen = prefs.getStringList(_kPrefsSeen) ?? const <String>[];
    _seen
      ..clear()
      ..addAll(seen.take(500));
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
          setState(() {
            _current = match;
            _currentAnimationType = null;
          });
          _fadeInController.forward(from: 0.0);
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
      _currentAnimationType = null;
    });
    
    // Trigger fade-in animation
    _fadeInController.forward(from: 0.0);

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
    _consumeCreditOrGate(() async {
      setState(() {
        _currentAnimationType = 'keep';
        _keptCount++;
      });
      _persistState();
      _keepAnimController.forward(from: 0.0);
      await Future.delayed(const Duration(milliseconds: 400));
      _nextRandom();
    });
  }

  Future<void> _onShare() async {
    _consumeCreditOrGate(() async {
      final asset = _current;
      if (asset == null) return;

      setState(() {
        _busy = true;
        _currentAnimationType = 'share';
      });
      _shareAnimController.forward(from: 0.0);
      await Future.delayed(const Duration(milliseconds: 300));
      
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
        _shareAnimController.reverse();
      }
    });
  }

  Future<void> _onDelete() async {
    _consumeCreditOrGate(() async {
      final asset = _current;
      if (asset == null) return;

      setState(() {
        _busy = true;
        _currentAnimationType = 'delete';
      });
      _deleteAnimController.forward(from: 0.0);
      await Future.delayed(const Duration(milliseconds: 400));
      
      try {
        // Get file size before deletion
        int fileSize = 0;
        try {
          final file = await asset.file;
          if (file != null) {
            fileSize = await file.length();
          }
        } catch (_) {}
        
        final deletedIds = await PhotoManager.editor.deleteWithIds([asset.id]);
        final deleted = deletedIds.isNotEmpty;

        if (deleted) {
          _assets.removeWhere((a) => a.id == asset.id);
          _seen.remove(asset.id);
          setState(() {
            _deletedCount++;
            _savedSpaceBytes += fileSize;
          });
          _persistState();
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
        setState(() => _credits = 50);
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

  void _showStats() {
    if (_showingStats) return;
    setState(() => _showingStats = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showingStats = false);
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
      child: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  _TopBar(
                    credits: _credits,
                    onReload: _busy ? null : _loadAssets,
                    onStats: _showStats,
                  ),
                  const SizedBox(height: 6),

                  // ✅ FIX: Give the image more vertical space.
                  // Buttons are still there, but image area is bigger now.
                  Expanded(
                    flex: 15,
                    child: GestureDetector(
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        transform: Matrix4.translationValues(_dragDx, 0, 0),
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

                  const SizedBox(height: 8),

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
                          imageDragDx: _dragDx,
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
          // Stats Overlay
          if (_showingStats)
            Positioned(
              top: 120,
              left: 20,
              right: 20,
              child: _StatsOverlay(
                deletedCount: _deletedCount,
                keptCount: _keptCount,
                savedSpaceBytes: _savedSpaceBytes,
              ),
            ),
        ],
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
  final VoidCallback? onStats;

  const _TopBar({required this.credits, required this.onReload, this.onStats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo oben, zentriert
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: SizedBox(
            height: 60,
            child: Image.asset(
              'Logo/3.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Stats Icon
            GestureDetector(
              onTap: onStats,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    Text(
                      "📊",
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Stats",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Credits
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
          ],
        ),
      ],
    );
  }
}

class _MediaCard extends StatelessWidget {
  final AssetEntity? asset;
  final bool busy;
  final AnimationController fadeInController;
  final AnimationController keepAnimController;
  final AnimationController deleteAnimController;
  final AnimationController shareAnimController;
  final String? animationType;

  const _MediaCard({
    required this.asset,
    required this.busy,
    required this.fadeInController,
    required this.keepAnimController,
    required this.deleteAnimController,
    required this.shareAnimController,
    this.animationType,
  });

  @override
  Widget build(BuildContext context) {
    // Fade-in animation
    final fadeAnimation = CurvedAnimation(
      parent: fadeInController,
      curve: Curves.easeOut,
    );
    
    // Scale-in animation
    final scaleInAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: fadeInController, curve: Curves.easeOutCubic),
    );
    
    // Keep animation (scale pulse)
    final keepScaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: keepAnimController, curve: Curves.easeInOut),
    );
    
    // Delete animation (dissolve)
    final deleteOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: deleteAnimController, curve: Curves.easeIn),
    );
    final deleteScaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: deleteAnimController, curve: Curves.easeIn),
    );
    
    // Share animation (lift)
    final shareOffsetAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.03)).animate(
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
        
        // Apply animation based on type
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
                    // Keep animation overlay (heart)
                    if (animationType == 'keep' && keepAnimController.value > 0)
                      Center(
                        child: Transform.scale(
                          scale: keepAnimController.value * 3,
                          child: Opacity(
                            opacity: 1.0 - keepAnimController.value,
                            child: Icon(
                              Icons.favorite,
                              color: const Color(0xFF5E2D91),
                              size: 50,
                            ),
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
  final bool enabled;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onKeep;
  final double imageDragDx;

  const _ActionRow({
    required this.enabled,
    required this.onDelete,
    required this.onShare,
    required this.onKeep,
    this.imageDragDx = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final threshold = w * 0.22;
    // Swipe links auf Bild → Delete-Kreis zieht mit nach links (dragDx < 0)
    final deleteFraction = imageDragDx < 0 ? (-imageDragDx / threshold).clamp(0.0, 1.0) : 0.0;
    // Swipe rechts auf Bild → Keep-Kreis zieht mit nach rechts (dragDx > 0)
    final keepFraction = imageDragDx > 0 ? (imageDragDx / threshold).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        // Keep: Kreis startet links, schieben nach rechts (zur Mitte)
        Expanded(
          child: _SlideToConfirmButton(
            icon: Icons.favorite_border,
            arrowIcon: Icons.arrow_forward,
            label: "Keep",
            bgColor: const Color(0xFF5E2D91),
            borderColor: const Color(0xFF5E2D91),
            slideFromLeft: true,
            enabled: enabled,
            onConfirm: onKeep,
            externalDragFraction: keepFraction,
          ),
        ),
        const SizedBox(width: 10),
        // Share bleibt ein normaler Button - kleiner in der Mitte
        SizedBox(
          width: 80,
          child: InkWell(
            onTap: enabled ? onShare : null,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFA23289).withOpacity(enabled ? 0.25 : 0.15),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFFA23289).withOpacity(enabled ? 0.6 : 0.3),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.ios_share,
                      size: 18,
                      color: Colors.white.withOpacity(enabled ? 0.9 : 0.5)),
                  const SizedBox(width: 8),
                  Text(
                    "Share",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(enabled ? 0.9 : 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Delete: Kreis startet rechts, schieben nach links (zur Mitte)
        Expanded(
          child: _SlideToConfirmButton(
            icon: Icons.delete_outline,
            arrowIcon: Icons.arrow_back,
            label: "Delete",
            bgColor: const Color(0xFFE63780),
            borderColor: const Color(0xFFE85D5D),
            slideFromLeft: false,
            enabled: enabled,
            onConfirm: onDelete,
            externalDragFraction: deleteFraction,
          ),
        ),
      ],
    );
  }
}

/// Slide-to-confirm: Kreis wird zur Mitte gezogen, um die Aktion auszulösen.
class _SlideToConfirmButton extends StatefulWidget {
  final IconData icon;
  final IconData arrowIcon;
  final String label;
  final Color bgColor;
  final Color borderColor;
  final bool slideFromLeft; // true = Kreis startet links, false = rechts
  final bool enabled;
  final VoidCallback onConfirm;
  final double externalDragFraction;

  const _SlideToConfirmButton({
    required this.icon,
    required this.arrowIcon,
    required this.label,
    required this.bgColor,
    required this.borderColor,
    required this.slideFromLeft,
    required this.enabled,
    required this.onConfirm,
    this.externalDragFraction = 0.0,
  });

  @override
  State<_SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<_SlideToConfirmButton>
    with SingleTickerProviderStateMixin {
  double _dragFraction = 0.0; // 0 = am Rand, 1 = ganz zur Mitte geschoben
  bool _confirmed = false;

  late AnimationController _snapBack;

  static const double _circleSize = 60.0;
  static const double _trackHeight = 44.0;

  @override
  void initState() {
    super.initState();
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        setState(() {
          _dragFraction = _snapBack.value * _dragFraction;
        });
      });
  }

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, double maxSlide) {
    if (!widget.enabled || _confirmed) return;
    setState(() {
      if (widget.slideFromLeft) {
        // Kreis startet links → positive dx = nach rechts schieben
        _dragFraction = (_dragFraction + details.delta.dx / maxSlide).clamp(0.0, 1.0);
      } else {
        // Kreis startet rechts → negative dx = nach links schieben
        _dragFraction = (_dragFraction - details.delta.dx / maxSlide).clamp(0.0, 1.0);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.enabled || _confirmed) return;
    if (_dragFraction >= 0.75) {
      setState(() {
        _confirmed = true;
        _dragFraction = 1.0;
      });
      widget.onConfirm();
      // Reset nach kurzer Verzögerung
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _confirmed = false;
            _dragFraction = 0.0;
          });
        }
      });
    } else {
      // Snap back
      final startFraction = _dragFraction;
      _snapBack.reset();
      _snapBack.addListener(_snapBackListener(startFraction));
      _snapBack.forward();
    }
  }

  VoidCallback _snapBackListener(double startFraction) {
    late VoidCallback listener;
    listener = () {
      setState(() {
        _dragFraction = startFraction * (1 - _snapBack.value);
      });
      if (_snapBack.isCompleted) {
        _snapBack.removeListener(listener);
      }
    };
    return listener;
  }

  @override
  Widget build(BuildContext context) {
    final borderHighlight = widget.borderColor.withOpacity(0.9);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxSlide = trackWidth - _circleSize;
        // Nutze das Maximum aus internem Drag und externem (Bild-Swipe)
        final effectiveFraction = max(_dragFraction, widget.externalDragFraction).clamp(0.0, 1.0);
        final circleOffset = effectiveFraction * maxSlide;
        
        // Hervorhebungs-Effekte basierend auf Drag-Fortschritt
        final highlightIntensity = effectiveFraction;
        final scaleValue = 1.0 + (highlightIntensity * 0.05); // Bis zu 5% größer
        final glowBlur = 6.0 + (highlightIntensity * 12.0); // Bis zu 18 blur
        final glowSpread = highlightIntensity * 3.0;
        final textOpacity = 0.85 + (highlightIntensity * 0.15); // Bis zu 1.0

        return Transform.scale(
          scale: scaleValue,
          child: Container(
            height: _trackHeight,
            decoration: BoxDecoration(
              color: widget.bgColor.withOpacity(0.6 + highlightIntensity * 0.2),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderHighlight, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: widget.bgColor.withOpacity(0.2 + highlightIntensity * 0.5),
                  blurRadius: glowBlur,
                  spreadRadius: glowSpread,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Label + Icon im Track
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Align(
                    alignment: widget.slideFromLeft ? Alignment.centerRight : Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.slideFromLeft
                          ? [
                              // Keep: Text zuerst, dann Icon (rechtsbündig)
                              Text(
                                widget.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withOpacity(textOpacity),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(widget.icon, size: 18, color: Colors.white.withOpacity(textOpacity)),
                            ]
                          : [
                              // Delete: Icon zuerst, dann Text (linksbündig)
                              Icon(widget.icon, size: 18, color: Colors.white.withOpacity(textOpacity)),
                              const SizedBox(width: 6),
                              Text(
                                widget.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withOpacity(textOpacity),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                    ),
                  ),
                ),
                // Draggable Kreis
                Positioned(
                  left: widget.slideFromLeft ? circleOffset : null,
                  right: widget.slideFromLeft ? null : circleOffset,
                  top: (_trackHeight - _circleSize) / 2,
                  child: GestureDetector(
                    onPanUpdate: (d) => _onPanUpdate(d, maxSlide),
                    onPanEnd: _onPanEnd,
                    child: AnimatedContainer(
                      duration: _confirmed
                          ? const Duration(milliseconds: 200)
                          : Duration.zero,
                      width: _circleSize,
                      height: _circleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.bgColor,
                        border: Border.all(color: borderHighlight, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: widget.bgColor.withOpacity(0.45 + highlightIntensity * 0.35),
                            blurRadius: 10 + highlightIntensity * 15,
                            spreadRadius: 1 + highlightIntensity * 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.arrowIcon,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

class _StatsOverlay extends StatelessWidget {
  final int deletedCount;
  final int keptCount;
  final int savedSpaceBytes;

  const _StatsOverlay({
    required this.deletedCount,
    required this.keptCount,
    required this.savedSpaceBytes,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1620).withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                "📊",
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 10),
              Text(
                "Statistiken",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StatRow(
            icon: "🗑️",
            label: "Gelöscht",
            value: "$deletedCount",
            color: const Color(0xFFE63780),
          ),
          const SizedBox(height: 10),
          _StatRow(
            icon: "❤️",
            label: "Behalten",
            value: "$keptCount",
            color: const Color(0xFF5E2D91),
          ),
          const SizedBox(height: 10),
          _StatRow(
            icon: "💾",
            label: "Gespart",
            value: _formatBytes(savedSpaceBytes),
            color: const Color(0xFFA23289),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdIds {
  static const String rewardedAndroidTest =
      "ca-app-pub-3940256099942544/5224354917";
}
