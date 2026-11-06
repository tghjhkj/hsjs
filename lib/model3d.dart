part of 'avatar.dart';

// The 3D view: the same body measurements as a turnable model, wearing the same
// fitted clothes. The clothes are drawn flat exactly as in 2D (without outlines),
// then wrapped around the body from the front; the back shows the same picture.
// Everything is drawn with Flutter's own canvas (no 3D package), so it works on
// Android and on the web, offline.

const _texScale = 3.0; // clothes picture: 240 x 480 model units at 3x
const _whiteUv = 4.5; // a white spot in the picture's top-left corner, for parts without clothes

/// A ring of a tube: centre (x, y, z) and its half-width (rx) and half-depth (rz).
class _Ring {
  final double x, y, rx, rz, z;
  const _Ring(this.x, this.y, this.rx, this.rz, [this.z = 0]);
}

/// All the triangles of the model, in model units (x right, y down, z toward you).
class _Mesh {
  final pos = <double>[]; // x, y, z per vertex
  final nrm = <double>[]; // outward normal per vertex
  final uv = <double>[]; // texture position (pixels) per vertex
  final col = <double>[]; // base colour (r, g, b, 0..1) per vertex
  final tri = <int>[]; // three vertex numbers per triangle
  final triCull = <bool>[]; // hide when facing away (closed shapes only)
  final triBias = <double>[]; // drawn as if this much nearer (clothes over skin)
  final triNrm = <double>[]; // outward normal per triangle

  int get count => pos.length ~/ 3;

