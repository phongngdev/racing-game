import 'package:flame/components.dart';

enum SprintGraphicsStyle { legacy, kenney }

typedef SprintSpriteLoader = Future<Sprite> Function(String assetPath);

/// Images are loaded once, shared by both sprint viewports, and owned by
/// Flame's image cache. Missing images leave the Canvas fallback available.
class SprintGraphicsAssets {
  SprintGraphicsAssets({SprintSpriteLoader? loadSprite})
    : _loadSprite = loadSprite ?? _loadDefaultSprite;

  final SprintSpriteLoader _loadSprite;
  Future<void>? _preloadFuture;
  final Map<String, Sprite> _sprites = {};

  Future<void> preload() => _preloadFuture ??= _load();

  Sprite? operator [](String key) => _sprites[key];

  bool get hasCars =>
      _sprites.containsKey('vehicles/car_red_1.png') &&
      _sprites.containsKey('vehicles/car_blue_1.png');

  Future<void> _load() async {
    await Future.wait(
      _assetKeys.map((key) async {
        try {
          _sprites[key] = await _loadSprite('racing/$key');
        } catch (_) {
          // A broken optional art asset must never prevent a race from starting.
        }
      }),
    );
  }

  static Future<Sprite> _loadDefaultSprite(String assetPath) =>
      Sprite.load(assetPath);

  static const _assetKeys = <String>[
    'vehicles/car_red_1.png',
    'vehicles/car_blue_1.png',
    'scenery/tree_small.png',
    'scenery/tree_large.png',
    'scenery/rock1.png',
    'scenery/rock2.png',
    'scenery/rock3.png',
    'scenery/tent_blue.png',
    'scenery/cone_straight.png',
    'scenery/barrel_blue.png',
    'scenery/tires_white.png',
  ];
}
