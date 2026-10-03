import 'dart:typed_data';
import 'dart:ui';

import 'package:tracend/features/train/muscle_groups.dart';

/// Which side of the body the muscle map shows.
enum BodySide { front, back }

/// The figure's design space. The left half is drawn and mirrored at x 100.
const double kBodyWidth = 200;
const double kBodyHeight = 420;

/// One shape of the figure. A null [group] is neutral (head, hands, knees,
/// forearms and the like) and never lights.
class BodyPart {
  BodyPart(this.id, this.group, String d, {this.mirrored = true})
    : recessed = false,
      path = _withMirror(parseSvgPath(d), mirrored);

  BodyPart.path(
    this.id,
    this.group,
    Path source, {
    this.mirrored = true,
    this.recessed = false,
  }) : path = _withMirror(source, mirrored);

  final String id;
  final MuscleGroup? group;
  final bool mirrored;

  /// A surface detail (the kneecap) drawn in the base colour, unoutlined.
  final bool recessed;

  /// Both halves in design space.
  final Path path;

  /// Everything around the part, for a glow that never covers the part.
  late final Path outside = Path.combine(
    PathOperation.difference,
    Path()..addRect(
      const Rect.fromLTWH(-20, -20, kBodyWidth + 40, kBodyHeight + 40),
    ),
    path,
  );

  static Path _withMirror(Path half, bool mirrored) {
    if (!mirrored) return half;
    return Path()
      ..addPath(half, Offset.zero)
      ..addPath(half.transform(_mirror), Offset.zero);
  }
}

final Float64List _mirror = Float64List.fromList([
  -1, 0, 0, 0, //
  0, 1, 0, 0, //
  0, 0, 1, 0, //
  kBodyWidth, 0, 0, 1,
]);

/// The figure for one side: the silhouette (drawn in the base colour, so it
/// shows as the thin separation lines) and the parts in paint order.
class BodyFigure {
  BodyFigure._(this.silhouette, this.parts);

  final Path silhouette;
  final List<BodyPart> parts;

  static final BodyFigure front = BodyFigure._(_silhouette, _frontParts());
  static final BodyFigure back = BodyFigure._(_silhouette, _backParts());

  static BodyFigure of(BodySide side) => side == BodySide.front ? front : back;

  /// The muscle group under [point] (design space), or null.
  MuscleGroup? groupAt(Offset point) {
    for (final part in parts.reversed) {
      if (part.path.contains(point)) return part.group;
    }
    return null;
  }
}

final Path _silhouette = () {
  final half = parseSvgPath(
    'M100 50 L90 50 C90 56 88 62 84 64 C76 66 66 66 60 67 C50 68 43 73 41 82 '
    'C38 94 38 106 37 118 C36 130 36 140 36 150 C33 160 30 172 28 186 '
    'C27 196 27 206 28 214 C25 222 24 232 28 240 C32 244 37 242 39 236 '
    'C40 228 40 220 39 214 C41 204 45 190 48 176 C51 166 52 158 52 150 '
    'C53 140 54 130 56 120 L58 112 C60 124 62 138 66 150 C69 162 70 174 70 184 '
    'C67 194 64 206 64 220 C62 240 62 260 64 280 C65 292 66 300 66 308 '
    'C63 318 62 330 62.6 342 C63.4 356 66 372 68.6 386 C66 394 64 400 66 404 '
    'L86 404 C87 398 86 392 84.6 386 C86 372 88.6 358 89.4 346 C90 334 89.6 320 88 308 '
    'C90 296 92 282 94 264 C96 250 98 236 99 226 L100 226 Z',
  );
  return Path()
    ..addPath(half, Offset.zero)
    ..addPath(half.transform(_mirror), Offset.zero)
    ..addOval(
      Rect.fromCenter(center: const Offset(100, 28), width: 32, height: 42),
    );
}();