  /// Adds a tube through [rings]. a = 0 is the front. [a0]..[a1] (in turns) makes
  /// a partial ring. [textured] parts take the clothes picture; [wrap] spreads the
  /// picture evenly around (skirts) instead of projecting it from the front.
  void tube(
    List<_Ring> rings, {
    int seg = 24,
    double a0 = 0,
    double a1 = 1,
    bool cap = false,
    Color color = Colors.white,
    Color Function(double x, double y)? colorAt,
    bool textured = false,
    double head = 1,
    bool cull = true,
    double bias = 0,
    double wrap = 0,
  }) {
    final start = count;
    final full = a1 - a0 >= 1;
    final n = full ? seg : seg + 1;
    void vertex(double x, double y, double z, double ux) {
      final hx = 120 + (x - 120) * head, hy = 50 + (y - 50) * head;
      pos.addAll([hx, hy, z * head]);
      nrm.addAll([0, 0, 0]);
      if (textured) {
        uv.addAll([ux * _texScale, hy * _texScale]);
      } else {
        uv.addAll([_whiteUv, _whiteUv]);
      }
      final c = colorAt?.call(x, y) ?? color;
      col.addAll([c.r, c.g, c.b]);
    }

    for (final r in rings) {
      for (var k = 0; k < n; k++) {
        final a = (a0 + (a1 - a0) * k / seg) * pi * 2;
        final x = r.x + r.rx * sin(a), z = r.z + r.rz * cos(a);
        final ux = wrap > 0 ? r.x + r.rx * wrap * (asin(sin(a)) / (pi / 2)) : 120 + (x - 120) * head;
        vertex(x, r.y, z, ux);
      }
    }
    final triStart = tri.length ~/ 3;
    for (var i = 0; i < rings.length - 1; i++) {
      for (var k = 0; k < (full ? n : n - 1); k++) {
        final a = start + i * n + k, b = start + i * n + (k + 1) % n, c = a + n, d = b + n;
        tri.addAll([a, c, b, b, c, d]);
      }
    }
    if (cap && full) {
      for (final ri in [0, rings.length - 1]) {
        final r = rings[ri];
        final centre = count;
        vertex(r.x, r.y, r.z, r.x);
        for (var k = 0; k < n; k++) {
          tri.addAll([centre, start + ri * n + k, start + ri * n + (k + 1) % n]);
        }
      }
    }
    final triEnd = tri.length ~/ 3;

    // Normals: add up the faces around each vertex, then make sure they point outward
    // (away from the tube's middle at that height).
    for (var t = triStart; t < triEnd; t++) {
      final i0 = tri[t * 3], i1 = tri[t * 3 + 1], i2 = tri[t * 3 + 2];
      final ax = pos[i1 * 3] - pos[i0 * 3], ay = pos[i1 * 3 + 1] - pos[i0 * 3 + 1], az = pos[i1 * 3 + 2] - pos[i0 * 3 + 2];
      final bx = pos[i2 * 3] - pos[i0 * 3], by = pos[i2 * 3 + 1] - pos[i0 * 3 + 1], bz = pos[i2 * 3 + 2] - pos[i0 * 3 + 2];
      final nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
      for (final i in [i0, i1, i2]) {
        nrm[i * 3] += nx;
        nrm[i * 3 + 1] += ny;
        nrm[i * 3 + 2] += nz;
      }
    }
    // The middle of the tube at each height, to tell outward from inward.
    double midX(double y) => rings.reduce((a, b) => (a.y - y).abs() < (b.y - y).abs() ? a : b).x * head + 120 * (1 - head);
    double midZ(double y) => rings.reduce((a, b) => (a.y - y).abs() < (b.y - y).abs() ? a : b).z * head;
    for (var i = start; i < count; i++) {
      var nx = nrm[i * 3], ny = nrm[i * 3 + 1], nz = nrm[i * 3 + 2];
      final len = sqrt(nx * nx + ny * ny + nz * nz);
      if (len < 1e-9) {
        nx = 0;
        ny = 0;
        nz = 1;
      } else {
        nx /= len;
        ny /= len;
        nz /= len;
      }
      final py = (pos[i * 3 + 1] - 50) / head + 50;
      final ox = pos[i * 3] - midX(py), oz = pos[i * 3 + 2] - midZ(py);
      if (nx * ox + nz * oz < 0 && (ox.abs() + oz.abs()) > 0.01) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
      }
      nrm[i * 3] = nx;
      nrm[i * 3 + 1] = ny;
      nrm[i * 3 + 2] = nz;
    }
    for (var t = triStart; t < triEnd; t++) {
      var nx = 0.0, ny = 0.0, nz = 0.0;
      for (var j = 0; j < 3; j++) {
        final i = tri[t * 3 + j];
        nx += nrm[i * 3];
        ny += nrm[i * 3 + 1];
        nz += nrm[i * 3 + 2];
      }
      triNrm.addAll([nx / 3, ny / 3, nz / 3]);
      triCull.add(cull);
      triBias.add(bias);
    }
  }

  /// A surface through a grid of points ([x, y, z, shade] rows), shown from both
  /// sides; [centre] gives the middle at a height, to point the normals outward.
  void grid(List<List<List<double>>> rows, Color base, {double head = 1, required List<double> Function(double y) centre}) {
    final start = count;
    final cols = rows.first.length;
    for (final row in rows) {
      for (final p in row) {
        final hx = 120 + (p[0] - 120) * head, hy = 50 + (p[1] - 50) * head;
        pos.addAll([hx, hy, p[2] * head]);
        nrm.addAll([0, 0, 0]);
        uv.addAll([_whiteUv, _whiteUv]);
        col.addAll([base.r * p[3], base.g * p[3], base.b * p[3]]);
      }
    }
    final triStart = tri.length ~/ 3;
    for (var j = 0; j < rows.length - 1; j++) {
      for (var k = 0; k < cols - 1; k++) {
        final a = start + j * cols + k, b = a + 1, c = a + cols, d = c + 1;
        tri.addAll([a, c, b, b, c, d]);
      }
    }
    final triEnd = tri.length ~/ 3;
    for (var t = triStart; t < triEnd; t++) {
      final i0 = tri[t * 3], i1 = tri[t * 3 + 1], i2 = tri[t * 3 + 2];
      final ax = pos[i1 * 3] - pos[i0 * 3], ay = pos[i1 * 3 + 1] - pos[i0 * 3 + 1], az = pos[i1 * 3 + 2] - pos[i0 * 3 + 2];
      final bx = pos[i2 * 3] - pos[i0 * 3], by = pos[i2 * 3 + 1] - pos[i0 * 3 + 1], bz = pos[i2 * 3 + 2] - pos[i0 * 3 + 2];
      final nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
      for (final i in [i0, i1, i2]) {
        nrm[i * 3] += nx;
        nrm[i * 3 + 1] += ny;
        nrm[i * 3 + 2] += nz;
      }
    }
    for (var i = start; i < count; i++) {
      var nx = nrm[i * 3], ny = nrm[i * 3 + 1], nz = nrm[i * 3 + 2];
      final len = sqrt(nx * nx + ny * ny + nz * nz);
      if (len < 1e-9) {
        nx = 0;
        ny = -1;
        nz = 0;
      } else {
        nx /= len;
        ny /= len;
        nz /= len;
      }
      final y = (pos[i * 3 + 1] - 50) / head + 50;
      final c = centre(y);
      final ox = pos[i * 3] - (120 + (c[0] - 120) * head), oy = pos[i * 3 + 1] - (50 + (c[1] - 50) * head), oz = pos[i * 3 + 2] - c[2] * head;
      if (nx * ox + ny * oy + nz * oz < 0) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
      }
      nrm[i * 3] = nx;
      nrm[i * 3 + 1] = ny;
      nrm[i * 3 + 2] = nz;
    }
    for (var t = triStart; t < triEnd; t++) {
      var nx = 0.0, ny = 0.0, nz = 0.0;
      for (var j = 0; j < 3; j++) {
        final i = tri[t * 3 + j];
        nx += nrm[i * 3];
        ny += nrm[i * 3 + 1];
        nz += nrm[i * 3 + 2];
      }
      triNrm.addAll([nx / 3, ny / 3, nz / 3]);
      triCull.add(false);
      // Drawn just in front of the head it sits on, so the two never flicker through each other.
      triBias.add(2.5);
    }
  }

  /// A flat picture card facing forward (seen from both sides), for a bag.
  void card(Rect r, double z, {double bias = 0}) {
    final start = count;
    for (final (x, y) in [(r.left, r.top), (r.right, r.top), (r.left, r.bottom), (r.right, r.bottom)]) {
      pos.addAll([x, y, z]);
      nrm.addAll([0, 0, 1]);
      uv.addAll([x * _texScale, y * _texScale]);
      col.addAll([1, 1, 1]);
    }
    tri.addAll([start, start + 2, start + 1, start + 1, start + 2, start + 3]);
    for (var t = 0; t < 2; t++) {
      triNrm.addAll([0, 0, 1]);
      triCull.add(false);
      triBias.add(bias);
    }
  }

  /// An ellipsoid (or a band of one, from latitude [t0] to [t1], 0 = top).
  void blob(double cx, double cy, double cz, double rx, double ry, double rz,
      {double t0 = 0,
      double t1 = 1,
      int steps = 14,
      int seg = 20,
      Color color = Colors.white,
      bool textured = false,
      double head = 1,
      bool cull = true,
      double bias = 0,
      double a0 = 0,
      double a1 = 1}) {
    final rings = <_Ring>[
      for (var i = 0; i <= steps; i++)
        () {
          final t = (t0 + (t1 - t0) * i / steps) * pi;
          return _Ring(cx, cy - ry * cos(t), max(0.01, rx * sin(t)), max(0.01, rz * sin(t)), cz);
        }()
    ];
    tube(rings, seg: seg, color: color, textured: textured, head: head, cull: cull, bias: bias, a0: a0, a1: a1);
  }
}

