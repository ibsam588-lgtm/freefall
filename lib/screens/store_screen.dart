// screens/store_screen.dart
//
// Six-tab cosmetic + upgrade store. Top-of-screen coin pill stays in
// sync with [CoinRepository.balanceStream]; tabs scroll horizontally
// and host a grid of cards. Cosmetic cards show ownership + equip
// state; upgrade cards show level progress + cost-of-next-level;
// coin-pack tab is a stubbed list for Phase 12 IAP.
//
// State machine per cosmetic card:
//   not owned + cant afford → grayed Buy button
//   not owned + affordable  → Buy button → preview overlay → purchase
//   owned + not equipped    → Equip button (teal)
//   owned + equipped        → "Equipped" badge
//
// Upgrade cards have a 3-step progress bar + Buy button for the
// next level (or "MAX" badge at level 3).

import 'dart:async';

import 'package:flutter/material.dart';

import '../components/store_item_preview.dart';
import '../models/death_effect.dart';
import '../models/powerup_upgrade.dart';
import '../models/shield_skin.dart';
import '../models/trail_effect.dart';
import '../repositories/coin_repository.dart';
import '../repositories/store_repository.dart';
import '../store/store_inventory.dart';

class StoreScreen extends StatefulWidget {
  final CoinRepository coinRepo;
  final StoreRepository storeRepo;

  const StoreScreen({
    super.key,
    required this.coinRepo,
    required this.storeRepo,
  });

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<int>? _balanceSub;

  // Live state, refreshed after every purchase / equip.
  int _balance = 0;
  Set<String> _owned = const {};
  String _equippedSkin = '';
  String _equippedTrail = '';
  String _equippedShield = '';
  String _equippedDeath = '';
  Map<PowerupUpgradeId, int> _upgradeLevels = const {};

  static const _tabs = <_StoreTabSpec>[
    _StoreTabSpec(StoreCategory.skins, 'Skins'),
    _StoreTabSpec(StoreCategory.trails, 'Trails'),
    _StoreTabSpec(StoreCategory.shields, 'Shields'),
    _StoreTabSpec(StoreCategory.deathEffects, 'Death FX'),
    _StoreTabSpec(StoreCategory.upgrades, 'Upgrades'),
    _StoreTabSpec(StoreCategory.coinPacks, 'Coin Packs'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final balance = await widget.coinRepo.getBalance();
    final owned = await widget.storeRepo.getOwnedItems();
    final eqSkin = await widget.storeRepo.getEquippedSkin();
    final eqTrail = await widget.storeRepo.getEquippedTrail();
    final eqShield = await widget.storeRepo.getEquippedShield();
    final eqDeath = await widget.storeRepo.getEquippedDeathEffect();
    final levels = <PowerupUpgradeId, int>{};
    for (final u in PowerupUpgrade.catalog) {
      levels[u.id] = await widget.storeRepo.getUpgradeLevelById(u.id);
    }
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _owned = owned;
      _equippedSkin = StoreInventory.skinIdOf(eqSkin);
      _equippedTrail = StoreInventory.trailIdOf(eqTrail);
      _equippedShield = StoreInventory.shieldIdOf(eqShield);
      _equippedDeath = StoreInventory.deathIdOf(eqDeath);
      _upgradeLevels = levels;
    });

