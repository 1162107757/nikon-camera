import 'hue_icons.dart';

// Each current adjustment has its own symbol. Keep this independent of schema
// order so adding or rearranging controls cannot silently pick a generic icon.
const editorAdjustmentIcons = <String, HueIconKind>{
  'BRIGHTNESS': HueIconKind.brightness,
  'EXPOSURE': HueIconKind.exposure,
  'CONTRAST': HueIconKind.contrast,
  'HIGHLIGHTS': HueIconKind.highlights,
  'SHADOWS': HueIconKind.shadows,
  'WHITES': HueIconKind.whites,
  'BLACKS': HueIconKind.blacks,
  'TEMPERATURE': HueIconKind.temperature,
  'TINT': HueIconKind.tint,
  'SATURATION': HueIconKind.saturation,
  'VIBRANCE': HueIconKind.vibrance,
  'CLARITY': HueIconKind.clarity,
  'SHARPENING': HueIconKind.sharpening,
  'LUMA_DENOISE': HueIconKind.lumaDenoise,
  'COLOR_DENOISE': HueIconKind.colorDenoise,
  'GRAIN': HueIconKind.grain,
  'VIGNETTE': HueIconKind.vignette,
};

const editorAdvancedIcons = <int, HueIconKind>{
  -5: HueIconKind.curve,
  -6: HueIconKind.hsl,
  -2: HueIconKind.palette,
  -7: HueIconKind.cleanup,
  -8: HueIconKind.brush,
  -9: HueIconKind.patch,
};

HueIconKind editorParameterIcon(String name) =>
    editorAdjustmentIcons[name] ?? HueIconKind.adjust;

HueIconKind editorAdvancedToolIcon(int index) =>
    editorAdvancedIcons[index] ?? HueIconKind.adjust;
