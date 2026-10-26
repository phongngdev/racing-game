import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../input/car_input.dart';
import '../simulation/race_simulation.dart';

enum RaceAudioPhase { ready, countdown, racing, paused, finished }

class RaceFeedbackEvent {
  const RaceFeedbackEvent(this.event, {this.player, this.count});
  final String event;
  final PlayerId? player;
  final int? count;
}

class EngineAudioMix {
  const EngineAudioMix({
    required this.idle,
    required this.mid,
    required this.high,
    required this.pitch,
  });

  final double idle;
  final double mid;
  final double high;
  final double pitch;

  static EngineAudioMix forCar({
    required double speed,
    required double throttle,
    required double reverse,
    required double steering,
    required double brake,
  }) {
    final normalizedSpeed = (speed / 190).clamp(0.0, 1.0);
    final rpm =
        (0.08 +
                normalizedSpeed * 0.72 +
                throttle.clamp(0.0, 1.0) * 0.2 +
                reverse.clamp(0.0, 1.0) * 0.08)
            .clamp(0.08, 1.0);
    final blend = ((rpm - 0.22) / 0.78).clamp(0.0, 1.0);
    final highBlend = ((rpm - 0.62) / 0.38).clamp(0.0, 1.0);
    final decel =
        (brake.clamp(0.0, 1.0) * 0.15 +
                (steering.abs().clamp(0.0, 1.0) * normalizedSpeed * 0.06))
            .clamp(0.0, 0.2);
    final idle = math.sqrt((1 - blend).clamp(0.0, 1.0));
    final high = math.sqrt(highBlend);
    final mid = math.sqrt((1 - idle * idle - high * high).clamp(0.0, 1.0));
    return EngineAudioMix(
      idle: idle * (1 - decel * 0.4),
      mid: mid * (1 - decel),
      high: high * (1 + throttle.clamp(0.0, 1.0) * 0.18),
      pitch: 0.8 + rpm * 0.82 + throttle.clamp(0.0, 1.0) * 0.15,
    );
  }
}

class AudioSettingsController extends ChangeNotifier {
  AudioSettingsController._() {
    unawaited(_load());
  }

  static final shared = AudioSettingsController._();
  static const _masterKey = 'raceAudio.master';
  static const _engineKey = 'raceAudio.engine';
  static const _effectsKey = 'raceAudio.effects';
  static const _vibrationKey = 'raceAudio.vibration';

  final _prefs = SharedPreferencesAsync();
  double master = 0.82;
  double engine = 0.6;
  double effects = 0.9;
  bool vibration = true;
  bool _loaded = false;
  Timer? _saveTimer;

  Future<void> _load() async {
    try {
      master = (await _prefs.getDouble(_masterKey) ?? master).clamp(0.0, 1.0);
      engine = (await _prefs.getDouble(_engineKey) ?? engine).clamp(0.0, 1.0);
      effects = (await _prefs.getDouble(_effectsKey) ?? effects).clamp(
        0.0,
        1.0,
      );
      vibration = await _prefs.getBool(_vibrationKey) ?? vibration;
    } catch (_) {
      // Defaults remain usable if browser storage is unavailable.
    }
    _loaded = true;
    notifyListeners();
    RaceAudioService.instance
      ..applyMaster(master)
      ..applyEffects(effects);
  }

  bool get loaded => _loaded;
  void setMaster(double value) => _set(() => master = value.clamp(0.0, 1.0));
  void setEngine(double value) => _set(() => engine = value.clamp(0.0, 1.0));
  void setEffects(double value) => _set(() => effects = value.clamp(0.0, 1.0));
  void setVibration(bool value) => _set(() => vibration = value);

  void _set(void Function() change) {
    change();
    RaceAudioService.instance
      ..applyMaster(master)
      ..applyEffects(effects);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 240), () async {
      try {
        await _prefs.setDouble(_masterKey, master);
        await _prefs.setDouble(_engineKey, engine);
        await _prefs.setDouble(_effectsKey, effects);
        await _prefs.setBool(_vibrationKey, vibration);
      } catch (_) {
        // Storage failures should not interrupt a race.
      }
    });
  }
}

class RaceAudioService {
  RaceAudioService._();
  static final instance = RaceAudioService._();
  static const _root = 'assets/audio/racing/';

