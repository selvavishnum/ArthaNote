import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/audio_params.dart';
import 'fft_service.dart';

/// All audio processing algorithms — Dart port of the NoiseClear browser tool.
/// Runs inside an Isolate via [compute] so the UI stays smooth.
class ProcessorService {
  static const _N = 2048;
  static const _HOP = 512;

  // ─────────────────────────────────────────────────────────
  // Public entry point
  // ─────────────────────────────────────────────────────────
  static Future<Float32List> process({
    required Float32List signal,
    required int sampleRate,
    required AudioParams params,
    ValueChanged<double>? onProgress,
  }) async {
    // compute() runs the heavy work in a background isolate.
    // We pass everything as a plain Map because isolates can't
    // share Dart objects across message boundaries easily.
    final result = await compute(
      _processIsolate,
      _IsolateArgs(signal: signal, sampleRate: sampleRate, params: params),
    );
    return result;
  }

  // ─────────────────────────────────────────────────────────
  // Isolate worker
  // ─────────────────────────────────────────────────────────
  static Float32List _processIsolate(_IsolateArgs args) {
    var s = Float32List.fromList(args.signal);
    final p = args.params;
    final sr = args.sampleRate;

    // --- Step 1: Spectral smoothing (de-roughness) ---
    s = _spectralSmooth(s, p.smoothAmount);

    // --- Step 2: Build smart noise profile ---
    final noiseProfile = _buildNoiseProfile(s);

    // --- Step 3: Pass 1 — Wiener filter ---
    s = _wienerFilter(s, noiseProfile, p.nrStrength, p.nrAlpha, p.nrFloor);

    // --- Step 4: Pass 2 — Hard spectral gate ---
    final gateRat = 0.5 + p.gateThreshold / 100 * 4.5;
    s = _hardSpectralGate(s, noiseProfile, gateRat);

    // --- Step 5: Pass 3 — VAD silence gate ---
    s = _vadGate(s, sr, p.vadSensitivity, p.vadHoldMs);

    // --- Step 6: Pitch shift (phase vocoder) ---
    if (p.pitchSemitones.abs() > 0.1) {
      s = _pitchShift(s, p.pitchSemitones);
    }

    // --- Step 7: Formant shift ---
    if ((p.formantFactor - 1.0).abs() > 0.03) {
      s = _formantShift(s, p.formantFactor);
    }

    // --- Step 8: Harmonic exciter ---
    if (p.exciterAmount > 0) {
      s = _harmonicExciter(s, p.exciterAmount);
    }

    // --- Step 9: Simple EQ (biquad approximation) ---
    s = _applyEQ(s, sr, p.hpFreq, p.bassGain, p.deHarshGain, p.presGain, p.airGain);

    // --- Step 10: Soft compression ---
    s = _softCompress(s, p.compThreshold, p.compRatio);

    // --- Step 11: De-esser ---
    if (p.deEssAmt > 0) {
      s = _deEss(s, sr, p.deEssFreq, p.deEssAmt);
    }

    // --- Step 12: LUFS normalize ---
    s = _normalizeLufs(s, p.targetLufs);

    return s;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 1 — Smart Noise Profile (VAD-based)
  // Finds lowest 30% energy frames → averages their spectra.
  // ─────────────────────────────────────────────────────────
  static Float32List _buildNoiseProfile(Float32List signal) {
    final win = FFTService.hannWindow(_N);
    final numF = (signal.length - _N) ~/ _HOP;
    if (numF < 4) return Float32List(_N)..fillRange(0, _N, 0.001);

    final energies = Float64List(numF);
    final spectra = <Float64List>[];

    for (int fi = 0; fi < numF; fi++) {
      final re = Float64List(_N), im = Float64List(_N);
      final off = fi * _HOP;
      for (int k = 0; k < _N; k++) {
        re[k] = (off + k < signal.length ? signal[off + k] : 0.0) * win[k];
      }
      FFTService.fft(re, im);
      final mag = Float64List(_N);
      double e = 0;
      for (int k = 0; k < _N; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
        e += mag[k] * mag[k];
      }
      energies[fi] = e;
      spectra.add(mag);
    }

    // Sort energies, find 30th percentile threshold
    final sorted = Float64List.fromList(energies)..sort();
    final thresh = sorted[(numF * 0.30).floor()];

    final profile = Float64List(_N);
    int cnt = 0;
    for (int fi = 0; fi < numF; fi++) {
      if (energies[fi] <= thresh) {
        for (int k = 0; k < _N; k++) profile[k] += spectra[fi][k];
        cnt++;
      }
    }
    if (cnt > 0) {
      for (int k = 0; k < _N; k++) profile[k] /= cnt;
    }
    return Float32List(_N)
      ..setAll(0, profile.map((v) => v.toDouble()));
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 2 — Decision-Directed MMSE Wiener Filter
  // snrPrio = α * |prevMag|² / noise² + (1-α) * max(snrPost-1, 0)
  // gain H = snrPrio / (1 + snrPrio)
  // ─────────────────────────────────────────────────────────
  static Float32List _wienerFilter(
    Float32List signal, Float32List noise,
    double strength, double alphaP, double floorMult,
  ) {
    final win = FFTService.hannWindow(_N);
    final str = strength / 100;
    final alp = alphaP / 100;
    final numF = (signal.length - _N) ~/ _HOP + 1;
    final out = Float64List(signal.length + _N);
    final nrm = Float64List(signal.length + _N);
    final prev = Float64List(_N);

    for (int fi = 0; fi < numF; fi++) {
      final re = Float64List(_N), im = Float64List(_N);
      final off = fi * _HOP;
      for (int k = 0; k < _N; k++) {
        re[k] = (off + k < signal.length ? signal[off + k] : 0.0) * win[k];
      }
      FFTService.fft(re, im);

      final mag = Float64List(_N), ph = Float64List(_N);
      for (int k = 0; k < _N; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
        ph[k] = atan2(im[k], re[k]);
      }

      final oR = Float64List(_N), oI = Float64List(_N);
      for (int k = 0; k < _N; k++) {
        final n = noise[k] * floorMult;
        final n2 = n * n + 1e-14;
        final snrPost = mag[k] * mag[k] / n2 - 1;
        final snrPrio = alp * (prev[k] * prev[k]) / n2 +
            (1 - alp) * (snrPost > 0 ? snrPost : 0);
        final H = snrPrio / (1 + snrPrio);
        final gain = max(0.001, 1 - str * (1 - H));
        final nm = mag[k] * gain;
        prev[k] = nm;
        oR[k] = nm * cos(ph[k]);
        oI[k] = nm * sin(ph[k]);
      }

      FFTService.ifft(oR, oI);
      for (int k = 0; k < _N; k++) {
        final idx = off + k;
        if (idx < out.length) {
          out[idx] += oR[k] * win[k];
          nrm[idx] += win[k] * win[k];
        }
      }
    }

    final res = Float32List(signal.length);
    for (int i = 0; i < signal.length; i++) {
      res[i] = nrm[i] > 0.001 ? (out[i] / nrm[i]).toDouble() : 0.0;
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 3 — Hard Spectral Gate
  // Zeros any bin still below gateRatio × noise floor.
  // Eliminates musical noise and residual noise floor.
  // ─────────────────────────────────────────────────────────
  static Float32List _hardSpectralGate(
    Float32List signal, Float32List noise, double gateRatio,
  ) {
    if (gateRatio <= 0) return signal;
    final win = FFTService.hannWindow(_N);
    final numF = (signal.length - _N) ~/ _HOP + 1;
    final out = Float64List(signal.length + _N);
    final nrm = Float64List(signal.length + _N);

    for (int fi = 0; fi < numF; fi++) {
      final re = Float64List(_N), im = Float64List(_N);
      final off = fi * _HOP;
      for (int k = 0; k < _N; k++) {
        re[k] = (off + k < signal.length ? signal[off + k] : 0.0) * win[k];
      }
      FFTService.fft(re, im);
      for (int k = 0; k < _N; k++) {
        final mag = sqrt(re[k] * re[k] + im[k] * im[k]);
        if (mag < noise[k] * gateRatio) { re[k] = 0; im[k] = 0; }
      }
      FFTService.ifft(re, im);
      for (int k = 0; k < _N; k++) {
        final idx = off + k;
        if (idx < out.length) {
          out[idx] += re[k] * win[k];
          nrm[idx] += win[k] * win[k];
        }
      }
    }

    final res = Float32List(signal.length);
    for (int i = 0; i < signal.length; i++) {
      res[i] = nrm[i] > 0.001 ? (out[i] / nrm[i]).toDouble() : 0.0;
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 4 — VAD Silence Gate
  // 20ms frames, detects speech, silences non-speech segments.
  // ─────────────────────────────────────────────────────────
  static Float32List _vadGate(
    Float32List signal, int rate, double sensitivity, int holdMs,
  ) {
    final fSamp = (0.02 * rate).floor(); // 20ms frames
    final numF = signal.length ~/ fSamp;
    final energies = Float64List(numF);

    for (int fi = 0; fi < numF; fi++) {
      double e = 0;
      for (int k = 0; k < fSamp; k++) {
        final v = signal[fi * fSamp + k];
        e += v * v;
      }
      energies[fi] = sqrt(e / fSamp);
    }

    // Noise floor = median of lowest 40% frames
    final sorted = Float64List.fromList(energies)..sort();
    final noiseFloor = sorted[(numF * 0.40).floor()] + 1e-9;
    final thresh = noiseFloor * sensitivity;

    // VAD with hold
    final holdF = (holdMs / 20).ceil();
    final vadOn = List<bool>.filled(numF, false);
    int hold = 0;
    for (int fi = 0; fi < numF; fi++) {
      if (energies[fi] > thresh) { vadOn[fi] = true; hold = holdF; }
      else if (hold > 0) { vadOn[fi] = true; hold--; }
    }

    // Smooth gain (attack 3 frames, release 8 frames)
    final gains = Float64List(numF);
    double g = 0;
    const attF = 3.0, relF = 8.0;
    for (int fi = 0; fi < numF; fi++) {
      final t = vadOn[fi] ? 1.0 : 0.0;
      final spd = t > g ? 1 / attF : 1 / relF;
      g = min(1, max(0.0001, g + (t - g) * spd));
      gains[fi] = g;
    }

    final res = Float32List.fromList(signal);
    for (int fi = 0; fi < numF; fi++) {
      final s = fi * fSamp;
      final e = min(signal.length, s + fSamp);
      for (int i = s; i < e; i++) res[i] = (res[i] * gains[fi]).toDouble();
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 5 — Phase Vocoder Pitch Shift
  // Shifts pitch by semitones while preserving voice character.
  // ─────────────────────────────────────────────────────────
  static Float32List _pitchShift(Float32List signal, double semitones) {
    final ratio = pow(2, semitones / 12).toDouble();
    const hopA = _HOP;
    final hopS = max(1, (hopA * ratio).round());
    final win = FFTService.hannWindow(_N);
    final numF = (signal.length - _N) ~/ hopA;
    final outLen = numF * hopS + _N;
    final out = Float64List(outLen);
    final nrm = Float64List(outLen);
    final prevPhA = Float64List(_N ~/ 2 + 1);
    final sumPhS = Float64List(_N ~/ 2 + 1);

    for (int fi = 0; fi < numF; fi++) {
      final re = Float64List(_N), im = Float64List(_N);
      final off = fi * hopA;
      for (int k = 0; k < _N; k++) {
        re[k] = (off + k < signal.length ? signal[off + k] : 0.0) * win[k];
      }
      FFTService.fft(re, im);

      final mag = Float64List(_N ~/ 2 + 1), ph = Float64List(_N ~/ 2 + 1);
      for (int k = 0; k <= _N ~/ 2; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
        ph[k] = atan2(im[k], re[k]);
      }

      final sRe = Float64List(_N), sIm = Float64List(_N);
      for (int k = 0; k <= _N ~/ 2; k++) {
        final dp = ph[k] - prevPhA[k] - 2 * pi * k * hopA / _N;
        prevPhA[k] = ph[k];
        final trueFreq = 2 * pi * k / _N + FFTService.princArg(dp) / hopA;
        sumPhS[k] += trueFreq * hopS;
        sRe[k] = mag[k] * cos(sumPhS[k]);
        sIm[k] = mag[k] * sin(sumPhS[k]);
        if (k > 0 && k < _N ~/ 2) {
          sRe[_N - k] = sRe[k];
          sIm[_N - k] = -sIm[k];
        }
      }

      FFTService.ifft(sRe, sIm);
      final sOff = fi * hopS;
      for (int k = 0; k < _N; k++) {
        final idx = sOff + k;
        if (idx < outLen) {
          out[idx] += sRe[k] * win[k];
          nrm[idx] += win[k] * win[k];
        }
      }
    }

    final normalized = Float64List(outLen);
    for (int i = 0; i < outLen; i++) {
      normalized[i] = nrm[i] > 0.001 ? out[i] / nrm[i] : 0.0;
    }
    return _resample(normalized, signal.length);
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 6 — Formant Shift (Cepstral Envelope)
  // Reshapes vocal tract resonances independently of pitch.
  // ─────────────────────────────────────────────────────────
  static Float32List _formantShift(Float32List signal, double factor) {
    const hop = _N ~/ 4;
    final win = FFTService.hannWindow(_N);
    const lifter = 40; // ~40 quefrency bins = vocal tract
    final numF = (signal.length - _N) ~/ hop + 1;
    final out = Float64List(signal.length + _N);
    final nrm = Float64List(signal.length + _N);

    for (int fi = 0; fi < numF; fi++) {
      final re = Float64List(_N), im = Float64List(_N);
      final off = fi * hop;
      for (int k = 0; k < _N; k++) {
        re[k] = (off + k < signal.length ? signal[off + k] : 0.0) * win[k];
      }
      FFTService.fft(re, im);

      final mag = Float64List(_N), ph = Float64List(_N);
      for (int k = 0; k < _N; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
        ph[k] = atan2(im[k], re[k]);
      }

      // Log spectrum → cepstrum
      final logMag = Float64List(_N);
      for (int k = 0; k < _N; k++) logMag[k] = log(mag[k] + 1e-8);
      final cR = Float64List.fromList(logMag), cI = Float64List(_N);
      FFTService.ifft(cR, cI);

      // Low-quefrency lifter (vocal tract only)
      final liftR = Float64List(_N);
      for (int k = 0; k < lifter; k++) liftR[k] = cR[k];
      for (int k = _N - lifter; k < _N; k++) liftR[k] = cR[k];

      final envR = Float64List.fromList(liftR), envI = Float64List(_N);
      FFTService.fft(envR, envI);
      final env = Float64List(_N);
      for (int k = 0; k < _N; k++) env[k] = exp(envR[k]);

      // Shift spectral envelope
      final shiftEnv = Float64List(_N);
      for (int k = 0; k < _N ~/ 2; k++) {
        final src = k / factor;
        final i0 = src.floor();
        final i1 = min(_N ~/ 2 - 1, i0 + 1);
        shiftEnv[k] = FFTService.lerp(env[i0], env[i1], src - i0);
      }
      for (int k = _N ~/ 2; k < _N; k++) shiftEnv[k] = shiftEnv[_N - k];

      final oRe = Float64List(_N), oIm = Float64List(_N);
      for (int k = 0; k < _N; k++) {
        final nm = (mag[k] / (env[k] + 1e-10)) * shiftEnv[k];
        oRe[k] = nm * cos(ph[k]);
        oIm[k] = nm * sin(ph[k]);
      }
      FFTService.ifft(oRe, oIm);
      for (int k = 0; k < _N; k++) {
        final idx = off + k;
        if (idx < out.length) {
          out[idx] += oRe[k] * win[k];
          nrm[idx] += win[k] * win[k];
        }
      }
    }

    final res = Float32List(signal.length);
    for (int i = 0; i < signal.length; i++) {
      res[i] = nrm[i] > 0.001 ? (out[i] / nrm[i]).toDouble() : 0.0;
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 7 — Harmonic Exciter
  // Soft-clipping + band-pass → adds richness & presence.
  // ─────────────────────────────────────────────────────────
  static Float32List _harmonicExciter(Float32List signal, double amount) {
    final mix = amount / 100;
    // Soft-clip (tanh) generates rich harmonics
    // Simple 2nd-order band-pass approximation in time domain
    final res = Float32List(signal.length);
    double prev1 = 0, prev2 = 0;
    for (int i = 0; i < signal.length; i++) {
      // Generate harmonics via tanh saturation
      final sat = tanh(signal[i] * 4) * 0.2;
      // Simple high-pass (1-pole) to keep only 2kHz+ harmonics
      final hp = sat - prev1 * 0.85;
      prev1 = sat;
      // Mix back
      res[i] = signal[i] + hp * mix;
      prev2 = prev1;
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 8 — Spectral Smoothing
  // Moving average on magnitude spectrum → reduces roughness.
  // ─────────────────────────────────────────────────────────
  static Float32List _spectralSmooth(Float32List signal, double strength) {
    if (strength <= 0) return signal;
    final win = FFTService.hannWindow(_N);
    const hop = _N ~/ 4;
    final smW = (1 + strength / 100 * 6).round();
    final numF = (signal.length - _N) ~/ hop + 1;
    final out = Float64List(signal.length + _N);
    final nrm = Float64List(signal.length + _N);

    for (int fi = 0; fi < numF; fi++) {
      final re = Float64List(_N), im = Float64List(_N);
      final off = fi * hop;
      for (int k = 0; k < _N; k++) {
        re[k] = (off + k < signal.length ? signal[off + k] : 0.0) * win[k];
      }
      FFTService.fft(re, im);

      final mag = Float64List(_N), ph = Float64List(_N);
      for (int k = 0; k < _N; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
        ph[k] = atan2(im[k], re[k]);
      }

      final sMag = Float64List(_N);
      for (int k = 0; k < _N; k++) {
        double sum = 0;
        for (int d = -smW; d <= smW; d++) {
          sum += mag[(k + d + _N) % _N];
        }
        sMag[k] = sum / (2 * smW + 1);
      }

      final mix = strength / 100;
      final oRe = Float64List(_N), oIm = Float64List(_N);
      for (int k = 0; k < _N; k++) {
        final m = mag[k] * (1 - mix) + sMag[k] * mix;
        oRe[k] = m * cos(ph[k]);
        oIm[k] = m * sin(ph[k]);
      }
      FFTService.ifft(oRe, oIm);
      for (int k = 0; k < _N; k++) {
        final idx = off + k;
        if (idx < out.length) {
          out[idx] += oRe[k] * win[k];
          nrm[idx] += win[k] * win[k];
        }
      }
    }

    final res = Float32List(signal.length);
    for (int i = 0; i < signal.length; i++) {
      res[i] = nrm[i] > 0.001 ? (out[i] / nrm[i]).toDouble() : 0.0;
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 9 — Simple EQ (1-pole biquad approximation)
  // ─────────────────────────────────────────────────────────
  static Float32List _applyEQ(
    Float32List signal, int rate,
    double hpFreq, double bassGain, double deHarshGain,
    double presGain, double airGain,
  ) {
    var s = signal;
    s = _biquadHP(s, rate, hpFreq);
    if (bassGain.abs() > 0.1) s = _biquadLowShelf(s, rate, 200, bassGain);
    if (deHarshGain.abs() > 0.1) s = _biquadPeak(s, rate, 2000, 1.5, deHarshGain);
    if (presGain.abs() > 0.1)  s = _biquadPeak(s, rate, 4000, 1.0, presGain);
    if (airGain.abs() > 0.1)   s = _biquadHighShelf(s, rate, 12000, airGain);
    return s;
  }

  // Biquad high-pass filter
  static Float32List _biquadHP(Float32List signal, int rate, double freq) {
    final w0 = 2 * pi * freq / rate;
    final alpha = sin(w0) / (2 * 0.7071);
    final b0 = (1 + cos(w0)) / 2, b1 = -(1 + cos(w0)), b2 = (1 + cos(w0)) / 2;
    final a0 = 1 + alpha, a1 = -2 * cos(w0), a2 = 1 - alpha;
    return _biquad(signal, b0/a0, b1/a0, b2/a0, a1/a0, a2/a0);
  }

  static Float32List _biquadLowShelf(Float32List s, int rate, double freq, double gainDb) {
    final A = pow(10, gainDb / 40).toDouble();
    final w0 = 2 * pi * freq / rate;
    final alpha = sin(w0) / 2 * sqrt((A + 1/A) * (1/0.9 - 1) + 2);
    final b0 = A*((A+1)-(A-1)*cos(w0)+2*sqrt(A)*alpha);
    final b1 = 2*A*((A-1)-(A+1)*cos(w0));
    final b2 = A*((A+1)-(A-1)*cos(w0)-2*sqrt(A)*alpha);
    final a0 = (A+1)+(A-1)*cos(w0)+2*sqrt(A)*alpha;
    final a1 = -2*((A-1)+(A+1)*cos(w0));
    final a2 = (A+1)+(A-1)*cos(w0)-2*sqrt(A)*alpha;
    return _biquad(s, b0/a0, b1/a0, b2/a0, a1/a0, a2/a0);
  }

  static Float32List _biquadHighShelf(Float32List s, int rate, double freq, double gainDb) {
    final A = pow(10, gainDb / 40).toDouble();
    final w0 = 2 * pi * freq / rate;
    final alpha = sin(w0) / 2 * sqrt((A + 1/A) * (1/0.9 - 1) + 2);
    final b0 = A*((A+1)+(A-1)*cos(w0)+2*sqrt(A)*alpha);
    final b1 = -2*A*((A-1)+(A+1)*cos(w0));
    final b2 = A*((A+1)+(A-1)*cos(w0)-2*sqrt(A)*alpha);
    final a0 = (A+1)-(A-1)*cos(w0)+2*sqrt(A)*alpha;
    final a1 = 2*((A-1)-(A+1)*cos(w0));
    final a2 = (A+1)-(A-1)*cos(w0)-2*sqrt(A)*alpha;
    return _biquad(s, b0/a0, b1/a0, b2/a0, a1/a0, a2/a0);
  }

  static Float32List _biquadPeak(Float32List s, int rate, double freq, double Q, double gainDb) {
    final A = pow(10, gainDb / 40).toDouble();
    final w0 = 2 * pi * freq / rate;
    final alpha = sin(w0) / (2 * Q);
    final b0 = 1 + alpha * A, b1 = -2 * cos(w0), b2 = 1 - alpha * A;
    final a0 = 1 + alpha / A, a1 = -2 * cos(w0), a2 = 1 - alpha / A;
    return _biquad(s, b0/a0, b1/a0, b2/a0, a1/a0, a2/a0);
  }

  static Float32List _biquad(Float32List s, double b0, double b1, double b2, double a1, double a2) {
    final out = Float32List(s.length);
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (int i = 0; i < s.length; i++) {
      final x0 = s[i].toDouble();
      final y0 = b0*x0 + b1*x1 + b2*x2 - a1*y1 - a2*y2;
      out[i] = y0.clamp(-1.0, 1.0).toDouble();
      x2 = x1; x1 = x0; y2 = y1; y1 = y0;
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 10 — Soft Compressor (look-ahead RMS)
  // ─────────────────────────────────────────────────────────
  static Float32List _softCompress(Float32List signal, double threshDb, double ratio) {
    final thresh = pow(10, threshDb / 20).toDouble();
    final res = Float32List(signal.length);
    double envRms = 0;
    const attack = 0.003, release = 0.25, frameRate = 44100.0;
    final attCoef = exp(-2.2 / (attack * frameRate));
    final relCoef = exp(-2.2 / (release * frameRate));

    for (int i = 0; i < signal.length; i++) {
      final rms = signal[i].abs().toDouble();
      envRms = rms > envRms ? attCoef*envRms + (1-attCoef)*rms
                            : relCoef*envRms + (1-relCoef)*rms;
      double gain = 1.0;
      if (envRms > thresh) {
        final over = envRms / thresh;
        gain = (1 + (ratio - 1) * log(over) / log(ratio)) / over;
      }
      res[i] = (signal[i] * gain).clamp(-0.99, 0.99).toDouble();
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 11 — De-esser
  // ─────────────────────────────────────────────────────────
  static Float32List _deEss(Float32List signal, int rate, double freq, double amount) {
    const n = 1024, hop = 256;
    final win = FFTService.hannWindow(n);
    final binHz = rate / n;
    final b0 = (freq / binHz).floor();
    final b1 = min(n ~/ 2, (freq * 1.5 / binHz).floor());
    final red = amount / 100;
    final numF = (signal.length - n) ~/ hop + 1;
    final out = Float64List(signal.length + n);
    final nrm = Float64List(signal.length + n);

    for (int fi = 0; fi < numF; fi++) {
      final re = Float64List(n), im = Float64List(n);
      final off = fi * hop;
      for (int k = 0; k < n; k++) {
        re[k] = (off + k < signal.length ? signal[off + k] : 0.0) * win[k];
      }
      FFTService.fft(re, im);
      double ess = 0, tot = 0;
      for (int k = b0; k < b1; k++) ess += re[k]*re[k] + im[k]*im[k];
      for (int k = 1; k < n ~/ 2; k++) tot += re[k]*re[k] + im[k]*im[k];
      final r = ess / (tot + 1e-10);
      if (r > 0.12) {
        final g = 1 - red * min(1.0, (r - 0.12) / 0.18);
        for (int k = b0; k < b1; k++) {
          re[k] *= g; im[k] *= g;
          if (k > 0) { re[n - k] *= g; im[n - k] *= g; }
        }
      }
      FFTService.ifft(re, im);
      for (int k = 0; k < n; k++) {
        final idx = off + k;
        if (idx < out.length) {
          out[idx] += re[k] * win[k];
          nrm[idx] += win[k] * win[k];
        }
      }
    }
    final res = Float32List(signal.length);
    for (int i = 0; i < signal.length; i++) {
      res[i] = nrm[i] > 0.001 ? (out[i] / nrm[i]).toDouble() : 0.0;
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Algorithm 12 — LUFS Normalize (RMS-based)
  // ─────────────────────────────────────────────────────────
  static Float32List _normalizeLufs(Float32List signal, double targetLufs) {
    double rms = 0;
    for (int i = 0; i < signal.length; i++) rms += signal[i] * signal[i];
    rms = sqrt(rms / signal.length);
    final curLufs = 20 * log(rms + 1e-12) / ln10;
    final gain = pow(10, (targetLufs - curLufs) / 20).toDouble();
    final res = Float32List(signal.length);
    for (int i = 0; i < signal.length; i++) {
      res[i] = (signal[i] * gain).clamp(-0.98, 0.98).toDouble();
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────
  // Utility — linear resampler
  // ─────────────────────────────────────────────────────────
  static Float32List _resample(Float64List signal, int targetLen) {
    final res = Float32List(targetLen);
    final ratio = (signal.length - 1) / (targetLen - 1);
    for (int i = 0; i < targetLen; i++) {
      final p = i * ratio;
      final i0 = p.floor();
      final i1 = min(signal.length - 1, i0 + 1);
      res[i] = FFTService.lerp(signal[i0], signal[i1], p - i0).toDouble();
    }
    return res;
  }

  static double tanh(double x) {
    if (x > 20) return 1.0;
    if (x < -20) return -1.0;
    final e = exp(2 * x);
    return (e - 1) / (e + 1);
  }
}

// Transfer object for compute()
class _IsolateArgs {
  final Float32List signal;
  final int sampleRate;
  final AudioParams params;
  const _IsolateArgs({required this.signal, required this.sampleRate, required this.params});
}