BodyPart _head() => BodyPart.path(
  'head',
  null,
  Path()..addOval(
    Rect.fromCenter(center: const Offset(100, 28), width: 32, height: 42),
  ),
  mirrored: false,
);

List<BodyPart> _sharedLimbs() => [
  BodyPart(
    'forearm_outer',
    null,
    'M36.5 154 C33.5 163 30.8 174 29.4 186 C28.6 196 28.4 205 28.9 212.5 '
        'L33.4 212.5 C34.6 200 37.6 187 41.4 175 C43.6 167 45.4 160 46.2 155 '
        'C42.8 155.6 39.6 155.2 36.5 154 Z',
  ),
  BodyPart(
    'forearm_inner',
    null,
    'M47.8 155 C46.4 162 44.6 169 42.6 176 C39.4 188 36.6 200 35.2 212.5 '
        'L38.6 212.5 C40.2 204 43 193 46.6 180.5 C49.6 170 51.4 162 51.6 155 '
        'C50.4 155.2 49 155.2 47.8 155 Z',
  ),
  BodyPart(
    'hand',
    null,
    'M28.6 215.5 C26.2 222.5 25.6 231.5 28.6 238.5 C31.6 242 35.8 241.6 38.2 236 '
        'C39.4 229 39.4 222 38.8 215.5 Z',
  ),
  BodyPart(
    'foot',
    null,
    'M66.4 389 C64.8 395 63.8 400 65.6 403.6 L85.8 403.6 C86.6 398 86 393 84.6 389 '
        'C79 390 72 390 66.4 389 Z',
  ),
];