  final SoLoud _soloud = SoLoud.instance;
  Future<void>? _loading;
  final Map<String, AudioSource> _sources = {};
  final Map<PlayerId, List<SoundHandle>> _engines = {};
  final Set<SoundHandle> _loops = {};
  final Map<PlayerId, bool> _enginePaused = {};
  final Map<PlayerId, double> _rpm = {PlayerId.red: 0.08, PlayerId.blue: 0.08};
  final Map<PlayerId, double> _engineGain = {PlayerId.red: 0, PlayerId.blue: 0};
  final Set<SoundHandle> _oneshots = {};
  final Map<SoundHandle, double> _oneshotBaseVolumes = {};
  double _master = 0.82;
  bool _ready = false;

  bool get ready => _ready;
  Future<void> preload() => _loading ??= _initialize();

  Future<void> _initialize() async {
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init(
          sampleRate: 44100,
          bufferSize: 1024,
          channels: Channels.stereo,
        );
      }
      const paths = <String>[
        'engine/engine_idle.wav',
        'engine/engine_mid.wav',
        'engine/engine_high.wav',
        'collision/wall_light.ogg',
        'collision/wall_heavy.ogg',
        'collision/wall_heavy_2.ogg',
        'collision/car_medium.ogg',
        'collision/car_medium_2.ogg',
        'collision/car_heavy.ogg',
        'collision/dirt_thud.ogg',
        'collision/dirt_thud_2.ogg',
        'surface/edge_debris.ogg',
        'surface/road_roll.wav',
        'race/countdown_tick.ogg',
        'race/countdown_tick_alt.ogg',
        'race/go.ogg',
        'race/checkpoint.ogg',
        'race/finish.ogg',
        'result/victory.ogg',
        'result/draw.ogg',
        'result/dnf.ogg',
      ];
      await Future.wait(
        paths.map((path) async {
          _sources[path] = await _soloud.loadAsset('$_root$path');
        }),
      );
      _ready = true;
      _soloud.setGlobalVolume(_master);
    } catch (error) {
      debugPrint('[RaceAudio] Audio initialization failed: $error');
      _loading = null;
    }
  }

  Future<void> unlock() {
    if (_soloud.isInitialized) return _resumeDevice();
    return preload().then((_) async {
      if (_ready) await _resumeDevice();
    });
  }

  Future<void> _resumeDevice() async {
    try {
      await _soloud.startAudioDevice();
    } catch (error) {
      debugPrint('[RaceAudio] Could not resume audio device: $error');
    }
  }

  void applyMaster(double value) {
    _master = value.clamp(0.0, 1.0);
    if (_soloud.isInitialized) _soloud.setGlobalVolume(_master);
  }

  void applyEffects(double value) {
    if (!_soloud.isInitialized) return;
    for (final entry in _oneshotBaseVolumes.entries) {
      _soloud.setVolume(entry.key, entry.value * value.clamp(0.0, 1.0));
    }
  }

  void updateEngines({
    required double dt,
    required RaceSimulation simulation,
    required InputSource input,
    required RaceAudioPhase phase,
  }) {
    if (!_ready || !_soloud.isInitialized) return;
    final active =
        phase == RaceAudioPhase.ready ||
        phase == RaceAudioPhase.countdown ||
        phase == RaceAudioPhase.racing;
    for (final player in PlayerId.values) {
      final car = player == PlayerId.red ? simulation.red : simulation.blue;
      final control = input.inputFor(player);
      final targetRpm =
          (0.08 +
                  (car.speed / 190).clamp(0.0, 1.0) * 0.72 +
                  control.throttle * 0.2 +
                  control.reverse * 0.08)
              .clamp(0.08, 1.0);
      final previous = _rpm[player] ?? targetRpm;
      final smoothing =
          1 -
          math.exp(-dt.clamp(0.0, 0.1) * (targetRpm > previous ? 7.5 : 4.2));
      final rpm = previous + (targetRpm - previous) * smoothing;
      _rpm[player] = rpm;
      final mix = EngineAudioMix.forCar(
        speed: rpm * 190,
        throttle: control.throttle,
        reverse: control.reverse,
        steering: control.steering,
        brake: control.brake,
      );
      final handles = _engines[player];
      if (handles == null && active) _startEngine(player);
      final current = _engines[player];
      if (current == null) continue;
      final previousGain = _engineGain[player] ?? 0;
      final targetGain = active ? 1.0 : 0.0;
      final gainBlend =
          1 - math.exp(-dt.clamp(0.0, 0.1) * (active ? 5.5 : 8.5));
      final gain = previousGain + (targetGain - previousGain) * gainBlend;
      _engineGain[player] = gain;
      final shouldPause = !active && gain < 0.01;
      if (_enginePaused[player] != shouldPause) {
        for (final handle in current) {
          _soloud.setPause(handle, shouldPause);
        }
        _enginePaused[player] = shouldPause;
      }
      final level =
          AudioSettingsController.shared.engine *
          0.55 *
          gain *
          (player == PlayerId.red ? 0.94 : 0.86);
      final mixes = [mix.idle, mix.mid, mix.high];
      for (var i = 0; i < current.length; i++) {
        _soloud.setVolume(current[i], mixes[i] * level);
        _soloud.setRelativePlaySpeed(
          current[i],
          mix.pitch *
              (i == 0
                  ? 0.94
                  : i == 2
                  ? 1.045
                  : 1.0),
        );
      }
    }
  }

  void _startEngine(PlayerId player) {
    try {
      final pan = player == PlayerId.red ? -0.12 : 0.12;
      _engines[player] = [
        _soloud.play(
          _sources['engine/engine_idle.wav']!,
          looping: true,
          volume: 0,
          pan: pan,
        ),
        _soloud.play(
          _sources['engine/engine_mid.wav']!,
          looping: true,
          volume: 0,
          pan: pan,
        ),
        _soloud.play(
          _sources['engine/engine_high.wav']!,
          looping: true,
          volume: 0,
          pan: pan,
        ),
      ];
      _loops.addAll(_engines[player]!);
    } catch (error) {
      debugPrint('[RaceAudio] Engine playback failed: $error');
    }
  }

  void play(
    String asset, {
    double volume = 1,
    double pan = 0,
    double pitch = 1,
  }) {
    if (!_ready ||
        !_soloud.isInitialized ||
        AudioSettingsController.shared.effects <= 0) {
      return;
    }
    final source = _sources[asset];
    if (source == null) return;
    try {
      final handle = _soloud.play(
        source,
        volume: (volume * AudioSettingsController.shared.effects).clamp(
          0.0,
          1.0,
        ),
        pan: pan.clamp(-1.0, 1.0),
        scale: pitch,
      );
      _oneshots.add(handle);
      _oneshotBaseVolumes[handle] = volume.clamp(0.0, 1.0);
      if (_oneshots.length > 36) {
        final oldest = _oneshots.first;
        _oneshots.remove(oldest);
        _oneshotBaseVolumes.remove(oldest);
        unawaited(_soloud.stop(oldest));
      }
    } catch (error) {
      debugPrint('[RaceAudio] Effect playback failed: $error');
    }
  }

  void stopAll() {
    for (final handle in _loops) {
      if (_soloud.isInitialized) unawaited(_soloud.stop(handle));
    }
    _loops.clear();
    _engines.clear();
    for (final handle in _oneshots.toList()) {
      if (_soloud.isInitialized) unawaited(_soloud.stop(handle));
    }
    _oneshots.clear();
    _oneshotBaseVolumes.clear();
  }
}