/// Where the hair meets the skin at angle [a] around the head (turns; 0 = front,
/// + = to the right), as a height in model units.
double _hairline(String style, double a) {
  final t = a.abs();
  if (style == 'bun') return _interp([[0, 30], [0.18, 40], [0.25, 44], [0.33, 56], [0.5, 66]], t);
  if (style == 'buzz') return _interp([[0, 31], [0.2, 42], [0.25, 44], [0.35, 56], [0.5, 64]], t);
  // Short and long: a little fringe swept to one side, over the ears, down to the nape.
  return _interp([[0, 32], [0.12, 38], [0.18, 43], [0.25, 47], [0.33, 58], [0.5, 70]], t) +
      7 * exp(-pow((a + 0.035) / 0.06, 2));
}

/// Strands: a gentle light-and-dark ripple across the hair.
double _strand(double a, double f) => 0.84 + 0.1 * sin(a * pi * 2 * 17 + f * 2.2) + 0.06 * sin(a * pi * 2 * 41);

/// Grids of points [x, y, z, shade] for a hair style, each with the middle used to
/// tell outward from inward at a given height.
List<({List<List<List<double>>> rows, List<double> Function(double y) centre})> _hairGrids(String style) {
  const cx = 120.0, cy = 51.0, cz = -0.8;
  final grow = style == 'buzz' ? 1.1 : 2.4;
  final rx = 25 + grow, ry = 30.5 + grow, rz = 27 + grow, top = cy - ry;
  double signed(double a) => a > 0.5 ? a - 1 : a;
  const n = 48, mRows = 14;
  final cap = <List<List<double>>>[
    for (var j = 0; j <= mRows; j++)
      [
        for (var k = 0; k <= n; k++)
          () {
            final f = j / mRows, a = k / n;
            final y = top + (_hairline(style, signed(a)) - top) * f;
            final dy = ((y - cy) / ry).clamp(-1.0, 1.0), r = sqrt(1 - dy * dy);
            final puff = style == 'buzz' ? 0.0 : 2.2 * (1 - f) * f * 2; // fuller over the crown
            // A buzz cut is too short for strands: just a faint even texture.
            final shade = style == 'buzz' ? 0.95 : _strand(a, f);
            return [cx + (rx + puff) * r * sin(a * pi * 2), y, cz + (rz + puff) * r * cos(a * pi * 2), shade];
          }()
      ]
  ];
  final grids = [(rows: cap, centre: (double y) => [cx, cy, cz])];
  if (style == 'long') {
    // Falls from under the cap down the back and sides, with locks framing the face.
    const a0 = 0.16, a1 = 0.84, nl = 34, ml = 20; // locks stay beside the face, not over it
    final r64 = sqrt(1 - pow((64 - cy) / ry, 2));
    final panel = <List<List<double>>>[
      for (var j = 0; j <= ml; j++)
        [
          for (var k = 0; k <= nl; k++)
            () {
              final f = j / ml, a = a0 + (a1 - a0) * k / nl;
              final yStart = _hairline('long', signed(a)) - 4, yEnd = 152 + 7 * sin(a * pi * 2 * 5);
              final y = yStart + (yEnd - yStart) * f;
              double rxY, rzY, czY;
              if (y <= 64) {
                final dy = ((y - cy) / ry).clamp(-1.0, 1.0), r = sqrt(1 - dy * dy);
                rxY = (rx + 0.6) * r;
                rzY = (rz + 0.6) * r;
                czY = cz;
              } else {
                rxY = _interp([[64, (rx + 0.6) * r64], [92, 24], [128, 29], [158, 27]], y);
                rzY = _interp([[64, (rz + 0.6) * r64], [92, 19], [128, 21], [158, 19]], y);
                czY = _interp([[64, cz], [100, -4], [158, -7]], y);
              }
              return [cx + rxY * sin(a * pi * 2), y, czY + rzY * cos(a * pi * 2), _strand(a, f) * (0.92 + 0.08 * (1 - f))];
            }()
        ]
    ];
    grids.add((rows: panel, centre: (double y) => [cx, y, y <= 64 ? cz : _interp([[64, cz], [100, -4], [158, -7]], y)]));
  }
  return grids;
}