List<BodyPart> _frontParts() => [
  _head(),
  BodyPart(
    'neck',
    null,
    'M90.6 44 L100 44 L100 65.5 C96 66 92 65.6 88.8 64.8 C90.6 60.6 91.2 56 90.6 50 Z',
  ),
  BodyPart(
    'traps_front',
    MuscleGroup.back,
    'M90.2 52 C89.6 57.5 87.6 62 83.6 64.4 C77 66.4 68.4 66.6 61.6 67.6 '
        'C70 68.8 80 68.2 87.6 66.2 C90.6 64.6 91.6 60.6 91.6 56.4 Z',
  ),
  BodyPart(
    'biceps',
    MuscleGroup.biceps,
    'M46.6 101 C50.4 97 55.4 96.6 58.4 100 C58.8 104 58.4 108 57.4 113 '
        'C55.8 123 53.8 134 51.8 143.5 C50.6 149.6 47 152.4 43 151 '
        'C39.2 145.5 37.6 137 37.8 127 C38.4 115.5 41.4 106 46.6 101 Z',
  ),
  BodyPart(
    'deltoid',
    MuscleGroup.shoulders,
    'M64 68 C54 66 45 71 42 82 C40 92 42 103 46 112 C50 104 55 94 60 86 '
        'C63 80 66 74 67 70 Z',
  ),
  BodyPart(
    'pec',
    MuscleGroup.chest,
    'M68 70 C64 78 60 86 57 94 C58 104 62 112 70 116 C80 120 92 118 98 114 '
        'L98 72 C90 70 80 68 68 70 Z',
  ),
  BodyPart(
    'serratus',
    null,
    'M60.4 115.6 C63.6 117.4 67.6 118.8 72.4 120.4 L73.6 131.6 '
        'C70 133.6 66.4 135 63.4 136 C61.8 129 60.8 122 60.4 115.6 Z',
  ),
  BodyPart(
    'oblique',
    MuscleGroup.core,
    'M63.8 138.4 C67.6 137 71.6 134.6 75.2 129 C78.6 124.4 81.8 122 85.2 121.6 '
        'L86 174 C86.6 184 87.6 194 89 203 C82.4 201.4 76.4 197.2 71.6 190.6 '
        'C70.8 182 70 174 68.8 166 C67.4 156 65.8 147 63.8 138.4 Z',
  ),
  BodyPart(
    'abs_1',
    MuscleGroup.core,
    'M89.4 121.2 C92 120.4 95 120.2 97.4 120.6 L97.6 133.6 C97.6 135.6 96.6 136.6 '
        '94.8 136.6 L89.6 136.6 C87.8 136.6 86.8 135.4 86.8 133.6 L86.4 124.6 '
        'C86.4 122.6 87.6 121.6 89.4 121.2 Z',
  ),
  BodyPart(
    'abs_2',
    MuscleGroup.core,
    'M89.8 139 L95.2 139 C97 139 97.8 140 97.8 141.8 L98 152.2 C98 154 97 155 '
        '95.2 155 L90.4 155 C88.6 155 87.6 154 87.6 152.2 L87 141.8 '
        'C87 140 88 139 89.8 139 Z',
  ),
  BodyPart(
    'abs_3',
    MuscleGroup.core,
    'M90.6 157.4 L95.6 157.4 C97.3 157.4 98.1 158.4 98.1 160.2 L98.3 170.6 '
        'C98.3 172.4 97.3 173.4 95.6 173.4 L91.4 173.4 C89.6 173.4 88.6 172.4 '
        '88.6 170.6 L87.8 160.2 C87.8 158.4 88.8 157.4 90.6 157.4 Z',
  ),
  BodyPart(
    'abs_lower',
    MuscleGroup.core,
    'M91.4 176 L95.8 176 C97.6 176 98.4 177.2 98.4 179 L98.4 211 '
        'C95.4 208 92.6 202 91 195 C89.8 189.4 89.2 183.6 89.4 179.6 '
        'C89.6 177.2 90.2 176 91.4 176 Z',
  ),
  BodyPart(
    'adductor',
    null,
    'M84.4 213 C87.8 219.6 92.6 223.6 98.6 226 C97.4 240 95.4 254 92.4 267 '
        'C90.6 261 88.6 255.6 86.6 250.6 C87.2 238 86.4 225.4 84.4 213 Z',
  ),
  BodyPart(
    'vastus_lateralis',
    MuscleGroup.quads,
    'M70.6 194.4 C66.6 204 64.4 218 63.4 234 C62.6 252 63.2 268 65 282 '
        'C66.2 290 68.2 297 71 302 C72.4 290 72.6 276 73.4 262 C74.2 246 75 230 '
        '76.4 214 C74.8 206 72.8 199.6 70.6 194.4 Z',
  ),
  BodyPart(
    'rectus_femoris',
    MuscleGroup.quads,
    'M77.6 203 C74.8 217 73.8 235 73.8 252 C73.8 268 75.6 282 79.2 292 '
        'C82.6 285 84.4 273 85 259 C85.6 243 85.4 227 83.6 212.6 '
        'C81.8 207.4 79.8 204.4 77.6 203 Z',
  ),
  BodyPart(
    'vastus_medialis',
    MuscleGroup.quads,
    'M86.6 252 C84 263 81.8 276 81.2 289 C82 297 85 302.4 88.6 301.8 '
        'C90.6 295.6 91.6 286 91.6 276.4 C91.2 266.4 89.2 258 86.6 252 Z',
  ),
  BodyPart(
    'knee',
    null,
    'M70.6 303.4 C69 308 69.2 313.6 71 318 C75.4 321.6 82.8 321.6 86.8 318 '
        'C88.4 313.4 88.4 308.4 87.4 304.6 C84 306.6 79.6 306.8 76 305.6 '
        'C73.8 305 72 304.4 70.6 303.4 Z',
  ),
  BodyPart.path(
    'kneecap',
    null,
    Path()..addOval(
      Rect.fromCenter(center: const Offset(79, 311.4), width: 8.4, height: 10),
    ),
    recessed: true,
  ),
  BodyPart(
    'calf_outer',
    MuscleGroup.calves,
    'M66.2 321 C63.2 329 62.4 340 63.4 350 C64.4 360 66.2 368 68 375 '
        'C69.4 362 70.6 348 70.8 336 C70.6 329 69 324 66.2 321 Z',
  ),
  BodyPart(
    'tibialis',
    null,
    'M72.2 323 C71.4 337 71.8 352 73.2 366 C74.2 374 75.4 380 76.4 385.6 '
        'L79.6 385.6 C78.8 372 78.4 356 78.4 342 C78.4 333 77.4 327 75.6 323 '
        'C74.4 322.6 73.2 322.6 72.2 323 Z',
  ),
  BodyPart(
    'calf_inner',
    MuscleGroup.calves,
    'M80.6 322 C79.6 330 79.8 342 80.8 352 C81.6 360 83 366 84.8 370 '
        'C87.6 362 89.8 350 89.8 338 C89.8 330 88 324 85.4 321 '
        'C83.6 321 82 321.4 80.6 322 Z',
  ),
  ..._sharedLimbs(),
];

