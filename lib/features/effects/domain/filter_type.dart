enum FilterType {
  dualTone('Dual Tone', 'Kontras sian & magenta bergaya retro'),
  thermal('Thermal', 'Peta suhu inframerah biru-merah-kuning'),
  sketch('Sketch', 'Sketsa pensil monokrom bertekstur tepi'),
  pixelate('Pixelate', 'Mozaik piksel retro 8-bit'),
  glitch('Glitch', 'Pergeseran kanal RGB & garis pemindaian'),
  invert('Invert', 'Negatif warna spektrum penuh'),
  redChannel('Red Channel', 'Isolasi kanal merah dramatis'),
  edgeDetection('Edge Detection', 'Deteksi kontur neon matriks Sobel'),
  blur('Blur', 'Efek kabur lembut di dalam portal'),
  cartoon('Cartoon', 'Posterisasi warna & garis tepi komik'),
  rainbowWave('Rainbow Wave', 'Gelombang spektrum warna pelangi');

  final String displayName;
  final String description;

  const FilterType(this.displayName, this.description);

  FilterType get next {
    final nextIndex = (index + 1) % FilterType.values.length;
    return FilterType.values[nextIndex];
  }

  FilterType get previous {
    final prevIndex =
        (index - 1 + FilterType.values.length) % FilterType.values.length;
    return FilterType.values[prevIndex];
  }

  /// Secondary complementary filter used for the inner layer in 3D-inspired portal mode.
  FilterType get complementary3DFilter {
    final compIndex = (index + 3) % FilterType.values.length;
    return FilterType.values[compIndex];
  }
}

enum PortalRenderMode {
  mode2D('2D Portal'),
  mode3D('3D Portal');

  final String label;
  const PortalRenderMode(this.label);

  PortalRenderMode get toggled =>
      this == PortalRenderMode.mode2D
          ? PortalRenderMode.mode3D
          : PortalRenderMode.mode2D;
}
