import 'dart:async';
import 'dart:math' as math;
import 'dart:ui'
    show
        Canvas,
        Color,
        FilterQuality,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        PathOperation,
        Radius,
        Rect,
        RRect;

import 'package:flame/components.dart';
import 'package:flame/camera.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import 'input/car_input.dart';
import 'graphics/race_scenery_component.dart';
import 'graphics/race_surface_patches.dart';
import 'graphics/race_surface_textures.dart';
import 'lap/lap_race_track.dart';
import 'simulation/race_simulation.dart';
import 'tracks/track_definition.dart';
import 'sprint/sprint_camera.dart';
import 'sprint/sprint_graphics_assets.dart';
import 'sprint/sprint_track_component.dart';

class RaceSnapshot {
  const RaceSnapshot({this.redSpeed = 0, this.blueSpeed = 0});

  final double redSpeed;
  final double blueSpeed;
}

class ApexRacingGame extends FlameGame with KeyboardEvents {
  ApexRacingGame({
    required this.simulation,
    required this.inputSource,
    required this.snapshot,
    required this.onKeyboardEvent,
    this.lapTrack,
    this.sprintTrack,
    SprintGraphicsAssets? sprintGraphicsAssets,
    this.onFrameUpdate,
  }) : super(
         camera: CameraComponent.withFixedResolution(
           width: RaceTrackLayout.worldWidth,
           height: RaceTrackLayout.worldHeight,
         ),
       ) {
    final track = sprintTrack;
    final supportsRaceGraphics = track != null || lapTrack != null;
    _graphicsAssets = supportsRaceGraphics
        ? sprintGraphicsAssets ?? SprintGraphicsAssets()
        : null;
    _surfaceTextures = supportsRaceGraphics ? RaceSurfaceTextures() : null;
    camera.viewfinder.position = Vector2(
      RaceTrackLayout.worldWidth / 2,
      RaceTrackLayout.worldHeight / 2,
    );
    _sprintTrackComponent = track == null
        ? null
        : SprintTrackComponent(
            track,
            _graphicsAssets,
            hasKenneyPresentation: true,
            surfaceTextures: _surfaceTextures,
          );
    _lapTrackComponent = TrackComponent(
      lapTrack: lapTrack,
      surfaceTextures: _surfaceTextures,
    );
    _sceneryComponents = _graphicsAssets == null
        ? []
        : [
            if (track != null)
              RaceSceneryComponent.sprint(track, _graphicsAssets)
            else if (lapTrack != null)
              RaceSceneryComponent.lap(_graphicsAssets),
          ];
    _redCarComponent = CarComponent(
      state: simulation.red,
      color: const Color(0xFFE34B50),
      isFinished: () => simulation.isPlayerFinished(PlayerId.red),
      graphicsAssets: _graphicsAssets,
    );
    _blueCarComponent = CarComponent(
      state: simulation.blue,
      color: const Color(0xFF4388F5),
      isFinished: () => simulation.isPlayerFinished(PlayerId.blue),
      graphicsAssets: _graphicsAssets,
    );
    world.addAll([
      if (_sprintTrackComponent case final component?)
        component
      else
        _lapTrackComponent,
      ..._sceneryComponents,
      _redCarComponent,
      _blueCarComponent,
    ]);
    if (sprintTrack case final track?) {
      camera.viewport = FixedSizeViewport(1, 1);
      _secondCamera = CameraComponent(
        world: world,
        viewport: FixedSizeViewport(1, 1),
      );
      add(_secondCamera!);
      _cameraRigs = [SprintCameraRig(track), SprintCameraRig(track)];
    }
  }

  final RaceSimulation simulation;
  final InputSource inputSource;
  final ValueNotifier<RaceSnapshot> snapshot;
  final KeyEventResult Function(KeyEvent event) onKeyboardEvent;
  final LapRaceTrack? lapTrack;
  final TrackDefinition? sprintTrack;
  late final SprintGraphicsAssets? _graphicsAssets;
  late final RaceSurfaceTextures? _surfaceTextures;
  final Completer<void> _graphicsPreloadCompleter = Completer<void>();
  Future<void> get graphicsPreload => _graphicsPreloadCompleter.future;
  bool get isGraphicsPreloading =>
      _graphicsAssets != null && !_graphicsPreloadCompleter.isCompleted;
  late final SprintTrackComponent? _sprintTrackComponent;
  late final TrackComponent _lapTrackComponent;
  late final List<RaceSceneryComponent> _sceneryComponents;
  late final CarComponent _redCarComponent;
  late final CarComponent _blueCarComponent;
  SprintGraphicsStyle _graphicsStyle = SprintGraphicsStyle.legacy;
  SprintGraphicsStyle get graphicsStyle => _graphicsStyle;
  bool get supportsGraphicsSelection => _graphicsAssets != null;
  bool get supportsKenneyGraphics => _graphicsAssets?.hasCars ?? false;
  CameraComponent? _secondCamera;
  List<SprintCameraRig> _cameraRigs = [];
  int _cameraResetRevision = -1;
  final void Function(double frameSeconds)? onFrameUpdate;
  double _snapshotElapsed = 0;