class RaceAudioDirector {
  RaceAudioDirector({required this.simulation, required this.input});
  final RaceSimulation simulation;
  final InputSource input;
  final RaceAudioService _audio = RaceAudioService.instance;
  final Map<PlayerId, SoundHandle> _roadRolling = {};
  final Map<(PlayerId, String), bool> _loopPaused = {};
  int _collisionVariation = 0;
  bool _disposed = false;

  void preload() => unawaited(_audio.preload());
  Future<void> unlock() => _audio.unlock();
  void phaseEvent(String event, {PlayerId? player, int? count}) {
    switch (event) {
      case 'countdown':
        _audio.play(
          count == 2
              ? 'race/countdown_tick_alt.ogg'
              : 'race/countdown_tick.ogg',
          volume: 0.75,
        );
        break;
      case 'go':
        _audio.play('race/go.ogg', volume: 1);
        break;
      case 'checkpoint':
        _audio.play('race/checkpoint.ogg', volume: 0.85, pan: _pan(player));
        break;
      case 'finish':
        _audio.play('race/finish.ogg', volume: 0.95, pan: _pan(player));
        break;
      case 'victory':
        _audio.play('result/victory.ogg', volume: 1);
        break;
      case 'draw':
        _audio.play('result/draw.ogg', volume: 1);
        break;
      case 'dnf':
        _audio.play('result/dnf.ogg', volume: 0.95);
        break;
    }
  }

