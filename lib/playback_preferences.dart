import 'video_enhancement_preferences.dart';

const playbackSpeeds = [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0];
const danmakuFontScales = [
  1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75,
  3.0, 3.25, 3.5, 3.75, 4.0, 4.25, 4.5, 4.75, 5.0,
];
const danmakuRowsOptions = [1, 2, 3, 4, 5, 6];

enum TelevisionDecoder { optimized, hardware, software }
enum DanmakuColorMode { normal, colorful, gradient }

class PlaybackPreferences {
  const PlaybackPreferences({
    this.speed = 1,
    this.quality = 0,
    this.autoAdvance = true,
    this.danmaku = true,
    this.preload = true,
    this.enhancement = const VideoEnhancementPreferences(),
    this.televisionDecoder = TelevisionDecoder.optimized,
    this.danmakuFontScale = 1,
    this.danmakuRows = 4,
    this.danmakuColorMode = DanmakuColorMode.normal,
  });

  final double speed;
  final int quality;
  final bool autoAdvance;
  final bool danmaku;
  final bool preload;
  final VideoEnhancementPreferences enhancement;
  final TelevisionDecoder televisionDecoder;
  final double danmakuFontScale;
  final int danmakuRows;
  final DanmakuColorMode danmakuColorMode;

  PlaybackPreferences copyWith({
    double? speed,
    int? quality,
    bool? autoAdvance,
    bool? danmaku,
    bool? preload,
    VideoEnhancementPreferences? enhancement,
    TelevisionDecoder? televisionDecoder,
    double? danmakuFontScale,
    int? danmakuRows,
    DanmakuColorMode? danmakuColorMode,
  }) => PlaybackPreferences(
    speed: speed ?? this.speed,
    quality: quality ?? this.quality,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    danmaku: danmaku ?? this.danmaku,
    preload: preload ?? this.preload,
    enhancement: enhancement ?? this.enhancement,
    televisionDecoder: televisionDecoder ?? this.televisionDecoder,
    danmakuFontScale: danmakuFontScale ?? this.danmakuFontScale,
    danmakuRows: danmakuRows ?? this.danmakuRows,
    danmakuColorMode: danmakuColorMode ?? this.danmakuColorMode,
  );

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'quality': quality,
    'autoAdvance': autoAdvance,
    'danmaku': danmaku,
    'preload': preload,
    'enhancement': enhancement.toJson(),
    'televisionDecoder': televisionDecoder.name,
    'danmakuFontScale': danmakuFontScale,
    'danmakuRows': danmakuRows,
    'danmakuColorMode': danmakuColorMode.name,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final speed = (value['speed'] as num? ?? 1).toDouble();
    final quality = value['quality'] as int? ?? 0;
    final autoAdvance = value['autoAdvance'] as bool? ?? true;
    final danmaku = value['danmaku'] as bool? ?? true;
    final preload = value['preload'] as bool? ?? true;
    final danmakuFontScale =
        (value['danmakuFontScale'] as num? ?? 1).toDouble();
    final danmakuRows = value['danmakuRows'] as int? ?? 4;
    final danmakuColorMode =
        DanmakuColorMode.values.asNameMap()[value['danmakuColorMode']] ??
        DanmakuColorMode.normal;
    if (!playbackSpeeds.contains(speed) ||
        quality < 0 ||
        quality > 4320 ||
        !danmakuFontScales.contains(danmakuFontScale) ||
        !danmakuRowsOptions.contains(danmakuRows)) {
      throw const FormatException('播放偏好无效');
    }
    return PlaybackPreferences(
      speed: speed,
      quality: quality,
      autoAdvance: autoAdvance,
      danmaku: danmaku,
      preload: preload,
      enhancement: VideoEnhancementPreferences.fromJson(value['enhancement']),
      televisionDecoder:
          TelevisionDecoder.values.asNameMap()[value['televisionDecoder']] ??
          TelevisionDecoder.optimized,
      danmakuFontScale: danmakuFontScale,
      danmakuRows: danmakuRows,
      danmakuColorMode: danmakuColorMode,
    );
  }
}