  bool setGraphicsStyle(SprintGraphicsStyle style) {
    if (_graphicsAssets == null ||
        (style == SprintGraphicsStyle.kenney && !supportsKenneyGraphics)) {
      return false;
    }
    _graphicsStyle = style;
    _sprintTrackComponent?.style = style;
    _lapTrackComponent.style = style;
    for (final component in _sceneryComponents) {
      component.style = style;
    }
    _redCarComponent.style = style;
    _blueCarComponent.style = style;
    return true;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final assets = _graphicsAssets;
    if (assets == null) {
      _graphicsPreloadCompleter.complete();
      return;
    }
    unawaited(_preloadRaceGraphics(assets));
  }

  Future<void> _preloadRaceGraphics(SprintGraphicsAssets assets) async {
    try {
      await assets.preload();
      await _surfaceTextures?.prepare(assets);
      if (supportsKenneyGraphics) {
        setGraphicsStyle(SprintGraphicsStyle.kenney);
      }
    } catch (_) {
      // Optional graphics must not prevent Fixed Sprint from starting.
    } finally {
      if (!_graphicsPreloadCompleter.isCompleted) {
        _graphicsPreloadCompleter.complete();
      }
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_secondCamera == null) return;
    final panes = sprintViewports(size.x, size.y);
    if (panes.length != 2) return;
    final cameras = [camera, _secondCamera!];
    final cars = [simulation.red, simulation.blue];
    for (var i = 0; i < 2; i++) {
      final pane = panes[i];
      cameras[i].viewport.size = Vector2(pane.width, pane.height);
      cameras[i].viewport.position = Vector2(pane.left, pane.top);
      _cameraRigs[i].resize(pane.width, pane.height);
      _cameraRigs[i].snap(cars[i]);
      cameras[i].viewfinder.zoom = _cameraRigs[i].zoom;
      cameras[i].viewfinder.position = _cameraRigs[i].position;
    }
  }

  void _updateCameras(double dt) {
    if (_secondCamera == null) return;
    final cameras = [camera, _secondCamera!];
    final cars = [simulation.red, simulation.blue];
    for (var i = 0; i < 2; i++) {
      final rig = _cameraRigs[i];
      if (_cameraResetRevision != simulation.resetRevision) rig.snap(cars[i]);
      rig.update(
        dt,
        cars[i],
        running: simulation.isRunning,
        finished: simulation.isPlayerFinished(cars[i].player),
      );
      cameras[i].viewfinder.position = rig.position;
      cameras[i].viewfinder.zoom = rig.zoom;
    }
    _cameraResetRevision = simulation.resetRevision;
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) => onKeyboardEvent(event);

  @override
  Color backgroundColor() => const Color(0xFF193323);

  @override
  void onRemove() {
    _surfaceTextures?.dispose();
    super.onRemove();
  }

  @override
  void update(double dt) {
    final frameUpdate = onFrameUpdate;
    if (frameUpdate == null) {
      simulation.update(dt, inputSource);
    } else {
      frameUpdate(dt);
    }
    simulation.updateRenderPoses();
    _updateCameras(dt);
    super.update(dt);
    _snapshotElapsed += dt;
    if (_snapshotElapsed >= 0.1) {
      _snapshotElapsed %= 0.1;
      snapshot.value = RaceSnapshot(
        redSpeed: simulation.red.speed,
        blueSpeed: simulation.blue.speed,
      );
    }
  }
}

class TrackComponent extends Component {
  TrackComponent({this.lapTrack, this.surfaceTextures})
    : _lapRoadPath = lapTrack == null ? Path() : _makeLapRoadPath(),
      _dirtPatches = lapTrack == null ? const [] : RaceSurfacePatches.lap();