    _balanceSub = widget.coinRepo.balanceStream.listen((next) {
      if (!mounted) return;
      setState(() => _balance = next);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _balanceSub?.cancel();
    super.dispose();
  }

  bool _isEquipped(StoreItem item) => switch (item.category) {
        StoreCategory.skins => item.id == _equippedSkin,
        StoreCategory.trails => item.id == _equippedTrail,
        StoreCategory.shields => item.id == _equippedShield,
        StoreCategory.deathEffects => item.id == _equippedDeath,
        StoreCategory.upgrades => false,
        StoreCategory.coinPacks => false,
      };

  bool _isOwned(StoreItem item) {
    if (item.isDefaultTier) return true;
    return _owned.contains(item.id);
  }

  // ---- actions ------------------------------------------------------------

  Future<void> _equip(StoreItem item) async {
    try {
      await widget.storeRepo.equipItem(item.id);
      // Pull fresh equipped slot for THIS category only — don't re-load
      // the whole repo for a single change.
      final next = await switch (item.category) {
        StoreCategory.skins => widget.storeRepo
            .getEquippedSkin()
            .then(StoreInventory.skinIdOf),
        StoreCategory.trails => widget.storeRepo
            .getEquippedTrail()
            .then(StoreInventory.trailIdOf),
        StoreCategory.shields => widget.storeRepo
            .getEquippedShield()
            .then(StoreInventory.shieldIdOf),
        StoreCategory.deathEffects => widget.storeRepo
            .getEquippedDeathEffect()
            .then(StoreInventory.deathIdOf),
        StoreCategory.upgrades || StoreCategory.coinPacks => Future.value(''),
      };
      if (!mounted) return;
      setState(() {
        switch (item.category) {
          case StoreCategory.skins:
            _equippedSkin = next;
            break;
          case StoreCategory.trails:
            _equippedTrail = next;
            break;
          case StoreCategory.shields:
            _equippedShield = next;
            break;
          case StoreCategory.deathEffects:
            _equippedDeath = next;
            break;
          case StoreCategory.upgrades:
          case StoreCategory.coinPacks:
            break;
        }
      });
    } on StateError catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _showPreview(StoreItem item) async {
    final canAfford = _balance >= item.coinCost;
    final confirmed = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: const Color(0x88000000),
        pageBuilder: (_, __, ___) => StoreItemPreview(
          item: item,
          description: _descriptionFor(item),
          displayCost: item.coinCost,
          canAfford: canAfford,
          onConfirm: () => Navigator.of(context).pop(true),
          onCancel: () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (confirmed != true) return;
    await _purchaseCosmetic(item);
  }

  Future<void> _purchaseCosmetic(StoreItem item) async {
    try {
      final result = await widget.storeRepo.purchaseItem(item.id, item.coinCost);
      if (result == PurchaseResult.purchased) {
        // Refresh owned set; balance updates via the stream subscription.
        final owned = await widget.storeRepo.getOwnedItems();
        if (!mounted) return;
        setState(() => _owned = owned);
        _showSnack('${item.name} unlocked!');
      } else if (result == PurchaseResult.alreadyOwned) {
        _showSnack('${item.name} already owned');
      }
    } on InsufficientCoinsException {
      _showSnack('Not enough coins');
    }
  }

  Future<void> _purchaseUpgrade(PowerupUpgrade upgrade) async {
    final id = StoreInventory.upgradeIdOf(upgrade.id);
    try {
      final result = await widget.storeRepo.purchaseUpgrade(id);
      if (result == PurchaseResult.purchased) {
        final lvl = await widget.storeRepo.getUpgradeLevelById(upgrade.id);
        if (!mounted) return;
        setState(() {
          _upgradeLevels = {..._upgradeLevels, upgrade.id: lvl};
        });
        _showSnack('${upgrade.name} → Lv $lvl');
      } else if (result == PurchaseResult.alreadyOwned) {
        _showSnack('${upgrade.name} is maxed out');
      }
    } on InsufficientCoinsException {
      _showSnack('Not enough coins');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'STORE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        actions: [_buildCoinPill()],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final t in _tabs) Tab(text: t.label),
          ],
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          for (final t in _tabs) _buildTab(t.category),
        ],
      ),
    );
  }

