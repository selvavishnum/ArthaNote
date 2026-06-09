import 'dart:math';
import 'dart:typed_data';

/// Cooley-Tukey FFT — ported from the NoiseClear browser tool.
/// Uses Float64List for precision during spectral processing.
class FFTService {
  static Float64List hannWindow(int n) {
    final w = Float64List(n);
    for (int i = 0; i < n; i++) {
      w[i] = 0.5 * (1 - cos(2 * pi * i / n));
    }
    return w;
  }

  /// In-place forward FFT.
  static void fft(Float64List re, Float64List im) {
    final n = re.length;
    // Bit-reversal permutation
    for (int i = 1, j = 0; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        double tmp = re[i]; re[i] = re[j]; re[j] = tmp;
        tmp = im[i]; im[i] = im[j]; im[j] = tmp;
      }
    }
    // Butterfly
    for (int len = 2; len <= n; len <<= 1) {
      final ang = -2 * pi / len;
      final wR = cos(ang), wI = sin(ang);
      for (int i = 0; i < n; i += len) {
        double cR = 1, cI = 0;
        for (int j = 0; j < len ~/ 2; j++) {
          final uR = re[i + j], uI = im[i + j];
          final vR = re[i + j + len ~/ 2] * cR - im[i + j + len ~/ 2] * cI;
          final vI = re[i + j + len ~/ 2] * cI + im[i + j + len ~/ 2] * cR;
          re[i + j] = uR + vR; im[i + j] = uI + vI;
          re[i + j + len ~/ 2] = uR - vR;
          im[i + j + len ~/ 2] = uI - vI;
          final newR = cR * wR - cI * wI;
          cI = cR * wI + cI * wR;
          cR = newR;
        }
      }
    }
  }

  /// In-place inverse FFT.
  static void ifft(Float64List re, Float64List im) {
    for (int i = 0; i < im.length; i++) {
      im[i] = -im[i];
    }
    fft(re, im);
    final n = re.length;
    for (int i = 0; i < n; i++) {
      re[i] /= n;
      im[i] = -im[i] / n;
    }
  }

  /// Wraps x into [-π, π].
  static double princArg(double x) {
    return x - 2 * pi * (x / (2 * pi)).roundToDouble();
  }

  /// Linear interpolation helper.
  static double lerp(double a, double b, double t) => a + (b - a) * t;
}