  final LapRaceTrack? lapTrack;
  final RaceSurfaceTextures? surfaceTextures;
  final Path _lapRoadPath;
  final List<RaceSurfacePatch> _dirtPatches;
  SprintGraphicsStyle style = SprintGraphicsStyle.legacy;

  static Path _makeLapRoadPath() {
    final asphalt = Path()..addRect(const Rect.fromLTWH(64, 64, 832, 512));
    final island = Path()..addRect(RaceTrackLayout.island);
    return Path.combine(PathOperation.difference, asphalt, island);
  }

  @override
  void render(Canvas canvas) {
    final grass = Paint()..color = const Color(0xFF24452F);
    final asphalt = Paint()..color = const Color(0xFF34383C);
    final islandPaint = Paint()..color = const Color(0xFF2C573A);
    final wallShadow = Paint()..color = const Color(0xFF797F7C);
    final kerbRed = Paint()..color = const Color(0xFFE95458);
    final kerbWhite = Paint()..color = const Color(0xFFF0E9D8);
    final lane = Paint()..color = const Color(0xFFA6A394);

    final texturedRace =
        lapTrack != null &&
        style == SprintGraphicsStyle.kenney &&
        surfaceTextures != null;
    if (texturedRace) {
      final visible =
          CameraComponent.currentCamera?.visibleWorldRect ??
          Rect.fromLTWH(
            0,
            0,
            RaceTrackLayout.worldWidth,
            RaceTrackLayout.worldHeight,
          );
      final bounds = visible.intersect(
        const Rect.fromLTWH(
          0,
          0,
          RaceTrackLayout.worldWidth,
          RaceTrackLayout.worldHeight,
        ),
      );
      surfaceTextures!.drawGrass(canvas, bounds, grass.color);
      surfaceTextures!.drawDirtPatches(canvas, _dirtPatches, visible);
      surfaceTextures!.drawAsphalt(canvas, _lapRoadPath, asphalt.color);
    } else {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          0,
          RaceTrackLayout.worldWidth,
          RaceTrackLayout.worldHeight,
        ),
        grass,
      );
      canvas.drawRect(const Rect.fromLTWH(64, 64, 832, 512), asphalt);
      canvas.drawRect(RaceTrackLayout.island, islandPaint);
    }

    for (final wall in RaceTrackLayout.walls) {
      if (wall.$1 == 'island') {
        canvas.drawRect(
          wall.$2.inflate(4),
          Paint()
            ..color = wallShadow.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12,
        );
        canvas.drawRect(
          wall.$2.inflate(4),
          Paint()
            ..color = kerbRed.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8,
        );
        canvas.drawRect(
          wall.$2.inflate(4),
          Paint()
            ..color = kerbWhite.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        continue;
      }
      canvas.drawRect(wall.$2, wallShadow);
      const step = 16.0;
      final bounds = wall.$2;
      if (bounds.width > bounds.height) {
        for (var x = bounds.left; x < bounds.right; x += step) {
          canvas.drawRect(
            Rect.fromLTWH(x, bounds.top, step / 2, bounds.height),
            ((x / step).floor().isEven) ? kerbRed : kerbWhite,
          );
        }
      } else {
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          canvas.drawRect(
            Rect.fromLTWH(bounds.left, y, bounds.width, step / 2),
            ((y / step).floor().isEven) ? kerbRed : kerbWhite,
          );
        }
      }
    }

    canvas.drawRect(
      RaceTrackLayout.island,
      Paint()
        ..color = const Color(0xFF191E1D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Small rectangular dashes keep the top-down track readable at game scale.
    for (var x = 190.0; x < 850; x += 48) {
      canvas.drawRect(Rect.fromLTWH(x, 136, 22, 3), lane);
      canvas.drawRect(Rect.fromLTWH(x, 501, 22, 3), lane);
    }
    for (var y = 260.0; y < 400; y += 42) {
      canvas.drawRect(Rect.fromLTWH(172, y, 3, 20), lane);
      canvas.drawRect(Rect.fromLTWH(785, y, 3, 20), lane);
    }

    final finish = lapTrack?.finish;
    if (finish == null) {
      // Preserve the Practice mode's original decorative line.
      const startX = 126.0;
      for (var row = 0; row < 18; row++) {
        for (var column = 0; column < 2; column++) {
          final paint = (row + column).isEven ? kerbWhite : wallShadow;
          canvas.drawRect(
            Rect.fromLTWH(startX + column * 8, 70 + row * 8, 8, 8),
            paint,
          );
        }
      }
    } else {
      final top = finish.start.y;
      final bottom = finish.end.y;
      var row = 0;
      for (var y = top; y < bottom; y += 8, row++) {
        for (var column = 0; column < 2; column++) {
          final paint = (row + column).isEven ? kerbWhite : wallShadow;
          canvas.drawRect(
            Rect.fromLTWH(finish.start.x - 8 + column * 8, y, 8, 8),
            paint,
          );
        }
      }
    }

    if (texturedRace) return;

    // A few square grass tufts add texture without external image assets.
    final tuft = Paint()..color = const Color(0xFF397049);
    for (var i = 0; i < 70; i++) {
      final x = (i * 137 + 31) % 944;
      final y = (i * 83 + 19) % 624;
      final insideOuterTrack = x >= 64 && x <= 896 && y >= 64 && y <= 576;
      final insideIsland =
          x >= RaceTrackLayout.island.left &&
          x <= RaceTrackLayout.island.right &&
          y >= RaceTrackLayout.island.top &&
          y <= RaceTrackLayout.island.bottom;
      if (!insideOuterTrack || insideIsland) {
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 4, 4), tuft);
      }
    }
  }
}

