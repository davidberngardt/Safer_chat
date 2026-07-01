import 'package:flutter/foundation.dart';

class FontScaleProvider with ChangeNotifier {
  double _fontSizeScale = 1.0;
  
  double get fontSizeScale => _fontSizeScale;
  
  void setFontSizeScale(double scale) {
    _fontSizeScale = _clampScale(scale);
    notifyListeners();
  }

  void resetFontSizeScale() {
    _fontSizeScale = 1.0;
    notifyListeners();
  }

  double _clampScale(double scale) {
    if (scale < 0.8) return 0.8;
    if (scale > 1.3) return 1.3;
    return scale;
  }

  double getScaledValue(double baseValue) {
    return baseValue * _fontSizeScale;
  }

  double getClampedValue(double baseValue) {
    return baseValue * _clampScale(_fontSizeScale);
  }
}