/// Builds the model: body, face and hair, then the clothes as shells just outside
/// the body. [skirt] (optional) are rings for a skirt or dress hanging free.
_Mesh _buildModel(AvatarSettings s, List<_Ring>? skirt, [Rect? bag]) {
  final m = _Mesh();
  final g = _Geo(s.m, s.arms);
  final sh = g.sh, hi = g.hi, th = g.th, k = g.k;
  final skin = s.skinTone;
  const base = Color(0xFFC4BBD0);
  final hair = s.hairTone;
  final h = s.head;

  // Torso: shoulder slope, then the same widths as the 2D body.
  double torsoHalf(double y) => y < 107
      ? _interp([[90, 9], [93, 13], [96, sh / 2 - 7], [100, sh / 2 - 2.5], [107, sh / 2 + 1]], y)
      : (y <= 216 ? g.body(y) : _interp([[216, hi / 2], [226, hi / 2 - 2], [234, hi / 2 - 8]], y));
  double depth(double y) => _interp([[90, 0.9], [100, 0.5], [118, 0.56], [134, 0.66], [168, 0.62], [216, 0.68], [234, 0.62]], y);
  List<_Ring> torso({double grow = 0, double scale = 1, double from = 90, double to = 234}) => [
        for (var y = from; y <= to; y += 4)
          () {
            final rx = torsoHalf(y) * scale + grow;
            return _Ring(120, y, rx, rx * depth(y) + grow * 0.4);
          }()
      ];
  List<_Ring> leg(double side, {double grow = 0}) => [
        for (var y = 208.0; y <= 438; y += 6)
          () {
            final o = g.legOuter(side, y), i = g.legInner(side, y);
            final rx = (o - i).abs() / 2 + grow;
            return _Ring((o + i) / 2, y, rx, rx * 0.95);
          }()
      ];
  double armAt(double side, double y) {
    final xt = 120 + side * (sh / 2 + 3), xw = 120 + side * (sh / 2 + 15);
    return xt + (xw - xt) * (y - 100) / 126;
  }

  double armHalf(double y) =>
      k * _interp([[100, 10.2], [114, 10.8], [152, 8.4], [162, 8.1], [180, 8.6], [222, 5.4], [229, 5.4]], y);
  List<_Ring> arm(double side, {double grow = 0}) => [
        for (var y = 102.0; y <= 229; y += 5) _Ring(armAt(side, y), y, armHalf(y) + grow, armHalf(y) * 0.95 + grow)
      ];

  m.tube(torso(), cap: true, colorAt: (x, y) => y >= 136 ? base : skin);
  for (final side in [-1.0, 1.0]) {
    m.tube(leg(side), cap: true, colorAt: (x, y) => y < 224 ? base : skin);
    final ca = 120 + side * (2 + th / 2) - 2 * side, ha = th * 0.22;
    m.blob(ca, 452, 6, ha + 1.5, 9, 15, color: skin, steps: 10, seg: 16);
    m.tube(arm(side), cap: true, color: skin);
    // Shoulder: kept low enough that a top always covers it.
    m.blob(armAt(side, 106), 108, 0, 10.8 * k, 9.5, 10.3 * k, color: skin, steps: 10, seg: 16);
    m.blob(armAt(side, 238), 240, 0, 6 * k, 13, 4.5 * k, color: skin, steps: 10, seg: 14);
  }
  // Neck and head (head size scales the head, face and hair together).
  m.tube(const [_Ring(120, 66, 9, 9.5), _Ring(120, 100, 9.5, 10)], color: skin);
  m.blob(120, 51, 0, 25, 30.5, 27, color: skin, head: h, steps: 16, seg: 28);
  for (final side in [-1.0, 1.0]) {
    m.blob(120 + side * 24.5, 53, -1, 3.5, 6, 4, color: skin, head: h, steps: 6, seg: 10);
  }
  m.blob(120, 59, 25.8, 2.2, 4.2, 3, color: Color.lerp(skin, const Color(0xFF4A2A1C), 0.06)!, head: h, steps: 6, seg: 10, bias: 0.5);
  for (final side in [-1.0, 1.0]) {
    final x = 120 + side * 9.5;
    m.blob(x, 52, 23.6, 4.4, 2.8, 1.6, color: const Color(0xFFFBFAF8), head: h, steps: 6, seg: 12, bias: 0.6);
    m.blob(x, 52, 24.7, 2.1, 2.1, 0.9, color: s.eyeTone, head: h, steps: 6, seg: 10, bias: 0.8);
    m.blob(x + 0.2, 52, 25.3, 1.0, 1.0, 0.5, color: const Color(0xFF120C0A), head: h, steps: 4, seg: 8, bias: 1.0);
    m.blob(x - side * 0.3, 45.4, 25.6, 5.2, 0.9, 0.8, color: Color.lerp(hair, Colors.black, 0.1)!, head: h, steps: 4, seg: 10, bias: 0.6);
  }
  m.blob(120, 67.6, 24.2, 4.8, 1.6, 1.4, color: Color.lerp(skin, const Color(0xFFB04A50), 0.5)!, head: h, steps: 6, seg: 12, bias: 0.6);

  // Hair: a shell over the skull that follows a natural hairline (a side-swept
  // fringe, over the tops of the ears, down to the nape), with soft strand shading.
  if (s.hair != 4) {
    final style = const ['short', 'long', 'bun', 'buzz'][s.hair];
    final tint = style == 'buzz' ? Color.lerp(hair, skin, 0.35)! : hair;
    for (final g in _hairGrids(style)) {
      m.grid(g.rows, tint, head: h, centre: g.centre);
    }
    if (style == 'bun') {
      m.blob(120, 19, -11, 11.5, 10.5, 11.5, color: Color.lerp(hair, Colors.black, 0.05)!, head: h, steps: 10, seg: 18);
      m.tube(const [_Ring(120, 27, 7, 7, -8), _Ring(120, 30, 8.5, 8.5, -8)],
          color: Color.lerp(hair, Colors.black, 0.3)!, head: h, seg: 16);
    }
  }

  // Clothes: shells just outside the body, showing the flat fitted clothes.
  const clothBias = 2.5;
  m.tube(torso(grow: 1.6, scale: 1.05, from: 86, to: 236), textured: true, bias: clothBias);
  for (final side in [-1.0, 1.0]) {
    m.tube(leg(side, grow: 1.6), textured: true, bias: clothBias);
    m.tube(arm(side, grow: 1.7), textured: true, bias: clothBias);
    m.blob(armAt(side, 106), 107.5, 0, 10.8 * k + 1.9, 11, 10.3 * k + 1.9, t0: 0, t1: 0.55, textured: true, bias: clothBias, steps: 8, seg: 16);
    final ca = 120 + side * (2 + th / 2) - 2 * side, ha = th * 0.22;
    m.blob(ca, 451, 6, ha + 3.4, 11, 17, textured: true, bias: clothBias, steps: 10, seg: 16);
  }
  // Accessories: a shell over the head (hat, glasses), the neck (scarf), and a flat
  // card for a bag held at the hand.
  m.blob(120, 50, 0, 28.6, 34.2, 30.6, textured: true, head: h, bias: 4, steps: 14, seg: 28);
  m.tube(const [_Ring(120, 64, 11.5, 12), _Ring(120, 100, 12, 12.5)], textured: true, bias: clothBias);
  if (bag != null) m.card(bag, 4, bias: 4);
  if (skirt != null && skirt.length > 2) {
    m.tube(skirt, textured: true, wrap: 0.86, seg: 32, cull: false, bias: clothBias);
  }
  return m;
}

