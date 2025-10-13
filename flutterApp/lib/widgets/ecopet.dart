import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../api/pawprint_api.dart' show PetMood;

class EcoPet extends StatefulWidget {
  final PetMood mood;
  final double size;
  const EcoPet({super.key, required this.mood, this.size = 240});

  @override
  State<EcoPet> createState() => _EcoPetState();
}

class _EcoPetState extends State<EcoPet> {
  PetMood? _currentMood;
  bool _playing = false;
  bool _loading = false;
  bool _loaded = false;

  List<ui.Image> _frames = [];
  List<Duration> _durations = [];
  int _frameIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentMood = widget.mood;
    _loadFor(_currentMood!);
  }

  @override
  void didUpdateWidget(covariant EcoPet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _switchMood(widget.mood);
  }

  @override
  void dispose() {
    _stopPlayback();
    _disposeFrames();
    super.dispose();
  }

  void _switchMood(PetMood mood) {
    if (_currentMood == mood) return;
    _stopPlayback();
    _disposeFrames();
    setState(() {
      _currentMood = mood;
      _loaded = false;
      _loading = false;
      _frameIndex = 0;
    });
    _loadFor(mood);
  }

  String _gifPathFor(PetMood mood) {
    switch (mood) {
      case PetMood.happy:
        return 'assets/images/eco_pet/happy_2.gif';
      case PetMood.neutral:
        return 'assets/images/eco_pet/neutral_2.gif';
      case PetMood.sad:
        return 'assets/images/eco_pet/sad_2.gif';
    }
  }

  Future<void> _loadFor(PetMood mood) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loaded = false;
      _frameIndex = 0;
    });

    try {
      final data = await rootBundle.load(_gifPathFor(mood));
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());

      final frames = <ui.Image>[];
      final durations = <Duration>[];

      for (int i = 0; i < codec.frameCount; i++) {
        final fi = await codec.getNextFrame();
        frames.add(fi.image);
        durations.add(fi.duration);
      }

      if (!mounted) {
        for (final f in frames) f.dispose();
        return;
      }
      if (_currentMood != mood) {
        for (final f in frames) f.dispose();
        return;
      }

      setState(() {
        _frames = frames;
        _durations = durations;
        _loaded = _frames.isNotEmpty;
        _loading = false;
        _frameIndex = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loaded = false;
      });
    }
  }

  void _disposeFrames() {
    for (final f in _frames) f.dispose();
    _frames = [];
    _durations = [];
  }

  void _stopPlayback() {
    _timer?.cancel();
    _timer = null;
    _playing = false;
  }

  Future<void> _playOnce() async {
    if (_playing || !_loaded) return;
    setState(() {
      _playing = true;
      _frameIndex = 0;
    });

    void tick() {
      if (!mounted) return;
      if (_frameIndex >= _frames.length - 1) {
        _stopPlayback();
        setState(() => _frameIndex = 0);
        return;
      }
      final delay = _durations[_frameIndex];
      _timer = Timer(delay, () {
        if (!mounted) return;
        setState(() => _frameIndex += 1);
        tick();
      });
    }

    tick();
  }

  @override
  Widget build(BuildContext context) {
    final child = (!_loaded || _frames.isEmpty)
        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
        : RawImage(image: _frames[_frameIndex], fit: BoxFit.contain, filterQuality: FilterQuality.high);

    return GestureDetector(
      onTap: _playOnce,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Align(alignment: Alignment.center, child: child),
      ),
    );
  }
}