List<BodyPart> _backParts() => [
  _head(),
  BodyPart(
    'erector',
    MuscleGroup.back,
    'M89.4 122 C88.4 138 88.2 155 88.8 171 C89.4 183 90.4 195 92.4 206 '
        'L98.6 206 L98.6 142 C96.4 134 93 127 89.4 122 Z',
  ),
  BodyPart(
    'lats',
    MuscleGroup.back,
    'M59.6 113.6 C61 128 64 142 67.2 155 C69.6 166 71 176 71.6 186 '
        'C77.2 182 82.8 176.4 87.4 170.6 L88.6 124 C94 120 96 112 92 100 '
        'C88 94 84 92 81.4 100.8 C76 108 67.6 114 59.6 113.6 Z',
  ),
  BodyPart(
    'oblique_back',
    MuscleGroup.core,
    'M71.8 188.6 C77.6 184.6 83.4 179 88 173.4 C88.6 183 89.6 192.4 91 200.4 '
        'C84.6 202.6 77.8 203.6 70.8 203.8 C71.2 198.6 71.6 193.6 71.8 188.6 Z',
  ),
  BodyPart(
    'teres',
    MuscleGroup.back,
    'M59.4 97.6 C58.4 102.6 58.4 107.6 59.4 111.8 C65.2 112.8 71.2 110.6 77 105.6 '
        'C71 105 65 102.4 59.4 97.6 Z',
  ),
  BodyPart(
    'infraspinatus',
    MuscleGroup.back,
    'M64 72.4 C61 79.4 60 87 60.6 95 C66 101 74 103.2 81.2 101.2 '
        'C83.6 95.4 84 90.4 82.6 86 C77.2 80.2 71.2 75.8 64 72.4 Z',
  ),
  BodyPart(
    'traps',
    MuscleGroup.back,
    'M99.6 47 L91.4 47 C90.8 53 88.2 60 83.6 63.4 C77 66 69 67 62 68.6 '
        'C69.4 72.4 77.2 78.4 83.2 86.2 C89.2 96 94.4 114 99.6 140 Z',
  ),
  BodyPart(
    'rear_delt',
    MuscleGroup.shoulders,
    'M63 69.4 C54 66.6 45 71 42 82 C40 92 42 103 46 111.4 C50 103 55 95 60 89 '
        'C63 84 64.6 77 63 69.4 Z',
  ),
  BodyPart(
    'triceps',
    MuscleGroup.triceps,
    'M41.4 101.6 C38.6 110 37.2 122 37 134 C37 142 37.2 147.6 37.8 151.6 '
        'L45 151.6 C45.4 144.6 46.8 138 49.2 133.4 C51.4 138 52.4 144.6 52.2 151.6 '
        'L52.8 151.6 C54 140 55.6 126 57.4 113 C53.6 105.6 47.6 101.6 41.4 101.6 Z',
  ),
  BodyPart(
    'triceps_tendon',
    null,
    'M45 151.6 C45.4 144.6 46.8 138 49.2 133.4 C51.4 138 52.4 144.6 52.2 151.6 Z',
  ),
  BodyPart(
    'glutes',
    MuscleGroup.glutes,
    'M70 204 C66 214 65 226 68 236 C72 244 82 248 92 246 C96 244 98.5 240 98.5 234 '
        'L98.5 206 C92 200 80 200 70 204 Z',
  ),
  BodyPart(
    'hamstring_outer',
    MuscleGroup.hamstrings,
    'M65.8 245.4 C63 259 63 273 65 285.6 C66.8 294 69.8 300 73.6 303.6 '
        'C75.6 292 76.8 278 77.8 264 C78.4 258 78.8 252.6 79 248.4 '
        'C74.4 248.6 70 247.6 65.8 245.4 Z',
  ),
  BodyPart(
    'hamstring_inner',
    MuscleGroup.hamstrings,
    'M81.2 249 C80.6 262 80.6 276 81.6 290 C82.6 297.6 84.6 302.6 87.2 304.6 '
        'C89.2 296 91 284 92.6 272 C94 262 95.4 254 96.4 247.4 '
        'C91.4 248.8 86.4 249.4 81.2 249 Z',
  ),
  BodyPart(
    'knee',
    null,
    'M70.2 305.4 C69 309.6 69.4 314 70.8 317.6 C76 319.6 82 319.6 86.8 317 '
        'C88 313.4 88 309.6 87.6 306.2 C82.2 308 75.6 308 70.2 305.4 Z',
  ),
  BodyPart(
    'gastroc_outer',
    MuscleGroup.calves,
    'M66.4 319.6 C63.6 328 62.8 340 64.2 351 C65.6 359 69 364 73.6 365 '
        'C75.6 355 76.8 343 76.8 331 C76.8 325.6 76 321.6 74.2 319.8 '
        'C71.4 320.4 68.8 320.4 66.4 319.6 Z',
  ),
  BodyPart(
    'gastroc_inner',
    MuscleGroup.calves,
    'M79.2 319.8 C78.6 329 79 342 80.6 353 C82 361 84.6 367 87.6 367.4 '
        'C89.6 358 90 346 89.6 334 C89.2 327 88 322.4 86.2 319.4 '
        'C83.8 320.2 81.6 320.4 79.2 319.8 Z',
  ),
  BodyPart(
    'achilles',
    null,
    'M68.4 360 C67.8 370 68.2 379 68.8 386.4 L84.4 386.4 C85.2 380 86.2 374 '
        '87 368.6 C83.4 371.2 77.6 370.8 72.6 367.4 C70.6 365.6 69.2 363 68.4 360 Z',
  ),
  ..._sharedLimbs(),
];

/// Parses the absolute SVG path commands the figure uses: M, L, H, V, C, Q
/// and Z, with numbers separated by spaces or commas.
Path parseSvgPath(String d) {
  final tokens = RegExp(
    r'[MLHVCQZmlhvcqz]|-?\d*\.?\d+(?:e-?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var command = '';
  var x = 0.0;
  var y = 0.0;
  double next() => double.parse(tokens[i++]);
  bool isCommand(String token) => RegExp('^[A-Za-z]\$').hasMatch(token);
  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      command = tokens[i++];
      if (command == 'Z' || command == 'z') {
        path.close();
        continue;
      }
    }
    switch (command) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x, y);
        command = 'L';
      case 'L':
        x = next();
        y = next();
        path.lineTo(x, y);
      case 'H':
        x = next();
        path.lineTo(x, y);
      case 'V':
        y = next();
        path.lineTo(x, y);
      case 'C':
        final x1 = next(), y1 = next(), x2 = next(), y2 = next();
        x = next();
        y = next();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Q':
        final x1 = next(), y1 = next();
        x = next();
        y = next();
        path.quadraticBezierTo(x1, y1, x, y);
      default:
        throw FormatException('Unsupported path command "$command"', d);
    }
  }
  return path;
}