/// The clothes, drawn flat and fitted (no outlines), as the 3D model's picture.
ui.Image _clothesPicture(Map<String, FlatSpec?> specs, Map<String, _Photo?> photos, Map<String, ui.Image?> accessories) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(_texScale);
  c.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = Colors.white);
  _ClothesPainter(avatarSettings, specs, photos, edges: false, accessories: accessories).paint(c, const Size(240, 480));
  return rec.endRecording().toImageSync((240 * _texScale).round(), (480 * _texScale).round());
}

/// Rings for a skirt or dress that hangs free between the legs, measured from the
/// clothes picture (null when nothing covers the gap between the legs).
Future<List<_Ring>?> _skirtRings(ui.Image picture, double hips) async {
  final bd = await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bd == null) return null;
  final w = picture.width, hh = picture.height;
  bool solid(double x, double y) {
    final px = (x * _texScale).round(), py = (y * _texScale).round();
    return px >= 0 && py >= 0 && px < w && py < hh && bd.getUint8((py * w + px) * 4 + 3) > 100;
  }

  final rings = <_Ring>[];
  for (var y = 240.0; y <= 470; y += 4) {
    if (!solid(120, y)) {
      if (rings.isNotEmpty) break;
      continue;
    }
    var l = 120.0, r = 120.0;
    while (l > 2 && solid(l - 1, y)) {
      l--;
    }
    while (r < 238 && solid(r + 1, y)) {
      r++;
    }
    final rx = max(120 - l, r - 120) + 0.5;
    rings.add(_Ring(120, y, rx, rx * 0.72));
  }
  if (rings.length <= 5 || rings.last.y <= 268) return null;
  return [_Ring(120, 212, hips / 2 + 3, (hips / 2 + 3) * 0.72), ...rings];
}