  void collision(CollisionEvent event) {
    final intensity = event.intensity.clamp(0.0, 1.0);
    final pan = event.players.length != 1 ? 0.0 : _pan(event.players.first);
    final variant = _collisionVariation++;
    if (event.type == CollisionType.vehicle) {
      _audio.play(
        intensity > 0.7
            ? 'collision/car_heavy.ogg'
            : variant.isEven
            ? 'collision/car_medium.ogg'
            : 'collision/car_medium_2.ogg',
        volume: 0.45 + intensity * 0.55,
        pan: pan,
        pitch: 0.9 + (1 - intensity) * 0.2,
      );
      if (intensity > 0.7) {
        _audio.play(
          variant.isEven
              ? 'collision/car_medium.ogg'
              : 'collision/car_medium_2.ogg',
          volume: intensity * 0.38,
          pan: -pan,
          pitch: 0.95,
        );
      }
    } else if (intensity > 0.72) {
      _audio.play(
        variant.isEven
            ? 'collision/wall_heavy.ogg'
            : 'collision/wall_heavy_2.ogg',
        volume: 0.44 + intensity * 0.56,
        pan: pan,
        pitch: 0.92 + (1 - intensity) * 0.12,
      );
      _audio.play(
        variant.isEven
            ? 'collision/dirt_thud.ogg'
            : 'collision/dirt_thud_2.ogg',
        volume: intensity * 0.56,
        pan: pan * 0.6,
      );
    } else {
      _audio.play(
        'collision/wall_light.ogg',
        volume: 0.38 + intensity * 0.48,
        pan: pan,
      );
    }
  }

  void edgeGrit({required PlayerId player, required double speed}) {
    _audio.play(
      'surface/edge_debris.ogg',
      volume: (speed / 190).clamp(0.0, 0.42),
      pan: _pan(player),
      pitch: 0.92 + (speed / 500),
    );
  }

  void update(double dt, RaceAudioPhase phase) {
    if (_disposed) return;
    _audio.updateEngines(
      dt: dt,
      simulation: simulation,
      input: input,
      phase: phase,
    );
    for (final player in PlayerId.values) {
      final car = player == PlayerId.red ? simulation.red : simulation.blue;
      final rolling = phase == RaceAudioPhase.racing
          ? ((car.speed - 9) / 150).clamp(0.0, 1.0)
          : 0.0;
      var roadHandle = _roadRolling[player];
      if (roadHandle == null && rolling > 0.015 && _audio._ready) {
        final source = _audio._sources['surface/road_roll.wav'];
        if (source != null) {
          roadHandle = SoLoud.instance.play(
            source,
            looping: true,
            volume: 0,
            pan: _pan(player),
          );
          _roadRolling[player] = roadHandle;
          _audio._loops.add(roadHandle);
        }
      }
      if (roadHandle != null) {
        SoLoud.instance.setVolume(
          roadHandle,
          rolling * 0.19 * AudioSettingsController.shared.effects,
        );
        SoLoud.instance.setRelativePlaySpeed(
          roadHandle,
          0.76 + car.speed / 210,
        );
        final pause = rolling <= 0.015;
        if (_loopPaused[(player, 'road')] != pause) {
          SoLoud.instance.setPause(roadHandle, pause);
          _loopPaused[(player, 'road')] = pause;
        }
      }
    }
  }

  double _pan(PlayerId? player) => player == PlayerId.red
      ? -0.2
      : player == PlayerId.blue
      ? 0.2
      : 0;
  void dispose() {
    _disposed = true;
    _audio.stopAll();
  }
}

class RaceAudioSettingsPanel extends StatelessWidget {
  const RaceAudioSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AudioSettingsController.shared,
    builder: (context, _) {
      final settings = AudioSettingsController.shared;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Âm thanh & rung',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _AudioSlider(
                label: 'Âm lượng chung',
                value: settings.master,
                onChanged: settings.setMaster,
              ),
              _AudioSlider(
                label: 'Động cơ',
                value: settings.engine,
                onChanged: settings.setEngine,
              ),
              _AudioSlider(
                label: 'Hiệu ứng',
                value: settings.effects,
                onChanged: settings.setEffects,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rung trên điện thoại'),
                value: settings.vibration,
                onChanged: settings.setVibration,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AudioSlider extends StatelessWidget {
  const _AudioSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text('${(value * 100).round()}%'),
        ],
      ),
      Slider(value: value, onChanged: onChanged),
    ],
  );
}

class RaceAudioSettingsButton extends StatelessWidget {
  const RaceAudioSettingsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: 'Cài đặt âm thanh',
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RaceAudioSettingsPanel(),
          ),
        ),
      ),
    ),
    icon: const Icon(Icons.tune_rounded),
  );
}