class CarComponent extends Component {
  CarComponent({
    required this.state,
    required this.color,
    this.isFinished = _neverFinished,
    this.graphicsAssets,
  }) : _spriteKey = state.player == PlayerId.red
           ? 'vehicles/car_red_1.png'
           : 'vehicles/car_blue_1.png';

  final CarState state;
  final Color color;
  final bool Function() isFinished;
  final SprintGraphicsAssets? graphicsAssets;
  final String _spriteKey;
  SprintGraphicsStyle style = SprintGraphicsStyle.legacy;
  static final _spritePaint = Paint()..filterQuality = FilterQuality.low;

  static bool _neverFinished() => false;

  @override
  void render(Canvas canvas) {
    final visible = CameraComponent.currentCamera?.visibleWorldRect;
    if (visible != null &&
        !visible.overlaps(
          Rect.fromCenter(
            center: Offset(state.position.x, state.position.y),
            width: 60,
            height: 60,
          ),
        )) {
      return;
    }
    canvas.save();
    canvas.translate(state.renderPosition.x, state.renderPosition.y);
    final sprite = style == SprintGraphicsStyle.kenney && graphicsAssets != null
        ? graphicsAssets![_spriteKey]
        : null;
    if (sprite != null) {
      canvas.rotate(state.renderHeading + math.pi / 2);
      const height = 38.0;
      const width = height * 71 / 131;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: width,
          height: height,
        ).shift(const Offset(1, 2)),
        Paint()..color = const Color(0x66000000),
      );
      canvas.drawImageRect(
        sprite.image,
        sprite.src,
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        isFinished()
            ? (_spritePaint..color = const Color(0x70FFFFFF))
            : (_spritePaint..color = const Color(0xFFFFFFFF)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, -6), width: 8, height: 4),
          const Radius.circular(1),
        ),
        Paint()..color = color,
      );
      canvas.restore();
      return;
    }
    canvas.rotate(state.renderHeading);

    canvas.drawRect(
      const Rect.fromLTWH(-17, -9, 38, 24),
      Paint()..color = const Color(0x66000000),
    );
    final tire = Paint()..color = const Color(0xFF111416);
    canvas.drawRect(const Rect.fromLTWH(-13, -14, 8, 5), tire);
    canvas.drawRect(const Rect.fromLTWH(9, -14, 8, 5), tire);
    canvas.drawRect(const Rect.fromLTWH(-13, 10, 8, 5), tire);
    canvas.drawRect(const Rect.fromLTWH(9, 10, 8, 5), tire);

    canvas.drawRect(
      const Rect.fromLTWH(-19, -12, 38, 24),
      Paint()..color = isFinished() ? color.withAlpha(112) : color,
    );
    canvas.drawRect(
      const Rect.fromLTWH(-18, -10, 3, 20),
      Paint()..color = const Color(0xFF22292B),
    );
    canvas.drawRect(
      const Rect.fromLTWH(15, -13, 5, 26),
      Paint()..color = const Color(0xFFEDE7D7),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-6, -8, 13, 16),
      Paint()..color = const Color(0xFFB8D2D5),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-1, -8, 3, 16),
      Paint()..color = const Color(0xFF4D6570),
    );
    canvas.drawRect(
      const Rect.fromLTWH(5, -2, 14, 4),
      Paint()..color = color.withAlpha(120),
    );
    canvas.restore();
  }
}