  Widget _buildCoinPill() {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x55000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD700), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFD700),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$_balance',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(StoreCategory category) {
    if (category == StoreCategory.coinPacks) return _buildCoinPacksTab();

    final items = StoreInventory.itemsForCategory(category);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildItemCard(items[i]),
    );
  }

  Widget _buildItemCard(StoreItem item) {
    if (item.category == StoreCategory.upgrades) {
      return _buildUpgradeCard(item);
    }
    final owned = _isOwned(item);
    final equipped = owned && _isEquipped(item);
    final canAfford = _balance >= item.coinCost;
    return _CardShell(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: StoreItemArtwork(item: item, size: 80),
          ),
          Text(
            item.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (equipped)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'EQUIPPED',
                style: TextStyle(
                  color: Color(0xFF40E0D0),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            )
          else if (owned)
            _cardButton(
              'EQUIP',
              const Color(0xFF40E0D0),
              () => _equip(item),
            )
          else
            _cardButton(
              '${item.coinCost}',
              const Color(0xFFFFD700),
              canAfford ? () => _showPreview(item) : null,
              icon: Icons.shopping_cart,
            ),
        ],
      ),
    );
  }

  Widget _buildUpgradeCard(StoreItem item) {
    final upgradeId = StoreInventory.parseUpgradeId(item.id);
    if (upgradeId == null) return const SizedBox.shrink();
    final upgrade = PowerupUpgrade.byId(upgradeId);
    final level = _upgradeLevels[upgradeId] ?? 0;
    final maxed = level >= upgrade.maxLevel;
    final nextCost = upgrade.costForNextLevel(level);
    final canAfford = _balance >= nextCost;
    final currentValue = upgrade.valueAtLevel(level);
    final nextValue = upgrade.valueAtLevel(level + 1);

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(child: StoreItemArtwork(item: item, size: 56)),
          ),
          Text(
            upgrade.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _buildLevelBar(level, upgrade.maxLevel),
          const SizedBox(height: 6),
          Text(
            maxed
                ? 'MAX (${currentValue.toStringAsFixed(1)}${upgrade.unit})'
                : '${currentValue.toStringAsFixed(1)}${upgrade.unit} → ${nextValue.toStringAsFixed(1)}${upgrade.unit}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          if (maxed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'MAXED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF40E0D0),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            )
          else
            _cardButton(
              '$nextCost',
              const Color(0xFFFFD700),
              canAfford ? () => _purchaseUpgrade(upgrade) : null,
              icon: Icons.shopping_cart,
            ),
        ],
      ),
    );
  }

  Widget _buildLevelBar(int level, int maxLevel) {
    return Row(
      children: List.generate(maxLevel, (i) {
        final filled = i < level;
        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: i == maxLevel - 1 ? 0 : 4),
            decoration: BoxDecoration(
              color: filled
                  ? const Color(0xFF40E0D0)
                  : const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCoinPacksTab() {
    const packs = [
      _CoinPackStub('Small Pack', '1,000 coins', '\$0.99'),
      _CoinPackStub('Medium Pack', '5,500 coins', '\$4.99'),
      _CoinPackStub('Large Pack', '12,000 coins', '\$9.99'),
      _CoinPackStub('Mega Pack', '30,000 coins', '\$19.99'),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: packs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final p = packs[i];
        return _CardShell(
          child: ListTile(
            title: Text(
              p.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              p.subtitle,
              style: const TextStyle(color: Color(0xFFFFD700)),
            ),
            trailing: FilledButton(
              onPressed: () => _showSnack('Coin packs coming in Phase 12'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: const Color(0xFF101018),
              ),
              child: Text(p.price),
            ),
          ),
        );
      },
    );
  }

  Widget _cardButton(
    String label,
    Color color,
    VoidCallback? onPressed, {
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: SizedBox(
        height: 32,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: const Color(0xFF101018),
            disabledBackgroundColor: const Color(0x33FFFFFF),
            disabledForegroundColor: Colors.white60,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _descriptionFor(StoreItem item) {
    final skinId = StoreInventory.parseSkinId(item.id);
    if (skinId != null) {
      return 'Cosmetic skin for the player orb. Doesn\'t affect gameplay — just looks great.';
    }
    final trailId = StoreInventory.parseTrailId(item.id);
    if (trailId != null) {
      final t = TrailEffect.byId(trailId);
      return 'Animated motion trail. Renders ${t.sampleCount} samples behind the orb.';
    }
    final shieldId = StoreInventory.parseShieldId(item.id);
    if (shieldId != null) {
      final s = ShieldSkin.byId(shieldId);
      return '${s.name} bubble — shows during invincibility frames after a hit.';
    }
    final deathId = StoreInventory.parseDeathId(item.id);
    if (deathId != null) {
      final d = DeathEffect.byId(deathId);
      return '${d.name} — particle effect that plays when the orb is destroyed.';
    }
    return 'Cosmetic upgrade';
  }
}

// ---- helpers ---------------------------------------------------------------

class _StoreTabSpec {
  final StoreCategory category;
  final String label;
  const _StoreTabSpec(this.category, this.label);
}

class _CoinPackStub {
  final String title;
  final String subtitle;
  final String price;
  const _CoinPackStub(this.title, this.subtitle, this.price);
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x44000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: child,
    );
  }
}
