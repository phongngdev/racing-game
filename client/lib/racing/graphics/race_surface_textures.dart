import 'dart:typed_data';
import 'dart:ui' as ui;

import '../sprint/sprint_graphics_assets.dart';
import 'race_surface_patches.dart';

/// Game-scoped, preloaded surface shaders shared by every race camera.
class RaceSurfaceTextures {
  ui.ImageShader? _grassShader;
  ui.ImageShader? _dirtShader;
  ui.ImageShader? _asphaltShader;
  ui.Image? _generatedAsphalt;
  bool _prepared = false;
  bool _disposed = false;

  final ui.Paint _grassPaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  final ui.Paint _dirtPaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..color = const ui.Color(0x38FFFFFF);
  final ui.Paint _asphaltPaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low;

  bool get hasGrassTexture => _grassShader != null;
  bool get hasDirtTexture => _dirtShader != null;
  bool get hasAsphaltTexture => _asphaltShader != null;

  Future<void> prepare(SprintGraphicsAssets assets) async {
    if (_prepared || _disposed) return;
    _prepared = true;

    final grass = assets['surfaces/land_grass.png']?.image;
    if (grass != null) {
      try {
        _grassShader = _makeWorldShader(grass);
      } catch (_) {
        // A missing or unsupported optional shader falls back to Canvas color.
      }
    }

    final dirt = assets['surfaces/land_dirt.png']?.image;
    if (dirt != null) {
      try {
        _dirtShader = _makeWorldShader(dirt);
      } catch (_) {
        // Dirt detail is optional; it does not affect the road or race.
      }
    }

    final asphalt = assets['surfaces/road_asphalt.png']?.image;
    if (asphalt != null) {
      try {
        _generatedAsphalt = await _bakeAsphalt(asphalt, dirt);
        if (!_disposed && _generatedAsphalt != null) {
          _asphaltShader = _makeWorldShader(_generatedAsphalt!);
        }
      } catch (_) {
        _generatedAsphalt?.dispose();
        _generatedAsphalt = null;
      }
    }
    if (_disposed) _releaseResources();
  }

  void drawGrass(ui.Canvas canvas, ui.Rect bounds, ui.Color fallback) {
    _grassPaint
      ..shader = _grassShader
      ..color = const ui.Color(0xFFFFFFFF);
    if (_grassShader == null) {
      _grassPaint.color = fallback;
    }
    canvas.drawRect(bounds, _grassPaint);
  }

  void drawAsphalt(ui.Canvas canvas, ui.Path road, ui.Color fallback) {
    _asphaltPaint
      ..shader = _asphaltShader
      ..color = const ui.Color(0xFFFFFFFF);
    if (_asphaltShader == null) {
      _asphaltPaint.color = fallback;
    }
    canvas.drawPath(road, _asphaltPaint);
  }

  void drawDirtPatches(
    ui.Canvas canvas,
    List<RaceSurfacePatch> patches,
    ui.Rect visible,
  ) {
    final shader = _dirtShader;
    if (shader == null) {
      return;
    }
    _dirtPaint.shader = shader;
    for (final patch in patches) {
      if (visible.overlaps(patch.bounds)) {
        canvas.drawPath(patch.path, _dirtPaint);
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseResources();
  }

  void _releaseResources() {
    _grassPaint.shader = null;
    _dirtPaint.shader = null;
    _asphaltPaint.shader = null;
    _grassShader?.dispose();
    _grassShader = null;
    _dirtShader?.dispose();
    _dirtShader = null;
    _asphaltShader?.dispose();
    _asphaltShader = null;
    _generatedAsphalt?.dispose();
    _generatedAsphalt = null;
  }

  static ui.ImageShader _makeWorldShader(ui.Image image) => ui.ImageShader(
    image,
    ui.TileMode.mirror,
    ui.TileMode.mirror,
    _identityMatrix(),
    filterQuality: ui.FilterQuality.low,
  );

  static Float64List _identityMatrix() => Float64List.fromList(const [
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  static Future<ui.Image> _bakeAsphalt(ui.Image asphalt, ui.Image? dirt) async {
    const tileSize = 128.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final tileRect = const ui.Rect.fromLTWH(0, 0, tileSize, tileSize);
    canvas.drawImageRect(
      asphalt,
      ui.Rect.fromLTWH(
        0,
        0,
        asphalt.width.toDouble(),
        asphalt.height.toDouble(),
      ),
      tileRect,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.low
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xFF34383C),
          ui.BlendMode.srcIn,
        ),
    );
    if (dirt != null) {
      canvas.drawImageRect(
        dirt,
        ui.Rect.fromLTWH(0, 0, dirt.width.toDouble(), dirt.height.toDouble()),
        tileRect,
        ui.Paint()
          ..filterQuality = ui.FilterQuality.low
          ..color = const ui.Color(0x38FFFFFF)
          ..colorFilter = const ui.ColorFilter.matrix(<double>[
            0.299,
            0.587,
            0.114,
            0,
            0,
            0.299,
            0.587,
            0.114,
            0,
            0,
            0.299,
            0.587,
            0.114,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
      );
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(tileSize.toInt(), tileSize.toInt());
    } finally {
      picture.dispose();
    }
  }
}
