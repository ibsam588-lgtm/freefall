// Phase-4 player system tests.
//
// These exercise the deterministic state surface of [Player] without
// booting Flame or sensors_plus. Player is constructed without an
// external PlayerParticleSystem so the fallback in-process death burst
// is observable, but the hit/lives/respawn logic is identical either
// way — the test covers the contract, not the visual.

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/particle_system.dart';
import 'package:freefall/components/player.dart';
import 'package:freefall/models/player_skin.dart';
import 'package:freefall/models/trail_effect.dart';
import 'package:freefall/systems/gravity_system.dart';

Player _player({
  PlayerSkin? skin,
  int maxLives = Player.defaultMaxLives,
  PlayerParticleSystem? particles,
}) {
  return Player(
    gravity: GravitySystem(),
    startPosition: Vector2(100, 100),
    skin: skin,
    maxLives: maxLives,
    particleSystem: particles,
  );
}

void main() {
  group('Player lives + hit', () {
    test('starts at maxLives and decrements on each hit', () {
      final p = _player();
      expect(p.lives, 3);
      expect(p.maxLives, 3);

      // First hit: lives 3 -> 2, grants i-frames.
      expect(p.onHit(), isTrue);
      expect(p.lives, 2);
      expect(p.isInvincible, isTrue);
      expect(p.isAlive, isTrue);
      expect(p.isDead, isFalse);

      // Burn through i-frames so the next hit lands.
      p.update(Player.invincibilityDuration + 0.1);
      expect(p.isInvincible, isFalse);

      expect(p.onHit(), isTrue);
      expect(p.lives, 1);
    });

    test('hit during i-frames is ignored', () {
      final p = _player();

      expect(p.onHit(), isTrue);
      expect(p.lives, 2);
      // Still invincible — second hit returns false and lives unchanged.
      expect(p.isInvincible, isTrue);
      expect(p.onHit(), isFalse);
      expect(p.lives, 2);
    });

    test('death triggers when lives reach 0', () {
      final p = _player(maxLives: 2);
      expect(p.lives, 2);

      // First hit (non-fatal).
      p.onHit();
      expect(p.lives, 1);
      expect(p.isDead, isFalse);

      // Burn i-frames.
      p.update(Player.invincibilityDuration + 0.1);

      // Fatal hit.
      expect(p.onHit(), isTrue);
      expect(p.lives, 0);
      expect(p.isDead, isTrue);
      expect(p.isAlive, isFalse);

      // Once dead, further hits do nothing.
      expect(p.onHit(), isFalse);
      expect(p.lives, 0);
    });

    test('death emits fallback particles when no particle system wired', () {
      final p = _player(maxLives: 1);
      p.onHit(); // fatal
      expect(p.isDead, isTrue);
      expect(p.activeFallbackParticleCount, greaterThanOrEqualTo(30));
    });

    test('death routes through external PlayerParticleSystem when wired', () {
      final ps = PlayerParticleSystem();
      final p = _player(maxLives: 1, particles: ps);

      p.onHit();
      expect(p.isDead, isTrue);
      expect(ps.mode, ParticleMode.death);
      expect(ps.activeCount, PlayerParticleSystem.particleCount);
      // Fallback path should NOT have fired.
      expect(p.activeFallbackParticleCount, 0);
    });
  });

  group('Player.respawn', () {
    test('resets lives, position, velocity, and clears death state', () {
      final p = _player(maxLives: 3);

      // Drain to dead.
      p.onHit();
      p.update(Player.invincibilityDuration + 0.1);
      p.onHit();
      p.update(Player.invincibilityDuration + 0.1);
      p.onHit();
      expect(p.isDead, isTrue);
      expect(p.lives, 0);

      // Move/dirty state so respawn has something to reset.
      p.position.setValues(999, 999);
      p.velocity.setValues(123, 456);

      final spawnAt = Vector2(50, 60);
      p.respawn(spawnAt);

      expect(p.isDead, isFalse);
      expect(p.isAlive, isTrue);
      expect(p.lives, p.maxLives);
      expect(p.position.x, 50);
      expect(p.position.y, 60);
      expect(p.velocity.length, 0);
      // Respawn grants brief i-frames so the player isn't murdered on re-entry.
      expect(p.isInvincible, isTrue);
    });

    test('respawn without target returns to startPosition', () {
      final p = _player();
      p.onHit();
      p.position.setValues(0, 0);
      p.respawn();
      expect(p.position.x, 100);
      expect(p.position.y, 100);
    });

    test('respawn triggers PlayerParticleSystem inward converge', () {
      final ps = PlayerParticleSystem();
      final p = _player(maxLives: 1, particles: ps);
      p.onHit(); // dies
      expect(ps.mode, ParticleMode.death);

      p.respawn(Vector2(200, 200));
      expect(ps.mode, ParticleMode.respawn);
      expect(ps.activeCount, PlayerParticleSystem.particleCount);
    });
  });

  group('Player.maxLives upgrade', () {
    test('clamped to absoluteMaxLives and lives bumped if at full', () {
      final p = _player(maxLives: 3);
      expect(p.lives, 3);

      p.maxLives = 4;
      expect(p.maxLives, 4);
      expect(p.lives, 4);

      // Above the cap should clamp, not overflow.
      p.maxLives = 99;
      expect(p.maxLives, Player.absoluteMaxLives);
    });

    test('lowering max clamps current lives', () {
      final p = _player(maxLives: 4);
      p.maxLives = 2;
      expect(p.lives, 2);
    });
  });

  group('PlayerSkin catalog', () {
    test('contains exactly 9 skins covering every SkinId', () {
      expect(PlayerSkin.catalog, hasLength(SkinId.values.length));
      expect(PlayerSkin.catalog, hasLength(9));
      for (final id in SkinId.values) {
        expect(
          PlayerSkin.catalog.where((s) => s.id == id),
          hasLength(1),
          reason: 'Skin $id should appear exactly once',
        );
      }
    });

    test('coin costs match the spec', () {
      // All non-default skins fit under the 200-coin store ceiling.
      // Tier ordering (cheap → premium) is preserved across the catalog.
      Map<SkinId, int> expected = {
        SkinId.defaultOrb: 0,
        SkinId.fire: 100,
        SkinId.ice: 100,
        SkinId.electric: 150,
        SkinId.shadow: 150,
        SkinId.rainbow: 200,
        SkinId.neon: 200,
        SkinId.void_: 200,
        SkinId.golden: 200,
      };
      for (final entry in expected.entries) {
        expect(PlayerSkin.byId(entry.key).coinCost, entry.value,
            reason: 'cost mismatch for ${entry.key}');
      }
    });

    test('default skin has white-ish colors and zero cost', () {
      final s = PlayerSkin.defaultSkin;
      expect(s.id, SkinId.defaultOrb);
      expect(s.coinCost, 0);
      expect(s.primaryColor, const Color(0xFFFFFFFF));
    });

    test('fire and ice have visibly different primary colors', () {
      final fire = PlayerSkin.byId(SkinId.fire);
      final ice = PlayerSkin.byId(SkinId.ice);
      expect(fire.primaryColor, isNot(equals(ice.primaryColor)));
      expect(fire.coinCost, ice.coinCost); // same tier
    });

    test('every skin has non-empty name', () {
      for (final s in PlayerSkin.catalog) {
        expect(s.name, isNotEmpty);
      }
    });
  });

  group('TrailEffect catalog', () {
    test('contains all 7 trail ids with matching costs', () {
      // Same flat 200-coin ceiling as the skin catalog.
      final expected = {
        TrailId.default_: 0,
        TrailId.comet: 100,
        TrailId.helix: 150,
        TrailId.sparkle: 150,
        TrailId.glitch: 200,
        TrailId.ghost: 200,
        TrailId.warp: 200,
      };
      expect(TrailEffect.catalog, hasLength(7));
      for (final entry in expected.entries) {
        expect(TrailEffect.byId(entry.key).coinCost, entry.value);
      }
    });
  });

  group('Player zone color sync', () {
    test('setZoneColor blends the effective glow toward zone accent', () {
      final p = _player(skin: PlayerSkin.byId(SkinId.fire));
      final beforeRaw = p.skin.glowColor;
      p.setZoneColor(const Color(0xFF40E0D0)); // ocean teal
      // The effective color is a blend, not the raw skin color.
      expect(p.effectiveGlowColor, isNot(equals(beforeRaw)));
      expect(p.zoneAccent, const Color(0xFF40E0D0));
    });
  });

  group('PlayerParticleSystem', () {
    test('death mode releases all particles after deathLifetime', () {
      final ps = PlayerParticleSystem();
      ps.triggerDeath(Vector2(0, 0), const Color(0xFFFFFFFF));
      expect(ps.activeCount, PlayerParticleSystem.particleCount);

      // Step well past the death lifetime in fixed-ish chunks.
      const dt = 1 / 60;
      final steps = (PlayerParticleSystem.deathLifetime * 1.5 / dt).ceil();
      for (int i = 0; i < steps; i++) {
        ps.update(dt);
      }
      expect(ps.activeCount, 0);
      expect(ps.mode, ParticleMode.idle);
    });

    test('respawn converges and goes idle within respawnDuration', () {
      final ps = PlayerParticleSystem();
      ps.triggerRespawn(Vector2(50, 50), const Color(0xFFFFFFFF));
      expect(ps.activeCount, PlayerParticleSystem.particleCount);

      const dt = 1 / 60;
      final steps =
          (PlayerParticleSystem.respawnDuration * 1.1 / dt).ceil();
      for (int i = 0; i < steps; i++) {
        ps.update(dt);
      }
      expect(ps.mode, ParticleMode.idle);
      expect(ps.activeCount, 0);
    });
  });
}