class Model3DView extends StatefulWidget {
  const Model3DView({super.key});

  @override
  State<Model3DView> createState() => _Model3DViewState();
}

class _Model3DViewState extends State<Model3DView> {
  double _turn = -0.45;
  String? _key;
  _Mesh? _mesh;
  ui.Image? _picture;
  Rect? _bag; // where a bag held at the hand sits
  final _focus = FocusNode();

  void _ready() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.dispose();
    _picture?.dispose();
    super.dispose();
  }

  /// Rebuilds the model and its clothes picture when the body or outfit changes.
  void _refresh() {
    final s = avatarSettings;
    final looks = _wornLooks(_ready);
    final key = [
      s.m.join(','), s.arms, s.head, s.skinTone.toARGB32(), s.hair, s.hairTone.toARGB32(), s.eyeTone.toARGB32(),
      for (final slot in outfitSlots) '${avatarOutfit[slot]?.id}:${looks.photos[slot] != null}',
      for (final k in accessoryKinds) '${avatarAccessories[k]?.id}:${looks.accessories[k] != null}',
    ].join('|');
    if (key == _key) return;
    _key = key;
    _picture?.dispose();
    _picture = _clothesPicture(looks.specs, looks.photos, looks.accessories);
    _bag = looks.accessories['bag'] == null ? null : _ClothesPainter.accessoryBox(_Geo(s.m, s.arms), 'bag', looks.accessories['bag']!);
    _mesh = _buildModel(s, null, _bag);
    // A skirt or dress needs measuring from the picture, which takes a moment.
    final picture = _picture!;
    _skirtRings(picture, s.m[3]).then((rings) {
      if (!mounted || _key != key || rings == null) return;
      setState(() => _mesh = _buildModel(avatarSettings, rings, _bag));
    });
  }

  void _spin(double by) => setState(() => _turn += by);

  @override
  Widget build(BuildContext context) {
    _refresh();
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _spin(-0.3);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
          _spin(0.3);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label: 'Your model in 3D. Drag sideways to turn it.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focus.requestFocus(),
          onHorizontalDragUpdate: (d) => _spin(d.delta.dx * 0.012),
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(painter: _Model3DPainter(_mesh!, _picture!, _turn, avatarSettings.height)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.threesixty, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Drag to turn', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Draws the mesh: turns it, shades it, hides faces pointing away, and paints the
/// triangles from back to front with the clothes picture.
class _Model3DPainter extends CustomPainter {
  final _Mesh mesh;
  final ui.Image picture;
  final double turn, height;
  _Model3DPainter(this.mesh, this.picture, this.turn, this.height);

  @override
  void paint(Canvas canvas, Size size) {
    final n = mesh.count;
    if (n == 0 || n > 65535) return;
    const distance = 1060.0, centreY = 248.0;
    final focal = (size.height / 2) / tan(13 * pi / 180) * 0.95;
    final c = cos(turn), s = sin(turn);
    final px = Float32List(n * 2), depth = Float32List(n);
    final colors = Int32List(n);
    // Light from the front, up and to the right, plus a soft rim from behind.
    const lx = 0.36, ly = -0.58, lz = 0.73;
    const rx = -0.5, ry = -0.3, rz = -0.81;

    for (var i = 0; i < n; i++) {
      // Height scales the model toward its feet.
      final x = (mesh.pos[i * 3] - 120) * height;
      final y = 480 - (480 - mesh.pos[i * 3 + 1]) * height - centreY;
      final z = mesh.pos[i * 3 + 2] * height;
      final xr = x * c + z * s, zr = -x * s + z * c;
      final d = distance - zr;
      depth[i] = d;
      px[i * 2] = size.width / 2 + xr * focal / d;
      px[i * 2 + 1] = size.height / 2 + y * focal / d;
      final nx = mesh.nrm[i * 3], ny = mesh.nrm[i * 3 + 1], nz = mesh.nrm[i * 3 + 2];
      final nxr = nx * c + nz * s, nzr = -nx * s + nz * c;
      final light = 0.6 + 0.5 * max(0.0, nxr * lx + ny * ly + nzr * lz) + 0.16 * max(0.0, nxr * rx + ny * ry + nzr * rz);
      int ch(double v) => (v * light * 255).clamp(0, 255).round();
      colors[i] = (0xFF << 24) | (ch(mesh.col[i * 3]) << 16) | (ch(mesh.col[i * 3 + 1]) << 8) | ch(mesh.col[i * 3 + 2]);
    }

    // Faces pointing away are hidden; the rest are painted far to near.
    final tris = mesh.tri.length ~/ 3;
    final order = <int>[];
    final key = Float32List(tris);
    for (var t = 0; t < tris; t++) {
      final i0 = mesh.tri[t * 3], i1 = mesh.tri[t * 3 + 1], i2 = mesh.tri[t * 3 + 2];
      if (mesh.triCull[t]) {
        final nx = mesh.triNrm[t * 3], nz = mesh.triNrm[t * 3 + 2];
        final nxr = nx * c + nz * s, nzr = -nx * s + nz * c;
        // Direction from the face toward the camera (in turned space).
        final fx = (mesh.pos[i0 * 3] - 120) * height, fz = mesh.pos[i0 * 3 + 2] * height;
        final vx = -(fx * c + fz * s), vz = distance - (-fx * s + fz * c);
        final ny = mesh.triNrm[t * 3 + 1];
        final vy = -(480 - (480 - mesh.pos[i0 * 3 + 1]) * height - centreY);
        if (nxr * vx + ny * vy + nzr * vz <= 0) continue;
      }
      key[t] = (depth[i0] + depth[i1] + depth[i2]) / 3 - mesh.triBias[t];
      order.add(t);
    }
    order.sort((a, b) => key[b].compareTo(key[a]));
    final idx = Uint16List(order.length * 3);
    for (var j = 0; j < order.length; j++) {
      final t = order[j];
      idx[j * 3] = mesh.tri[t * 3];
      idx[j * 3 + 1] = mesh.tri[t * 3 + 1];
      idx[j * 3 + 2] = mesh.tri[t * 3 + 2];
    }

    // A soft shadow on the floor.
    final floorY = size.height / 2 + (480 - (480 - 466) * height - centreY) * focal / distance;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, floorY), width: size.height * 0.24, height: size.height * 0.035),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawVertices(
      ui.Vertices.raw(ui.VertexMode.triangles, px,
          textureCoordinates: Float32List.fromList(mesh.uv), colors: colors, indices: idx),
      BlendMode.modulate,
      Paint()
        ..shader = ui.ImageShader(picture, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage,
            filterQuality: FilterQuality.medium),
    );
  }

  @override
  bool shouldRepaint(covariant _Model3DPainter old) =>
      old.turn != turn || old.mesh != mesh || old.picture != picture || old.height != height;
}
