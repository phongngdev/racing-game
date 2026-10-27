import 'dart:async' as async;
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apex_racing_game.dart';
import '../input/remote_input_source.dart';
import '../practice_controller_session.dart';
import '../simulation/race_simulation.dart';
import '../speed_units.dart';
import '../graphics/race_surface_textures.dart';
import '../sprint/sprint_graphics_assets.dart';
import '../tracks/track_geometry.dart';
import 'academy_session.dart';
import 'academy_input_source.dart';
import 'academy_track.dart';

class AcademyGamePage extends StatefulWidget {
  const AcademyGamePage({
    super.key,
    required this.onReturnToAcademy,
    this.practiceSession,
  });

  final VoidCallback onReturnToAcademy;
  final PracticeControllerSession? practiceSession;

  @override
  State<AcademyGamePage> createState() => _AcademyGamePageState();
}

class _AcademyGamePageState extends State<AcademyGamePage>
    with WidgetsBindingObserver {
  static final _drivingKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  late final AcademyTrack _track;
  late final RaceSimulation _simulation;
  late final RemoteInputSource _remote;
  late final AcademyInputSource _input;
  late final AcademySession _session;
  late final AcademyFlameGame _game;
  final _focus = FocusNode(debugLabel: 'Academy S-bend game');
  async.Timer? _phoneWatchdog;
  bool _overview = false;
  bool _resultShown = false;
  String? _controllerNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _track = AcademyTrack.sBend();
    _simulation = RaceSimulation(
      config: RaceConfig.academy,
      wallRects: const [],
      redStartPosition: Vector2(_track.spawn.x, _track.spawn.y),
      blueStartPosition: Vector2(-5000, -5000),
    );
    _remote = widget.practiceSession?.remoteInput ?? RemoteInputSource();
    _input = AcademyInputSource(
      remote: _remote,
      usePhone: widget.practiceSession != null,
    );
    _session = AcademySession(
      simulation: _simulation,
      input: _input,
      track: _track,
    )..addListener(_changed);
    _game = AcademyFlameGame(
      simulation: _simulation,
      session: _session,
      track: _track,
      showDebugGeometry:
          kDebugMode && const bool.fromEnvironment('ACADEMY_DEBUG_GEOMETRY'),
    );
    _focus.requestFocus();
    if (widget.practiceSession != null) {
      _phoneWatchdog = async.Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) {
        if (_session.phase == AcademyPhase.running && !_remote.hasFreshInput) {
          _controllerNotice =
              'Mất tín hiệu điện thoại · bài luyện đã tạm dừng.';
          _input.clear();
          _session.pause();
        }
      });
      widget.practiceSession!.addListener(_controllerChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phoneWatchdog?.cancel();
    widget.practiceSession?.removeListener(_controllerChanged);
    _session.removeListener(_changed);
    _input.clear();
    _simulation.dispose();
    _session.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pauseForSafety('Ứng dụng tạm dừng · chạm Tiếp tục để lái tiếp.');
    }
  }

  void _controllerChanged() {
    final controller = widget.practiceSession;
    if (controller == null) return;
    if (_session.phase == AcademyPhase.running &&
        (!controller.isPhoneConnected || !_remote.hasFreshInput)) {
      _pauseForSafety('Mất kết nối điện thoại · bài luyện đã tạm dừng.');
    }
  }

  void _pauseForSafety(String message) {
    if (_session.phase != AcademyPhase.running) return;
    _controllerNotice = message;
    _input.clear();
    _session.pause();
  }

  void _pauseManually() {
    _input.clear();
    _session.pause();
  }

  void _changed() {
    if (!mounted) return;
    if (_session.isTerminal && !_resultShown) _resultShown = true;
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape &&
          _session.phase == AcademyPhase.running) {
        _pauseManually();
        return KeyEventResult.handled;
      }
      if (_drivingKeys.contains(event.logicalKey)) {
        _input.handleKey(event.logicalKey, true);
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent && _drivingKeys.contains(event.logicalKey)) {
      _input.handleKey(event.logicalKey, false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _restart() {
    _input.clear();
    _controllerNotice = null;
    _resultShown = false;
    _session.restart();
    _overview = false;
    _game.setOverview(false);
    _focus.requestFocus();
    setState(() {});
  }

  void _toggleCamera() {
    setState(() => _overview = !_overview);
    // This only updates the viewport's zoom and position in the Flame game.
    _game.setOverview(_overview);
  }

  void _exitToAcademy() {
    _input.clear();
    _session.pause();
    _simulation.setRunning(false);
    widget.onReturnToAcademy();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _handleKey,
    child: Scaffold(
      backgroundColor: const Color(0xFF111719),
      body: SafeArea(
        child: Column(
          children: [
            _hud(context),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GameWidget<AcademyFlameGame>(game: _game),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: FilledButton.tonalIcon(
                      onPressed: _toggleCamera,
                      icon: Icon(
                        _overview
                            ? Icons.center_focus_strong_rounded
                            : Icons.map_rounded,
                      ),
                      label: Text(_overview ? 'Theo xe' : 'Toàn sân'),
                    ),
                  ),
                  if (_session.phase == AcademyPhase.ready)
                    _stateCard(
                      title: 'Sẵn sàng vào bài',
                      body: 'Đi hết hai cung cong theo mũi tên và vượt đích theo chiều tiến.',
                      primaryLabel: 'Bắt đầu',
                      onPrimary: () {
                        _controllerNotice = null;
                        _session.start();
                        _focus.requestFocus();
                      },
                    ),
                  if (_session.phase == AcademyPhase.paused)
                    _stateCard(
                      title: 'Đã tạm dừng',
                      body:
                          _controllerNotice ??
                          'Thời gian và chấm điểm đã dừng.',
                      primaryLabel: 'Tiếp tục',
                      onPrimary: () {
                        final controller = widget.practiceSession;
                        if (controller != null &&
                            (!controller.isPhoneConnected ||
                                !_remote.hasFreshInput)) {
                          _controllerNotice =
                              'Chờ kết nối điện thoại và tín hiệu điều khiển.';
                          setState(() {});
                          return;
                        }
                        _controllerNotice = null;
                        _session.resume();
                        _focus.requestFocus();
                      },
                      secondaryLabel: 'Thử lại',
                      onSecondary: _restart,
                    ),
                  if (_session.isTerminal)
                    _stateCard(
                      title: _session.phase == AcademyPhase.completed
                          ? 'Hoàn thành bài luyện'
                          : 'Bài luyện chưa đạt',
                      body: _resultDescription(),
                      primaryLabel: 'Chơi lại',
                      onPrimary: _restart,
                      secondaryLabel: 'Về Driving Academy',
                      onSecondary: _exitToAcademy,
                    ),
                  if (_session.phase == AcademyPhase.running)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _pauseManually,
                            icon: const Icon(Icons.pause_rounded),
                            label: const Text('Tạm dừng'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _restart,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  if (_session.penalties.isNotEmpty)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _latestPenalty(_session.penalties.last),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _hud(BuildContext context) {
    final overStandard =
        _session.elapsedSeconds > AcademySession.durationSeconds;
    final time = overStandard
        ? (_session.elapsedSeconds - AcademySession.durationSeconds).ceil()
        : math.max(
            0,
            AcademySession.durationSeconds.ceil() -
                _session.elapsedSeconds.ceil(),
          );
    final speed = speedKmh(_simulation.red.speed);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      color: const Color(0xFF1D2528),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          TextButton.icon(
            onPressed: _exitToAcademy,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Về Academy'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          const Text(
            'ĐƯỜNG VÒNG QUANH CO',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          _hudValue(
            'ĐIỂM',
            '${_session.score}',
            color: const Color(0xFF77E0A2),
          ),
          _hudValue(
            overStandard ? 'QUÁ CHUẨN' : 'THỜI GIAN',
            '${overStandard ? '+' : ''}${(time ~/ 60).toString().padLeft(2, '0')}:${(time % 60).toString().padLeft(2, '0')}',
            color: overStandard ? const Color(0xFFFFC16B) : Colors.white,
          ),
          _hudValue('TỐC ĐỘ', '$speed km/h'),
          _hudValue('TIẾN ĐỘ', '${_session.nextCheckpoint.clamp(0, 2)}/2'),
          const Text(
            'WASD / ↑←↓→ · Esc tạm dừng',
            style: TextStyle(color: Color(0xFFB9C5CA), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _hudValue(String label, String value, {Color color = Colors.white}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9CAAB0),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      );

  Widget _latestPenalty(AcademyPenalty penalty) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xE61D2528),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFA927D)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Text(
        '${penalty.basis == AcademyRuleBasis.regulation12 ? 'Luật mô phỏng' : 'Quy ước game'} · ${penalty.label} · −${penalty.points}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _stateCard({
    required String title,
    required String body,
    required String primaryLabel,
    required VoidCallback onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Card(
        margin: const EdgeInsets.all(18),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(body),
              const SizedBox(height: 16),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
              if (secondaryLabel != null) ...[
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  String _resultDescription() {
    final regulation = _session.penalties
        .where((p) => p.basis == AcademyRuleBasis.regulation12)
        .toList();
    final game = _session.penalties
        .where((p) => p.basis == AcademyRuleBasis.gameConvention)
        .toList();
    final lines = <String>[
      'Điểm: ${_session.score}/100 · Thời gian: ${_session.elapsedSeconds.toStringAsFixed(1)} giây',
      _session.finalMessage ?? '',
      if (regulation.isEmpty)
        'Lỗi theo Thông tư được mô phỏng: không có.'
      else
        'Theo Thông tư 12/2025: ${regulation.map((p) => '${p.label} −${p.points}').join('; ')}.',
      if (game.isNotEmpty)
        'Quy ước game: ${game.map((p) => p.label).join('; ')}.',
      if (_session.penalties.isNotEmpty)
        'Nhật ký lỗi: ${_session.penalties.map((p) => '${p.elapsed.toStringAsFixed(1)}s · ${p.label} · −${p.points}').join(' | ')}.',
      'Đây là kết quả bài luyện trong game, không phải kết quả sát hạch chính thức.',
    ];
    return lines.where((line) => line.isNotEmpty).join('\n\n');
  }
}

class AcademyFlameGame extends FlameGame {
  AcademyFlameGame({
    required this.simulation,
    required this.session,
    required this.track,
    this.showDebugGeometry = false,
  }) : _assets = SprintGraphicsAssets(),
       super(
         camera: CameraComponent.withFixedResolution(
           width: AcademyTrack.worldWidth,
           height: AcademyTrack.worldHeight,
         ),
       ) {
    camera.viewfinder.position = Vector2(track.spawn.x, track.spawn.y);
    _surfaces = RaceSurfaceTextures();
    _road = AcademyTrackComponent(
      track,
      _surfaces,
      showDebugGeometry: showDebugGeometry && kDebugMode,
    );
    _car = CarComponent(
      state: simulation.red,
      color: const Color(0xFFE34B50),
      graphicsAssets: _assets,
    );
    _car.priority = 10;
    world.addAll([_road, _car]);
  }

  final RaceSimulation simulation;
  final AcademySession session;
  final AcademyTrack track;
  final bool showDebugGeometry;
  final SprintGraphicsAssets _assets;
  late final RaceSurfaceTextures _surfaces;
  late final AcademyTrackComponent _road;
  late final CarComponent _car;
  bool _overview = false;

  void setOverview(bool value) {
    _overview = value;
    camera.viewfinder
      ..position = value
          ? Vector2(AcademyTrack.worldWidth / 2, AcademyTrack.worldHeight / 2)
          : Vector2(simulation.red.position.x, simulation.red.position.y)
      ..zoom = value ? 0.69 : 1.12;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await _assets.preload();
    await _surfaces.prepare(_assets);
    if (_assets.hasCars) _car.style = SprintGraphicsStyle.kenney;
    final cone = _assets['scenery/cone_straight.png'];
    if (cone != null) {
      final stations = [
        AcademyTrack.startStation,
        if (showDebugGeometry && kDebugMode) ...track.checkpointStations,
        track.totalLength * .955,
      ];
      world.addAll([
        for (final station in stations)
          for (final marker in _conePositions(station))
            SpriteComponent(
              sprite: cone,
              position: Vector2(marker.x, marker.y),
              size: Vector2.all(20),
              anchor: Anchor.center,
              priority: 5,
            ),
      ]);
    }
  }

  List<TrackPoint> _conePositions(double station) {
    final gate = track.gateAt(station);
    final direction = track.directionAt(station);
    final nx = -direction.y;
    final ny = direction.x;
    return [
      TrackPoint(gate.$1.x + nx * 12, gate.$1.y + ny * 12),
      TrackPoint(gate.$2.x - nx * 12, gate.$2.y - ny * 12),
    ];
  }

  @override
  void update(double dt) {
    if (session.phase == AcademyPhase.running) {
      simulation.update(dt, session.input, onFixedStep: session.advanceStep);
    }
    simulation.updateRenderPoses();
    if (!_overview) {
      camera.viewfinder.position = Vector2(
        simulation.red.renderPosition.x,
        simulation.red.renderPosition.y,
      );
    }
    super.update(dt);
  }

  @override
  void onRemove() {
    _surfaces.dispose();
    super.onRemove();
  }
}

class AcademyTrackComponent extends Component {
  AcademyTrackComponent(
    this.track,
    this.surfaces, {
    this.showDebugGeometry = false,
  });
  final AcademyTrack track;
  final RaceSurfaceTextures surfaces;
  final bool showDebugGeometry;
  final Paint _grass = Paint()..color = const Color(0xFF24452F);
  final Paint _edge = Paint()
    ..color = const Color(0xFFEEE9D8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = AcademyTrack.boundaryLineWidth
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  final Paint _road = Paint()..color = const Color(0xFF34383C);
  final Paint _dash = Paint()
    ..color = const Color(0xFFAAA595)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  final Paint _gate = Paint()
    ..color = const Color(0xFFDBD5C7)
    ..strokeWidth = 5;
  final Paint _finishWhite = Paint()
    ..color = const Color(0xFFF7F5ED)
    ..strokeWidth = 9
    ..strokeCap = StrokeCap.square;
  final Paint _finishBlack = Paint()
    ..color = const Color(0xFF15191B)
    ..strokeWidth = 9
    ..strokeCap = StrokeCap.square;

  @override
  void render(Canvas canvas) {
    surfaces.drawGrass(
      canvas,
      const Rect.fromLTWH(
        0,
        0,
        AcademyTrack.worldWidth,
        AcademyTrack.worldHeight,
      ),
      _grass.color,
    );
    final road = track.roadPath();
    // drawAsphalt fills its input. The corridor must be a closed polygon,
    // rather than an open centreline that Canvas would close with a chord.
    surfaces.drawAsphalt(canvas, road, _road.color);
    canvas.drawPath(track.leftBoundaryPath(), _edge);
    canvas.drawPath(track.rightBoundaryPath(), _edge);
    for (var i = 12; i < track.centerline.length - 12; i += 18) {
      final p = track.centerline[i];
      final d = track.directionAt(_stationAt(i));
      final center = Offset(p.x, p.y);
      final a = center - Offset(d.x, d.y) * 5;
      final b = center + Offset(d.x, d.y) * 5;
      canvas.drawLine(a, b, _dash);
    }
    _drawCheckeredGate(canvas, track.gateAt(track.totalLength * .955));
    canvas.drawLine(
      _asOffset(track.gateAt(AcademyTrack.startStation).$1),
      _asOffset(track.gateAt(AcademyTrack.startStation).$2),
      _gate..color = const Color(0xFFEEE9D8),
    );
    if (showDebugGeometry && kDebugMode) {
      for (final station in track.checkpointStations) {
        canvas.drawLine(
          _asOffset(track.gateAt(station).$1),
          _asOffset(track.gateAt(station).$2),
          _gate..color = const Color(0xFF58D18A),
        );
      }
    }
    for (final station in [
      140.0,
      track.totalLength * .50,
      track.totalLength * .83,
    ]) {
      _drawDirectionArrow(
        canvas,
        track.pointAt(station),
        track.directionAt(station),
      );
    }
  }

  double _stationAt(int pointIndex) {
    var distance = 0.0;
    for (var i = 1; i <= pointIndex; i++) {
      final a = track.centerline[i - 1];
      final b = track.centerline[i];
      distance += math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
    }
    return distance;
  }

  void _drawCheckeredGate(Canvas canvas, (TrackPoint, TrackPoint) gate) {
    final a = Offset(gate.$1.x, gate.$1.y);
    final b = Offset(gate.$2.x, gate.$2.y);
    final delta = b - a;
    const tiles = 14;
    for (var i = 0; i < tiles; i++) {
      canvas.drawLine(
        a + delta * (i / tiles),
        a + delta * ((i + 1) / tiles),
        i.isEven ? _finishWhite : _finishBlack,
      );
    }
  }

  void _drawDirectionArrow(
    Canvas canvas,
    TrackPoint point,
    TrackPoint direction,
  ) {
    final center = Offset(point.x, point.y);
    final forward = Offset(direction.x, direction.y);
    final side = Offset(-direction.y, direction.x);
    final arrow = Path()
      ..moveTo((center + forward * 17).dx, (center + forward * 17).dy)
      ..lineTo(
        (center - forward * 9 + side * 9).dx,
        (center - forward * 9 + side * 9).dy,
      )
      ..lineTo(
        (center - forward * 9 - side * 9).dx,
        (center - forward * 9 - side * 9).dy,
      )
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFD7D2C5));
  }
}

Offset _asOffset(TrackPoint point) => Offset(point.x, point.y);
