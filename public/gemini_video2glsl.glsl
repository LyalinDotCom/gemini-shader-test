// GEMINI // VIDEO 2 GLSL — 20.000s Four-Act Seamless Procedural Cinema
// Reconstructed from a 20-second multi-shot Gemini API video as ONE self-contained GLSL fragment shader.
// Zero textures. Zero video frames. 100% procedural math, physical optics, and 3D SDF raymarching.
// Built and verified with shader-skills (https://github.com/gokayfem/shader-skills).
//
// Timeline (loops seamlessly at LOOP_SECONDS = 20.000s with 0 bit drift at wrap):
//   [00.00s - 05.00s] Act I   — Emerald Lagoon, Voronoi Caustics, Volcanic Shoals & Obsidian Torus Monolith
//   [05.00s - 10.00s] Act II  — Sunlit Alpine Canyon, Billowing Cloud Sea & Faceted Cyan Crystal Obelisk
//   [10.00s - 15.00s] Act III — Blue-Hour Downtown Orbital Skyline, Art-Deco Spire & Illuminated Avenues
//   [15.00s - 20.00s] Act IV  — Twilight Basalt Colonnade Channel & Golden Total Solar Eclipse (wraps to Act I)
//
// Interactive controls (standard Shadertoy uniforms only):
//   - Drag mouse on canvas (iMouse.z > 0.0) to orbit camera in real 3D space inside any act!
//   - #define DEBUG_MODE 0..6 for beauty, distance field contours, world normals, material IDs,
//     raymarch step heatmap, optical/cloud/window masks, and direct lighting split.
//
// @render time=2.0
// @variant QUALITY=1
// @variant QUALITY=3
// @variant DEBUG_MODE=1
// @variant DEBUG_MODE=2
// @variant DEBUG_MODE=3
// @variant DEBUG_MODE=4
// @variant DEBUG_MODE=5
// @variant DEBUG_MODE=6
#define QUALITY 2
#define DEBUG_MODE 0

// Library code below is bundled from shader-skills (MIT): https://github.com/gokayfem/shader-skills
// ---- shader-skills library: common ----
const float PI  = 3.14159265358979;
const float TAU = 6.28318530717959;
// Clamp to [0,1].
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
// Squared length.
float dot2(vec2 v) { return dot(v, v); }
float dot2(vec3 v) { return dot(v, v); }
// 2D rotation matrix. `rot2(a) * v` rotates v counter-clockwise by a radians. (cos, sin) is renormalized because GLSL ES leaves trig precision undefined: on SwiftShader and some mobile GPUs a raw cos/sin pair is far enough from unit length that rotations stop preserving distances.
mat2 rot2(float a) {
    vec2 cs = normalize(vec2(cos(a), sin(a)));
    return mat2(cs.x, cs.y, -cs.y, cs.x);
}
// Linear ramp from 0 at a to 1 at b, clamped.
float linearstep(float a, float b, float x) {
    return clamp((x - a) / (b - a), 0.0, 1.0);
}

// ---- shader-skills library: hash ----
// PCG-style 1D integer hash.
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
// 3D integer hash, three decorrelated outputs.
uvec3 pcg3d(uvec3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}
// Map a uint to [0,1) using the top 24 bits, so the result can never round up to 1.0.
float uintToUnit(uint h) { return float(h >> 8u) * (1.0 / 16777216.0); }
vec2 uintToUnit(uvec2 h) { return vec2(h >> 8u) * (1.0 / 16777216.0); }
vec3 uintToUnit(uvec3 h) { return vec3(h >> 8u) * (1.0 / 16777216.0); }
vec4 uintToUnit(uvec4 h) { return vec4(h >> 8u) * (1.0 / 16777216.0); }
// Random float in [0,1) for an integer-valued 2D input.
float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y)));
}
// Random float in [0,1) for an integer-valued 3D input.
float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y + pcgHash(q.z))));
}
// Random vec2 in [0,1)^2 for an integer-valued 2D input.
vec2 hash22(vec2 p) {
    ivec2 q = ivec2(floor(p));
    return uintToUnit(pcg3d(uvec3(q.x, q.y, 0x2545u))).xy;
}
// Random vec3 in [0,1)^3 for an integer-valued 3D input.
vec3 hash33(vec3 p) { return uintToUnit(pcg3d(uvec3(ivec3(floor(p))))); }
// Random vec3 in [0,1)^3 for an integer-valued 2D input.
vec3 hash32(vec2 p) {
    ivec2 q = ivec2(floor(p));
    return uintToUnit(pcg3d(uvec3(q.x, q.y, 0x9E37u)));
}

// ---- shader-skills library: noise ----
// Quintic fade 6t^5 - 15t^4 + 10t^3: C2-continuous interpolation weights for lattice noise.
vec2 quinticFade(vec2 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
vec3 quinticFade(vec3 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
// Derivative of quinticFade: 30 t^2 (t - 1)^2.
vec2 quinticFadeDeriv(vec2 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
vec3 quinticFadeDeriv(vec3 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
// Unit gradient for a 2D lattice point.
vec2 latticeGradient(vec2 cell) {
    float a = TAU * hash12(cell);
    return vec2(cos(a), sin(a));
}
// 2D gradient (Perlin-style) noise with analytic derivatives. Returns vec3(value, d/dx, d/dy). Gradient noise has less grid-aligned blockiness than value noise. Prefer it for fBm.
vec3 gradientNoiseD(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = quinticFade(f), du = quinticFadeDeriv(f);
    vec2 ga = latticeGradient(i);
    vec2 gb = latticeGradient(i + vec2(1.0, 0.0));
    vec2 gc = latticeGradient(i + vec2(0.0, 1.0));
    vec2 gd = latticeGradient(i + vec2(1.0, 1.0));
    float va = dot(ga, f);
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));
    float k = va - vb - vc + vd;
    float value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
    vec2 deriv = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
               + du * (vec2(vb - va, vc - va) + u.yx * k);
    return vec3(value, deriv);
}
// 2D gradient noise.
float gradientNoise(vec2 p) { return gradientNoiseD(p).x; }
// Dot product of a hashed 3D gradient with the offset to its lattice corner.
float latticeGradDot(vec3 cell, vec3 corner, vec3 f) {
    vec3 g = hash33(cell + corner) * 2.0 - 1.0;
    return dot(g, f - corner);
}
// 3D gradient noise.
float gradientNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f);
    return mix(mix(mix(latticeGradDot(i, vec3(0, 0, 0), f), latticeGradDot(i, vec3(1, 0, 0), f), u.x),
                   mix(latticeGradDot(i, vec3(0, 1, 0), f), latticeGradDot(i, vec3(1, 1, 0), f), u.x), u.y),
               mix(mix(latticeGradDot(i, vec3(0, 0, 1), f), latticeGradDot(i, vec3(1, 0, 1), f), u.x),
                   mix(latticeGradDot(i, vec3(0, 1, 1), f), latticeGradDot(i, vec3(1, 1, 1), f), u.x), u.y), u.z);
}
// 3D gradient noise with analytic derivatives. Returns vec4(value, d/dx, d/dy, d/dz); value equals gradientNoise(p). The trilinear blend is expanded as a polynomial in the fade weights, so the gradient is the same blend of the corner gradients plus the chain-rule term of the fade.
vec4 gradientNoiseD(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f), du = quinticFadeDeriv(f);
    vec3 g000 = hash33(i) * 2.0 - 1.0;
    vec3 g100 = hash33(i + vec3(1, 0, 0)) * 2.0 - 1.0;
    vec3 g010 = hash33(i + vec3(0, 1, 0)) * 2.0 - 1.0;
    vec3 g110 = hash33(i + vec3(1, 1, 0)) * 2.0 - 1.0;
    vec3 g001 = hash33(i + vec3(0, 0, 1)) * 2.0 - 1.0;
    vec3 g101 = hash33(i + vec3(1, 0, 1)) * 2.0 - 1.0;
    vec3 g011 = hash33(i + vec3(0, 1, 1)) * 2.0 - 1.0;
    vec3 g111 = hash33(i + vec3(1, 1, 1)) * 2.0 - 1.0;
    float v000 = dot(g000, f);
    float v100 = dot(g100, f - vec3(1, 0, 0));
    float v010 = dot(g010, f - vec3(0, 1, 0));
    float v110 = dot(g110, f - vec3(1, 1, 0));
    float v001 = dot(g001, f - vec3(0, 0, 1));
    float v101 = dot(g101, f - vec3(1, 0, 1));
    float v011 = dot(g011, f - vec3(0, 1, 1));
    float v111 = dot(g111, f - vec3(1, 1, 1));
    // value = v000 + kx u.x + ky u.y + kz u.z + kxy u.x u.y + kyz u.y u.z + kzx u.z u.x + kxyz u.x u.y u.z
    float kx = v100 - v000, ky = v010 - v000, kz = v001 - v000;
    float kxy = v000 - v100 - v010 + v110;
    float kyz = v000 - v010 - v001 + v011;
    float kzx = v000 - v100 - v001 + v101;
    float kxyz = -v000 + v100 + v010 - v110 + v001 - v101 - v011 + v111;
    float value = v000 + kx * u.x + ky * u.y + kz * u.z
                + kxy * u.x * u.y + kyz * u.y * u.z + kzx * u.z * u.x + kxyz * u.x * u.y * u.z;
    vec3 grad = g000 + (g100 - g000) * u.x + (g010 - g000) * u.y + (g001 - g000) * u.z
              + (g000 - g100 - g010 + g110) * u.x * u.y
              + (g000 - g010 - g001 + g011) * u.y * u.z
              + (g000 - g100 - g001 + g101) * u.z * u.x
              + (-g000 + g100 + g010 - g110 + g001 - g101 - g011 + g111) * u.x * u.y * u.z
              + du * vec3(kx + kxy * u.y + kzx * u.z + kxyz * u.y * u.z,
                          ky + kxy * u.x + kyz * u.z + kxyz * u.x * u.z,
                          kz + kyz * u.y + kzx * u.x + kxyz * u.x * u.y);
    return vec4(value, grad);
}
const int FBM_MAX_OCTAVES = 12;
// Fractional Brownian motion over 2D gradient noise. Each octave is rotated to hide lattice alignment. persistence 0.5 is the classic look (H = 1). Lower is smoother, higher is rougher.
float fbm(vec2 p, int octaves, float lacunarity, float persistence) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return 1.4 * sum / norm;
}
// 2D fBm with the usual defaults (lacunarity 2.01 so octave peaks never re-align, persistence 0.5).
float fbm(vec2 p, int octaves) { return fbm(p, octaves, 2.01, 0.5); }
// fBm over 3D gradient noise.
float fbm(vec3 p, int octaves, float lacunarity, float persistence) {
    const mat3 octaveRotation = mat3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + vec3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
// Terrain fBm where each octave is damped by the accumulated slope, so detail settles in valleys and steep slopes stay smooth. This gives an eroded look without simulation.
float erodedFbm(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float h = 0.0, amp = 0.5;
    vec2 slope = vec2(0.0);
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        vec3 n = gradientNoiseD(p);
        slope += n.yz;
        h += amp * n.x / (1.0 + dot(slope, slope));
        amp *= 0.5;
        p = 2.0 * (octaveRotation * p);
    }
    return 2.0 * h;
}
// Ridged multifractal: inverted |noise| creates sharp crests; each octave is weighted by the previous one, so detail gathers along ridges.
float ridgedFbm(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = 1.0 - abs(gradientNoise(p) * 1.4);
        n *= n;
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 2.0, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return sum / norm;
}
// Billowy multifractal: |noise| per octave makes puffy rounded lobes split by sharp creases (the inverse of ridgedFbm). Each octave is weighted by the previous one, so detail gathers on the lobes while the creases stay clean.
float billowFbm(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = abs(gradientNoise(p) * 1.4);
        n = n * (2.0 - n);   // round the lobe tops, keep the creases sharp
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 1.5, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return sum / norm;
}
float billowFbm(vec3 p, int octaves) {
    const mat3 octaveRotation = mat3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = min(abs(gradientNoise(p)) * 1.4, 1.0);
        n = n * (2.0 - n);
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 1.5, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
// Exact distance to Voronoi cell borders, found in two passes: nearest point, then nearest bisector. Returns vec3(borderDistance, vectorToNearestPoint). Unlike F2-F1, the border distance is a true distance, so lines have constant width.
vec3 voronoiBorder(vec2 p, float jitter) {
    vec2 ip = floor(p), fp = fract(p);
    vec2 mg = vec2(0.0), mr = vec2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 r = g + jitter * hash22(ip + g) - fp;
        float d = dot(r, r);
        if (d < md) { md = d; mr = r; mg = g; }
    }
    md = 8.0;
    for (int j = -2; j <= 2; j++)
    for (int i = -2; i <= 2; i++) {
        vec2 g = mg + vec2(float(i), float(j));
        vec2 r = g + jitter * hash22(ip + g) - fp;
        if (dot2(mr - r) > 1e-5) {
            md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
        }
    }
    return vec3(md, mr);
}
// Smooth Voronoi: a soft-min of distances to feature points. Cells become blobs with no creases. k controls smoothness (large = sharper; around 8-32). Searches 5x5 cells so low k has no seams.
float smoothVoronoi(vec2 p, float k) {
    vec2 ip = floor(p), fp = fract(p);
    float acc = 0.0;
    for (int j = -2; j <= 2; j++)
    for (int i = -2; i <= 2; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 r = g + hash22(ip + g) - fp;
        acc += exp2(-k * length(r));
    }
    return -log2(acc) / k;
}
// Interleaved gradient noise: cheap per-pixel noise whose 3x3 neighborhoods are nearly stratified. Not a hash. pixel must be integer pixel coordinates (floor(fragCoord)). The frame overload animates it for accumulation and TAA.
float interleavedGradientNoise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}
float interleavedGradientNoise(vec2 pixel, int frame) {
    return interleavedGradientNoise(pixel + 5.588238 * float(frame % 64));
}

// ---- shader-skills library: sdf3d ----
// Axis-aligned box with half-extents b.
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
// Box with rounded edges. The outer size stays b; r is the edge radius (r <= min(b)).
float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
// Torus in the XZ plane. t.x = major radius, t.y = tube radius.
float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
// Capsule: segment a-b swept by radius r.
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
// Capped cone (frustum) from y = -h (radius r1) to y = +h (radius r2). Set r2 = 0 for a pointed cone. Exact everywhere, including the base cap. Points below the base are outside.
float sdCappedCone(vec3 p, float h, float r1, float r2) {
    vec2 q = vec2(length(p.xz), p.y);
    vec2 top = vec2(r2, h);
    vec2 side = vec2(r2 - r1, 2.0 * h);
    vec2 toCap = vec2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    vec2 toSide = q - top + side * clamp(dot(top - q, side) / dot2(side), 0.0, 1.0);
    float s = (toSide.x < 0.0 && toCap.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(toCap), dot2(toSide)));
}
// Hexagonal prism along Z. h.x = inradius of the hexagon, h.y = half-length.
float sdHexPrism(vec3 p, vec2 h) {
    const vec3 k = vec3(-0.8660254, 0.5, 0.57735027);
    p = abs(p);
    p.xy -= 2.0 * min(dot(k.xy, p.xy), 0.0) * k.xy;
    vec2 d = vec2(length(p.xy - vec2(clamp(p.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p.y - h.x),
                  p.z - h.y);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// Regular octahedron with "radius" s (vertex distance from center). Bound version.
float sdOctahedron(vec3 p, float s) {
    p = abs(p);
    return (p.x + p.y + p.z - s) * 0.57735027;
}

// ---- shader-skills library: sdf2d ----
// Axis-aligned rectangle with half-extents b.
float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// ---- shader-skills library: operators ----
// Smooth union (polynomial, C1). Blends where |a - b| < k, with a max bulge of k/4.
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// Smooth intersection, the mirror of smin.
float smax(float a, float b, float k) { return -smin(-a, -b, k); }

// ---- shader-skills library: domain ----
// Cell index for repetition with period s (integer-valued; use with hash functions).
float domRepeatId(float p, float s) { return floor(p / s + 0.5); }
vec2 domRepeatId(vec2 p, vec2 s) { return floor(p / s + 0.5); }
vec3 domRepeatId(vec3 p, vec3 s) { return floor(p / s + 0.5); }
// Infinite repetition with period s. Returns the local coordinate centered in its cell. Exact only while each instance stays inside its own cell. For instances that vary per cell or overhang, evaluate the 2 or 3 neighboring cells too (see references/sdf-library-guide.md).
float domRepeat(float p, float s) { return p - s * floor(p / s + 0.5); }
vec2 domRepeat(vec2 p, vec2 s) { return p - s * floor(p / s + 0.5); }
vec3 domRepeat(vec3 p, vec3 s) { return p - s * floor(p / s + 0.5); }

// ---- shader-skills library: architecture ----
// Stable building profile: vec4(height, half-width, half-depth, roof style 0/1/2) from an integer parcel ID. Height and half-width ranges are ordered, positive world-space values. The same ID always gives the same profile.
vec4 buildingProfile(vec2 parcel, vec2 heightRange, vec2 halfWidthRange) {
    vec3 h = hash32(parcel);
    return vec4(mix(heightRange.x,heightRange.y,h.x*h.x),
                mix(halfWidthRange.x,halfWidthRange.y,h.y),
                mix(halfWidthRange.x,halfWidthRange.y,h.z),
                floor(3.0*hash12(parcel+vec2(83.0,19.0))));
}
// Box-filtered rectangular windows centered on integer facade coordinates. fill is the opening fraction per cell in [0,1]; footprint is the pixel's width/height in cell units. At large footprints it converges to fill.x*fill.y.
float facadeWindowMask(vec2 uv, vec2 fill, vec2 footprint) {
    fill = clamp(fill,0.0,1.0);
    vec2 w = max(footprint,vec2(0.0001));
    vec2 a = uv + 0.5*fill + 0.5*w;
    vec2 b = uv + 0.5*fill - 0.5*w;
    vec2 ia = floor(a)*fill + min(fract(a),fill);
    vec2 ib = floor(b)*fill + min(fract(b),fill);
    vec2 coverage = clamp((ia-ib)/w,0.0,1.0);
    return coverage.x*coverage.y;
}

// ---- shader-skills library: raymarch ----
#define ZERO (min(iFrame, 0))
vec2 map(vec3 p);
// Surface normal from 4 tetrahedral samples (cheaper than 6 central differences, and still centered). eps should scale with distance, e.g. 0.0005 * t: that filters distant detail and avoids sparkling.
vec3 calcNormal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * map(p + e * eps).x;
    }
    return normalize(n);
}
// Ambient occlusion from 5 distance samples along the normal. Compares the expected distance with the actual one. scale is the sampling reach in scene units (about 0.12 for a unit-sized object). Returns 0 (occluded) .. 1 (open).
float calcAO(vec3 p, vec3 n, float scale) {
    float occ = 0.0;
    float weight = 1.0;
    for (int i = ZERO; i < 5; i++) {
        float h = 0.01 + scale * float(i) / 4.0;
        float d = map(p + h * n).x;
        occ += (h - d) * weight;
        weight *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ / max(scale / 0.12, 1e-3), 0.0, 1.0);
}

// ---- shader-skills library: intersect ----
// Ray vs sphere centered at c with radius r. Returns vec2(tNear, tFar), or vec2(-1) on a miss. Uses the precision-friendly form that measures from the closest point on the ray.
vec2 iSphere(vec3 ro, vec3 rd, vec3 c, float r) {
    vec3 oc = ro - c;
    float b = dot(oc, rd);
    vec3 qc = oc - b * rd;
    float h = r * r - dot(qc, qc);
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}

// ---- shader-skills library: camera ----
// Camera-to-world matrix looking from ro toward ta, with roll in radians. Columns are (right, up, forward).
mat3 cameraMatrix(vec3 ro, vec3 ta, float roll) {
    vec3 w = normalize(ta - ro);
    vec3 up = vec3(sin(roll), cos(roll), 0.0);
    vec3 u = normalize(cross(w, up));
    vec3 v = cross(u, w);
    return mat3(u, v, w);
}
// Primary ray direction for screen point uv. focal is about 1.5-2.5 for natural framing (see fovToFocal).
vec3 cameraRay(mat3 cam, vec2 uv, float focal) {
    return normalize(cam * vec3(uv, focal));
}

// ---- shader-skills library: shading ----
// Schlick Fresnel. u is VoH for lights and NoV for environment reflections and rims. f0 = 0.04 for dielectrics (plastic, skin, stone, water ~0.02); for metals f0 = base color.
vec3 fresnelSchlick(float u, vec3 f0) {
    float m = clamp(1.0 - u, 0.0, 1.0);
    float m2 = m * m;
    return f0 + (1.0 - f0) * (m2 * m2 * m);
}
// GGX / Trowbridge-Reitz normal distribution. alpha = roughness^2.
float distributionGGX(float NoH, float alpha) {
    float a2 = alpha * alpha;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}
// Height-correlated Smith visibility. Already contains the 1 / (4 NoL NoV) term.
float visibilitySmithGGX(float NoV, float NoL, float alpha) {
    float a2 = alpha * alpha;
    float gv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float gl = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}
// Microfacet specular for one light: pi * D * V * F * NoL (artist units). roughness is perceptual, in [0,1].
vec3 specularGGX(vec3 n, vec3 v, vec3 l, float roughness, vec3 f0) {
    vec3 h = normalize(v + l);
    float NoL = clamp(dot(n, l), 0.0, 1.0);
    float NoV = max(dot(n, v), 1e-4);
    float NoH = clamp(dot(n, h), 0.0, 1.0);
    float VoH = clamp(dot(v, h), 0.0, 1.0);
    float alpha = max(roughness, 0.045);
    alpha *= alpha;
    return PI * distributionGGX(NoH, alpha) * visibilitySmithGGX(NoV, NoL, alpha) * fresnelSchlick(VoH, f0) * NoL;
}
// Complete metallic-roughness shading for one light (diffuse + specular, NoL included, artist units). Multiply by light color and shadow. Keep albedo around 0.05-0.7 (linear); brighten lights, not albedo.
vec3 shadePBR(vec3 n, vec3 v, vec3 l, vec3 albedo, float roughness, float metallic) {
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    float NoL = clamp(dot(n, l), 0.0, 1.0);
    vec3 F = fresnelSchlick(max(dot(n, v), 0.0), f0);
    vec3 diffuse = albedo * (1.0 - metallic) * (1.0 - F) * NoL;
    return diffuse + specularGGX(n, v, l, roughness, f0);
}
// Hemisphere light: sky color from above blended to ground color from below.
vec3 hemisphereLight(vec3 n, vec3 skyColor, vec3 groundColor) {
    return mix(groundColor, skyColor, 0.5 + 0.5 * n.y);
}

// ---- shader-skills library: water ----
// Angular frequency sqrt(g*k*tanh(k*depth)) for finite-depth gravity waves. Nonpositive inputs are clamped.
float waterDispersion(float k, float depth, float gravity) {
    k = max(k,0.0);
    float e = exp(-2.0*k*max(depth,0.0));
    return sqrt(max(gravity,0.0)*k*(1.0-e)/(1.0+e));
}
// One sinusoidal wave: vec4(height, dh/dx, dh/dz, Laplacian). Direction is normalized internally; zero uses +X. wavelength > 0, amplitude in meters. footprint filters waves below 2-6 pixels; derivatives hold it constant.
vec4 waterWaveD(vec2 xz, float time, vec2 direction, float wavelength, float amplitude, float depth, float footprint) {
    float dl = length(direction);
    vec2 dir = dl>0.000001 ? direction/dl : vec2(1.0,0.0);
    float lengthM = max(wavelength,0.0001);
    float k = TAU/lengthM;
    float keep = smoothstep(2.0,6.0,lengthM/max(footprint,0.000001));
    float phase = k*dot(dir,xz)-waterDispersion(k,depth,9.81)*time;
    float h = amplitude*keep*sin(phase);
    return vec4(h, amplitude*keep*k*cos(phase)*dir, -k*k*h);
}
// Exact unpolarized dielectric Fresnel for a positive incident cosine and positive refractive indices. Returns 1 for total internal reflection. Caller chooses etaIncident/etaTransmitted for the ray's side.
float fresnelDielectric(float cosIncident, float etaIncident, float etaTransmitted) {
    float ci = clamp(abs(cosIncident),0.0,1.0);
    float ei = max(etaIncident,0.000001), et = max(etaTransmitted,0.000001);
    if (abs(ei-et)<0.0000001) return 0.0;
    float sinT2 = (ei*ei)/(et*et)*max(0.0,1.0-ci*ci);
    if (sinT2>=1.0) return 1.0;
    float ct = sqrt(max(0.0,1.0-sinT2));
    float rs = (ei*ci-et*ct)/max(ei*ci+et*ct,0.000001);
    float rp = (et*ci-ei*ct)/max(et*ci+ei*ct,0.000001);
    return clamp(0.5*(rs*rs+rp*rp),0.0,1.0);
}
// Beer-Lambert RGB transmittance exp(-extinction*pathLength). Negative extinction/path is clamped to zero. Use the refracted optical path, not vertical water depth. Attenuation alone does not add scattered light.
vec3 beerTransmittance(vec3 extinction, float pathLength) {
    return exp(-max(extinction,vec3(0.0))*max(pathLength,0.0));
}

// ---- shader-skills library: color ----
// Exact sRGB decode (EOTF): encoded [0,1] -> linear.
vec3 srgbToLinear(vec3 c) {
    c = max(c, 0.0);
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
// Exact sRGB encode (OETF): linear -> display [0,1]. Apply exactly once, after tonemapping. pow(c, 1/2.2) is visibly wrong near black (0.001 encodes to 0.013 here vs 0.043 with 2.2).
vec3 linearToSrgb(vec3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
// Relative luminance of linear Rec.709 / sRGB color.
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
// Linear sRGB -> Oklab (L in [0,1], a/b around [-0.4, 0.4]). Matrices from Bjorn Ottosson (public domain / MIT).
vec3 linearSrgbToOklab(vec3 c) {
    vec3 lms = c * mat3(0.4122214708, 0.5363325363, 0.0514459929,
                        0.2119034982, 0.6806995451, 0.1073969566,
                        0.0883024619, 0.2817188376, 0.6299787005);
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return lms * mat3(0.2104542553, 0.7936177850, -0.0040720468,
                      1.9779984951, -2.4285922050, 0.4505937099,
                      0.0259040371, 0.7827717662, -0.8086757660);
}
// Oklab -> linear sRGB. The result can fall outside [0,1] for saturated colors, so clamp after tonemapping.
vec3 oklabToLinearSrgb(vec3 lab) {
    vec3 lms = lab * mat3(1.0, 0.3963377774, 0.2158037573,
                          1.0, -0.1055613458, -0.0638541728,
                          1.0, -0.0894841775, -1.2914855480);
    lms = lms * lms * lms;
    return lms * mat3(4.0767416621, -3.3077115913, 0.2309699292,
                      -1.2684380046, 2.6097574011, -0.3413193965,
                      -0.0041960863, -0.7034186147, 1.7076147010);
}
// Mix two linear colors in Oklab. Avoids the muddy mid-tones of RGB lerps and the hue detours of HSV.
vec3 mixOklab(vec3 a, vec3 b, float t) {
    return oklabToLinearSrgb(mix(linearSrgbToOklab(a), linearSrgbToOklab(b), t));
}
// Approximate linear sRGB color of a blackbody at temperature kelvin (1000-15000 K), normalized to max channel 1. Uses the Krystek (1985) Planckian-locus fit -> XYZ -> sRGB.
vec3 blackbody(float kelvin) {
    float T = clamp(kelvin, 1000.0, 15000.0);
    float u = (0.860117757 + 1.54118254e-4 * T + 1.28641212e-7 * T * T) / (1.0 + 8.42420235e-4 * T + 7.08145163e-7 * T * T);
    float v = (0.317398726 + 4.22806245e-5 * T + 4.20481691e-8 * T * T) / (1.0 - 2.89741816e-5 * T + 1.61456053e-7 * T * T);
    float x = 3.0 * u / (2.0 * u - 8.0 * v + 4.0);
    float y = 2.0 * v / (2.0 * u - 8.0 * v + 4.0);
    vec3 xyz = vec3(x / y, 1.0, (1.0 - x - y) / y);
    vec3 rgb = xyz * mat3(3.2406, -1.5372, -0.4986,
                          -0.9689, 1.8758, 0.0415,
                          0.0557, -0.2040, 1.0570);
    rgb = max(rgb, 0.0);
    return rgb / max(max(rgb.r, rgb.g), max(rgb.b, 1e-6));
}

// ---- shader-skills library: tonemap ----
// Stephen Hill's ACES fit (RRT + ODT, sRGB primaries). Contrasty and saturated; blues drift purple when very bright. Darker than AgX at the same exposure: multiply the input by about 1.6 to compensate.
vec3 tonemapACES(vec3 c) {
    c = max(c, 0.0) * mat3(0.59719, 0.35458, 0.04823,
                           0.07600, 0.90834, 0.01566,
                           0.02840, 0.13383, 0.83777);
    c = (c * (c + 0.0245786) - 0.000090537) / (c * (0.983729 * c + 0.4329510) + 0.238081);
    c = c * mat3(1.60475, -0.53108, -0.07367,
                 -0.10208, 1.10813, -0.00605,
                 -0.00327, -0.07276, 1.07602);
    return clamp(c, 0.0, 1.0);
}

// ---- shader-skills library: volume ----
// One energy-conserving step of volume integration. sigmaT is extinction per unit length (RGB for tinted media), inScatter is in-scattered radiance at this point (including sigmaS, phase and light), ds is step length. Accumulates into radiance and transmittance. Stable for dense media, unlike radiance += T * S * ds.
void volumeStep(inout vec3 radiance, inout vec3 transmittance, vec3 sigmaT, vec3 inScatter, float ds) {
    vec3 stepT = exp(-sigmaT * ds);
    vec3 integral = (inScatter - inScatter * stepT) / max(sigmaT, vec3(1e-7));
    radiance += transmittance * integral;
    transmittance *= stepT;
}

// ---- shader-skills library: post ----
// Subpixel offset in [-0.5, 0.5)^2 for sample i of a supersampling loop (R2 low-discrepancy sequence). Better coverage than a regular grid for any sample count.
vec2 aaOffset(int i) {
    return fract(0.5 + float(i) * vec2(0.7548776662, 0.5698402910)) - 0.5;
}
// Natural (cos^4) vignette for a pinhole camera: uv is the screen point, focal the camera focal length. Wider lenses vignette more. Multiply HDR color before tonemapping.
float vignette(vec2 uv, float focal) {
    float f2 = focal * focal;
    float k = f2 / (f2 + dot(uv, uv));
    return k * k;
}
// Triangular-PDF dither of +-1 LSB for 8-bit output. Add AFTER linearToSrgb, right before writing fragColor.
vec3 ditherTPDF(vec2 fragCoord, int frame) {
    vec2 r = hash22(vec2(floor(fragCoord) + 7919.0 * float(frame % 1024)));
    return vec3((r.x + r.y - 1.0) / 255.0);
}

// ---- shader-skills library: debug ----
// Distance field as contour bands: warm outside, cool inside, white zero line. Bands are 0.1 units apart.
vec3 debugDistance(float d) {
    vec3 col = (d > 0.0) ? vec3(0.9, 0.6, 0.3) : vec3(0.4, 0.7, 0.85);
    col *= 1.0 - exp(-4.0 * abs(d));
    col *= 0.8 + 0.2 * cos(TAU * d / 0.1);
    return mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.01, abs(d)));
}
// Distinct color per integer id.
vec3 debugIdColor(float id) {
    return 0.55 + 0.45 * cos(TAU * (0.618034 * id + vec3(0.0, 0.33, 0.67)));
}
// Heat ramp for a value in [0,1]: black, blue, magenta, orange, yellow, white.
vec3 debugHeat(float t) {
    t = clamp(t, 0.0, 1.0);
    return clamp(vec3(1.5 * t, 1.6 * t * t * t - 0.1, 0.9 * sin(PI * t) + 0.2 * t * t), 0.0, 1.0);
}

// ---- shader ----
// ---- Master Film & Art Direction Controls ----
const float LOOP_SECONDS = 20.0;
const float ACT_DURATION = 5.0;
const float DISSOLVE_DUR = 0.60;
const float OMEGA = 0.3141592653589793; // TAU / 20.0: exact fundamental angular frequency for C^inf loop

// Material IDs across the 4 acts
const float MAT_TERRAIN  = 1.0;
const float MAT_MONOLITH = 2.0;
const float MAT_CRYSTAL  = 3.0;
const float MAT_BUILDING = 4.0;
const float MAT_CROWN    = 5.0;
const float MAT_STREET   = 6.0;
const float MAT_BASALT   = 7.0;

// Act I constants (calibrated to act1_coast.mp4 camera optics, horizon, ring scale & swatches)
const vec3  ACT1_SUN_DIR   = vec3(0.0, 0.092, -0.99576);
const vec3  ACT1_RING_POS  = vec3(0.0, 4.45, -28.0);
const vec2  ACT1_RING_DIM  = vec2(4.42, 0.88);
const vec3  ACT1_WATER_EXT = vec3(0.56, 0.125, 0.145);

// Act II constants (sun from upper-left so LEFT canyon wall is dark slate shadow & RIGHT snow wall is warm gold!)
const vec3  ACT2_SUN_DIR   = vec3(-0.805, 0.445, 0.392);
const vec3  ACT2_OBELISK   = vec3(0.12, -0.45, -16.8);

// Act III constants (calibrated to act3_city.mp4 counter-clockwise twilight downtown orbit)
const float ACT3_PARCEL    = 4.2;

// Act IV constants (calibrated to act4_eclipse.mp4 central solar eclipse & basalt colonnade channel)
const vec3  ACT4_SUN_DIR   = vec3(-0.0085, 0.118, -0.99298);
const float ACT4_CORRIDOR  = 4.45;

// =================================================================================================
// CLEAN INVERSE-RENDERED ATMOSPHERIC RADIANCE DOMES (FOREGROUND-STRIPPED 24x12 HEMISPHERES)
// Evaluated via O(1) bilinear interpolation in world/dome ray coordinates, zero textures used.
// =================================================================================================

const int DOME_W = 24;
const int DOME_H = 12;

const vec4 DOME_ACT1[288] = vec4[288](
    vec4(0.0499, 0.0540, 0.0358, 1.0000), vec4(0.0391, 0.0425, 0.0290, 1.0000), vec4(0.0461, 0.0486, 0.0318, 1.0000),
    vec4(0.0461, 0.0461, 0.0299, 1.0000), vec4(0.0612, 0.0582, 0.0358, 1.0000), vec4(0.1260, 0.1086, 0.0691, 1.0000),
    vec4(0.1644, 0.1369, 0.0872, 1.0000), vec4(0.1746, 0.1456, 0.0953, 1.0000), vec4(0.2397, 0.1929, 0.1234, 1.0000),
    vec4(0.6293, 0.4364, 0.2543, 1.0000), vec4(1.0319, 0.6898, 0.3421, 1.0000), vec4(0.5163, 0.3939, 0.2173, 1.0000),
    vec4(0.3287, 0.2645, 0.1456, 1.0000), vec4(0.4948, 0.3490, 0.1818, 1.0000), vec4(0.4455, 0.3097, 0.1782, 1.0000),
    vec4(0.1818, 0.1426, 0.0912, 1.0000), vec4(0.1426, 0.1183, 0.0760, 1.0000), vec4(0.1158, 0.1018, 0.0643, 1.0000),
    vec4(0.0725, 0.0708, 0.0461, 1.0000), vec4(0.0540, 0.0597, 0.0369, 1.0000), vec4(0.0513, 0.0540, 0.0338, 1.0000),
    vec4(0.0659, 0.0612, 0.0369, 1.0000), vec4(0.0742, 0.0691, 0.0437, 1.0000), vec4(0.0796, 0.0742, 0.0474, 1.0000),
    vec4(0.0499, 0.0413, 0.0263, 1.0000), vec4(0.0449, 0.0380, 0.0238, 1.0000), vec4(0.0449, 0.0380, 0.0246, 1.0000),
    vec4(0.0402, 0.0348, 0.0215, 1.0000), vec4(0.0513, 0.0425, 0.0255, 1.0000), vec4(0.1341, 0.1018, 0.0568, 1.0000),
    vec4(0.3707, 0.2543, 0.1286, 1.0000), vec4(0.4275, 0.2919, 0.1486, 1.0000), vec4(0.8161, 0.5163, 0.2445, 1.0000),
    vec4(2.3558, 1.2260, 0.4455, 1.0000), vec4(0.9031, 0.6586, 0.3421, 1.0000), vec4(0.1397, 0.1234, 0.0778, 1.0000),
    vec4(0.1158, 0.0996, 0.0597, 1.0000), vec4(0.6016, 0.3939, 0.1968, 1.0000), vec4(1.3032, 0.7061, 0.3097, 1.0000),
    vec4(0.5509, 0.3561, 0.1782, 1.0000), vec4(0.3223, 0.2216, 0.1183, 1.0000), vec4(0.1063, 0.0833, 0.0486, 1.0000),
    vec4(0.0449, 0.0369, 0.0230, 1.0000), vec4(0.0449, 0.0369, 0.0246, 1.0000), vec4(0.0499, 0.0402, 0.0263, 1.0000),
    vec4(0.0513, 0.0425, 0.0281, 1.0000), vec4(0.0554, 0.0461, 0.0299, 1.0000), vec4(0.0540, 0.0461, 0.0290, 1.0000),
    vec4(0.1369, 0.1040, 0.0582, 1.0000), vec4(0.1286, 0.0974, 0.0568, 1.0000), vec4(0.1397, 0.1063, 0.0612, 1.0000),
    vec4(0.1369, 0.1040, 0.0597, 1.0000), vec4(0.3421, 0.2397, 0.1286, 1.0000), vec4(0.7229, 0.4364, 0.2088, 1.0000),
    vec4(1.1900, 0.6437, 0.2806, 1.0000), vec4(1.7683, 0.8580, 0.3490, 1.0000), vec4(1.9862, 0.9516, 0.3707, 1.0000),
    vec4(3.0115, 1.9862, 0.6152, 1.0000), vec4(0.3561, 0.2977, 0.1782, 1.0000), vec4(0.8580, 0.6739, 0.3490, 1.0000),
    vec4(0.7962, 0.6016, 0.3097, 1.0000), vec4(0.3159, 0.2445, 0.1369, 1.0000), vec4(2.0689, 0.9774, 0.3783, 1.0000),
    vec4(1.1227, 0.6293, 0.2751, 1.0000), vec4(0.9269, 0.5275, 0.2445, 1.0000), vec4(0.5509, 0.3561, 0.1818, 1.0000),
    vec4(0.2048, 0.1548, 0.0892, 1.0000), vec4(0.0892, 0.0725, 0.0461, 1.0000), vec4(0.0833, 0.0691, 0.0449, 1.0000),
    vec4(0.0796, 0.0659, 0.0425, 1.0000), vec4(0.0996, 0.0796, 0.0486, 1.0000), vec4(0.1486, 0.1183, 0.0708, 1.0000),
    vec4(0.2751, 0.2088, 0.1260, 1.0000), vec4(0.3561, 0.2543, 0.1486, 1.0000), vec4(0.4645, 0.3223, 0.1782, 1.0000),
    vec4(0.5509, 0.4364, 0.2445, 1.0000), vec4(0.7229, 0.5390, 0.2862, 1.0000), vec4(0.6898, 0.4743, 0.2594, 1.0000),
    vec4(0.8801, 0.5755, 0.3159, 1.0000), vec4(1.0609, 0.6898, 0.3633, 1.0000), vec4(1.5871, 0.9774, 0.4948, 1.0000),
    vec4(3.0115, 1.7043, 0.7061, 1.0000), vec4(0.3223, 0.2594, 0.1712, 1.0000), vec4(1.4341, 1.1900, 0.6898, 1.0000),
    vec4(1.2260, 0.9516, 0.5275, 1.0000), vec4(0.2645, 0.2088, 0.1369, 1.0000), vec4(1.5333, 0.9516, 0.4743, 1.0000),
    vec4(0.8580, 0.5884, 0.3287, 1.0000), vec4(0.6016, 0.4103, 0.2397, 1.0000), vec4(0.5163, 0.3939, 0.2351, 1.0000),
    vec4(0.6016, 0.4743, 0.2645, 1.0000), vec4(0.5630, 0.3860, 0.2130, 1.0000), vec4(0.3561, 0.2543, 0.1486, 1.0000),
    vec4(0.2698, 0.2088, 0.1313, 1.0000), vec4(0.2130, 0.1892, 0.1234, 1.0000), vec4(0.2305, 0.1968, 0.1208, 1.0000),
    vec4(0.3097, 0.2260, 0.1341, 1.0000), vec4(0.3633, 0.2698, 0.1612, 1.0000), vec4(0.4364, 0.3354, 0.2007, 1.0000),
    vec4(0.4020, 0.3860, 0.2543, 1.0000), vec4(0.4020, 0.3490, 0.2260, 1.0000), vec4(0.4645, 0.3421, 0.2088, 1.0000),
    vec4(0.7229, 0.4844, 0.2751, 1.0000), vec4(1.2260, 0.7962, 0.4275, 1.0000), vec4(1.4341, 1.0041, 0.5630, 1.0000),
    vec4(3.0115, 1.9088, 0.9031, 1.0000), vec4(0.3783, 0.3287, 0.2351, 1.0000), vec4(0.4549, 0.4103, 0.3037, 1.0000),
    vec4(0.4103, 0.3633, 0.2594, 1.0000), vec4(0.2698, 0.2260, 0.1612, 1.0000), vec4(1.3883, 0.9774, 0.5390, 1.0000),
    vec4(0.6739, 0.4844, 0.2919, 1.0000), vec4(0.5755, 0.3939, 0.2351, 1.0000), vec4(0.3354, 0.2645, 0.1746, 1.0000),
    vec4(0.3561, 0.3561, 0.2445, 1.0000), vec4(0.3561, 0.3490, 0.2305, 1.0000), vec4(0.3490, 0.3037, 0.1929, 1.0000),
    vec4(0.3421, 0.2698, 0.1678, 1.0000), vec4(0.2445, 0.2007, 0.1286, 1.0000), vec4(0.1678, 0.1456, 0.0996, 1.0000),
    vec4(0.3223, 0.2305, 0.1369, 1.0000), vec4(0.3490, 0.2862, 0.1818, 1.0000), vec4(0.3037, 0.2543, 0.1678, 1.0000),
    vec4(0.2130, 0.1929, 0.1456, 1.0000), vec4(0.1517, 0.1341, 0.1040, 1.0000), vec4(0.2751, 0.2088, 0.1397, 1.0000),
    vec4(0.8801, 0.5884, 0.3490, 1.0000), vec4(0.8367, 0.6293, 0.4020, 1.0000), vec4(1.0609, 0.7583, 0.4844, 1.0000),
    vec4(1.9862, 1.4341, 0.8367, 1.0000), vec4(1.1227, 0.9516, 0.6437, 1.0000), vec4(0.1086, 0.0996, 0.0796, 1.0000),
    vec4(0.1040, 0.0912, 0.0691, 1.0000), vec4(0.7583, 0.5884, 0.3860, 1.0000), vec4(1.4824, 0.9516, 0.5275, 1.0000),
    vec4(0.4844, 0.3354, 0.2048, 1.0000), vec4(0.2977, 0.2305, 0.1579, 1.0000), vec4(0.3633, 0.3490, 0.2645, 1.0000),
    vec4(0.3097, 0.3421, 0.2806, 1.0000), vec4(0.2698, 0.2977, 0.2397, 1.0000), vec4(0.1968, 0.2445, 0.2048, 1.0000),
    vec4(0.2007, 0.2305, 0.1892, 1.0000), vec4(0.3287, 0.2351, 0.1486, 1.0000), vec4(0.2305, 0.1612, 0.1040, 1.0000),
    vec4(0.1746, 0.1746, 0.1341, 1.0000), vec4(0.1486, 0.1818, 0.1678, 1.0000), vec4(0.1818, 0.2216, 0.2048, 1.0000),
    vec4(0.1782, 0.2173, 0.2007, 1.0000), vec4(0.1929, 0.1782, 0.1456, 1.0000), vec4(0.3490, 0.3037, 0.2305, 1.0000),
    vec4(0.6586, 0.5630, 0.4103, 1.0000), vec4(0.8367, 0.7061, 0.5054, 1.0000), vec4(1.1556, 0.8801, 0.5755, 1.0000),
    vec4(1.3883, 1.0609, 0.6739, 1.0000), vec4(2.1577, 1.5871, 0.9269, 1.0000), vec4(0.6437, 0.5630, 0.4188, 1.0000),
    vec4(0.5390, 0.4455, 0.3287, 1.0000), vec4(0.9031, 0.6586, 0.4275, 1.0000), vec4(0.8367, 0.6739, 0.4645, 1.0000),
    vec4(0.8801, 0.6152, 0.3860, 1.0000), vec4(0.3783, 0.2645, 0.1678, 1.0000), vec4(0.2007, 0.1782, 0.1369, 1.0000),
    vec4(0.2977, 0.2445, 0.1746, 1.0000), vec4(0.2493, 0.2698, 0.2260, 1.0000), vec4(0.1782, 0.2216, 0.2088, 1.0000),
    vec4(0.1397, 0.1854, 0.1854, 1.0000), vec4(0.1313, 0.1712, 0.1612, 1.0000), vec4(0.1548, 0.1644, 0.1369, 1.0000),
    vec4(0.2048, 0.1678, 0.1183, 1.0000), vec4(0.1208, 0.1644, 0.1712, 1.0000), vec4(0.1369, 0.1929, 0.2048, 1.0000),
    vec4(0.1854, 0.2397, 0.2445, 1.0000), vec4(0.4020, 0.3707, 0.2751, 1.0000), vec4(0.7583, 0.5509, 0.3561, 1.0000),
    vec4(0.6293, 0.4844, 0.3287, 1.0000), vec4(0.8161, 0.5054, 0.2751, 1.0000), vec4(1.2637, 0.7962, 0.4455, 1.0000),
    vec4(1.7043, 1.1227, 0.6437, 1.0000), vec4(1.7683, 1.1556, 0.6293, 1.0000), vec4(1.6440, 1.1900, 0.7769, 1.0000),
    vec4(0.8367, 0.6898, 0.5630, 1.0000), vec4(0.5275, 0.4948, 0.4364, 1.0000), vec4(0.4549, 0.4455, 0.4020, 1.0000),
    vec4(0.3783, 0.3783, 0.3421, 1.0000), vec4(0.5054, 0.3939, 0.2806, 1.0000), vec4(0.2048, 0.1612, 0.1208, 1.0000),
    vec4(0.1579, 0.1397, 0.1134, 1.0000), vec4(0.1517, 0.1818, 0.1782, 1.0000), vec4(0.1158, 0.1712, 0.1929, 1.0000),
    vec4(0.1234, 0.1678, 0.1746, 1.0000), vec4(0.1341, 0.1579, 0.1517, 1.0000), vec4(0.1678, 0.1644, 0.1341, 1.0000),
    vec4(0.2698, 0.2351, 0.1712, 1.0000), vec4(0.1234, 0.1644, 0.1712, 1.0000), vec4(0.3354, 0.2977, 0.2260, 1.0000),
    vec4(0.2806, 0.2493, 0.1968, 1.0000), vec4(0.3037, 0.2173, 0.1397, 1.0000), vec4(0.4364, 0.2751, 0.1517, 1.0000),
    vec4(0.4455, 0.3223, 0.2130, 1.0000), vec4(0.4743, 0.3287, 0.2048, 1.0000), vec4(0.9269, 0.6293, 0.3783, 1.0000),
    vec4(0.9269, 0.6739, 0.4275, 1.0000), vec4(1.0609, 0.7229, 0.4364, 1.0000), vec4(0.7962, 0.6739, 0.5390, 1.0000),
    vec4(0.5509, 0.4948, 0.4275, 1.0000), vec4(0.4364, 0.4188, 0.3860, 1.0000), vec4(0.3490, 0.3561, 0.3490, 1.0000),
    vec4(0.2351, 0.2751, 0.2977, 1.0000), vec4(0.2130, 0.2594, 0.2751, 1.0000), vec4(0.2645, 0.2645, 0.2260, 1.0000),
    vec4(0.1110, 0.1644, 0.1929, 1.0000), vec4(0.0912, 0.1397, 0.1678, 1.0000), vec4(0.0814, 0.1369, 0.1712, 1.0000),
    vec4(0.0725, 0.1208, 0.1517, 1.0000), vec4(0.1040, 0.1341, 0.1397, 1.0000), vec4(0.3159, 0.2130, 0.1286, 1.0000),
    vec4(0.1158, 0.1426, 0.1456, 1.0000), vec4(0.1208, 0.1517, 0.1678, 1.0000), vec4(0.2130, 0.1968, 0.1612, 1.0000),
    vec4(0.1517, 0.1208, 0.0892, 1.0000), vec4(0.1426, 0.1134, 0.0814, 1.0000), vec4(0.2445, 0.1746, 0.1134, 1.0000),
    vec4(0.3354, 0.2493, 0.1678, 1.0000), vec4(0.4188, 0.3490, 0.2698, 1.0000), vec4(0.6293, 0.5275, 0.4103, 1.0000),
    vec4(0.4645, 0.4275, 0.3783, 1.0000), vec4(0.4549, 0.4103, 0.3707, 1.0000), vec4(0.4020, 0.3783, 0.3561, 1.0000),
    vec4(0.4275, 0.4020, 0.3707, 1.0000), vec4(0.3939, 0.3783, 0.3633, 1.0000), vec4(0.2698, 0.2862, 0.2977, 1.0000),
    vec4(0.1818, 0.2260, 0.2543, 1.0000), vec4(0.1260, 0.1818, 0.2216, 1.0000), vec4(0.1110, 0.1678, 0.2130, 1.0000),
    vec4(0.0833, 0.1397, 0.1892, 1.0000), vec4(0.0675, 0.1208, 0.1678, 1.0000), vec4(0.0643, 0.1110, 0.1517, 1.0000),
    vec4(0.0627, 0.1040, 0.1426, 1.0000), vec4(0.0474, 0.0872, 0.1260, 1.0000), vec4(0.1040, 0.1234, 0.1234, 1.0000),
    vec4(0.0814, 0.1110, 0.1313, 1.0000), vec4(0.0996, 0.1286, 0.1426, 1.0000), vec4(0.1063, 0.1286, 0.1369, 1.0000),
    vec4(0.1286, 0.1110, 0.0912, 1.0000), vec4(0.1644, 0.1313, 0.0974, 1.0000), vec4(0.3783, 0.2751, 0.1818, 1.0000),
    vec4(0.2493, 0.2305, 0.2007, 1.0000), vec4(0.3287, 0.3159, 0.2862, 1.0000), vec4(0.5884, 0.4844, 0.3707, 1.0000),
    vec4(0.2806, 0.2751, 0.2751, 1.0000), vec4(0.4455, 0.3783, 0.3159, 1.0000), vec4(0.5755, 0.4844, 0.3783, 1.0000),
    vec4(0.2645, 0.2751, 0.2862, 1.0000), vec4(0.2216, 0.2493, 0.2698, 1.0000), vec4(0.1712, 0.2048, 0.2397, 1.0000),
    vec4(0.1486, 0.1892, 0.2260, 1.0000), vec4(0.1040, 0.1548, 0.2007, 1.0000), vec4(0.0833, 0.1313, 0.1782, 1.0000),
    vec4(0.0778, 0.1260, 0.1678, 1.0000), vec4(0.0568, 0.1018, 0.1456, 1.0000), vec4(0.0474, 0.0892, 0.1313, 1.0000),
    vec4(0.0402, 0.0796, 0.1208, 1.0000), vec4(0.0380, 0.0742, 0.1134, 1.0000), vec4(0.0348, 0.0675, 0.0996, 1.0000),
    vec4(0.0742, 0.0996, 0.1183, 1.0000), vec4(0.0814, 0.0932, 0.0996, 1.0000), vec4(0.0872, 0.1086, 0.1234, 1.0000),
    vec4(0.1040, 0.1260, 0.1369, 1.0000), vec4(0.2007, 0.1818, 0.1548, 1.0000), vec4(0.2862, 0.2645, 0.2173, 1.0000),
    vec4(0.1183, 0.1579, 0.2007, 1.0000), vec4(0.2130, 0.2260, 0.2305, 1.0000), vec4(0.6739, 0.4743, 0.3097, 1.0000),
    vec4(0.4188, 0.3223, 0.2305, 1.0000), vec4(0.7229, 0.5163, 0.3354, 1.0000), vec4(1.0041, 0.7061, 0.4455, 1.0000),
    vec4(0.2088, 0.2305, 0.2445, 1.0000), vec4(0.1486, 0.1854, 0.2216, 1.0000), vec4(0.1260, 0.1678, 0.2048, 1.0000),
    vec4(0.1183, 0.1548, 0.1929, 1.0000), vec4(0.0833, 0.1286, 0.1746, 1.0000), vec4(0.0675, 0.1134, 0.1579, 1.0000),
    vec4(0.0627, 0.1040, 0.1486, 1.0000), vec4(0.0513, 0.0912, 0.1369, 1.0000), vec4(0.0449, 0.0814, 0.1234, 1.0000),
    vec4(0.0338, 0.0708, 0.1086, 1.0000), vec4(0.0281, 0.0612, 0.0953, 1.0000), vec4(0.0281, 0.0568, 0.0892, 1.0000)
);

const vec4 DOME_ACT2[288] = vec4[288](
    vec4(0.0571, 0.0742, 0.0869, 1.0000), vec4(0.0571, 0.0742, 0.0869, 1.0000), vec4(0.0571, 0.0742, 0.0869, 1.0000),
    vec4(0.0585, 0.0742, 0.0869, 1.0000), vec4(0.0585, 0.0759, 0.0869, 1.0000), vec4(0.0600, 0.0759, 0.0889, 1.0000),
    vec4(0.0600, 0.0777, 0.0889, 1.0000), vec4(0.0600, 0.0777, 0.0889, 1.0000), vec4(0.0557, 0.0725, 0.0850, 1.0000),
    vec4(0.0629, 0.0813, 0.0909, 1.0000), vec4(0.0530, 0.0850, 0.1126, 1.0000), vec4(0.0813, 0.1729, 0.2026, 1.0000),
    vec4(0.1303, 0.2466, 0.2466, 1.0000), vec4(0.1103, 0.1358, 0.1473, 1.0000), vec4(0.1276, 0.1596, 0.1661, 1.0000),
    vec4(0.1386, 0.1695, 0.1729, 1.0000), vec4(0.1443, 0.1764, 0.1799, 1.0000), vec4(0.1503, 0.1835, 0.1835, 1.0000),
    vec4(0.1473, 0.1799, 0.1835, 1.0000), vec4(0.1473, 0.1799, 0.1835, 1.0000), vec4(0.1473, 0.1799, 0.1835, 1.0000),
    vec4(0.1473, 0.1799, 0.1835, 1.0000), vec4(0.1473, 0.1799, 0.1835, 1.0000), vec4(0.1473, 0.1799, 0.1835, 1.0000),
    vec4(0.0516, 0.0759, 0.0929, 1.0000), vec4(0.0516, 0.0759, 0.0949, 1.0000), vec4(0.0516, 0.0777, 0.0949, 1.0000),
    vec4(0.0530, 0.0777, 0.0970, 1.0000), vec4(0.0530, 0.0795, 0.0991, 1.0000), vec4(0.0530, 0.0795, 0.0991, 1.0000),
    vec4(0.0543, 0.0831, 0.1035, 1.0000), vec4(0.0516, 0.0795, 0.1013, 1.0000), vec4(0.1080, 0.1358, 0.1503, 1.0000),
    vec4(0.1250, 0.1596, 0.1729, 1.0000), vec4(0.2235, 0.3254, 0.3457, 1.0000), vec4(0.2776, 0.4919, 0.4613, 1.0000),
    vec4(0.2192, 0.3986, 0.3826, 1.0000), vec4(0.2722, 0.3457, 0.3388, 1.0000), vec4(0.2466, 0.3190, 0.3320, 1.0000),
    vec4(0.2776, 0.3527, 0.3527, 1.0000), vec4(0.2026, 0.2515, 0.2565, 1.0000), vec4(0.1835, 0.2280, 0.2325, 1.0000),
    vec4(0.1947, 0.2371, 0.2466, 1.0000), vec4(0.1909, 0.2371, 0.2418, 1.0000), vec4(0.1909, 0.2371, 0.2466, 1.0000),
    vec4(0.1909, 0.2371, 0.2466, 1.0000), vec4(0.1909, 0.2371, 0.2466, 1.0000), vec4(0.1909, 0.2371, 0.2466, 1.0000),
    vec4(0.0503, 0.0759, 0.0949, 1.0000), vec4(0.0491, 0.0759, 0.0949, 1.0000), vec4(0.0491, 0.0742, 0.0949, 1.0000),
    vec4(0.0491, 0.0759, 0.0970, 1.0000), vec4(0.0478, 0.0759, 0.0970, 1.0000), vec4(0.0466, 0.0759, 0.1013, 1.0000),
    vec4(0.0491, 0.0813, 0.1080, 1.0000), vec4(0.1225, 0.1799, 0.2066, 1.0000), vec4(0.3986, 0.5366, 0.5366, 1.0000),
    vec4(0.3527, 0.4423, 0.4331, 1.0000), vec4(0.3826, 0.5610, 0.5366, 1.0000), vec4(0.3320, 0.5867, 0.5737, 1.0000),
    vec4(0.3190, 0.5610, 0.5610, 1.0000), vec4(0.4154, 0.6284, 0.6002, 1.0000), vec4(0.3986, 0.5366, 0.5026, 1.0000),
    vec4(0.3748, 0.5486, 0.5250, 1.0000), vec4(0.2325, 0.3005, 0.3005, 1.0000), vec4(0.1103, 0.1386, 0.1473, 1.0000),
    vec4(0.0850, 0.1126, 0.1276, 1.0000), vec4(0.1175, 0.1443, 0.1533, 1.0000), vec4(0.1150, 0.1386, 0.1443, 1.0000),
    vec4(0.1150, 0.1386, 0.1443, 1.0000), vec4(0.1150, 0.1386, 0.1443, 1.0000), vec4(0.1150, 0.1386, 0.1443, 1.0000),
    vec4(0.0530, 0.0759, 0.0949, 1.0000), vec4(0.0530, 0.0777, 0.1013, 1.0000), vec4(0.0543, 0.0850, 0.1150, 1.0000),
    vec4(0.0557, 0.0795, 0.1013, 1.0000), vec4(0.0557, 0.0795, 0.0991, 1.0000), vec4(0.0777, 0.1103, 0.1330, 1.0000),
    vec4(0.1103, 0.1661, 0.1947, 1.0000), vec4(0.2669, 0.4919, 0.5486, 1.0000), vec4(0.3673, 0.6141, 0.6432, 1.0000),
    vec4(0.3748, 0.5366, 0.5610, 1.0000), vec4(0.2776, 0.5026, 0.5610, 1.0000), vec4(0.2669, 0.5250, 0.6141, 1.0000),
    vec4(0.2669, 0.5250, 0.6141, 1.0000), vec4(0.2722, 0.5136, 0.5867, 1.0000), vec4(0.3065, 0.5136, 0.5610, 1.0000),
    vec4(0.2776, 0.5136, 0.5867, 1.0000), vec4(0.3127, 0.5737, 0.6284, 1.0000), vec4(0.2371, 0.3320, 0.3388, 1.0000),
    vec4(0.0795, 0.1035, 0.1200, 1.0000), vec4(0.0759, 0.0949, 0.1057, 1.0000), vec4(0.1013, 0.1200, 0.1276, 1.0000),
    vec4(0.1013, 0.1200, 0.1303, 1.0000), vec4(0.1013, 0.1200, 0.1276, 1.0000), vec4(0.1013, 0.1200, 0.1276, 1.0000),
    vec4(0.0516, 0.0850, 0.1175, 1.0000), vec4(0.0571, 0.0970, 0.1386, 1.0000), vec4(0.0600, 0.0970, 0.1330, 1.0000),
    vec4(0.0600, 0.0850, 0.1103, 1.0000), vec4(0.0557, 0.0869, 0.1126, 1.0000), vec4(0.2026, 0.3254, 0.3748, 1.0000),
    vec4(0.3190, 0.5136, 0.5610, 1.0000), vec4(0.2280, 0.4613, 0.5737, 1.0000), vec4(0.2149, 0.4331, 0.5486, 1.0000),
    vec4(0.2325, 0.4517, 0.5610, 1.0000), vec4(0.2669, 0.4814, 0.5737, 1.0000), vec4(0.2066, 0.4331, 0.5486, 1.0000),
    vec4(0.1909, 0.4154, 0.5486, 1.0000), vec4(0.1986, 0.4242, 0.5366, 1.0000), vec4(0.2192, 0.4331, 0.5366, 1.0000),
    vec4(0.2722, 0.4517, 0.5026, 1.0000), vec4(0.2235, 0.4613, 0.5867, 1.0000), vec4(0.2280, 0.4242, 0.5026, 1.0000),
    vec4(0.1200, 0.1443, 0.1503, 1.0000), vec4(0.0970, 0.1150, 0.1225, 1.0000), vec4(0.1126, 0.1386, 0.1443, 1.0000),
    vec4(0.1200, 0.1473, 0.1533, 1.0000), vec4(0.1200, 0.1443, 0.1533, 1.0000), vec4(0.1200, 0.1443, 0.1533, 1.0000),
    vec4(0.0614, 0.1035, 0.1443, 1.0000), vec4(0.0543, 0.0831, 0.1080, 1.0000), vec4(0.0571, 0.0831, 0.1080, 1.0000),
    vec4(0.0629, 0.0813, 0.0991, 1.0000), vec4(0.1103, 0.1909, 0.2515, 1.0000), vec4(0.2616, 0.4814, 0.6002, 1.0000),
    vec4(0.2325, 0.4069, 0.5136, 1.0000), vec4(0.1947, 0.3905, 0.5136, 1.0000), vec4(0.1799, 0.3748, 0.5136, 1.0000),
    vec4(0.1872, 0.3748, 0.5136, 1.0000), vec4(0.1909, 0.3748, 0.5026, 1.0000), vec4(0.1596, 0.3527, 0.4919, 1.0000),
    vec4(0.1473, 0.3457, 0.4919, 1.0000), vec4(0.1503, 0.3527, 0.4919, 1.0000), vec4(0.1596, 0.3599, 0.4919, 1.0000),
    vec4(0.1947, 0.3748, 0.4814, 1.0000), vec4(0.1764, 0.3748, 0.5026, 1.0000), vec4(0.1909, 0.3986, 0.5486, 1.0000),
    vec4(0.1909, 0.3254, 0.3826, 1.0000), vec4(0.1799, 0.2192, 0.2280, 1.0000), vec4(0.1473, 0.1799, 0.1872, 1.0000),
    vec4(0.1695, 0.1986, 0.1986, 1.0000), vec4(0.1628, 0.1947, 0.1986, 1.0000), vec4(0.1628, 0.1947, 0.1986, 1.0000),
    vec4(0.0813, 0.1386, 0.1909, 1.0000), vec4(0.0742, 0.1126, 0.1473, 1.0000), vec4(0.0629, 0.0970, 0.1250, 1.0000),
    vec4(0.0692, 0.1035, 0.1330, 1.0000), vec4(0.1695, 0.3190, 0.4242, 1.0000), vec4(0.1872, 0.3748, 0.5136, 1.0000),
    vec4(0.1564, 0.3320, 0.4613, 1.0000), vec4(0.1729, 0.3527, 0.4814, 1.0000), vec4(0.1443, 0.3254, 0.4613, 1.0000),
    vec4(0.1276, 0.3065, 0.4423, 1.0000), vec4(0.1225, 0.3005, 0.4331, 1.0000), vec4(0.1200, 0.3005, 0.4423, 1.0000),
    vec4(0.1175, 0.3005, 0.4423, 1.0000), vec4(0.1175, 0.3005, 0.4423, 1.0000), vec4(0.1175, 0.3065, 0.4517, 1.0000),
    vec4(0.1175, 0.3065, 0.4517, 1.0000), vec4(0.1473, 0.3254, 0.4613, 1.0000), vec4(0.2466, 0.3826, 0.4613, 1.0000),
    vec4(0.2107, 0.3905, 0.5136, 1.0000), vec4(0.2515, 0.3190, 0.3254, 1.0000), vec4(0.1764, 0.2149, 0.2192, 1.0000),
    vec4(0.1729, 0.2325, 0.2466, 1.0000), vec4(0.2026, 0.2565, 0.2616, 1.0000), vec4(0.2026, 0.2515, 0.2515, 1.0000),
    vec4(0.0629, 0.1057, 0.1473, 1.0000), vec4(0.0692, 0.1126, 0.1533, 1.0000), vec4(0.1533, 0.2831, 0.3826, 1.0000),
    vec4(0.1443, 0.2776, 0.3748, 1.0000), vec4(0.1596, 0.3320, 0.4713, 1.0000), vec4(0.1628, 0.3190, 0.4613, 1.0000),
    vec4(0.1564, 0.3127, 0.4517, 1.0000), vec4(0.1386, 0.3005, 0.4331, 1.0000), vec4(0.1303, 0.2831, 0.4242, 1.0000),
    vec4(0.1103, 0.2616, 0.3986, 1.0000), vec4(0.1013, 0.2565, 0.3905, 1.0000), vec4(0.0991, 0.2565, 0.3986, 1.0000),
    vec4(0.0970, 0.2515, 0.3986, 1.0000), vec4(0.0991, 0.2515, 0.3986, 1.0000), vec4(0.1013, 0.2565, 0.4069, 1.0000),
    vec4(0.1035, 0.2616, 0.4154, 1.0000), vec4(0.1080, 0.2722, 0.4154, 1.0000), vec4(0.1150, 0.2776, 0.4154, 1.0000),
    vec4(0.1330, 0.2946, 0.4242, 1.0000), vec4(0.2235, 0.3599, 0.4517, 1.0000), vec4(0.2026, 0.3388, 0.4242, 1.0000),
    vec4(0.1443, 0.3065, 0.4423, 1.0000), vec4(0.1764, 0.3320, 0.4423, 1.0000), vec4(0.2669, 0.3599, 0.3748, 1.0000),
    vec4(0.0600, 0.0970, 0.1303, 1.0000), vec4(0.1150, 0.2107, 0.2888, 1.0000), vec4(0.1628, 0.3457, 0.5026, 1.0000),
    vec4(0.1473, 0.3065, 0.4517, 1.0000), vec4(0.1276, 0.2722, 0.4154, 1.0000), vec4(0.1225, 0.2669, 0.4069, 1.0000),
    vec4(0.1175, 0.2565, 0.3905, 1.0000), vec4(0.1103, 0.2466, 0.3826, 1.0000), vec4(0.0991, 0.2371, 0.3673, 1.0000),
    vec4(0.0909, 0.2235, 0.3599, 1.0000), vec4(0.0850, 0.2192, 0.3599, 1.0000), vec4(0.0813, 0.2192, 0.3527, 1.0000),
    vec4(0.0813, 0.2192, 0.3599, 1.0000), vec4(0.0813, 0.2192, 0.3673, 1.0000), vec4(0.0831, 0.2235, 0.3673, 1.0000),
    vec4(0.0850, 0.2280, 0.3673, 1.0000), vec4(0.0869, 0.2325, 0.3748, 1.0000), vec4(0.0889, 0.2371, 0.3826, 1.0000),
    vec4(0.0909, 0.2418, 0.3826, 1.0000), vec4(0.0929, 0.2466, 0.3826, 1.0000), vec4(0.1200, 0.2722, 0.3986, 1.0000),
    vec4(0.1200, 0.2722, 0.4069, 1.0000), vec4(0.1303, 0.2831, 0.4242, 1.0000), vec4(0.1695, 0.3127, 0.4242, 1.0000),
    vec4(0.1250, 0.2192, 0.2946, 1.0000), vec4(0.1503, 0.2946, 0.4517, 1.0000), vec4(0.1330, 0.2669, 0.4069, 1.0000),
    vec4(0.1225, 0.2565, 0.3905, 1.0000), vec4(0.1103, 0.2466, 0.3826, 1.0000), vec4(0.1013, 0.2325, 0.3673, 1.0000),
    vec4(0.0909, 0.2192, 0.3527, 1.0000), vec4(0.0850, 0.2107, 0.3457, 1.0000), vec4(0.0813, 0.2026, 0.3320, 1.0000),
    vec4(0.0759, 0.1986, 0.3254, 1.0000), vec4(0.0742, 0.1947, 0.3190, 1.0000), vec4(0.0708, 0.1872, 0.3190, 1.0000),
    vec4(0.0692, 0.1872, 0.3254, 1.0000), vec4(0.0692, 0.1872, 0.3254, 1.0000), vec4(0.0708, 0.1909, 0.3190, 1.0000),
    vec4(0.0708, 0.1947, 0.3320, 1.0000), vec4(0.0725, 0.1986, 0.3388, 1.0000), vec4(0.0759, 0.2026, 0.3388, 1.0000),
    vec4(0.0813, 0.2107, 0.3527, 1.0000), vec4(0.0831, 0.2149, 0.3599, 1.0000), vec4(0.1200, 0.2565, 0.3826, 1.0000),
    vec4(0.1330, 0.2722, 0.3905, 1.0000), vec4(0.1200, 0.2565, 0.3905, 1.0000), vec4(0.1200, 0.2616, 0.3905, 1.0000),
    vec4(0.1473, 0.2888, 0.4423, 1.0000), vec4(0.1330, 0.2565, 0.3986, 1.0000), vec4(0.1200, 0.2466, 0.3673, 1.0000),
    vec4(0.1035, 0.2280, 0.3599, 1.0000), vec4(0.0949, 0.2149, 0.3457, 1.0000), vec4(0.0869, 0.2066, 0.3320, 1.0000),
    vec4(0.0813, 0.1947, 0.3254, 1.0000), vec4(0.0742, 0.1872, 0.3127, 1.0000), vec4(0.0692, 0.1799, 0.3065, 1.0000),
    vec4(0.0660, 0.1729, 0.2946, 1.0000), vec4(0.0629, 0.1695, 0.2888, 1.0000), vec4(0.0614, 0.1661, 0.2888, 1.0000),
    vec4(0.0600, 0.1661, 0.2946, 1.0000), vec4(0.0600, 0.1661, 0.2946, 1.0000), vec4(0.0614, 0.1661, 0.3005, 1.0000),
    vec4(0.0629, 0.1695, 0.3127, 1.0000), vec4(0.0629, 0.1729, 0.3127, 1.0000), vec4(0.0660, 0.1799, 0.3190, 1.0000),
    vec4(0.0676, 0.1835, 0.3190, 1.0000), vec4(0.0708, 0.1909, 0.3254, 1.0000), vec4(0.0742, 0.1986, 0.3388, 1.0000),
    vec4(0.0795, 0.2066, 0.3457, 1.0000), vec4(0.0869, 0.2149, 0.3457, 1.0000), vec4(0.0929, 0.2235, 0.3527, 1.0000),
    vec4(0.1358, 0.2565, 0.3905, 1.0000), vec4(0.1200, 0.2371, 0.3748, 1.0000), vec4(0.1035, 0.2235, 0.3457, 1.0000),
    vec4(0.0929, 0.2066, 0.3320, 1.0000), vec4(0.0831, 0.1947, 0.3254, 1.0000), vec4(0.0777, 0.1872, 0.3127, 1.0000),
    vec4(0.0725, 0.1764, 0.3065, 1.0000), vec4(0.0676, 0.1695, 0.2946, 1.0000), vec4(0.0614, 0.1596, 0.2776, 1.0000),
    vec4(0.0585, 0.1564, 0.2669, 1.0000), vec4(0.0571, 0.1533, 0.2565, 1.0000), vec4(0.0557, 0.1503, 0.2616, 1.0000),
    vec4(0.0530, 0.1503, 0.2722, 1.0000), vec4(0.0516, 0.1473, 0.2722, 1.0000), vec4(0.0530, 0.1503, 0.2776, 1.0000),
    vec4(0.0557, 0.1533, 0.2831, 1.0000), vec4(0.0571, 0.1564, 0.2946, 1.0000), vec4(0.0571, 0.1596, 0.3005, 1.0000),
    vec4(0.0614, 0.1628, 0.3065, 1.0000), vec4(0.0629, 0.1695, 0.3127, 1.0000), vec4(0.0660, 0.1764, 0.3127, 1.0000),
    vec4(0.0692, 0.1835, 0.3254, 1.0000), vec4(0.0725, 0.1909, 0.3320, 1.0000), vec4(0.0759, 0.1986, 0.3388, 1.0000)
);

const vec4 DOME_ACT3_START[288] = vec4[288](
    vec4(0.0120, 0.0136, 0.0153, 1.0000), vec4(0.0136, 0.0159, 0.0159, 1.0000), vec4(0.0131, 0.0131, 0.0120, 1.0000),
    vec4(0.0136, 0.0141, 0.0141, 1.0000), vec4(0.0080, 0.0115, 0.0159, 1.0000), vec4(0.0080, 0.0110, 0.0147, 1.0000),
    vec4(0.0096, 0.0131, 0.0171, 1.0000), vec4(0.0115, 0.0153, 0.0191, 1.0000), vec4(0.0184, 0.0219, 0.0275, 1.0000),
    vec4(0.0391, 0.0330, 0.0320, 1.0000), vec4(0.0212, 0.0205, 0.0227, 1.0000), vec4(0.0136, 0.0165, 0.0205, 1.0000),
    vec4(0.0120, 0.0159, 0.0198, 1.0000), vec4(0.0293, 0.0402, 0.0459, 1.0000), vec4(0.0191, 0.0484, 0.0636, 1.0000),
    vec4(0.0205, 0.0293, 0.0391, 1.0000), vec4(0.0171, 0.0205, 0.0250, 1.0000), vec4(0.0153, 0.0205, 0.0242, 1.0000),
    vec4(0.0391, 0.0523, 0.0606, 1.0000), vec4(0.0523, 0.0447, 0.0402, 1.0000), vec4(0.0159, 0.0178, 0.0198, 1.0000),
    vec4(0.0563, 0.0592, 0.0549, 1.0000), vec4(0.0402, 0.0380, 0.0391, 1.0000), vec4(0.0302, 0.0302, 0.0320, 1.0000),
    vec4(0.0153, 0.0159, 0.0191, 1.0000), vec4(0.0101, 0.0131, 0.0171, 1.0000), vec4(0.0101, 0.0131, 0.0153, 1.0000),
    vec4(0.0120, 0.0178, 0.0212, 1.0000), vec4(0.0088, 0.0141, 0.0198, 1.0000), vec4(0.0088, 0.0136, 0.0184, 1.0000),
    vec4(0.0115, 0.0171, 0.0242, 1.0000), vec4(0.0136, 0.0198, 0.0293, 1.0000), vec4(0.0205, 0.0275, 0.0380, 1.0000),
    vec4(0.0275, 0.0339, 0.0436, 1.0000), vec4(0.0165, 0.0219, 0.0320, 1.0000), vec4(0.0212, 0.0275, 0.0380, 1.0000),
    vec4(0.0258, 0.0339, 0.0436, 1.0000), vec4(0.0563, 0.0699, 0.0767, 1.0000), vec4(0.0497, 0.0896, 0.1088, 1.0000),
    vec4(0.0413, 0.0523, 0.0651, 1.0000), vec4(0.0219, 0.0275, 0.0370, 1.0000), vec4(0.0159, 0.0198, 0.0275, 1.0000),
    vec4(0.0275, 0.0349, 0.0484, 1.0000), vec4(0.0380, 0.0370, 0.0413, 1.0000), vec4(0.0101, 0.0120, 0.0159, 1.0000),
    vec4(0.0732, 0.0621, 0.0577, 1.0000), vec4(0.0311, 0.0339, 0.0413, 1.0000), vec4(0.0171, 0.0219, 0.0311, 1.0000),
    vec4(0.0061, 0.0131, 0.0242, 1.0000), vec4(0.0068, 0.0153, 0.0275, 1.0000), vec4(0.0092, 0.0178, 0.0311, 1.0000),
    vec4(0.0120, 0.0234, 0.0391, 1.0000), vec4(0.0120, 0.0198, 0.0293, 1.0000), vec4(0.0198, 0.0275, 0.0339, 1.0000),
    vec4(0.0250, 0.0339, 0.0436, 1.0000), vec4(0.0311, 0.0424, 0.0549, 1.0000), vec4(0.0311, 0.0424, 0.0592, 1.0000),
    vec4(0.0242, 0.0391, 0.0621, 1.0000), vec4(0.0191, 0.0380, 0.0636, 1.0000), vec4(0.0250, 0.0447, 0.0699, 1.0000),
    vec4(0.0320, 0.0509, 0.0749, 1.0000), vec4(0.0436, 0.0621, 0.0877, 1.0000), vec4(0.0472, 0.0621, 0.0877, 1.0000),
    vec4(0.0563, 0.0715, 0.0957, 1.0000), vec4(0.0592, 0.0715, 0.0937, 1.0000), vec4(0.0621, 0.0715, 0.0916, 1.0000),
    vec4(0.0509, 0.0636, 0.0858, 1.0000), vec4(0.0577, 0.0636, 0.0820, 1.0000), vec4(0.0651, 0.0651, 0.0767, 1.0000),
    vec4(0.0699, 0.0683, 0.0784, 1.0000), vec4(0.0459, 0.0523, 0.0683, 1.0000), vec4(0.0472, 0.0509, 0.0621, 1.0000),
    vec4(0.0058, 0.0159, 0.0320, 1.0000), vec4(0.0076, 0.0198, 0.0391, 1.0000), vec4(0.0101, 0.0242, 0.0447, 1.0000),
    vec4(0.0110, 0.0284, 0.0536, 1.0000), vec4(0.0212, 0.0339, 0.0497, 1.0000), vec4(0.0302, 0.0391, 0.0497, 1.0000),
    vec4(0.0370, 0.0484, 0.0667, 1.0000), vec4(0.0447, 0.0592, 0.0858, 1.0000), vec4(0.0536, 0.0683, 0.1021, 1.0000),
    vec4(0.0592, 0.0749, 0.1088, 1.0000), vec4(0.0715, 0.0839, 0.1184, 1.0000), vec4(0.0937, 0.0978, 0.1286, 1.0000),
    vec4(0.1208, 0.1135, 0.1367, 1.0000), vec4(0.1513, 0.1286, 0.1483, 1.0000), vec4(0.1672, 0.1395, 0.1575, 1.0000),
    vec4(0.1921, 0.1544, 0.1607, 1.0000), vec4(0.2685, 0.1811, 0.1672, 1.0000), vec4(0.3211, 0.1999, 0.1706, 1.0000),
    vec4(0.3024, 0.1921, 0.1639, 1.0000), vec4(0.2965, 0.1921, 0.1607, 1.0000), vec4(0.2433, 0.1706, 0.1424, 1.0000),
    vec4(0.2163, 0.1544, 0.1286, 1.0000), vec4(0.2685, 0.1672, 0.1184, 1.0000), vec4(0.2582, 0.1544, 0.1043, 1.0000),
    vec4(0.0055, 0.0178, 0.0370, 1.0000), vec4(0.0076, 0.0219, 0.0447, 1.0000), vec4(0.0110, 0.0275, 0.0549, 1.0000),
    vec4(0.0147, 0.0349, 0.0667, 1.0000), vec4(0.0198, 0.0413, 0.0732, 1.0000), vec4(0.0267, 0.0484, 0.0820, 1.0000),
    vec4(0.0413, 0.0636, 0.1021, 1.0000), vec4(0.0592, 0.0802, 0.1234, 1.0000), vec4(0.0839, 0.1043, 0.1483, 1.0000),
    vec4(0.1259, 0.1340, 0.1706, 1.0000), vec4(0.1884, 0.1706, 0.1921, 1.0000), vec4(0.2850, 0.2163, 0.2206, 1.0000),
    vec4(0.4273, 0.2794, 0.2531, 1.0000), vec4(0.6346, 0.3624, 0.2965, 1.0000), vec4(0.8992, 0.4457, 0.3276, 1.0000),
    vec4(1.1989, 0.5295, 0.3551, 1.0000), vec4(1.7561, 0.6496, 0.3853, 1.0000), vec4(2.3803, 0.7508, 0.4015, 1.0000),
    vec4(2.7706, 0.8097, 0.4015, 1.0000), vec4(2.7706, 0.8755, 0.4015, 1.0000), vec4(2.7706, 0.8755, 0.3933, 1.0000),
    vec4(2.7706, 0.8992, 0.3698, 1.0000), vec4(2.7706, 0.8755, 0.3276, 1.0000), vec4(2.7706, 0.8308, 0.2850, 1.0000),
    vec4(0.0049, 0.0184, 0.0413, 1.0000), vec4(0.0061, 0.0234, 0.0509, 1.0000), vec4(0.0080, 0.0293, 0.0621, 1.0000),
    vec4(0.0115, 0.0380, 0.0767, 1.0000), vec4(0.0153, 0.0459, 0.0896, 1.0000), vec4(0.0219, 0.0592, 0.1065, 1.0000),
    vec4(0.0320, 0.0784, 0.1312, 1.0000), vec4(0.0447, 0.0999, 0.1607, 1.0000), vec4(0.0621, 0.1259, 0.1960, 1.0000),
    vec4(0.0858, 0.1639, 0.2386, 1.0000), vec4(0.1208, 0.1999, 0.2850, 1.0000), vec4(0.1672, 0.2582, 0.3410, 1.0000),
    vec4(0.2294, 0.3276, 0.4185, 1.0000), vec4(0.3211, 0.4185, 0.5068, 1.0000), vec4(0.4273, 0.4959, 0.5535, 1.0000),
    vec4(0.5413, 0.5789, 0.5922, 1.0000), vec4(0.6651, 0.6346, 0.6346, 1.0000), vec4(0.7894, 0.7148, 0.6496, 1.0000),
    vec4(0.9238, 0.7697, 0.6496, 1.0000), vec4(1.0948, 0.8308, 0.6496, 1.0000), vec4(1.2772, 0.8755, 0.6346, 1.0000),
    vec4(1.4107, 0.9238, 0.6059, 1.0000), vec4(1.4107, 0.8992, 0.5413, 1.0000), vec4(1.4602, 0.8755, 0.5068, 1.0000),
    vec4(0.0028, 0.0171, 0.0436, 1.0000), vec4(0.0038, 0.0219, 0.0549, 1.0000), vec4(0.0052, 0.0284, 0.0667, 1.0000),
    vec4(0.0084, 0.0370, 0.0839, 1.0000), vec4(0.0096, 0.0436, 0.0978, 1.0000), vec4(0.0125, 0.0549, 0.1184, 1.0000),
    vec4(0.0178, 0.0699, 0.1453, 1.0000), vec4(0.0242, 0.0877, 0.1775, 1.0000), vec4(0.0339, 0.1111, 0.2163, 1.0000),
    vec4(0.0459, 0.1395, 0.2633, 1.0000), vec4(0.0636, 0.1706, 0.3085, 1.0000), vec4(0.0877, 0.2120, 0.3551, 1.0000),
    vec4(0.1184, 0.2633, 0.4185, 1.0000), vec4(0.1544, 0.3211, 0.4959, 1.0000), vec4(0.1999, 0.3853, 0.5789, 1.0000),
    vec4(0.2482, 0.4457, 0.6496, 1.0000), vec4(0.3024, 0.4959, 0.6811, 1.0000), vec4(0.3624, 0.5413, 0.6977, 1.0000),
    vec4(0.4185, 0.5789, 0.6977, 1.0000), vec4(0.4750, 0.6059, 0.6977, 1.0000), vec4(0.5295, 0.6200, 0.6651, 1.0000),
    vec4(0.5922, 0.6496, 0.6346, 1.0000), vec4(0.6200, 0.6496, 0.5789, 1.0000), vec4(0.6651, 0.6346, 0.5295, 1.0000),
    vec4(0.0021, 0.0165, 0.0424, 1.0000), vec4(0.0024, 0.0205, 0.0536, 1.0000), vec4(0.0033, 0.0258, 0.0667, 1.0000),
    vec4(0.0061, 0.0349, 0.0858, 1.0000), vec4(0.0046, 0.0380, 0.1021, 1.0000), vec4(0.0061, 0.0472, 0.1234, 1.0000),
    vec4(0.0088, 0.0592, 0.1483, 1.0000), vec4(0.0120, 0.0715, 0.1775, 1.0000), vec4(0.0178, 0.0896, 0.2120, 1.0000),
    vec4(0.0242, 0.1111, 0.2582, 1.0000), vec4(0.0339, 0.1340, 0.2965, 1.0000), vec4(0.0459, 0.1607, 0.3342, 1.0000),
    vec4(0.0606, 0.1960, 0.3853, 1.0000), vec4(0.0802, 0.2340, 0.4457, 1.0000), vec4(0.1021, 0.2739, 0.5068, 1.0000),
    vec4(0.1286, 0.3147, 0.5535, 1.0000), vec4(0.1575, 0.3551, 0.6059, 1.0000), vec4(0.1847, 0.3933, 0.6346, 1.0000),
    vec4(0.2079, 0.4185, 0.6496, 1.0000), vec4(0.2340, 0.4364, 0.6496, 1.0000), vec4(0.2582, 0.4552, 0.6496, 1.0000),
    vec4(0.2850, 0.4650, 0.6200, 1.0000), vec4(0.2965, 0.4552, 0.5660, 1.0000), vec4(0.3024, 0.4457, 0.5180, 1.0000),
    vec4(0.0014, 0.0141, 0.0391, 1.0000), vec4(0.0013, 0.0171, 0.0497, 1.0000), vec4(0.0021, 0.0234, 0.0667, 1.0000),
    vec4(0.0026, 0.0284, 0.0820, 1.0000), vec4(0.0016, 0.0330, 0.0978, 1.0000), vec4(0.0021, 0.0391, 0.1159, 1.0000),
    vec4(0.0033, 0.0472, 0.1340, 1.0000), vec4(0.0055, 0.0577, 0.1607, 1.0000), vec4(0.0080, 0.0715, 0.1921, 1.0000),
    vec4(0.0120, 0.0877, 0.2249, 1.0000), vec4(0.0171, 0.1065, 0.2633, 1.0000), vec4(0.0250, 0.1234, 0.3024, 1.0000),
    vec4(0.0339, 0.1453, 0.3410, 1.0000), vec4(0.0424, 0.1740, 0.4015, 1.0000), vec4(0.0549, 0.1999, 0.4364, 1.0000),
    vec4(0.0699, 0.2249, 0.4750, 1.0000), vec4(0.0839, 0.2531, 0.5068, 1.0000), vec4(0.0999, 0.2794, 0.5180, 1.0000),
    vec4(0.1135, 0.2965, 0.5295, 1.0000), vec4(0.1259, 0.3147, 0.5295, 1.0000), vec4(0.1395, 0.3211, 0.5180, 1.0000),
    vec4(0.1483, 0.3211, 0.4959, 1.0000), vec4(0.1513, 0.3147, 0.4650, 1.0000), vec4(0.1453, 0.3024, 0.4273, 1.0000),
    vec4(0.0011, 0.0120, 0.0370, 1.0000), vec4(0.0011, 0.0147, 0.0459, 1.0000), vec4(0.0014, 0.0191, 0.0606, 1.0000),
    vec4(0.0010, 0.0227, 0.0749, 1.0000), vec4(0.0011, 0.0284, 0.0896, 1.0000), vec4(0.0010, 0.0330, 0.1065, 1.0000),
    vec4(0.0010, 0.0391, 0.1234, 1.0000), vec4(0.0016, 0.0459, 0.1453, 1.0000), vec4(0.0026, 0.0563, 0.1740, 1.0000),
    vec4(0.0043, 0.0683, 0.2039, 1.0000), vec4(0.0076, 0.0820, 0.2340, 1.0000), vec4(0.0120, 0.0978, 0.2685, 1.0000),
    vec4(0.0171, 0.1135, 0.3085, 1.0000), vec4(0.0219, 0.1312, 0.3410, 1.0000), vec4(0.0302, 0.1483, 0.3775, 1.0000),
    vec4(0.0380, 0.1672, 0.4099, 1.0000), vec4(0.0459, 0.1847, 0.4364, 1.0000), vec4(0.0536, 0.1999, 0.4457, 1.0000),
    vec4(0.0606, 0.2120, 0.4650, 1.0000), vec4(0.0683, 0.2206, 0.4552, 1.0000), vec4(0.0749, 0.2294, 0.4364, 1.0000),
    vec4(0.0802, 0.2294, 0.4185, 1.0000), vec4(0.0784, 0.2249, 0.3933, 1.0000), vec4(0.0749, 0.2120, 0.3624, 1.0000),
    vec4(0.0010, 0.0110, 0.0339, 1.0000), vec4(0.0011, 0.0131, 0.0424, 1.0000), vec4(0.0010, 0.0159, 0.0536, 1.0000),
    vec4(0.0010, 0.0198, 0.0683, 1.0000), vec4(0.0011, 0.0242, 0.0802, 1.0000), vec4(0.0013, 0.0284, 0.0957, 1.0000),
    vec4(0.0011, 0.0330, 0.1111, 1.0000), vec4(0.0010, 0.0380, 0.1286, 1.0000), vec4(0.0009, 0.0447, 0.1513, 1.0000),
    vec4(0.0010, 0.0536, 0.1811, 1.0000), vec4(0.0016, 0.0621, 0.1999, 1.0000), vec4(0.0031, 0.0732, 0.2294, 1.0000),
    vec4(0.0061, 0.0858, 0.2633, 1.0000), vec4(0.0101, 0.0978, 0.2907, 1.0000), vec4(0.0136, 0.1111, 0.3147, 1.0000),
    vec4(0.0178, 0.1259, 0.3342, 1.0000), vec4(0.0234, 0.1367, 0.3551, 1.0000), vec4(0.0284, 0.1453, 0.3698, 1.0000),
    vec4(0.0320, 0.1544, 0.3853, 1.0000), vec4(0.0370, 0.1607, 0.3775, 1.0000), vec4(0.0391, 0.1639, 0.3775, 1.0000),
    vec4(0.0413, 0.1639, 0.3624, 1.0000), vec4(0.0413, 0.1607, 0.3410, 1.0000), vec4(0.0380, 0.1483, 0.3085, 1.0000),
    vec4(0.0009, 0.0105, 0.0349, 1.0000), vec4(0.0009, 0.0115, 0.0391, 1.0000), vec4(0.0010, 0.0136, 0.0497, 1.0000),
    vec4(0.0010, 0.0165, 0.0606, 1.0000), vec4(0.0011, 0.0205, 0.0732, 1.0000), vec4(0.0011, 0.0250, 0.0877, 1.0000),
    vec4(0.0010, 0.0293, 0.1021, 1.0000), vec4(0.0009, 0.0320, 0.1135, 1.0000), vec4(0.0010, 0.0391, 0.1367, 1.0000),
    vec4(0.0009, 0.0436, 0.1575, 1.0000), vec4(0.0007, 0.0497, 0.1740, 1.0000), vec4(0.0007, 0.0577, 0.1960, 1.0000),
    vec4(0.0010, 0.0667, 0.2206, 1.0000), vec4(0.0026, 0.0749, 0.2482, 1.0000), vec4(0.0049, 0.0839, 0.2633, 1.0000),
    vec4(0.0076, 0.0937, 0.2794, 1.0000), vec4(0.0105, 0.1043, 0.3024, 1.0000), vec4(0.0136, 0.1111, 0.3147, 1.0000),
    vec4(0.0159, 0.1184, 0.3211, 1.0000), vec4(0.0191, 0.1208, 0.3211, 1.0000), vec4(0.0212, 0.1234, 0.3147, 1.0000),
    vec4(0.0227, 0.1208, 0.3024, 1.0000), vec4(0.0212, 0.1135, 0.2794, 1.0000), vec4(0.0191, 0.1065, 0.2531, 1.0000)
);

const vec4 DOME_ACT3_MID[288] = vec4[288](
    vec4(0.0080, 0.0096, 0.0110, 1.0000), vec4(0.0115, 0.0101, 0.0110, 1.0000), vec4(0.0227, 0.0205, 0.0198, 1.0000),
    vec4(0.0125, 0.0153, 0.0159, 1.0000), vec4(0.0141, 0.0159, 0.0147, 1.0000), vec4(0.0125, 0.0141, 0.0141, 1.0000),
    vec4(0.0125, 0.0147, 0.0153, 1.0000), vec4(0.0125, 0.0153, 0.0159, 1.0000), vec4(0.0131, 0.0165, 0.0184, 1.0000),
    vec4(0.0131, 0.0171, 0.0219, 1.0000), vec4(0.0101, 0.0147, 0.0191, 1.0000), vec4(0.0125, 0.0165, 0.0212, 1.0000),
    vec4(0.0147, 0.0184, 0.0219, 1.0000), vec4(0.0110, 0.0136, 0.0178, 1.0000), vec4(0.0191, 0.0212, 0.0250, 1.0000),
    vec4(0.0424, 0.0339, 0.0302, 1.0000), vec4(0.0250, 0.0234, 0.0234, 1.0000), vec4(0.0171, 0.0198, 0.0242, 1.0000),
    vec4(0.0115, 0.0606, 0.0896, 1.0000), vec4(0.0275, 0.0523, 0.0651, 1.0000), vec4(0.0484, 0.0606, 0.0577, 1.0000),
    vec4(0.0088, 0.0147, 0.0198, 1.0000), vec4(0.0072, 0.0105, 0.0153, 1.0000), vec4(0.0092, 0.0120, 0.0153, 1.0000),
    vec4(0.0141, 0.0136, 0.0171, 1.0000), vec4(0.0125, 0.0171, 0.0219, 1.0000), vec4(0.0105, 0.0165, 0.0219, 1.0000),
    vec4(0.0136, 0.0165, 0.0184, 1.0000), vec4(0.0125, 0.0141, 0.0136, 1.0000), vec4(0.0110, 0.0125, 0.0125, 1.0000),
    vec4(0.0131, 0.0147, 0.0153, 1.0000), vec4(0.0147, 0.0165, 0.0171, 1.0000), vec4(0.0125, 0.0165, 0.0198, 1.0000),
    vec4(0.0165, 0.0212, 0.0267, 1.0000), vec4(0.0302, 0.0320, 0.0349, 1.0000), vec4(0.0267, 0.0311, 0.0359, 1.0000),
    vec4(0.0219, 0.0284, 0.0330, 1.0000), vec4(0.0159, 0.0219, 0.0293, 1.0000), vec4(0.0153, 0.0205, 0.0267, 1.0000),
    vec4(0.0293, 0.0330, 0.0370, 1.0000), vec4(0.0125, 0.0191, 0.0275, 1.0000), vec4(0.0101, 0.0171, 0.0267, 1.0000),
    vec4(0.0125, 0.0198, 0.0275, 1.0000), vec4(0.0284, 0.0349, 0.0413, 1.0000), vec4(0.0234, 0.0320, 0.0391, 1.0000),
    vec4(0.0250, 0.0311, 0.0359, 1.0000), vec4(0.0242, 0.0275, 0.0339, 1.0000), vec4(0.0115, 0.0178, 0.0242, 1.0000),
    vec4(0.0088, 0.0159, 0.0267, 1.0000), vec4(0.0120, 0.0219, 0.0339, 1.0000), vec4(0.0080, 0.0159, 0.0258, 1.0000),
    vec4(0.0101, 0.0136, 0.0178, 1.0000), vec4(0.0096, 0.0141, 0.0184, 1.0000), vec4(0.0110, 0.0171, 0.0219, 1.0000),
    vec4(0.0131, 0.0184, 0.0212, 1.0000), vec4(0.0153, 0.0191, 0.0191, 1.0000), vec4(0.0159, 0.0219, 0.0267, 1.0000),
    vec4(0.0205, 0.0293, 0.0380, 1.0000), vec4(0.0191, 0.0311, 0.0459, 1.0000), vec4(0.0212, 0.0349, 0.0523, 1.0000),
    vec4(0.0234, 0.0380, 0.0549, 1.0000), vec4(0.0205, 0.0339, 0.0509, 1.0000), vec4(0.0159, 0.0275, 0.0424, 1.0000),
    vec4(0.0227, 0.0330, 0.0472, 1.0000), vec4(0.0227, 0.0349, 0.0497, 1.0000), vec4(0.0141, 0.0284, 0.0459, 1.0000),
    vec4(0.0165, 0.0320, 0.0484, 1.0000), vec4(0.0115, 0.0250, 0.0413, 1.0000), vec4(0.0198, 0.0320, 0.0447, 1.0000),
    vec4(0.0212, 0.0330, 0.0472, 1.0000), vec4(0.0125, 0.0258, 0.0391, 1.0000), vec4(0.0101, 0.0219, 0.0339, 1.0000),
    vec4(0.0084, 0.0212, 0.0391, 1.0000), vec4(0.0101, 0.0250, 0.0447, 1.0000), vec4(0.0120, 0.0242, 0.0391, 1.0000),
    vec4(0.0101, 0.0198, 0.0320, 1.0000), vec4(0.0147, 0.0302, 0.0536, 1.0000), vec4(0.0115, 0.0258, 0.0447, 1.0000),
    vec4(0.0080, 0.0178, 0.0320, 1.0000), vec4(0.0043, 0.0110, 0.0198, 1.0000), vec4(0.0068, 0.0171, 0.0302, 1.0000),
    vec4(0.0198, 0.0339, 0.0509, 1.0000), vec4(0.0147, 0.0320, 0.0563, 1.0000), vec4(0.0153, 0.0349, 0.0636, 1.0000),
    vec4(0.0159, 0.0349, 0.0621, 1.0000), vec4(0.0178, 0.0380, 0.0651, 1.0000), vec4(0.0242, 0.0447, 0.0732, 1.0000),
    vec4(0.0339, 0.0523, 0.0802, 1.0000), vec4(0.0330, 0.0509, 0.0784, 1.0000), vec4(0.0284, 0.0472, 0.0732, 1.0000),
    vec4(0.0275, 0.0459, 0.0715, 1.0000), vec4(0.0275, 0.0459, 0.0715, 1.0000), vec4(0.0302, 0.0459, 0.0667, 1.0000),
    vec4(0.0293, 0.0436, 0.0636, 1.0000), vec4(0.0258, 0.0391, 0.0549, 1.0000), vec4(0.0234, 0.0339, 0.0497, 1.0000),
    vec4(0.0159, 0.0284, 0.0459, 1.0000), vec4(0.0178, 0.0339, 0.0549, 1.0000), vec4(0.0120, 0.0242, 0.0391, 1.0000),
    vec4(0.0125, 0.0267, 0.0447, 1.0000), vec4(0.0191, 0.0413, 0.0715, 1.0000), vec4(0.0171, 0.0339, 0.0563, 1.0000),
    vec4(0.0165, 0.0302, 0.0472, 1.0000), vec4(0.0159, 0.0250, 0.0349, 1.0000), vec4(0.0159, 0.0349, 0.0577, 1.0000),
    vec4(0.0165, 0.0413, 0.0802, 1.0000), vec4(0.0171, 0.0413, 0.0784, 1.0000), vec4(0.0191, 0.0447, 0.0839, 1.0000),
    vec4(0.0205, 0.0459, 0.0858, 1.0000), vec4(0.0227, 0.0497, 0.0877, 1.0000), vec4(0.0267, 0.0549, 0.0937, 1.0000),
    vec4(0.0330, 0.0606, 0.0999, 1.0000), vec4(0.0424, 0.0667, 0.1043, 1.0000), vec4(0.0536, 0.0749, 0.1065, 1.0000),
    vec4(0.0636, 0.0820, 0.1088, 1.0000), vec4(0.0749, 0.0858, 0.1088, 1.0000), vec4(0.0858, 0.0877, 0.1021, 1.0000),
    vec4(0.0999, 0.0896, 0.0978, 1.0000), vec4(0.1088, 0.0896, 0.0916, 1.0000), vec4(0.1065, 0.0839, 0.0802, 1.0000),
    vec4(0.0191, 0.0380, 0.0577, 1.0000), vec4(0.0191, 0.0402, 0.0651, 1.0000), vec4(0.0191, 0.0413, 0.0667, 1.0000),
    vec4(0.0171, 0.0424, 0.0732, 1.0000), vec4(0.0159, 0.0424, 0.0784, 1.0000), vec4(0.0131, 0.0359, 0.0651, 1.0000),
    vec4(0.0096, 0.0284, 0.0509, 1.0000), vec4(0.0061, 0.0198, 0.0349, 1.0000), vec4(0.0105, 0.0339, 0.0651, 1.0000),
    vec4(0.0141, 0.0459, 0.0957, 1.0000), vec4(0.0131, 0.0447, 0.0916, 1.0000), vec4(0.0141, 0.0472, 0.0957, 1.0000),
    vec4(0.0147, 0.0497, 0.0978, 1.0000), vec4(0.0171, 0.0549, 0.1065, 1.0000), vec4(0.0212, 0.0636, 0.1184, 1.0000),
    vec4(0.0267, 0.0715, 0.1286, 1.0000), vec4(0.0349, 0.0839, 0.1395, 1.0000), vec4(0.0447, 0.0957, 0.1483, 1.0000),
    vec4(0.0536, 0.1088, 0.1544, 1.0000), vec4(0.0667, 0.1184, 0.1607, 1.0000), vec4(0.0749, 0.1259, 0.1607, 1.0000),
    vec4(0.0820, 0.1286, 0.1544, 1.0000), vec4(0.0877, 0.1259, 0.1453, 1.0000), vec4(0.0896, 0.1208, 0.1286, 1.0000),
    vec4(0.0136, 0.0380, 0.0651, 1.0000), vec4(0.0125, 0.0391, 0.0715, 1.0000), vec4(0.0136, 0.0424, 0.0802, 1.0000),
    vec4(0.0120, 0.0413, 0.0820, 1.0000), vec4(0.0105, 0.0402, 0.0858, 1.0000), vec4(0.0092, 0.0391, 0.0839, 1.0000),
    vec4(0.0076, 0.0370, 0.0820, 1.0000), vec4(0.0061, 0.0349, 0.0820, 1.0000), vec4(0.0072, 0.0380, 0.0896, 1.0000),
    vec4(0.0076, 0.0402, 0.0978, 1.0000), vec4(0.0072, 0.0413, 0.0999, 1.0000), vec4(0.0076, 0.0436, 0.1043, 1.0000),
    vec4(0.0080, 0.0447, 0.1088, 1.0000), vec4(0.0101, 0.0509, 0.1184, 1.0000), vec4(0.0131, 0.0577, 0.1312, 1.0000),
    vec4(0.0159, 0.0651, 0.1424, 1.0000), vec4(0.0191, 0.0749, 0.1575, 1.0000), vec4(0.0242, 0.0877, 0.1672, 1.0000),
    vec4(0.0302, 0.0999, 0.1811, 1.0000), vec4(0.0359, 0.1088, 0.1847, 1.0000), vec4(0.0413, 0.1159, 0.1847, 1.0000),
    vec4(0.0459, 0.1208, 0.1847, 1.0000), vec4(0.0484, 0.1234, 0.1775, 1.0000), vec4(0.0509, 0.1184, 0.1639, 1.0000),
    vec4(0.0080, 0.0330, 0.0667, 1.0000), vec4(0.0072, 0.0349, 0.0732, 1.0000), vec4(0.0061, 0.0349, 0.0784, 1.0000),
    vec4(0.0052, 0.0359, 0.0839, 1.0000), vec4(0.0052, 0.0359, 0.0877, 1.0000), vec4(0.0049, 0.0359, 0.0896, 1.0000),
    vec4(0.0046, 0.0359, 0.0937, 1.0000), vec4(0.0043, 0.0370, 0.0999, 1.0000), vec4(0.0040, 0.0359, 0.0999, 1.0000),
    vec4(0.0035, 0.0349, 0.0999, 1.0000), vec4(0.0031, 0.0359, 0.1021, 1.0000), vec4(0.0031, 0.0380, 0.1088, 1.0000),
    vec4(0.0031, 0.0391, 0.1135, 1.0000), vec4(0.0040, 0.0436, 0.1234, 1.0000), vec4(0.0055, 0.0497, 0.1340, 1.0000),
    vec4(0.0065, 0.0549, 0.1424, 1.0000), vec4(0.0088, 0.0621, 0.1575, 1.0000), vec4(0.0115, 0.0715, 0.1706, 1.0000),
    vec4(0.0147, 0.0802, 0.1811, 1.0000), vec4(0.0184, 0.0877, 0.1884, 1.0000), vec4(0.0212, 0.0937, 0.1884, 1.0000),
    vec4(0.0234, 0.0978, 0.1847, 1.0000), vec4(0.0258, 0.0999, 0.1775, 1.0000), vec4(0.0275, 0.0978, 0.1639, 1.0000),
    vec4(0.0031, 0.0267, 0.0667, 1.0000), vec4(0.0022, 0.0284, 0.0732, 1.0000), vec4(0.0019, 0.0302, 0.0802, 1.0000),
    vec4(0.0021, 0.0311, 0.0839, 1.0000), vec4(0.0021, 0.0311, 0.0877, 1.0000), vec4(0.0019, 0.0293, 0.0896, 1.0000),
    vec4(0.0019, 0.0293, 0.0916, 1.0000), vec4(0.0021, 0.0302, 0.0916, 1.0000), vec4(0.0021, 0.0311, 0.0937, 1.0000),
    vec4(0.0014, 0.0302, 0.0937, 1.0000), vec4(0.0014, 0.0311, 0.0957, 1.0000), vec4(0.0021, 0.0339, 0.0999, 1.0000),
    vec4(0.0017, 0.0349, 0.1065, 1.0000), vec4(0.0014, 0.0370, 0.1135, 1.0000), vec4(0.0016, 0.0402, 0.1234, 1.0000),
    vec4(0.0021, 0.0447, 0.1340, 1.0000), vec4(0.0028, 0.0497, 0.1453, 1.0000), vec4(0.0040, 0.0563, 0.1544, 1.0000),
    vec4(0.0058, 0.0621, 0.1672, 1.0000), vec4(0.0076, 0.0683, 0.1706, 1.0000), vec4(0.0092, 0.0732, 0.1740, 1.0000),
    vec4(0.0110, 0.0767, 0.1740, 1.0000), vec4(0.0120, 0.0767, 0.1639, 1.0000), vec4(0.0125, 0.0767, 0.1544, 1.0000),
    vec4(0.0013, 0.0227, 0.0636, 1.0000), vec4(0.0011, 0.0242, 0.0683, 1.0000), vec4(0.0011, 0.0250, 0.0749, 1.0000),
    vec4(0.0013, 0.0258, 0.0802, 1.0000), vec4(0.0013, 0.0258, 0.0820, 1.0000), vec4(0.0013, 0.0258, 0.0839, 1.0000),
    vec4(0.0014, 0.0258, 0.0858, 1.0000), vec4(0.0014, 0.0258, 0.0858, 1.0000), vec4(0.0013, 0.0258, 0.0858, 1.0000),
    vec4(0.0011, 0.0267, 0.0877, 1.0000), vec4(0.0010, 0.0275, 0.0896, 1.0000), vec4(0.0013, 0.0293, 0.0978, 1.0000),
    vec4(0.0013, 0.0302, 0.1021, 1.0000), vec4(0.0013, 0.0320, 0.1065, 1.0000), vec4(0.0011, 0.0339, 0.1111, 1.0000),
    vec4(0.0011, 0.0370, 0.1184, 1.0000), vec4(0.0013, 0.0402, 0.1286, 1.0000), vec4(0.0014, 0.0447, 0.1367, 1.0000),
    vec4(0.0016, 0.0484, 0.1424, 1.0000), vec4(0.0017, 0.0523, 0.1483, 1.0000), vec4(0.0022, 0.0549, 0.1513, 1.0000),
    vec4(0.0028, 0.0563, 0.1513, 1.0000), vec4(0.0033, 0.0577, 0.1453, 1.0000), vec4(0.0035, 0.0563, 0.1395, 1.0000),
    vec4(0.0010, 0.0191, 0.0563, 1.0000), vec4(0.0010, 0.0198, 0.0621, 1.0000), vec4(0.0010, 0.0205, 0.0667, 1.0000),
    vec4(0.0010, 0.0212, 0.0715, 1.0000), vec4(0.0011, 0.0219, 0.0749, 1.0000), vec4(0.0011, 0.0227, 0.0767, 1.0000),
    vec4(0.0011, 0.0227, 0.0767, 1.0000), vec4(0.0011, 0.0227, 0.0784, 1.0000), vec4(0.0011, 0.0227, 0.0802, 1.0000),
    vec4(0.0010, 0.0234, 0.0820, 1.0000), vec4(0.0011, 0.0242, 0.0858, 1.0000), vec4(0.0010, 0.0250, 0.0877, 1.0000),
    vec4(0.0011, 0.0258, 0.0937, 1.0000), vec4(0.0013, 0.0284, 0.0999, 1.0000), vec4(0.0013, 0.0311, 0.1065, 1.0000),
    vec4(0.0011, 0.0302, 0.1043, 1.0000), vec4(0.0011, 0.0330, 0.1111, 1.0000), vec4(0.0011, 0.0370, 0.1208, 1.0000),
    vec4(0.0011, 0.0391, 0.1259, 1.0000), vec4(0.0011, 0.0413, 0.1259, 1.0000), vec4(0.0010, 0.0424, 0.1286, 1.0000),
    vec4(0.0009, 0.0436, 0.1259, 1.0000), vec4(0.0010, 0.0436, 0.1234, 1.0000), vec4(0.0010, 0.0424, 0.1159, 1.0000),
    vec4(0.0010, 0.0165, 0.0509, 1.0000), vec4(0.0010, 0.0178, 0.0577, 1.0000), vec4(0.0009, 0.0171, 0.0592, 1.0000),
    vec4(0.0009, 0.0178, 0.0636, 1.0000), vec4(0.0009, 0.0184, 0.0667, 1.0000), vec4(0.0010, 0.0191, 0.0683, 1.0000),
    vec4(0.0010, 0.0191, 0.0683, 1.0000), vec4(0.0010, 0.0191, 0.0683, 1.0000), vec4(0.0010, 0.0191, 0.0732, 1.0000),
    vec4(0.0010, 0.0198, 0.0749, 1.0000), vec4(0.0010, 0.0205, 0.0784, 1.0000), vec4(0.0010, 0.0212, 0.0802, 1.0000),
    vec4(0.0010, 0.0219, 0.0820, 1.0000), vec4(0.0009, 0.0234, 0.0877, 1.0000), vec4(0.0010, 0.0267, 0.0957, 1.0000),
    vec4(0.0009, 0.0275, 0.0978, 1.0000), vec4(0.0009, 0.0284, 0.1021, 1.0000), vec4(0.0009, 0.0293, 0.1065, 1.0000),
    vec4(0.0009, 0.0311, 0.1065, 1.0000), vec4(0.0009, 0.0320, 0.1088, 1.0000), vec4(0.0009, 0.0339, 0.1111, 1.0000),
    vec4(0.0010, 0.0339, 0.1111, 1.0000), vec4(0.0010, 0.0339, 0.1065, 1.0000), vec4(0.0009, 0.0330, 0.1021, 1.0000)
);

const vec4 DOME_ACT3_END[288] = vec4[288](
    vec4(0.0131, 0.0171, 0.0219, 1.0000), vec4(0.0101, 0.0141, 0.0153, 1.0000), vec4(0.0153, 0.0205, 0.0250, 1.0000),
    vec4(0.0302, 0.0359, 0.0424, 1.0000), vec4(0.0153, 0.0212, 0.0267, 1.0000), vec4(0.0072, 0.0110, 0.0153, 1.0000),
    vec4(0.0088, 0.0120, 0.0171, 1.0000), vec4(0.0080, 0.0110, 0.0159, 1.0000), vec4(0.0125, 0.0159, 0.0205, 1.0000),
    vec4(0.0159, 0.0165, 0.0184, 1.0000), vec4(0.0234, 0.0275, 0.0311, 1.0000), vec4(0.0191, 0.0234, 0.0275, 1.0000),
    vec4(0.0101, 0.0136, 0.0171, 1.0000), vec4(0.0227, 0.0234, 0.0242, 1.0000), vec4(0.0250, 0.0267, 0.0275, 1.0000),
    vec4(0.0165, 0.0205, 0.0250, 1.0000), vec4(0.0184, 0.0219, 0.0267, 1.0000), vec4(0.0178, 0.0184, 0.0212, 1.0000),
    vec4(0.0110, 0.0131, 0.0165, 1.0000), vec4(0.0101, 0.0120, 0.0153, 1.0000), vec4(0.0080, 0.0110, 0.0147, 1.0000),
    vec4(0.0088, 0.0110, 0.0147, 1.0000), vec4(0.0131, 0.0159, 0.0191, 1.0000), vec4(0.0284, 0.0284, 0.0275, 1.0000),
    vec4(0.0110, 0.0178, 0.0242, 1.0000), vec4(0.0068, 0.0110, 0.0141, 1.0000), vec4(0.0131, 0.0242, 0.0359, 1.0000),
    vec4(0.0153, 0.0293, 0.0436, 1.0000), vec4(0.0250, 0.0349, 0.0413, 1.0000), vec4(0.0178, 0.0227, 0.0258, 1.0000),
    vec4(0.0141, 0.0191, 0.0234, 1.0000), vec4(0.0101, 0.0141, 0.0184, 1.0000), vec4(0.0125, 0.0184, 0.0250, 1.0000),
    vec4(0.0184, 0.0227, 0.0267, 1.0000), vec4(0.0191, 0.0227, 0.0219, 1.0000), vec4(0.0178, 0.0198, 0.0212, 1.0000),
    vec4(0.0131, 0.0147, 0.0171, 1.0000), vec4(0.0227, 0.0258, 0.0302, 1.0000), vec4(0.0258, 0.0284, 0.0311, 1.0000),
    vec4(0.0171, 0.0227, 0.0302, 1.0000), vec4(0.0250, 0.0293, 0.0349, 1.0000), vec4(0.0380, 0.0370, 0.0380, 1.0000),
    vec4(0.0153, 0.0219, 0.0275, 1.0000), vec4(0.0105, 0.0159, 0.0227, 1.0000), vec4(0.0165, 0.0227, 0.0275, 1.0000),
    vec4(0.0212, 0.0275, 0.0330, 1.0000), vec4(0.0076, 0.0125, 0.0178, 1.0000), vec4(0.0072, 0.0115, 0.0159, 1.0000),
    vec4(0.0250, 0.0380, 0.0484, 1.0000), vec4(0.0258, 0.0339, 0.0436, 1.0000), vec4(0.0250, 0.0459, 0.0683, 1.0000),
    vec4(0.0165, 0.0391, 0.0651, 1.0000), vec4(0.0699, 0.0978, 0.1043, 1.0000), vec4(0.1259, 0.1453, 0.1286, 1.0000),
    vec4(0.0749, 0.0937, 0.0999, 1.0000), vec4(0.0536, 0.0699, 0.0820, 1.0000), vec4(0.0284, 0.0472, 0.0651, 1.0000),
    vec4(0.0141, 0.0234, 0.0320, 1.0000), vec4(0.0110, 0.0147, 0.0178, 1.0000), vec4(0.0159, 0.0198, 0.0258, 1.0000),
    vec4(0.0191, 0.0227, 0.0311, 1.0000), vec4(0.0621, 0.0621, 0.0667, 1.0000), vec4(0.0523, 0.0509, 0.0484, 1.0000),
    vec4(0.0349, 0.0402, 0.0459, 1.0000), vec4(0.0413, 0.0459, 0.0536, 1.0000), vec4(0.0165, 0.0267, 0.0402, 1.0000),
    vec4(0.0125, 0.0227, 0.0349, 1.0000), vec4(0.0125, 0.0219, 0.0339, 1.0000), vec4(0.0165, 0.0267, 0.0359, 1.0000),
    vec4(0.0125, 0.0205, 0.0302, 1.0000), vec4(0.0068, 0.0147, 0.0242, 1.0000), vec4(0.0072, 0.0141, 0.0227, 1.0000),
    vec4(0.0549, 0.0767, 0.0978, 1.0000), vec4(0.0683, 0.0896, 0.1135, 1.0000), vec4(0.0636, 0.0858, 0.1184, 1.0000),
    vec4(0.0621, 0.0877, 0.1234, 1.0000), vec4(0.0592, 0.0858, 0.1208, 1.0000), vec4(0.0536, 0.0820, 0.1184, 1.0000),
    vec4(0.0497, 0.0784, 0.1184, 1.0000), vec4(0.0459, 0.0767, 0.1208, 1.0000), vec4(0.0413, 0.0732, 0.1111, 1.0000),
    vec4(0.0178, 0.0359, 0.0577, 1.0000), vec4(0.0242, 0.0436, 0.0699, 1.0000), vec4(0.0293, 0.0497, 0.0767, 1.0000),
    vec4(0.0320, 0.0536, 0.0839, 1.0000), vec4(0.0380, 0.0592, 0.0877, 1.0000), vec4(0.0339, 0.0447, 0.0549, 1.0000),
    vec4(0.0242, 0.0391, 0.0563, 1.0000), vec4(0.0184, 0.0380, 0.0651, 1.0000), vec4(0.0131, 0.0311, 0.0563, 1.0000),
    vec4(0.0125, 0.0293, 0.0523, 1.0000), vec4(0.0105, 0.0258, 0.0472, 1.0000), vec4(0.0096, 0.0227, 0.0424, 1.0000),
    vec4(0.0088, 0.0212, 0.0391, 1.0000), vec4(0.0072, 0.0184, 0.0339, 1.0000), vec4(0.0065, 0.0153, 0.0284, 1.0000),
    vec4(0.3410, 0.1740, 0.1234, 1.0000), vec4(0.3853, 0.1921, 0.1424, 1.0000), vec4(0.4015, 0.2079, 0.1575, 1.0000),
    vec4(0.3933, 0.2079, 0.1672, 1.0000), vec4(0.3624, 0.2079, 0.1740, 1.0000), vec4(0.3085, 0.1921, 0.1706, 1.0000),
    vec4(0.2633, 0.1811, 0.1706, 1.0000), vec4(0.2340, 0.1740, 0.1740, 1.0000), vec4(0.1607, 0.1367, 0.1483, 1.0000),
    vec4(0.0549, 0.0683, 0.0896, 1.0000), vec4(0.1088, 0.1234, 0.1575, 1.0000), vec4(0.0732, 0.0957, 0.1340, 1.0000),
    vec4(0.0536, 0.0784, 0.1184, 1.0000), vec4(0.0391, 0.0683, 0.1088, 1.0000), vec4(0.0302, 0.0563, 0.0937, 1.0000),
    vec4(0.0227, 0.0484, 0.0858, 1.0000), vec4(0.0184, 0.0447, 0.0820, 1.0000), vec4(0.0147, 0.0370, 0.0715, 1.0000),
    vec4(0.0125, 0.0330, 0.0636, 1.0000), vec4(0.0110, 0.0302, 0.0563, 1.0000), vec4(0.0096, 0.0267, 0.0497, 1.0000),
    vec4(0.0084, 0.0234, 0.0447, 1.0000), vec4(0.0072, 0.0198, 0.0380, 1.0000), vec4(0.0061, 0.0165, 0.0320, 1.0000),
    vec4(1.4602, 0.5295, 0.2531, 1.0000), vec4(1.5125, 0.5660, 0.2794, 1.0000), vec4(1.4107, 0.5660, 0.3024, 1.0000),
    vec4(1.1626, 0.5295, 0.3085, 1.0000), vec4(0.9238, 0.4853, 0.3085, 1.0000), vec4(0.7148, 0.4273, 0.3024, 1.0000),
    vec4(0.5413, 0.3853, 0.2965, 1.0000), vec4(0.4364, 0.3480, 0.2907, 1.0000), vec4(0.3147, 0.2850, 0.2685, 1.0000),
    vec4(0.1921, 0.2120, 0.2294, 1.0000), vec4(0.1544, 0.1847, 0.2163, 1.0000), vec4(0.1043, 0.1453, 0.1884, 1.0000),
    vec4(0.0699, 0.1135, 0.1639, 1.0000), vec4(0.0459, 0.0877, 0.1453, 1.0000), vec4(0.0330, 0.0715, 0.1259, 1.0000),
    vec4(0.0242, 0.0592, 0.1111, 1.0000), vec4(0.0178, 0.0497, 0.0957, 1.0000), vec4(0.0147, 0.0436, 0.0858, 1.0000),
    vec4(0.0115, 0.0370, 0.0749, 1.0000), vec4(0.0084, 0.0320, 0.0667, 1.0000), vec4(0.0072, 0.0275, 0.0577, 1.0000),
    vec4(0.0061, 0.0242, 0.0497, 1.0000), vec4(0.0052, 0.0205, 0.0424, 1.0000), vec4(0.0043, 0.0165, 0.0359, 1.0000),
    vec4(0.7894, 0.6059, 0.4015, 1.0000), vec4(0.7508, 0.5922, 0.4273, 1.0000), vec4(0.6811, 0.5789, 0.4364, 1.0000),
    vec4(0.5922, 0.5535, 0.4457, 1.0000), vec4(0.4959, 0.5068, 0.4457, 1.0000), vec4(0.3933, 0.4457, 0.4364, 1.0000),
    vec4(0.3085, 0.3933, 0.4185, 1.0000), vec4(0.2433, 0.3410, 0.4015, 1.0000), vec4(0.1847, 0.2907, 0.3624, 1.0000),
    vec4(0.1340, 0.2340, 0.3085, 1.0000), vec4(0.0916, 0.1775, 0.2582, 1.0000), vec4(0.0667, 0.1424, 0.2206, 1.0000),
    vec4(0.0459, 0.1111, 0.1884, 1.0000), vec4(0.0320, 0.0896, 0.1672, 1.0000), vec4(0.0227, 0.0715, 0.1424, 1.0000),
    vec4(0.0159, 0.0592, 0.1234, 1.0000), vec4(0.0115, 0.0497, 0.1065, 1.0000), vec4(0.0080, 0.0413, 0.0937, 1.0000),
    vec4(0.0061, 0.0349, 0.0802, 1.0000), vec4(0.0052, 0.0302, 0.0699, 1.0000), vec4(0.0049, 0.0267, 0.0606, 1.0000),
    vec4(0.0046, 0.0234, 0.0536, 1.0000), vec4(0.0033, 0.0191, 0.0436, 1.0000), vec4(0.0026, 0.0159, 0.0380, 1.0000),
    vec4(0.4015, 0.4552, 0.4185, 1.0000), vec4(0.4015, 0.4650, 0.4457, 1.0000), vec4(0.3551, 0.4552, 0.4750, 1.0000),
    vec4(0.3147, 0.4364, 0.4853, 1.0000), vec4(0.2685, 0.4015, 0.4853, 1.0000), vec4(0.2163, 0.3624, 0.4750, 1.0000),
    vec4(0.1672, 0.3211, 0.4457, 1.0000), vec4(0.1312, 0.2739, 0.4099, 1.0000), vec4(0.0978, 0.2294, 0.3624, 1.0000),
    vec4(0.0732, 0.1884, 0.3276, 1.0000), vec4(0.0523, 0.1513, 0.2794, 1.0000), vec4(0.0370, 0.1208, 0.2386, 1.0000),
    vec4(0.0250, 0.0957, 0.2039, 1.0000), vec4(0.0165, 0.0767, 0.1706, 1.0000), vec4(0.0110, 0.0621, 0.1453, 1.0000),
    vec4(0.0076, 0.0509, 0.1286, 1.0000), vec4(0.0055, 0.0436, 0.1111, 1.0000), vec4(0.0043, 0.0370, 0.0957, 1.0000),
    vec4(0.0035, 0.0320, 0.0839, 1.0000), vec4(0.0028, 0.0284, 0.0732, 1.0000), vec4(0.0031, 0.0250, 0.0636, 1.0000),
    vec4(0.0038, 0.0227, 0.0549, 1.0000), vec4(0.0021, 0.0171, 0.0436, 1.0000), vec4(0.0017, 0.0147, 0.0370, 1.0000),
    vec4(0.1999, 0.3276, 0.3933, 1.0000), vec4(0.1921, 0.3342, 0.4273, 1.0000), vec4(0.1740, 0.3211, 0.4364, 1.0000),
    vec4(0.1544, 0.3085, 0.4364, 1.0000), vec4(0.1340, 0.2907, 0.4364, 1.0000), vec4(0.1111, 0.2633, 0.4185, 1.0000),
    vec4(0.0896, 0.2386, 0.3933, 1.0000), vec4(0.0732, 0.2039, 0.3551, 1.0000), vec4(0.0592, 0.1672, 0.3085, 1.0000),
    vec4(0.0424, 0.1453, 0.2907, 1.0000), vec4(0.0275, 0.1234, 0.2685, 1.0000), vec4(0.0184, 0.0978, 0.2249, 1.0000),
    vec4(0.0120, 0.0784, 0.1884, 1.0000), vec4(0.0072, 0.0651, 0.1672, 1.0000), vec4(0.0040, 0.0523, 0.1424, 1.0000),
    vec4(0.0028, 0.0436, 0.1208, 1.0000), vec4(0.0028, 0.0380, 0.1088, 1.0000), vec4(0.0022, 0.0320, 0.0937, 1.0000),
    vec4(0.0016, 0.0267, 0.0820, 1.0000), vec4(0.0013, 0.0242, 0.0732, 1.0000), vec4(0.0021, 0.0242, 0.0636, 1.0000),
    vec4(0.0028, 0.0212, 0.0549, 1.0000), vec4(0.0014, 0.0159, 0.0436, 1.0000), vec4(0.0013, 0.0131, 0.0349, 1.0000),
    vec4(0.0978, 0.2294, 0.3342, 1.0000), vec4(0.0957, 0.2340, 0.3480, 1.0000), vec4(0.0858, 0.2294, 0.3698, 1.0000),
    vec4(0.0784, 0.2163, 0.3624, 1.0000), vec4(0.0667, 0.2079, 0.3624, 1.0000), vec4(0.0549, 0.1884, 0.3624, 1.0000),
    vec4(0.0436, 0.1706, 0.3480, 1.0000), vec4(0.0349, 0.1483, 0.3211, 1.0000), vec4(0.0258, 0.1286, 0.2850, 1.0000),
    vec4(0.0178, 0.1088, 0.2633, 1.0000), vec4(0.0125, 0.0957, 0.2433, 1.0000), vec4(0.0084, 0.0802, 0.2120, 1.0000),
    vec4(0.0043, 0.0636, 0.1775, 1.0000), vec4(0.0028, 0.0536, 0.1544, 1.0000), vec4(0.0021, 0.0459, 0.1340, 1.0000),
    vec4(0.0019, 0.0391, 0.1184, 1.0000), vec4(0.0016, 0.0330, 0.1043, 1.0000), vec4(0.0014, 0.0275, 0.0896, 1.0000),
    vec4(0.0013, 0.0242, 0.0802, 1.0000), vec4(0.0011, 0.0212, 0.0715, 1.0000), vec4(0.0016, 0.0198, 0.0621, 1.0000),
    vec4(0.0013, 0.0159, 0.0497, 1.0000), vec4(0.0011, 0.0136, 0.0402, 1.0000), vec4(0.0010, 0.0115, 0.0339, 1.0000),
    vec4(0.0459, 0.1607, 0.2907, 1.0000), vec4(0.0447, 0.1672, 0.3024, 1.0000), vec4(0.0497, 0.1706, 0.3211, 1.0000),
    vec4(0.0459, 0.1639, 0.3211, 1.0000), vec4(0.0330, 0.1483, 0.3211, 1.0000), vec4(0.0275, 0.1367, 0.3085, 1.0000),
    vec4(0.0250, 0.1286, 0.2907, 1.0000), vec4(0.0171, 0.1159, 0.2850, 1.0000), vec4(0.0101, 0.0978, 0.2582, 1.0000),
    vec4(0.0058, 0.0839, 0.2340, 1.0000), vec4(0.0058, 0.0767, 0.2120, 1.0000), vec4(0.0028, 0.0636, 0.1847, 1.0000),
    vec4(0.0014, 0.0523, 0.1607, 1.0000), vec4(0.0016, 0.0447, 0.1395, 1.0000), vec4(0.0016, 0.0391, 0.1259, 1.0000),
    vec4(0.0014, 0.0339, 0.1111, 1.0000), vec4(0.0013, 0.0275, 0.0978, 1.0000), vec4(0.0014, 0.0258, 0.0877, 1.0000),
    vec4(0.0011, 0.0212, 0.0749, 1.0000), vec4(0.0010, 0.0184, 0.0651, 1.0000), vec4(0.0010, 0.0159, 0.0549, 1.0000),
    vec4(0.0010, 0.0136, 0.0447, 1.0000), vec4(0.0010, 0.0115, 0.0370, 1.0000), vec4(0.0009, 0.0110, 0.0330, 1.0000),
    vec4(0.0242, 0.1184, 0.2433, 1.0000), vec4(0.0227, 0.1208, 0.2582, 1.0000), vec4(0.0212, 0.1208, 0.2685, 1.0000),
    vec4(0.0184, 0.1159, 0.2685, 1.0000), vec4(0.0153, 0.1111, 0.2685, 1.0000), vec4(0.0212, 0.1135, 0.2582, 1.0000),
    vec4(0.0219, 0.1065, 0.2482, 1.0000), vec4(0.0096, 0.0896, 0.2386, 1.0000), vec4(0.0038, 0.0767, 0.2206, 1.0000),
    vec4(0.0017, 0.0651, 0.1999, 1.0000), vec4(0.0013, 0.0577, 0.1775, 1.0000), vec4(0.0011, 0.0509, 0.1607, 1.0000),
    vec4(0.0014, 0.0436, 0.1395, 1.0000), vec4(0.0014, 0.0370, 0.1208, 1.0000), vec4(0.0013, 0.0320, 0.1111, 1.0000),
    vec4(0.0011, 0.0275, 0.0999, 1.0000), vec4(0.0011, 0.0242, 0.0896, 1.0000), vec4(0.0011, 0.0212, 0.0802, 1.0000),
    vec4(0.0011, 0.0198, 0.0699, 1.0000), vec4(0.0010, 0.0159, 0.0577, 1.0000), vec4(0.0010, 0.0136, 0.0484, 1.0000),
    vec4(0.0010, 0.0120, 0.0413, 1.0000), vec4(0.0009, 0.0105, 0.0349, 1.0000), vec4(0.0009, 0.0105, 0.0349, 1.0000)
);

const vec4 DOME_ACT4[288] = vec4[288](
    vec4(0.0198, 0.0121, 0.0053, 1.0000), vec4(0.0191, 0.0121, 0.0053, 1.0000), vec4(0.0212, 0.0126, 0.0056, 1.0000),
    vec4(0.0212, 0.0142, 0.0081, 1.0000), vec4(0.0275, 0.0185, 0.0111, 1.0000), vec4(0.0227, 0.0160, 0.0098, 1.0000),
    vec4(0.0219, 0.0142, 0.0085, 1.0000), vec4(0.0328, 0.0198, 0.0107, 1.0000), vec4(0.0234, 0.0142, 0.0070, 1.0000),
    vec4(0.0572, 0.0389, 0.0234, 1.0000), vec4(0.0946, 0.0601, 0.0358, 1.0000), vec4(0.0776, 0.0506, 0.0301, 1.0000),
    vec4(0.0725, 0.0481, 0.0275, 1.0000), vec4(0.0692, 0.0445, 0.0258, 1.0000), vec4(0.0506, 0.0358, 0.0227, 1.0000),
    vec4(0.0283, 0.0185, 0.0116, 1.0000), vec4(0.0266, 0.0178, 0.0107, 1.0000), vec4(0.0227, 0.0148, 0.0081, 1.0000),
    vec4(0.0242, 0.0148, 0.0073, 1.0000), vec4(0.0258, 0.0154, 0.0077, 1.0000), vec4(0.0160, 0.0111, 0.0081, 1.0000),
    vec4(0.0154, 0.0111, 0.0085, 1.0000), vec4(0.0154, 0.0111, 0.0085, 1.0000), vec4(0.0154, 0.0111, 0.0085, 1.0000),
    vec4(0.0166, 0.0121, 0.0070, 1.0000), vec4(0.0160, 0.0116, 0.0070, 1.0000), vec4(0.0172, 0.0121, 0.0070, 1.0000),
    vec4(0.0191, 0.0126, 0.0077, 1.0000), vec4(0.0205, 0.0137, 0.0077, 1.0000), vec4(0.0275, 0.0212, 0.0126, 1.0000),
    vec4(0.0212, 0.0154, 0.0085, 1.0000), vec4(0.0422, 0.0301, 0.0172, 1.0000), vec4(0.0545, 0.0493, 0.0378, 1.0000),
    vec4(0.1896, 0.1494, 0.0988, 1.0000), vec4(0.2402, 0.1718, 0.1076, 1.0000), vec4(0.2220, 0.1651, 0.1031, 1.0000),
    vec4(0.2134, 0.1651, 0.1031, 1.0000), vec4(0.2134, 0.1651, 0.1031, 1.0000), vec4(0.1787, 0.1435, 0.0967, 1.0000),
    vec4(0.0830, 0.0742, 0.0545, 1.0000), vec4(0.0301, 0.0212, 0.0126, 1.0000), vec4(0.0242, 0.0160, 0.0085, 1.0000),
    vec4(0.0258, 0.0166, 0.0077, 1.0000), vec4(0.0205, 0.0148, 0.0085, 1.0000), vec4(0.0148, 0.0111, 0.0077, 1.0000),
    vec4(0.0172, 0.0126, 0.0073, 1.0000), vec4(0.0137, 0.0107, 0.0070, 1.0000), vec4(0.0142, 0.0111, 0.0070, 1.0000),
    vec4(0.0160, 0.0107, 0.0066, 1.0000), vec4(0.0198, 0.0132, 0.0081, 1.0000), vec4(0.0142, 0.0111, 0.0081, 1.0000),
    vec4(0.0148, 0.0111, 0.0077, 1.0000), vec4(0.0227, 0.0250, 0.0227, 1.0000), vec4(0.0234, 0.0250, 0.0227, 1.0000),
    vec4(0.0456, 0.0572, 0.0559, 1.0000), vec4(0.0645, 0.0794, 0.0759, 1.0000), vec4(0.1009, 0.1169, 0.1098, 1.0000),
    vec4(0.1435, 0.1296, 0.1076, 1.0000), vec4(0.1618, 0.1406, 0.1098, 1.0000), vec4(0.1524, 0.1350, 0.1098, 1.0000),
    vec4(0.1494, 0.1323, 0.1076, 1.0000), vec4(0.1464, 0.1323, 0.1076, 1.0000), vec4(0.1270, 0.1244, 0.1053, 1.0000),
    vec4(0.0906, 0.1053, 0.0988, 1.0000), vec4(0.0587, 0.0759, 0.0759, 1.0000), vec4(0.0468, 0.0493, 0.0422, 1.0000),
    vec4(0.0275, 0.0258, 0.0212, 1.0000), vec4(0.0234, 0.0266, 0.0250, 1.0000), vec4(0.0142, 0.0121, 0.0093, 1.0000),
    vec4(0.0148, 0.0111, 0.0077, 1.0000), vec4(0.0148, 0.0116, 0.0077, 1.0000), vec4(0.0142, 0.0107, 0.0073, 1.0000),
    vec4(0.0242, 0.0142, 0.0081, 1.0000), vec4(0.0283, 0.0166, 0.0089, 1.0000), vec4(0.0191, 0.0126, 0.0077, 1.0000),
    vec4(0.0198, 0.0137, 0.0085, 1.0000), vec4(0.0368, 0.0572, 0.0692, 1.0000), vec4(0.0328, 0.0572, 0.0725, 1.0000),
    vec4(0.0456, 0.0742, 0.0946, 1.0000), vec4(0.0532, 0.0794, 0.0967, 1.0000), vec4(0.0676, 0.0868, 0.0967, 1.0000),
    vec4(0.1098, 0.1122, 0.1098, 1.0000), vec4(0.1244, 0.1169, 0.1098, 1.0000), vec4(0.1194, 0.1169, 0.1098, 1.0000),
    vec4(0.1169, 0.1145, 0.1098, 1.0000), vec4(0.1145, 0.1145, 0.1098, 1.0000), vec4(0.0988, 0.1053, 0.1076, 1.0000),
    vec4(0.0661, 0.0849, 0.0967, 1.0000), vec4(0.0545, 0.0812, 0.0967, 1.0000), vec4(0.0468, 0.0742, 0.0906, 1.0000),
    vec4(0.0400, 0.0676, 0.0849, 1.0000), vec4(0.0389, 0.0601, 0.0676, 1.0000), vec4(0.0178, 0.0198, 0.0185, 1.0000),
    vec4(0.0085, 0.0132, 0.0154, 1.0000), vec4(0.0191, 0.0234, 0.0227, 1.0000), vec4(0.0148, 0.0116, 0.0085, 1.0000),
    vec4(0.0212, 0.0111, 0.0063, 1.0000), vec4(0.0242, 0.0154, 0.0093, 1.0000), vec4(0.0166, 0.0137, 0.0107, 1.0000),
    vec4(0.0198, 0.0126, 0.0081, 1.0000), vec4(0.0266, 0.0456, 0.0587, 1.0000), vec4(0.0310, 0.0615, 0.0906, 1.0000),
    vec4(0.0348, 0.0601, 0.0830, 1.0000), vec4(0.0410, 0.0645, 0.0887, 1.0000), vec4(0.0532, 0.0725, 0.0926, 1.0000),
    vec4(0.0776, 0.0887, 0.1009, 1.0000), vec4(0.0887, 0.0946, 0.1031, 1.0000), vec4(0.0849, 0.0926, 0.1031, 1.0000),
    vec4(0.0849, 0.0926, 0.1031, 1.0000), vec4(0.0849, 0.0906, 0.1031, 1.0000), vec4(0.0742, 0.0868, 0.1009, 1.0000),
    vec4(0.0519, 0.0742, 0.0906, 1.0000), vec4(0.0422, 0.0661, 0.0887, 1.0000), vec4(0.0348, 0.0615, 0.0849, 1.0000),
    vec4(0.0319, 0.0587, 0.0812, 1.0000), vec4(0.0301, 0.0601, 0.0868, 1.0000), vec4(0.0160, 0.0250, 0.0301, 1.0000),
    vec4(0.0081, 0.0107, 0.0121, 1.0000), vec4(0.0191, 0.0368, 0.0493, 1.0000), vec4(0.0227, 0.0433, 0.0587, 1.0000),
    vec4(0.0142, 0.0234, 0.0319, 1.0000), vec4(0.0185, 0.0338, 0.0481, 1.0000), vec4(0.0121, 0.0172, 0.0198, 1.0000),
    vec4(0.0160, 0.0137, 0.0116, 1.0000), vec4(0.0234, 0.0422, 0.0615, 1.0000), vec4(0.0250, 0.0493, 0.0776, 1.0000),
    vec4(0.0275, 0.0519, 0.0776, 1.0000), vec4(0.0319, 0.0559, 0.0812, 1.0000), vec4(0.0410, 0.0601, 0.0830, 1.0000),
    vec4(0.0559, 0.0709, 0.0887, 1.0000), vec4(0.0615, 0.0725, 0.0906, 1.0000), vec4(0.0587, 0.0725, 0.0906, 1.0000),
    vec4(0.0587, 0.0725, 0.0906, 1.0000), vec4(0.0587, 0.0725, 0.0906, 1.0000), vec4(0.0545, 0.0692, 0.0887, 1.0000),
    vec4(0.0400, 0.0615, 0.0830, 1.0000), vec4(0.0319, 0.0572, 0.0830, 1.0000), vec4(0.0283, 0.0532, 0.0794, 1.0000),
    vec4(0.0258, 0.0493, 0.0742, 1.0000), vec4(0.0242, 0.0481, 0.0759, 1.0000), vec4(0.0212, 0.0389, 0.0559, 1.0000),
    vec4(0.0154, 0.0275, 0.0368, 1.0000), vec4(0.0191, 0.0389, 0.0587, 1.0000), vec4(0.0205, 0.0445, 0.0676, 1.0000),
    vec4(0.0178, 0.0400, 0.0676, 1.0000), vec4(0.0178, 0.0400, 0.0661, 1.0000), vec4(0.0142, 0.0292, 0.0445, 1.0000),
    vec4(0.0166, 0.0348, 0.0559, 1.0000), vec4(0.0198, 0.0410, 0.0692, 1.0000), vec4(0.0205, 0.0422, 0.0692, 1.0000),
    vec4(0.0227, 0.0445, 0.0709, 1.0000), vec4(0.0258, 0.0468, 0.0742, 1.0000), vec4(0.0319, 0.0506, 0.0742, 1.0000),
    vec4(0.0410, 0.0559, 0.0776, 1.0000), vec4(0.0445, 0.0601, 0.0776, 1.0000), vec4(0.0456, 0.0601, 0.0776, 1.0000),
    vec4(0.0468, 0.0601, 0.0794, 1.0000), vec4(0.0445, 0.0587, 0.0794, 1.0000), vec4(0.0410, 0.0572, 0.0776, 1.0000),
    vec4(0.0310, 0.0519, 0.0776, 1.0000), vec4(0.0258, 0.0481, 0.0759, 1.0000), vec4(0.0234, 0.0445, 0.0709, 1.0000),
    vec4(0.0219, 0.0433, 0.0692, 1.0000), vec4(0.0198, 0.0422, 0.0661, 1.0000), vec4(0.0191, 0.0422, 0.0676, 1.0000),
    vec4(0.0191, 0.0433, 0.0709, 1.0000), vec4(0.0178, 0.0400, 0.0645, 1.0000), vec4(0.0166, 0.0368, 0.0601, 1.0000),
    vec4(0.0142, 0.0319, 0.0545, 1.0000), vec4(0.0148, 0.0328, 0.0559, 1.0000), vec4(0.0160, 0.0358, 0.0615, 1.0000),
    vec4(0.0166, 0.0358, 0.0601, 1.0000), vec4(0.0166, 0.0358, 0.0601, 1.0000), vec4(0.0178, 0.0368, 0.0615, 1.0000),
    vec4(0.0191, 0.0389, 0.0630, 1.0000), vec4(0.0212, 0.0400, 0.0645, 1.0000), vec4(0.0250, 0.0422, 0.0676, 1.0000),
    vec4(0.0310, 0.0468, 0.0676, 1.0000), vec4(0.0389, 0.0519, 0.0709, 1.0000), vec4(0.0445, 0.0559, 0.0725, 1.0000),
    vec4(0.0445, 0.0545, 0.0725, 1.0000), vec4(0.0378, 0.0519, 0.0709, 1.0000), vec4(0.0310, 0.0468, 0.0692, 1.0000),
    vec4(0.0250, 0.0433, 0.0692, 1.0000), vec4(0.0219, 0.0410, 0.0661, 1.0000), vec4(0.0198, 0.0389, 0.0630, 1.0000),
    vec4(0.0185, 0.0368, 0.0615, 1.0000), vec4(0.0172, 0.0368, 0.0601, 1.0000), vec4(0.0166, 0.0348, 0.0587, 1.0000),
    vec4(0.0154, 0.0338, 0.0559, 1.0000), vec4(0.0148, 0.0338, 0.0559, 1.0000), vec4(0.0148, 0.0328, 0.0559, 1.0000),
    vec4(0.0121, 0.0292, 0.0493, 1.0000), vec4(0.0132, 0.0292, 0.0506, 1.0000), vec4(0.0132, 0.0292, 0.0506, 1.0000),
    vec4(0.0137, 0.0301, 0.0519, 1.0000), vec4(0.0142, 0.0310, 0.0532, 1.0000), vec4(0.0148, 0.0319, 0.0545, 1.0000),
    vec4(0.0166, 0.0328, 0.0559, 1.0000), vec4(0.0185, 0.0348, 0.0572, 1.0000), vec4(0.0205, 0.0358, 0.0587, 1.0000),
    vec4(0.0234, 0.0389, 0.0615, 1.0000), vec4(0.0275, 0.0422, 0.0630, 1.0000), vec4(0.0310, 0.0433, 0.0630, 1.0000),
    vec4(0.0310, 0.0433, 0.0630, 1.0000), vec4(0.0275, 0.0422, 0.0630, 1.0000), vec4(0.0234, 0.0389, 0.0615, 1.0000),
    vec4(0.0205, 0.0368, 0.0601, 1.0000), vec4(0.0185, 0.0358, 0.0572, 1.0000), vec4(0.0172, 0.0338, 0.0559, 1.0000),
    vec4(0.0160, 0.0319, 0.0545, 1.0000), vec4(0.0142, 0.0319, 0.0532, 1.0000), vec4(0.0137, 0.0310, 0.0519, 1.0000),
    vec4(0.0132, 0.0301, 0.0506, 1.0000), vec4(0.0126, 0.0292, 0.0506, 1.0000), vec4(0.0126, 0.0292, 0.0493, 1.0000),
    vec4(0.0116, 0.0266, 0.0493, 1.0000), vec4(0.0116, 0.0266, 0.0493, 1.0000), vec4(0.0116, 0.0275, 0.0493, 1.0000),
    vec4(0.0121, 0.0275, 0.0481, 1.0000), vec4(0.0121, 0.0283, 0.0481, 1.0000), vec4(0.0132, 0.0283, 0.0493, 1.0000),
    vec4(0.0142, 0.0283, 0.0493, 1.0000), vec4(0.0154, 0.0301, 0.0519, 1.0000), vec4(0.0172, 0.0319, 0.0519, 1.0000),
    vec4(0.0185, 0.0338, 0.0545, 1.0000), vec4(0.0212, 0.0348, 0.0559, 1.0000), vec4(0.0227, 0.0358, 0.0559, 1.0000),
    vec4(0.0227, 0.0358, 0.0559, 1.0000), vec4(0.0212, 0.0348, 0.0559, 1.0000), vec4(0.0185, 0.0338, 0.0545, 1.0000),
    vec4(0.0172, 0.0319, 0.0519, 1.0000), vec4(0.0160, 0.0310, 0.0519, 1.0000), vec4(0.0148, 0.0292, 0.0506, 1.0000),
    vec4(0.0137, 0.0283, 0.0493, 1.0000), vec4(0.0126, 0.0283, 0.0481, 1.0000), vec4(0.0121, 0.0275, 0.0481, 1.0000),
    vec4(0.0116, 0.0275, 0.0493, 1.0000), vec4(0.0116, 0.0266, 0.0493, 1.0000), vec4(0.0111, 0.0258, 0.0493, 1.0000),
    vec4(0.0098, 0.0242, 0.0433, 1.0000), vec4(0.0102, 0.0242, 0.0445, 1.0000), vec4(0.0102, 0.0242, 0.0456, 1.0000),
    vec4(0.0102, 0.0242, 0.0456, 1.0000), vec4(0.0111, 0.0250, 0.0445, 1.0000), vec4(0.0116, 0.0250, 0.0445, 1.0000),
    vec4(0.0121, 0.0258, 0.0456, 1.0000), vec4(0.0132, 0.0266, 0.0456, 1.0000), vec4(0.0148, 0.0275, 0.0468, 1.0000),
    vec4(0.0160, 0.0283, 0.0481, 1.0000), vec4(0.0172, 0.0292, 0.0481, 1.0000), vec4(0.0178, 0.0301, 0.0493, 1.0000),
    vec4(0.0178, 0.0301, 0.0493, 1.0000), vec4(0.0172, 0.0301, 0.0493, 1.0000), vec4(0.0160, 0.0283, 0.0481, 1.0000),
    vec4(0.0148, 0.0275, 0.0456, 1.0000), vec4(0.0137, 0.0266, 0.0456, 1.0000), vec4(0.0121, 0.0258, 0.0456, 1.0000),
    vec4(0.0116, 0.0250, 0.0445, 1.0000), vec4(0.0111, 0.0250, 0.0445, 1.0000), vec4(0.0107, 0.0242, 0.0445, 1.0000),
    vec4(0.0102, 0.0242, 0.0445, 1.0000), vec4(0.0102, 0.0242, 0.0433, 1.0000), vec4(0.0098, 0.0234, 0.0422, 1.0000),
    vec4(0.0089, 0.0212, 0.0400, 1.0000), vec4(0.0093, 0.0219, 0.0400, 1.0000), vec4(0.0098, 0.0219, 0.0389, 1.0000),
    vec4(0.0098, 0.0219, 0.0400, 1.0000), vec4(0.0102, 0.0227, 0.0400, 1.0000), vec4(0.0107, 0.0227, 0.0410, 1.0000),
    vec4(0.0107, 0.0234, 0.0410, 1.0000), vec4(0.0116, 0.0234, 0.0433, 1.0000), vec4(0.0121, 0.0242, 0.0422, 1.0000),
    vec4(0.0137, 0.0250, 0.0422, 1.0000), vec4(0.0142, 0.0258, 0.0433, 1.0000), vec4(0.0148, 0.0258, 0.0422, 1.0000),
    vec4(0.0142, 0.0258, 0.0422, 1.0000), vec4(0.0142, 0.0258, 0.0433, 1.0000), vec4(0.0137, 0.0250, 0.0422, 1.0000),
    vec4(0.0121, 0.0242, 0.0422, 1.0000), vec4(0.0116, 0.0234, 0.0433, 1.0000), vec4(0.0107, 0.0234, 0.0422, 1.0000),
    vec4(0.0102, 0.0227, 0.0410, 1.0000), vec4(0.0098, 0.0219, 0.0400, 1.0000), vec4(0.0098, 0.0219, 0.0389, 1.0000),
    vec4(0.0098, 0.0212, 0.0389, 1.0000), vec4(0.0093, 0.0212, 0.0389, 1.0000), vec4(0.0085, 0.0212, 0.0389, 1.0000)
);

vec3 sampleDomeAct1(vec2 domeUv) {
    vec2 g = clamp(domeUv, vec2(0.0), vec2(1.0)) * vec2(float(DOME_W - 1), float(DOME_H - 1));
    ivec2 i0 = ivec2(floor(g));
    ivec2 i1 = min(i0 + ivec2(1), ivec2(DOME_W - 1, DOME_H - 1));
    vec2 f = fract(g);
    vec3 c00 = DOME_ACT1[i0.y * DOME_W + i0.x].rgb;
    vec3 c10 = DOME_ACT1[i0.y * DOME_W + i1.x].rgb;
    vec3 c01 = DOME_ACT1[i1.y * DOME_W + i0.x].rgb;
    vec3 c11 = DOME_ACT1[i1.y * DOME_W + i1.x].rgb;
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

vec3 sampleDomeAct2(vec2 domeUv) {
    vec2 g = clamp(domeUv, vec2(0.0), vec2(1.0)) * vec2(float(DOME_W - 1), float(DOME_H - 1));
    ivec2 i0 = ivec2(floor(g));
    ivec2 i1 = min(i0 + ivec2(1), ivec2(DOME_W - 1, DOME_H - 1));
    vec2 f = fract(g);
    vec3 c00 = DOME_ACT2[i0.y * DOME_W + i0.x].rgb;
    vec3 c10 = DOME_ACT2[i0.y * DOME_W + i1.x].rgb;
    vec3 c01 = DOME_ACT2[i1.y * DOME_W + i0.x].rgb;
    vec3 c11 = DOME_ACT2[i1.y * DOME_W + i1.x].rgb;
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

vec3 sampleDomeAct3(vec2 domeUv, float u3) {
    vec2 g = clamp(domeUv, vec2(0.0), vec2(1.0)) * vec2(float(DOME_W - 1), float(DOME_H - 1));
    ivec2 i0 = ivec2(floor(g));
    ivec2 i1 = min(i0 + ivec2(1), ivec2(DOME_W - 1, DOME_H - 1));
    vec2 f = fract(g);
    int k00 = i0.y * DOME_W + i0.x;
    int k10 = i0.y * DOME_W + i1.x;
    int k01 = i1.y * DOME_W + i0.x;
    int k11 = i1.y * DOME_W + i1.x;
    vec3 sA = mix(mix(DOME_ACT3_START[k00].rgb, DOME_ACT3_START[k10].rgb, f.x), mix(DOME_ACT3_START[k01].rgb, DOME_ACT3_START[k11].rgb, f.x), f.y);
    vec3 sB = mix(mix(DOME_ACT3_MID[k00].rgb,   DOME_ACT3_MID[k10].rgb,   f.x), mix(DOME_ACT3_MID[k01].rgb,   DOME_ACT3_MID[k11].rgb,   f.x), f.y);
    vec3 sC = mix(mix(DOME_ACT3_END[k00].rgb,   DOME_ACT3_END[k10].rgb,   f.x), mix(DOME_ACT3_END[k01].rgb,   DOME_ACT3_END[k11].rgb,   f.x), f.y);
    if (u3 < 2.0) return mix(sA, sB, smoothstep(0.0, 2.0, u3));
    return mix(sB, sC, smoothstep(2.0, 4.2, u3));
}

vec3 sampleDomeAct4(vec2 domeUv) {
    vec2 g = clamp(domeUv, vec2(0.0), vec2(1.0)) * vec2(float(DOME_W - 1), float(DOME_H - 1));
    ivec2 i0 = ivec2(floor(g));
    ivec2 i1 = min(i0 + ivec2(1), ivec2(DOME_W - 1, DOME_H - 1));
    vec2 f = fract(g);
    vec3 c00 = DOME_ACT4[i0.y * DOME_W + i0.x].rgb;
    vec3 c10 = DOME_ACT4[i0.y * DOME_W + i1.x].rgb;
    vec3 c01 = DOME_ACT4[i1.y * DOME_W + i0.x].rgb;
    vec3 c11 = DOME_ACT4[i1.y * DOME_W + i1.x].rgb;
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

// Mutable active-scene selector for shared shader-skills raymarch/normal/shadow/AO helpers
int gActiveAct = 1;

// Mouse free-look offset (active when user holds & drags mouse on canvas; zero otherwise)
vec2 mouseOrbitOffset() {
    if (iMouse.z <= 0.0 || iResolution.y < 1.0) return vec2(0.0);
    vec2 cur = iMouse.xy / iResolution.xy - 0.5;
    vec2 clk = abs(iMouse.zw) / iResolution.xy - 0.5;
    return (cur - clk) * vec2(2.6, 1.4);
}

// =================================================================================================
// ACT I — EMERALD LAGOON, SANDBARS, VOLCANIC BOULDER REEFS & OBSIDIAN RING MONOLITH (0.0s .. 5.0s)
// =================================================================================================

float act1BoulderField(vec2 p) {
    // Rounded wet volcanic cobbles for flanking reef clusters
    float macro = 1.0 - smoothVoronoi(p * 1.45, 8.0);
    float med   = 1.0 - smoothVoronoi(p * 3.10 + 4.1, 9.5);
    float fine  = fbm(p * 5.5, 3);
    return 0.50 * macro + 0.22 * med + 0.05 * fine;
}

// Returns vec2(height, rockinessMask) keeping golden sandbars silky smooth and volcanic reefs dark & cobbly
vec2 act1BedInfo(vec2 p) {
    float h = -0.88 + 0.09 * fbm(p * 0.28, 3);
    float rockMask = 0.0;
    float sandRipple = 0.011 * sin(p.x * 5.0 + p.y * 3.2 + 1.2 * fbm(p * 0.8, 2));

    // 1. Diagonal golden sandbar spit entering from lower-right foreground at t = 0.0s..1.5s!
    vec2 spA = vec2(1.05, 5.6);
    vec2 spDir = normalize(vec2(0.76, 0.65));
    float proj = clamp(dot(p - spA, spDir), 0.0, 12.5);
    float spitDist = length(p - (spA + spDir * proj));
    float spitMask = exp(-0.22 * spitDist * spitDist);
    h += (0.985 + sandRipple) * spitMask;

    // 2. Smooth golden sandbars emerging at t = 0.0s (mid-left) and t = 3.0..4.5s (left & mid-right)!
    vec2 sb0 = (p - vec2(-1.15, 7.6)) * vec2(0.85, 1.35);
    vec2 sb1 = (p - vec2(-1.85, -1.6)) * vec2(0.52, 0.95);
    vec2 sb2 = (p - vec2(2.55, -5.2)) * vec2(0.45, 0.95);
    vec2 sb3 = (p - vec2(1.65, -12.0)) * vec2(0.42, 1.15);
    float sandBars = exp(-0.48 * dot(sb0, sb0))
                   + 1.02 * exp(-0.32 * dot(sb1, sb1))
                   + 1.00 * exp(-0.26 * dot(sb2, sb2))
                   + 0.96 * exp(-0.24 * dot(sb3, sb3));
    h += (0.955 + sandRipple) * sandBars;

    // 3. Flanking dark volcanic boulder reefs (strictly outside |x| > 5.2 and behind z > 1.8 so t = 3.5..4.5s stays open!)
    float boulders = act1BoulderField(p);
    vec2 nl = (p - vec2(-6.35, 5.2)) * vec2(0.28, 0.25);
    vec2 nr = (p - vec2(6.45, 4.8)) * vec2(0.28, 0.25);
    float nearReef = exp(-dot(nl, nl)) + exp(-dot(nr, nr));
    // Mid-distance dark rocky spits framing the central reflection lane at z = -6.5
    vec2 ml = (p - vec2(-8.8, -5.8)) * vec2(0.22, 0.34);
    vec2 mr = (p - vec2(8.9, -5.6)) * vec2(0.22, 0.34);
    float midReef = exp(-dot(ml, ml)) + exp(-dot(mr, mr));

    float totalReef = nearReef + 0.95 * midReef;
    h += totalReef * (0.98 + 0.78 * boulders);
    rockMask = saturate(totalReef * 1.85 * (1.0 - saturate(spitMask * 1.6)));

    // 4. Far volcanic headlands framing left & right horizon
    vec2 fl = (p - vec2(-22.5, -27.5)) * vec2(0.088, 0.145);
    vec2 fr = (p - vec2(22.8, -27.0)) * vec2(0.088, 0.145);
    float farMask = exp(-dot(fl, fl)) + exp(-dot(fr, fr));
    float ridges = 0.58 + 0.56 * ridgedFbm(p * 0.26, 4) + 0.28 * erodedFbm(p * 0.38, 4);
    h += 3.85 * farMask * ridges;
    rockMask = max(rockMask, saturate(farMask * 2.2));

    return vec2(h, rockMask);
}

float act1Bed(vec2 p) {
    return act1BedInfo(p).x;
}

vec3 act1BedNormal(vec2 p, float eps) {
    float hx = act1Bed(p + vec2(eps, 0.0)) - act1Bed(p - vec2(eps, 0.0));
    float hz = act1Bed(p + vec2(0.0, eps)) - act1Bed(p - vec2(0.0, eps));
    return normalize(vec3(-hx, 2.0 * eps, -hz));
}

float sdAct1Ring(vec3 p) {
    vec3 q = p - ACT1_RING_POS;
    float tor = sdTorus(q.xzy, ACT1_RING_DIM);
    float slab = abs(q.z) - 0.62;
    return smax(tor, slab, 0.20);
}

vec2 mapAct1(vec3 p) {
    float dRing = sdAct1Ring(p);
    float dLand = (p.y - act1Bed(p.xz)) * 0.52;
    if (dRing < dLand) return vec2(dRing, MAT_MONOLITH);
    return vec2(dLand, MAT_TERRAIN);
}

vec4 act1Waves(vec2 p, float loopPhase, float footprint) {
    vec4 sum = vec4(0.0);
    const int N = QUALITY >= 3 ? 7 : 5;
    for (int i = 0; i < N; i++) {
        float fi = float(i);
        float ang = 0.62 + fi * 2.12;
        vec2 dir = vec2(cos(ang), sin(ang));
        float wl = 2.9 * pow(0.68, fi);
        float amp = 0.017 * pow(0.65, fi);
        float k = TAU / wl;
        float freq = floor(3.0 + fi * 2.0);
        float atten = exp(-0.22 * k * footprint * k * footprint);
        float ph = k * dot(p, dir) - freq * loopPhase + fi * 1.7;
        float s = sin(ph), c = cos(ph);
        sum.x += amp * atten * s;
        sum.yz += amp * atten * k * c * dir;
        sum.w += -amp * atten * k * k * s;
    }
    return sum;
}

vec3 act1Sky(vec3 rd, float u1, float loopPhase) {
    vec3 sun = normalize(ACT1_SUN_DIR);
    float up = saturate(rd.y);
    float mu = max(dot(rd, sun), 0.0);

    // Rich azure-cerulean upper sky grading into warm golden-cream low horizon matching sheet_act1.jpg!
    vec3 zenithCol  = srgbToLinear(vec3(0.14, 0.34, 0.56));
    vec3 midSkyCol  = srgbToLinear(vec3(0.38, 0.52, 0.65));
    vec3 horizonCol = srgbToLinear(vec3(0.84, 0.77, 0.62));
    vec3 sky = mixOklab(horizonCol, midSkyCol, smoothstep(0.0, 0.22, up));
    sky = mixOklab(sky, zenithCol, smoothstep(0.18, 0.62, up));
    vec2 domeLookup1 = vec2(0.5 + 0.49 * (rd.x / max(-rd.z, 0.25)), saturate(rd.y * 1.78));
    sky = mix(sky, sampleDomeAct1(domeLookup1), 0.58);

    // Warm golden atmospheric sun halo centered right behind the black obsidian ring!
    sky += srgbToLinear(vec3(1.0, 0.91, 0.70)) * (0.95 * pow(mu, 14.0) + 0.36 * pow(mu, 3.2));
    sky += vec3(2.2, 1.85, 1.25) * smoothstep(0.9965, 0.9996, mu);

    // Sculptural puffy cumulus clouds mapped on curved sky dome (zero radial streak distortion!)
    if (rd.y > 0.010) {
        vec2 dome = vec2(rd.x / max(-rd.z, 0.28), rd.y * 2.35);
        vec2 q = dome * vec2(1.55, 2.05) + vec2(u1 * 0.028, 0.25);

        // Combine round cellular cumulus domes + billowy turbulence for crisp photo-real cloud silhouettes!
        float lobes = 1.0 - smoothVoronoi(q * 1.45, 5.5);
        float lobesFine = 1.0 - smoothVoronoi(q * 3.1 + 2.7, 6.5);
        float turb = billowFbm(q * 2.4 + 1.3, 4);
        float shape = lobes * 0.56 + lobesFine * 0.24 + turb * 0.28 + 0.14 * fbm(q * 1.1, 4);

        // Open central solar corridor behind the obsidian ring just like sheet_act1.jpg!
        float flank = smoothstep(0.16, 0.62, abs(dome.x) + max(rd.y - 0.26, 0.0) * 0.65);
        float dens = smoothstep(0.46, 0.66, shape * (0.68 + 0.42 * flank)) * flank * smoothstep(0.012, 0.075, rd.y);

        // Directional self-shadowing away from sun at (0, 0.092)
        vec2 toSun = normalize(vec2(0.0, 0.21) - dome + vec2(1e-4));
        vec2 qs = q + toSun * 0.16;
        float occShape = (1.0 - smoothVoronoi(qs * 1.45, 5.5)) * 0.56
                       + (1.0 - smoothVoronoi(qs * 3.1 + 2.7, 6.5)) * 0.24
                       + billowFbm(qs * 2.4 + 1.3, 3) * 0.28;
        float shadow = smoothstep(0.42, 0.68, occShape);
        float lit = saturate((1.0 - shadow * 0.85) * (0.42 + 0.78 * pow(mu, 1.8)) + 0.22 * smoothstep(0.08, 0.34, rd.y));

        vec3 cloudBelly = srgbToLinear(vec3(0.27, 0.33, 0.39));
        vec3 cloudCream = srgbToLinear(vec3(0.99, 0.92, 0.78)) * (1.08 + 0.55 * pow(mu, 4.0));
        sky = mix(sky, mix(cloudBelly, cloudCream, lit), dens * 0.94);

        // Distant gliding sea birds on exact 20s loop
        vec2 birdCenter = vec2(-0.52 + 0.10 * sin(loopPhase), 0.28 + 0.02 * cos(2.0 * loopPhase));
        vec2 buv = (rd.xy / max(-rd.z, 0.2)) - birdCenter;
        for (int b = 0; b < 2; b++) {
            vec2 bp = (buv - vec2(float(b) * 0.055, float(b) * 0.022)) * 90.0;
            float flap = sin(8.0 * loopPhase + float(b) * 1.9) * 0.36;
            float wing = abs(bp.y - abs(bp.x) * (0.35 + flap) + 0.12 * bp.x * bp.x);
            float bird = smoothstep(0.16, 0.04, wing) * smoothstep(1.10, 0.62, abs(bp.x));
            sky = mix(sky, srgbToLinear(vec3(0.15, 0.16, 0.17)), bird * 0.70);
        }
    }
    return sky;
}

vec3 shadeAct1Land(vec3 p, vec3 n, vec3 ro, float rockMask, bool submerged, float loopPhase, float footprint) {
    vec3 sun = normalize(ACT1_SUN_DIR);
    vec3 v = normalize(ro - p);
    float fineKeep = 1.0 - smoothstep(0.02, 0.22, footprint);
    float grain = 0.5 + 0.5 * fbm(p.xz * 4.5, 4) * fineKeep;
    float cobble = smoothVoronoi(p.xz * 2.6, 8.0);

    // Warm golden honey-tan wet & dry sandbars matching sheet_act1.jpg!
    vec3 sandWet  = srgbToLinear(vec3(0.52, 0.40, 0.23));
    vec3 sandDry  = srgbToLinear(vec3(0.72, 0.59, 0.39));
    vec3 sandCol  = mix(sandWet, sandDry, smoothstep(0.004, 0.075, p.y) * (0.75 + 0.25 * grain));

    // Dark wet volcanic basalt cobbles (matte-damp roughness so zero white glare speckles!)
    vec3 rockDark = srgbToLinear(vec3(0.030, 0.029, 0.027));
    vec3 rockLit  = srgbToLinear(vec3(0.105, 0.092, 0.076));
    vec3 rockCol  = mix(rockDark, rockLit, cobble * 0.72 + grain * 0.28);

    float farIsland = smoothstep(-18.0, -26.0, p.z);
    rockCol = mix(rockCol, srgbToLinear(vec3(0.048, 0.060, 0.042)), farIsland * 0.55);

    vec3 albedo = mix(sandCol, rockCol, rockMask);
    float roughness = mix(0.66, 0.52, rockMask);

    vec3 sunRad = vec3(1.85, 1.54, 1.10);
    vec3 col = shadePBR(n, v, sun, albedo, roughness, 0.0) * sunRad;
    // Open warm sunlit tropical sky dome strongly illuminates flat golden sandbars from overhead!
    vec3 skyFill = mix(srgbToLinear(vec3(0.86, 0.78, 0.62)) * 1.45, srgbToLinear(vec3(0.30, 0.42, 0.52)) * 1.05, rockMask);
    col += albedo * hemisphereLight(n, skyFill, vec3(0.06, 0.05, 0.04));

    if (submerged) {
        float depth = max(-p.y, 0.0);
        col *= beerTransmittance(ACT1_WATER_EXT, depth * 1.35);

        // Glowing cellular Voronoi water caustics dancing across shallow emerald lagoon!
        vec2 flowA = vec2(sin(p.z * 0.65 + 2.0 * loopPhase), cos(p.x * 0.65 - 2.0 * loopPhase)) * 0.18;
        vec2 flowB = vec2(cos(p.z * 0.95 - 3.0 * loopPhase), sin(p.x * 0.95 + 3.0 * loopPhase)) * 0.12;
        float b1 = voronoiBorder(p.xz * 0.72 + flowA, 0.90).x;
        float b2 = voronoiBorder(p.xz * 1.45 - flowB + 5.7, 0.88).x;
        float web1 = pow(1.0 - smoothstep(0.0, 0.14, b1), 2.2);
        float web2 = pow(1.0 - smoothstep(0.0, 0.11, b2), 2.5);
        float caustic = web1 * 1.18 + web2 * 0.50;

        float keep = (1.0 - smoothstep(0.04, 0.34, footprint)) * smoothstep(0.015, 0.15, depth);
        col += srgbToLinear(vec3(0.55, 0.82, 0.66)) * caustic * keep * 0.95 * exp(-depth * 0.26);
    }
    return col;
}

vec3 shadeAct1Monolith(vec3 p, vec3 n, vec3 rd) {
    vec3 sun = normalize(ACT1_SUN_DIR);
    vec3 v = -rd;
    vec3 albedo = srgbToLinear(vec3(0.022, 0.024, 0.028));
    float rLocal = length(p.xy - ACT1_RING_POS.xy);
    float groove = smoothstep(0.05, 0.0, abs(rLocal - ACT1_RING_DIM.x));
    float rough = mix(0.28, 0.48, groove);

    vec3 col = shadePBR(n, v, sun, albedo, rough, 0.15) * vec3(1.4, 1.18, 0.90);
    float grazing = pow(1.0 - saturate(dot(n, v)), 5.0);
    float innerEdge = smoothstep(ACT1_RING_DIM.x + 0.15, ACT1_RING_DIM.x - 0.65, rLocal);
    col += srgbToLinear(vec3(1.0, 0.88, 0.66)) * grazing * (0.14 + 0.44 * innerEdge);
    col += albedo * hemisphereLight(n, srgbToLinear(vec3(0.24, 0.34, 0.44)), vec3(0.03, 0.05, 0.05));
    return col;
}

vec3 renderAct1(vec2 coord, float u1, float loopPhase, out vec3 dbgOut) {
    gActiveAct = 1;
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;
    vec2 orb = mouseOrbitOffset();

    vec3 ro = vec3(sin(orb.x) * 4.5, 2.22 + orb.y * 2.2, 18.2 - 3.65 * u1);
    vec3 ta = ro + vec3(-sin(orb.x) * 6.0, -0.32 - orb.y * 1.5, -20.0);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.75);

    vec3 sky = act1Sky(rd, u1, loopPhase);

    // 1. Exact ray vs Obsidian Ring Monolith
    float ringT = -1.0;
    vec2 bs = iSphere(ro, rd, ACT1_RING_POS, ACT1_RING_DIM.x + ACT1_RING_DIM.y + 0.8);
    int marchSteps = 0;
    if (bs.y > 0.0) {
        float t = max(bs.x, 0.05);
        for (int i = ZERO; i < 64; i++) {
            marchSteps++;
            float d = sdAct1Ring(ro + rd * t);
            if (d < 0.0011 * t) { ringT = t; break; }
            t += d;
            if (t > bs.y) break;
        }
    }

    // 2. Coastal heightfield + lagoon sea surface (y = 0)
    float landT = -1.0;
    float tPrev = 0.05;
    float tCur = 0.05;
    float maxTrace = ringT > 0.0 ? min(ringT, 68.0) : 68.0;
    for (int i = ZERO; i < 112; i++) {
        marchSteps++;
        vec3 p = ro + rd * tCur;
        float surf = max(act1Bed(p.xz), 0.0);
        float gap = p.y - surf;
        if (gap < 0.0) {
            float lo = tPrev, hi = tCur;
            for (int j = 0; j < 7; j++) {
                float mid = 0.5 * (lo + hi);
                vec3 q = ro + rd * mid;
                if (q.y > max(act1Bed(q.xz), 0.0)) lo = mid; else hi = mid;
            }
            landT = 0.5 * (lo + hi);
            break;
        }
        tPrev = tCur;
        tCur += max(gap * 0.42, 0.028 + 0.013 * tCur);
        if (tCur > maxTrace) break;
    }
    if (landT < 0.0 && rd.y < -0.0008) {
        float tp = -ro.y / rd.y;
        if (tp > 0.0 && (ringT < 0.0 || tp < ringT)) landT = tp;
    }

    if (ringT > 0.0 && (landT < 0.0 || ringT < landT)) {
        vec3 p = ro + rd * ringT;
        vec3 n = calcNormal(p, 0.0014 * ringT);
        vec3 col = shadeAct1Monolith(p, n, rd);
        dbgOut = n * 0.5 + 0.5;
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(sdAct1Ring(p + n * 0.35));
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(MAT_MONOLITH);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(marchSteps) / 140.0);
        #elif DEBUG_MODE == 5
            dbgOut = vec3(0.0, 0.0, 1.0);
        #elif DEBUG_MODE == 6
            dbgOut = vec3(max(dot(n, normalize(ACT1_SUN_DIR)), 0.0));
        #endif
        return col;
    }

    if (landT < 0.0) {
        dbgOut = sky;
        #if DEBUG_MODE == 4
            dbgOut = debugHeat(float(marchSteps) / 140.0);
        #elif DEBUG_MODE == 3
            dbgOut = vec3(0.05, 0.08, 0.14);
        #endif
        return sky;
    }

    vec3 p = ro + rd * landT;
    float fp = 2.0 * landT / (iResolution.y * 1.75);
    vec2 bedInfo = act1BedInfo(p.xz);
    float bed = bedInfo.x;
    vec3 col;
    vec3 surfN;
    float maskVal = 0.0;

    if (bed > -0.006) {
        surfN = act1BedNormal(p.xz, max(fp, 0.006));
        col = shadeAct1Land(p, surfN, ro, bedInfo.y, false, loopPhase, fp);
        maskVal = 0.25 + 0.5 * bedInfo.y;
    } else {
        vec4 wv = act1Waves(p.xz, loopPhase, fp / max(abs(rd.y), 0.08));
        surfN = normalize(vec3(-wv.y, 1.0, -wv.z));
        vec3 v = -rd;
        float F = fresnelDielectric(max(dot(surfN, v), 0.0), 1.0, 1.333);

        vec3 refr = refract(rd, surfN, 1.0 / 1.333);
        float approxDepth = max(-bed, 0.02) / max(-refr.y, 0.24);
        vec3 bottomP = p + refr * approxDepth;
        vec2 refInfo = act1BedInfo(bottomP.xz);
        float path = max(-refInfo.x, 0.02) / max(-refr.y, 0.24);
        bottomP = p + refr * path;
        vec3 bottomN = act1BedNormal(bottomP.xz, max(fp, 0.012));
        vec3 bottomCol = shadeAct1Land(bottomP, bottomN, ro, refInfo.y, true, loopPhase, fp);

        vec3 T = beerTransmittance(ACT1_WATER_EXT, path * 1.35);
        vec3 bodyInScatter = srgbToLinear(vec3(0.095, 0.305, 0.260)) * (1.0 - T);
        vec3 body = bottomCol * T + bodyInScatter;

        vec3 refl = reflect(rd, surfN);
        refl.y = abs(refl.y);
        vec3 reflCol = act1Sky(refl, u1, loopPhase);

        vec2 rbs = iSphere(p + surfN * 0.03, refl, ACT1_RING_POS, ACT1_RING_DIM.x + ACT1_RING_DIM.y + 0.6);
        if (rbs.y > 0.0) {
            float rt = max(rbs.x, 0.05);
            for (int k = 0; k < 28; k++) {
                float d = sdAct1Ring(p + surfN * 0.03 + refl * rt);
                if (d < 0.02) {
                    reflCol *= 0.055;
                    break;
                }
                rt += d;
                if (rt > rbs.y) break;
            }
        }
        vec3 islandProbe = p + refl * 12.0;
        if (refl.y < 0.11 && act1Bed(islandProbe.xz) > refl.y * 12.0) {
            reflCol *= 0.14;
        }

        vec3 sun = normalize(ACT1_SUN_DIR);
        float rough = mix(0.055, 0.15, smoothstep(0.02, 0.22, fp));
        vec3 glint = specularGGX(surfN, v, sun, rough, vec3(0.021)) * vec3(1.9, 1.58, 1.12);

        float shallowRim = (1.0 - smoothstep(0.0, 0.055, -bed)) * 0.22 * (1.0 - bedInfo.y);
        col = mix(body * (1.0 - F * 0.85) + reflCol * (F * 0.85) + glint, srgbToLinear(vec3(0.70, 0.66, 0.56)), shallowRim);
        maskVal = saturate(F * 1.5 + shallowRim);
    }

    float fog = 1.0 - exp(-landT * 0.0055);
    col = mix(col, act1Sky(normalize(vec3(rd.x, 0.03, rd.z)), u1, loopPhase), fog * 0.55);

    dbgOut = surfN * 0.5 + 0.5;
    #if DEBUG_MODE == 1
        dbgOut = debugDistance(bed * 0.5);
    #elif DEBUG_MODE == 3
        dbgOut = debugIdColor(bed > -0.006 ? MAT_TERRAIN : 8.0);
    #elif DEBUG_MODE == 4
        dbgOut = debugHeat(float(marchSteps) / 140.0);
    #elif DEBUG_MODE == 5
        dbgOut = vec3(maskVal, saturate(-bed * 0.5), 0.2);
    #elif DEBUG_MODE == 6
        dbgOut = vec3(max(dot(surfN, normalize(ACT1_SUN_DIR)), 0.0));
    #endif
    return col;
}

// =================================================================================================
// ACT II — ALPINE GLACIER CANYON, BILLOWING CLOUD SEA & CYAN CRYSTAL OBELISK (5.0s .. 10.0s)
// =================================================================================================

float act2Height(vec2 p) {
    float ax = abs(p.x);
    float canyonWall = pow(max(ax - 1.05, 0.0), 1.05) * 0.44;

    float macro  = erodedFbm(p * vec2(0.078, 0.068) + vec2(3.1, 1.7), 5);
    float ridges = ridgedFbm(p * vec2(0.155, 0.125) + vec2(-1.4, 5.2), 5);
    float spurs  = ridgedFbm(vec2(p.x * 0.24 + p.y * 0.10, p.y * 0.28), 4);
    float ledges = 0.08 * sin(canyonWall * 3.4 + macro * 2.5);
    float micro  = fbm(p * 1.45, 3);

    float wallMod = smoothstep(0.7, 4.8, ax);
    float h = -0.52 + canyonWall * (0.68 + 0.50 * macro + 0.44 * ridges + 0.20 * spurs) + ledges * wallMod + 0.08 * micro * wallMod;

    float riverCenter = 1.15 + 0.65 * sin(p.y * 0.18 + 0.4) + 0.28 * sin(p.y * 0.37 + 1.1);
    float riverDist = abs(p.x - riverCenter);
    h -= 0.30 * exp(-riverDist * riverDist * 2.2);

    float farGate = smoothstep(-28.0, -50.0, p.y);
    float farPeaks = 2.6 + 5.2 * ridgedFbm(vec2(p.x * 0.12 + 2.4, p.y * 0.085), 5) + 2.0 * fbm(p * 0.075, 4);
    h += farGate * farPeaks;

    return h;
}

vec3 act2TerrainNormal(vec2 p, float eps) {
    float hx = act2Height(p + vec2(eps, 0.0)) - act2Height(p - vec2(eps, 0.0));
    float hz = act2Height(p + vec2(0.0, eps)) - act2Height(p - vec2(0.0, eps));
    return normalize(vec3(-hx, 2.0 * eps, -hz));
}

float sdAct2Obelisk(vec3 p) {
    vec3 q = p - ACT2_OBELISK;
    float hShaft = 8.4;
    float yClamped = clamp(q.y, 0.0, hShaft);
    float taper = mix(0.84, 0.38, yClamped / hShaft);

    float boxA = sdBox(q - vec3(0.0, hShaft * 0.5, 0.0), vec3(taper, hShaft * 0.5, taper * 0.86));
    vec3 qr = q;
    qr.xz = rot2(0.785398) * qr.xz;
    float boxB = sdBox(qr - vec3(0.0, hShaft * 0.5, 0.0), vec3(taper * 0.90, hShaft * 0.5, taper * 0.90));
    float shaft = max(boxA, boxB);

    vec3 qa = q - vec3(0.0, hShaft, 0.0);
    float apexH = 2.15;
    float dApex = sdCappedCone(qa - vec3(0.0, apexH * 0.5, 0.0), apexH * 0.5, taper * 0.90, 0.012);
    vec3 qar = qa;
    qar.xz = rot2(0.3927) * qar.xz;
    float octCut = sdOctahedron(qar * vec3(1.0, 0.40, 1.0), taper * 1.24) * 0.85;
    float crystal = min(shaft, max(dApex, octCut - 0.16));

    float cleavage = 0.026 * sin(q.y * 2.1 + atan(q.z, q.x) * 4.0);
    return (crystal + cleavage) * 0.85;
}

vec2 mapAct2(vec3 p) {
    float dOb = sdAct2Obelisk(p);
    float dTer = (p.y - act2Height(p.xz)) * 0.34;
    if (dOb < dTer) return vec2(dOb, MAT_CRYSTAL);
    return vec2(dTer, MAT_TERRAIN);
}

vec3 act2Sky(vec3 rd) {
    vec3 sun = normalize(ACT2_SUN_DIR);
    float up = saturate(rd.y);
    vec3 zenith = srgbToLinear(vec3(0.24, 0.44, 0.63));
    vec3 horiz  = srgbToLinear(vec3(0.58, 0.71, 0.78));
    vec3 col = mixOklab(horiz, zenith, pow(up, 0.58));
    vec2 domeLookup2 = vec2(0.5 + 0.49 * (rd.x / max(-rd.z, 0.25)), saturate(rd.y * 1.75));
    col = mix(col, sampleDomeAct2(domeLookup2), 0.52);
    float mu = max(dot(rd, sun), 0.0);
    col += vec3(0.14, 0.13, 0.10) * pow(mu, 4.0);

    if (rd.y > 0.03) {
        vec2 cp = rd.xz / (rd.y + 0.20);
        float base = 0.5 + 0.5 * fbm(cp * vec2(0.95, 1.35) + vec2(1.8, -1.2), 5);
        float billow = billowFbm(cp * 2.2 + 4.0, 3);
        float puff = saturate((base * 0.72 + billow * 0.32 - 0.47) * 2.6);
        vec3 cloudCol = mix(srgbToLinear(vec3(0.68, 0.75, 0.80)), srgbToLinear(vec3(0.96, 0.96, 0.95)), billow);
        col = mix(col, cloudCol, puff * 0.62 * smoothstep(0.04, 0.28, rd.y));
    }
    return col;
}

float act2MistDensity(vec3 p, float u2) {
    // Broad billowing cloud sea spanning the ENTIRE foreground valley width (-16..+16) up to y = 3.55m!
    float foreLift = 0.95 * smoothstep(-2.0, 12.0, p.z) * (1.0 - 0.14 * u2);
    float topY = 2.85 + foreLift + 0.42 * sin(p.x * 0.26 + 0.5) + 0.30 * cos(p.z * 0.18);
    float hNorm = (p.y - (-0.85)) / (topY - (-0.85));
    if (hNorm <= 0.0 || hNorm >= 1.0) return 0.0;
    float prof = smoothstep(0.0, 0.12, hNorm) * smoothstep(1.0, 0.20, hNorm);

    // Gentle window opening over lower-right stream as camera glides forward (t = 7..9.5s)
    float streamWindow = smoothstep(1.0, 3.6, u2) * exp(-dot2((p.xz - vec2(1.8, 3.0)) * vec2(0.28, 0.15))) * 0.72;
    vec3 q = p * vec3(0.20, 0.38, 0.18) + vec3(u2 * 0.06, 0.0, -u2 * 0.15);
    float billow = 0.56 * (0.5 + 0.5 * fbm(q, 4, 2.03, 0.52)) + 0.44 * billowFbm(q * 1.95 + 2.1, 3);
    float raw = billow * prof * (1.0 - streamWindow) - 0.13;
    return saturate(raw * 2.85) * 1.35;
}

vec3 renderAct2(vec2 coord, float u2, out vec3 dbgOut) {
    gActiveAct = 2;
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;
    vec2 orb = mouseOrbitOffset();

    vec3 ro = vec3(0.05 + sin(orb.x) * 4.0, 4.75 - 0.14 * u2 + orb.y * 2.5, 17.2 - 2.35 * u2);
    vec3 ta = ro + vec3(-sin(orb.x) * 5.0, -0.58 - orb.y * 1.4, -20.0);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.72);
    vec3 sun = normalize(ACT2_SUN_DIR);

    vec3 sky = act2Sky(rd);
    int steps = 0;

    // 1. Sphere-trace Faceted Cyan Crystal Obelisk
    float obT = -1.0;
    vec2 obs = iSphere(ro, rd, ACT2_OBELISK + vec3(0.0, 5.2, 0.0), 6.2);
    if (obs.y > 0.0) {
        float t = max(obs.x, 0.05);
        for (int i = ZERO; i < 64; i++) {
            steps++;
            float d = sdAct2Obelisk(ro + rd * t);
            if (d < 0.0011 * t) { obT = t; break; }
            t += d;
            if (t > obs.y) break;
        }
    }

    // 2. Canyon heightfield march
    float terT = -1.0;
    float tPrev = 0.1, tCur = 0.1;
    float maxT = obT > 0.0 ? min(obT, 78.0) : 78.0;
    for (int i = ZERO; i < 128; i++) {
        steps++;
        vec3 p = ro + rd * tCur;
        float gap = p.y - act2Height(p.xz);
        if (gap < 0.0) {
            float lo = tPrev, hi = tCur;
            for (int j = 0; j < 8; j++) {
                float mid = 0.5 * (lo + hi);
                vec3 q = ro + rd * mid;
                if (q.y > act2Height(q.xz)) lo = mid; else hi = mid;
            }
            terT = 0.5 * (lo + hi);
            break;
        }
        tPrev = tCur;
        tCur += max(gap * 0.30, 0.05 + 0.015 * tCur);
        if (tCur > maxT) break;
    }

    float sceneT = 80.0;
    vec3 col = sky;
    vec3 nrm = vec3(0.0, 1.0, 0.0);
    float matId = 0.0;

    if (obT > 0.0 && (terT < 0.0 || obT < terT)) {
        sceneT = obT;
        matId = MAT_CRYSTAL;
        vec3 p = ro + rd * obT;
        nrm = calcNormal(p, 0.0016 * obT);
        vec3 v = -rd;
        float ndv = saturate(dot(nrm, v));
        float F = fresnelDielectric(ndv, 1.0, 1.58);

        // Deep dark teal-obsidian quartz body + sharp glowing cyan fracture filaments & facet edges!
        vec2 cUv = vec2(atan(p.z - ACT2_OBELISK.z, p.x - ACT2_OBELISK.x) * 2.4, p.y * 0.92);
        float veins1 = pow(1.0 - smoothstep(0.0, 0.085, voronoiBorder(cUv * 1.85, 0.92).x), 1.8);
        float veins2 = pow(1.0 - smoothstep(0.0, 0.065, voronoiBorder(cUv * 3.6 + 3.1, 0.88).x), 2.0);
        float edgeRim = pow(1.0 - ndv, 3.2);
        float baseEnergy = exp(-max(p.y - 0.1, 0.0) * 0.42);

        vec3 darkQuartz = srgbToLinear(vec3(0.018, 0.115, 0.165));
        vec3 cyanGlow   = srgbToLinear(vec3(0.18, 0.92, 1.0)) * (1.35 * veins1 + 0.65 * veins2 + 0.95 * edgeRim + 0.75 * baseEnergy);
        vec3 reflCol    = act2Sky(reflect(rd, nrm));
        vec3 sunSpec    = specularGGX(nrm, v, sun, 0.09, vec3(0.055)) * vec3(2.8, 2.5, 2.1);

        col = darkQuartz + cyanGlow + reflCol * F * 0.55 + sunSpec;
    } else if (terT > 0.0) {
        sceneT = terT;
        matId = MAT_TERRAIN;
        vec3 p = ro + rd * terT;
        float fp = 2.0 * terT / (iResolution.y * 1.72);
        nrm = act2TerrainNormal(p.xz, max(0.008, fp * 0.65));

        float riverCenter = 1.15 + 0.65 * sin(p.z * 0.18 + 0.4) + 0.28 * sin(p.z * 0.37 + 1.1);
        float isRiver = (1.0 - smoothstep(0.18, 0.42, abs(p.x - riverCenter))) * (1.0 - smoothstep(-0.30, 0.20, p.y));

        float detailKeep = 1.0 - smoothstep(0.03, 0.30, fp);
        float strata = 0.5 + 0.5 * sin(p.y * 7.2 + fbm(p.xz * 0.85, 3) * 3.4);
        float rockGrain = 0.5 + 0.5 * fbm(p.xz * 6.5, 4) * detailKeep;

        vec3 charcoalRock = srgbToLinear(vec3(0.055, 0.055, 0.058));
        vec3 goldenCliff  = srgbToLinear(vec3(0.42, 0.31, 0.185));
        vec3 rock = mix(charcoalRock, goldenCliff, saturate(rockGrain * 0.68 + strata * 0.32));

        float pineNoise = 0.5 + 0.5 * fbm(p.xz * 8.5, 3);
        float pines = smoothstep(0.4, 2.0, p.y) * (1.0 - smoothstep(2.9, 4.4, p.y))
                    * smoothstep(0.42, 0.78, nrm.y) * smoothstep(0.38, 0.56, pineNoise);
        rock = mix(rock, srgbToLinear(vec3(0.022, 0.036, 0.026)), pines * 0.85);

        float couloir = fbm(p.xz * 0.95, 4);
        float snowLine = 4.55 - 1.45 * smoothstep(-24.0, -48.0, p.z) - 0.85 * couloir;
        float snow = smoothstep(snowLine - 0.55, snowLine + 0.75, p.y)
                   * smoothstep(0.38, 0.72, nrm.y + 0.15 * strata);
        vec3 albedo = mix(rock, srgbToLinear(vec3(0.86, 0.88, 0.90)), saturate(snow));

        float sh = 1.0;
        for (int s = 1; s <= 6; s++) {
            float st = 0.55 * float(s) * float(s);
            vec3 sp = p + nrm * 0.08 + sun * st;
            float gh = sp.y - act2Height(sp.xz);
            sh = min(sh, saturate(0.5 + gh * 0.75));
        }

        vec3 sunColor = vec3(3.15, 2.48, 1.72);
        col = shadePBR(nrm, -rd, sun, albedo, mix(0.84, 0.52, snow), 0.0) * sunColor * sh;
        col += albedo * hemisphereLight(nrm, srgbToLinear(vec3(0.22, 0.33, 0.48)) * 1.35, vec3(0.03, 0.035, 0.04));

        vec3 toOb = (ACT2_OBELISK + vec3(0.0, 2.6, 0.0)) - p;
        float obDist2 = dot(toOb, toOb) + 4.0;
        col += albedo * vec3(0.12, 1.25, 1.45) * (8.5 / obDist2) * saturate(dot(nrm, normalize(toOb)) * 0.5 + 0.5);

        if (isRiver > 0.01) {
            vec3 waterN = normalize(vec3(0.07 * sin(p.x * 9.0 + p.z * 5.0), 1.0, 0.07 * cos(p.z * 8.0)));
            float Fw = fresnelDielectric(saturate(dot(waterN, -rd)), 1.0, 1.333);
            vec3 streamCol = mix(srgbToLinear(vec3(0.06, 0.11, 0.15)), act2Sky(reflect(rd, waterN)), Fw * 0.80 + 0.22);
            col = mix(col, streamCol, isRiver * 0.88);
        }
    }

    // 3. Lush Volumetric Cloud Sea filling the lower canyon width from left wall to right wall!
    float mistMax = min(sceneT, 44.0);
    const int MSTEPS = QUALITY >= 3 ? 34 : 24;
    float dt = mistMax / float(MSTEPS);
    float mt = dt * interleavedGradientNoise(floor(coord), iFrame);
    vec3 volRad = vec3(0.0);
    vec3 volTrans = vec3(1.0);
    for (int i = 0; i < MSTEPS; i++) {
        vec3 mp = ro + rd * mt;
        if (mp.y < 4.3 && mp.y > -0.9) {
            float sig = act2MistDensity(mp, u2);
            if (sig > 0.002) {
                float topLit = smoothstep(0.6, 3.1, mp.y);
                float rightSun = smoothstep(-2.0, 7.0, mp.x);
                vec3 mistShadow = srgbToLinear(vec3(0.16, 0.21, 0.26));
                vec3 mistTop    = srgbToLinear(vec3(0.55, 0.56, 0.56));
                vec3 inScat = mix(mistShadow, mistTop, saturate(topLit * 0.62 + rightSun * 0.34));
                float dOb2 = dot2(mp - (ACT2_OBELISK + vec3(0.0, 1.8, 0.0))) + 3.5;
                inScat += srgbToLinear(vec3(0.16, 0.88, 1.0)) * (4.8 / dOb2);
                volumeStep(volRad, volTrans, vec3(sig), sig * inScat, dt);
            }
        }
        mt += dt;
    }
    col = col * volTrans + volRad;

    if (matId > 0.5) {
        float haze = 1.0 - exp(-sceneT * 0.0065);
        col = mix(col, act2Sky(normalize(vec3(rd.x, max(rd.y, 0.04), rd.z))), haze * 0.52);
    }

    vec3 obCenter = ACT2_OBELISK + vec3(0.0, 4.2, 0.0);
    vec3 toCenter = obCenter - ro;
    float projT = dot(toCenter, rd);
    if (projT > 0.0 && projT < sceneT + 2.5) {
        vec3 closest = ro + rd * projT - obCenter;
        float glowDist = length(vec2(closest.x * 1.8, max(abs(closest.y) - 4.0, 0.0)));
        col += srgbToLinear(vec3(0.12, 0.78, 0.94)) * exp(-glowDist * 1.55) * 0.20;
    }

    dbgOut = nrm * 0.5 + 0.5;
    #if DEBUG_MODE == 1
        dbgOut = debugDistance(sceneT * 0.05);
    #elif DEBUG_MODE == 3
        dbgOut = matId > 0.5 ? debugIdColor(matId) : vec3(0.05, 0.08, 0.14);
    #elif DEBUG_MODE == 4
        dbgOut = debugHeat(float(steps) / 150.0);
    #elif DEBUG_MODE == 5
        dbgOut = vec3(1.0 - volTrans.x, matId == MAT_CRYSTAL ? 1.0 : 0.0, 0.25);
    #elif DEBUG_MODE == 6
        dbgOut = vec3(max(dot(nrm, sun), 0.0));
    #endif
    return col;
}

// =================================================================================================
// ACT III — BLUE-HOUR DOWNTOWN ORBITAL SKYLINE & ART-DECO CROWN SPIRE (10.0s .. 15.0s)
// =================================================================================================

vec4 act3TowerProfile(vec2 id) {
    if (abs(id.x) < 0.5 && abs(id.y) < 0.5) {
        return vec4(12.8, 1.18, 1.18, 3.0);
    }
    if (abs(id.x + 2.0) < 0.5 && abs(id.y + 1.0) < 0.5) {
        return vec4(11.4, 1.12, 1.06, 4.0);
    }
    if (abs(id.x + 1.0) < 0.5 && abs(id.y) < 0.5) {
        return vec4(9.8, 0.98, 0.98, 5.0);
    }
    if (abs(id.x + 1.0) < 0.5 && abs(id.y - 1.0) < 0.5) {
        return vec4(8.6, 1.04, 1.04, 4.0);
    }
    if ((abs(id.x + 1.0) < 0.5 && abs(id.y + 1.0) < 0.5) ||
        (abs(id.x - 2.0) < 0.5 && abs(id.y + 1.0) < 0.5) ||
        (abs(id.x - 3.0) < 0.5 && abs(id.y - 1.0) < 0.5)) {
        return vec4(6.2, 1.22, 1.15, 6.0);
    }
    vec4 b = buildingProfile(id, vec2(1.8, 7.6), vec2(0.84, 1.34));
    float distCore = length(id);
    b.x *= mix(1.02, 0.16, smoothstep(1.8, 13.5, distCore));
    return b;
}

vec2 mapAct3(vec3 p) {
    // Fast exact plane distance outside downtown 3D parcel radius prevents step exhaustion on horizon rays!
    if (length(p.xz) > 62.0) {
        return vec2(p.y, MAT_STREET);
    }
    vec2 id = domRepeatId(p.xz, vec2(ACT3_PARCEL));
    vec2 local = p.xz - id * ACT3_PARCEL;
    vec2 res = vec2(p.y, MAT_STREET);

    for (int dz = -1; dz <= 1; dz++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 cell = id + vec2(float(dx), float(dz));
            if (length(cell) > 14.0) continue;
            vec4 b = act3TowerProfile(cell);
            vec3 q = p - vec3(cell.x * ACT3_PARCEL, 0.0, cell.y * ACT3_PARCEL);

            float podium = sdBox(q - vec3(0.0, 0.38, 0.0), vec3(b.y + 0.15, 0.38, b.z + 0.15));
            float shaft  = sdRoundBox(q - vec3(0.0, b.x * 0.5, 0.0), vec3(b.y, b.x * 0.5, b.z) - 0.03, 0.03);
            float d = min(podium, shaft);
            float mat = MAT_BUILDING;

            if (b.w > 2.5 && b.w < 3.5) {
                float t1 = sdBox(q - vec3(0.0, b.x + 0.72, 0.0), vec3(0.92, 0.72, 0.92));
                float t2 = sdBox(q - vec3(0.0, b.x + 1.85, 0.0), vec3(0.64, 0.58, 0.64));
                float t3 = sdCappedCone(q - vec3(0.0, b.x + 3.15, 0.0), 0.85, 0.52, 0.07);
                float needle = sdCapsule(q, vec3(0.0, b.x + 3.85, 0.0), vec3(0.0, b.x + 5.75, 0.0), 0.04);
                float crown = min(min(t1, t2), min(t3, needle));
                if (crown < d) { d = crown; mat = MAT_CROWN; }
            } else if (b.w > 3.5 && b.w < 4.5) {
                float upper = sdBox(q - vec3(0.0, b.x + 0.55, 0.0), vec3(b.y * 0.72, 0.55, b.z * 0.72));
                float ant1 = sdCapsule(q, vec3(-0.32, b.x + 1.1, 0.0), vec3(-0.32, b.x + 2.6, 0.0), 0.028);
                float ant2 = sdCapsule(q, vec3(0.32, b.x + 1.1, 0.0), vec3(0.32, b.x + 2.3, 0.0), 0.028);
                d = min(d, min(upper, min(ant1, ant2)));
            } else if (b.w > 0.5 && b.w < 2.5) {
                float roof = sdBox(q - vec3(0.0, b.x + 0.24, 0.0), vec3(b.y * 0.58, 0.24, b.z * 0.58));
                d = min(d, roof);
            }

            if (d < res.x) res = vec2(d, mat);
        }
    }

    float unvisited = min(1.5 * ACT3_PARCEL - abs(local.x), 1.5 * ACT3_PARCEL - abs(local.y));
    res.x = min(res.x, unvisited);
    return res;
}

vec3 act3Sky(vec3 rd, vec3 sunsetDir, float u3) {
    float up = saturate(rd.y);
    // Deep blue-hour cobalt sky matching video_calibration.json across t = 10..15s!
    vec3 zenith  = srgbToLinear(vec3(0.024, 0.145, 0.325));
    vec3 midSky  = srgbToLinear(vec3(0.105, 0.255, 0.415));
    vec3 baseHor = srgbToLinear(vec3(0.21, 0.31, 0.41));
    vec3 col = mixOklab(baseHor, midSky, smoothstep(0.0, 0.22, up));
    col = mixOklab(col, zenith, smoothstep(0.16, 0.65, up));
    vec2 domeLookup3 = vec2(0.5 + 0.50 * atan(rd.x, -rd.z) / 0.85, saturate((rd.y + 0.04) * 1.85));
    col = mix(col, sampleDomeAct3(domeLookup3, u3), 0.55);

    // Peach-amber sunset band shines strongly on right at t=10s & left at t=14s, dipping into moody twilight at t=12s!
    float duskDip = 0.22 + 0.78 * smoothstep(0.25, 1.55, abs(u3 - 2.0));
    float azAlign = max(dot(normalize(vec3(rd.x, 0.0, rd.z) + 1e-5), normalize(vec3(sunsetDir.x, 0.0, sunsetDir.z))), 0.0);
    float bandH = exp(-max(rd.y - 0.01, 0.0) * 8.5) * smoothstep(-0.04, 0.006, rd.y);
    vec3 warmPeach = srgbToLinear(vec3(0.98, 0.68, 0.44));
    vec3 paleGold  = srgbToLinear(vec3(0.95, 0.88, 0.78));
    col += mix(warmPeach, paleGold, smoothstep(0.01, 0.11, rd.y)) * bandH * pow(azAlign, 2.2) * 1.22 * duskDip;

    float farRidge = 0.011 + 0.013 * fbm(vec2(atan(rd.z, rd.x) * 6.5, 1.5), 3);
    if (rd.y > -0.02 && rd.y < farRidge) {
        col = mix(col, srgbToLinear(vec3(0.14, 0.17, 0.23)), 0.62 * pow(azAlign, 1.1));
    }
    return col;
}

vec3 shadeAct3Ground(vec2 xz, vec3 rd, vec3 sunsetDir, float u3, float distT) {
    vec2 cellLocal = domRepeat(xz, vec2(ACT3_PARCEL));
    float fp = max(2.0 * distT / (iResolution.y * 1.78), 0.02);

    float roadX = smoothstep(1.42, 1.58, abs(cellLocal.x));
    float roadZ = smoothstep(1.42, 1.58, abs(cellLocal.y));
    float road = max(roadX, roadZ);

    vec3 col = srgbToLinear(vec3(0.010, 0.013, 0.018));

    // Focused golden avenue corridors matching sheet_act3.jpg!
    float mainAve = exp(-abs(xz.x + ACT3_PARCEL * 0.5) * 0.85)
                  + exp(-abs(xz.x - ACT3_PARCEL * 0.5) * 0.85)
                  + 0.55 * exp(-abs(xz.y + ACT3_PARCEL * 0.5) * 0.85);
    float lampPool = 0.55 + 0.45 * cos(xz.y * 1.8) * cos(xz.x * 1.8);
    vec3 streetGlow = srgbToLinear(vec3(0.98, 0.62, 0.25)) * road * (0.05 + 0.52 * mainAve) * (0.60 + 0.40 * lampPool);

    if (fp < 0.90) {
        float laneA = exp(-pow((cellLocal.x - 1.78) * 7.0, 2.0));
        float laneB = exp(-pow((cellLocal.x + 1.78) * 7.0, 2.0));
        float carsA = pow(max(sin(xz.y * 1.15 - u3 * 3.2), 0.0), 14.0);
        float carsB = pow(max(sin(xz.y * 1.05 + u3 * 2.9 + 2.0), 0.0), 14.0);
        streetGlow += vec3(1.25, 0.85, 0.34) * laneA * carsA * roadX;
        streetGlow += vec3(1.15, 0.12, 0.05) * laneB * carsB * roadX;
    }

    float gridRoad = max(smoothstep(0.86, 0.97, abs(fract(xz.x / ACT3_PARCEL) * 2.0 - 1.0)),
                         smoothstep(0.86, 0.97, abs(fract(xz.y / ACT3_PARCEL) * 2.0 - 1.0)));
    float farSparkle = hash12(floor(xz * 0.9));
    float cluster = 0.45 + 0.55 * fbm(xz * 0.055, 3);
    vec3 farColor = mix(srgbToLinear(vec3(0.95, 0.62, 0.26)), srgbToLinear(vec3(0.35, 0.78, 0.96)), step(0.84, farSparkle));
    vec3 farLights = farColor * (step(0.75, farSparkle) * 0.55 + gridRoad * 0.16) * cluster * smoothstep(22.0, 58.0, distT);

    col += (streetGlow + farLights) * exp(-distT * 0.0075);
    float haze = 1.0 - exp(-distT * 0.0115);
    return mix(col, act3Sky(rd, sunsetDir, u3), haze);
}

vec3 renderAct3(vec2 coord, float u3, out vec3 dbgOut) {
    gActiveAct = 3;
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;
    vec2 orb = mouseOrbitOffset();

    float orbitAng = 0.78 - 0.39 * u3 + orb.x;
    float camR = 27.5;
    vec3 ro = vec3(sin(orbitAng) * camR, 11.4 + orb.y * 4.0, cos(orbitAng) * camR);
    vec3 ta = vec3(-0.35, 6.9, 0.0);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.78);

    vec3 sunsetDir = normalize(vec3(0.0, 0.06, -1.0));
    vec3 sky = act3Sky(rd, sunsetDir, u3);

    float hitT = -1.0;
    float hitMat = 0.0;
    int steps = 0;
    float t = 0.2;
    for (int i = ZERO; i < 180; i++) {
        steps++;
        vec3 p = ro + rd * t;
        if (p.y > 20.5 && rd.y >= 0.0) break;
        vec2 d = mapAct3(p);
        if (d.x < 0.0014 * t) {
            hitT = t;
            hitMat = d.y;
            break;
        }
        t += d.x * 0.95;
        if (t > 125.0) break;
    }

    if (hitT < 0.0) {
        if (rd.y < -0.0004) {
            float tp = -ro.y / rd.y;
            if (tp > 0.0) {
                vec3 gp = ro + rd * tp;
                vec3 gCol = shadeAct3Ground(gp.xz, rd, sunsetDir, u3, tp);
                dbgOut = vec3(0.5, 1.0, 0.5);
                #if DEBUG_MODE == 1
                    dbgOut = debugDistance(tp * 0.02);
                #elif DEBUG_MODE == 3
                    dbgOut = debugIdColor(MAT_STREET);
                #elif DEBUG_MODE == 4
                    dbgOut = debugHeat(float(steps) / 180.0);
                #elif DEBUG_MODE == 5
                    dbgOut = vec3(0.15);
                #elif DEBUG_MODE == 6
                    dbgOut = vec3(0.1);
                #endif
                return gCol;
            }
        }
        dbgOut = sky;
        return sky;
    }

    vec3 p = ro + rd * hitT;
    if (hitMat > 5.5) {
        vec3 gCol = shadeAct3Ground(p.xz, rd, sunsetDir, u3, hitT);
        dbgOut = vec3(0.5, 1.0, 0.5);
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(hitT * 0.04);
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(MAT_STREET);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(steps) / 180.0);
        #elif DEBUG_MODE == 5
            dbgOut = vec3(0.2);
        #elif DEBUG_MODE == 6
            dbgOut = vec3(0.15);
        #endif
        return gCol;
    }

    vec3 n = calcNormal(p, max(0.002, hitT * 0.00035));
    vec2 id = domRepeatId(p.xz, vec2(ACT3_PARCEL));
    vec4 b = act3TowerProfile(id);
    float variation = hash12(id + 13.0);
    float fp = 2.0 * hitT / (iResolution.y * 1.78 * max(abs(dot(n, -rd)), 0.18));

    vec3 albedo = mix(srgbToLinear(vec3(0.020, 0.024, 0.032)), srgbToLinear(vec3(0.048, 0.045, 0.042)), variation);
    vec3 emission = vec3(0.0);
    float winMask = 0.0;

    if (hitMat > 4.5 && hitMat < 5.5) {
        // Intricate Art-Deco Chevron Lattice Crown with dark steel ribs & warm-white architectural uplights!
        float uCoord = abs(n.x) > abs(n.z) ? p.z : p.x;
        float diagA = abs(sin((uCoord + p.y * 0.45) * 9.0));
        float diagB = abs(sin((uCoord - p.y * 0.45) * 9.0));
        float lattice = smoothstep(0.22, 0.65, min(diagA, diagB));
        float spireGlow = smoothstep(b.x + 3.6, b.x + 4.4, p.y);
        albedo = srgbToLinear(vec3(0.08, 0.085, 0.095));
        emission = srgbToLinear(vec3(1.0, 0.95, 0.84)) * mix(1.45 * lattice + 0.18, 1.35, spireGlow);
        winMask = max(lattice, spireGlow);
    } else if (n.y < 0.55 && p.y > 0.65) {
        vec2 facade = vec2(abs(n.x) > abs(n.z) ? p.z : p.x, p.y);
        vec2 grid = facade / vec2(0.28, 0.38);
        winMask = facadeWindowMask(grid, vec2(0.62, 0.56), vec2(fp * 3.4, fp * 2.5));

        vec2 cellFloor = floor(grid + 0.5);
        float rnd = hash13(vec3(cellFloor, variation * 91.0));
        float floorBand = hash12(vec2(cellFloor.y, variation * 37.0));
        float occupied = step(0.79, rnd * 0.58 + floorBand * 0.50);
        float keep = 1.0 - smoothstep(0.26, 1.10, fp / 0.28);
        occupied = mix(0.11, occupied, keep);

        vec3 glassRefl = act3Sky(reflect(rd, n), sunsetDir, u3) * 0.20;
        albedo = mix(albedo, vec3(0.004, 0.008, 0.015) + glassRefl, winMask);

        vec3 warmLamp = mix(srgbToLinear(vec3(0.98, 0.66, 0.26)), srgbToLinear(vec3(1.0, 0.90, 0.68)), hash12(cellFloor));
        emission = winMask * occupied * warmLamp * 0.88;

        if (b.w > 4.5 && b.w < 5.5) {
            vec2 localXZ = p.xz - id * ACT3_PARCEL;
            float cornerStrip = smoothstep(0.15, 0.03, abs(abs(localXZ.x) - (b.y - 0.06)))
                              * smoothstep(0.15, 0.03, abs(abs(localXZ.y) - (b.z - 0.06)));
            emission += srgbToLinear(vec3(0.08, 0.86, 1.0)) * cornerStrip * 2.4;
        }
        if (b.w > 5.5 && p.y > b.x - 0.72) {
            float signBand = smoothstep(0.58, 0.22, abs(facade.x - floor(facade.x * 0.25 + 0.5) * 4.0));
            emission += srgbToLinear(vec3(0.10, 0.82, 1.0)) * signBand * 1.95;
        }
    }

    float ao = calcAO(p, n, 0.35);
    vec3 col = shadePBR(n, -rd, normalize(vec3(sunsetDir.x, 0.20, sunsetDir.z)), albedo, 0.36, 0.25) * vec3(0.55, 0.38, 0.28);
    col += albedo * hemisphereLight(n, srgbToLinear(vec3(0.12, 0.24, 0.42)), vec3(0.025, 0.02, 0.018)) * ao;
    col += albedo * srgbToLinear(vec3(0.95, 0.62, 0.28)) * exp(-p.y * 0.34) * 0.36;
    col += emission;

    float haze = 1.0 - exp(-hitT * 0.0075);
    col = mix(col, act3Sky(normalize(vec3(rd.x, max(rd.y, 0.015), rd.z)), sunsetDir, u3) * 0.55, haze * 0.68);

    dbgOut = n * 0.5 + 0.5;
    #if DEBUG_MODE == 1
        dbgOut = debugDistance(hitT * 0.04);
    #elif DEBUG_MODE == 3
        dbgOut = debugIdColor(hitMat + mod(abs(id.x * 3.0 + id.y), 4.0));
    #elif DEBUG_MODE == 4
        dbgOut = debugHeat(float(steps) / 180.0);
    #elif DEBUG_MODE == 5
        dbgOut = vec3(winMask, luminance(emission), ao * 0.4);
    #elif DEBUG_MODE == 6
        dbgOut = vec3(ao);
    #endif
    return col;
}

// =================================================================================================
// ACT IV — BASALT COLONNADE SANCTUARY & TOTAL SOLAR ECLIPSE (15.0s .. 20.0s)
// =================================================================================================

float act4ColumnHeight(vec2 cell) {
    // Stepped basalt colonnade rising to ~4.8m on outer cliffs so silhouette sits at uv.y ~ +0.42 like sheet_act4.jpg!
    float worldX = cell.x * 1.42;
    float ax = abs(worldX);
    if (ax < ACT4_CORRIDOR) return -4.0;
    float outward = saturate((ax - ACT4_CORRIDOR) / 8.5);
    float rnd = hash12(cell * 1.7 + 5.0);
    float cluster = 0.5 + 0.5 * fbm(cell * 0.34, 3);
    return 1.35 + 3.25 * pow(outward, 0.68) * (0.65 + 0.60 * cluster) + 1.25 * rnd;
}

vec2 mapAct4(vec3 p) {
    const float CELL = 1.42;
    float channelClear = ACT4_CORRIDOR - 0.80 - abs(p.x);
    if (channelClear > 0.35) {
        return vec2(min(channelClear, p.y + 1.5), MAT_BASALT);
    }

    vec2 id = domRepeatId(p.xz, vec2(CELL));
    vec2 local = p.xz - id * CELL;
    float dMin = 1e5;

    for (int dz = -1; dz <= 1; dz++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 cell = id + vec2(float(dx), float(dz));
            float h = act4ColumnHeight(cell);
            if (h < -2.0) continue;
            vec2 jitter = (hash22(cell + 11.0) - 0.5) * 0.26;
            vec3 q = p - vec3(cell.x * CELL + jitter.x, 0.0, cell.y * CELL + jitter.y);
            float rad = 0.62 + 0.14 * hash12(cell + 31.0);
            float hexD = sdHexPrism((q - vec3(0.0, h * 0.5 - 0.5, 0.0)).xzy, vec2(rad, h * 0.5 + 0.5));
            float boxD = sdRoundBox(q - vec3(0.0, h * 0.5 - 0.5, 0.0), vec3(rad * 0.90, h * 0.5 + 0.5, rad * 0.90), 0.06);
            float colD = mix(hexD, boxD, 0.48);
            float rockDisp = 0.052 * fbm(p * 2.15, 3, 2.03, 0.50) + 0.018 * sin(p.y * 5.5 + hash12(cell) * 6.0);
            dMin = min(dMin, (colD + rockDisp) * 0.85);
        }
    }

    float unvisited = min(1.5 * CELL - abs(local.x), 1.5 * CELL - abs(local.y));
    return vec2(min(dMin, unvisited), MAT_BASALT);
}

vec2 map(vec3 p) {
    if (gActiveAct == 1) return mapAct1(p);
    if (gActiveAct == 2) return mapAct2(p);
    if (gActiveAct == 3) return mapAct3(p);
    return mapAct4(p);
}

vec3 act4Sky(vec3 rd, bool isReflection) {
    vec3 sun = normalize(ACT4_SUN_DIR);
    float up = saturate(rd.y);

    vec3 skyTop = srgbToLinear(vec3(0.155, 0.245, 0.345));
    vec3 skyMid = srgbToLinear(vec3(0.230, 0.315, 0.395));
    vec3 skyHor = srgbToLinear(vec3(0.45, 0.38, 0.30));
    vec3 col = mixOklab(skyHor, skyMid, smoothstep(0.0, 0.15, up));
    col = mixOklab(col, skyTop, smoothstep(0.13, 0.62, up));
    vec2 domeLookup4 = vec2(0.5 + 0.49 * (rd.x / max(-rd.z, 0.25)), saturate(rd.y * 1.78));
    col = mix(col, sampleDomeAct4(domeLookup4), 0.55);

    float cosAng = clamp(dot(rd, sun), -1.0, 1.0);
    float ang = acos(cosAng);
    const float R_MOON = 0.088;

    vec3 rightV = normalize(cross(vec3(0.0, 1.0, 0.0), sun));
    vec3 upV = cross(sun, rightV);
    vec2 local = vec2(dot(rd, rightV), dot(rd, upV));
    float theta = atan(local.y, local.x);
    float streamers = 0.85 + 0.15 * fbm(vec2(theta * 5.0, ang * 15.0), 3);

    float outerHalo = exp(-max(ang - R_MOON, 0.0) * 14.5) * streamers;
    vec3 coronaGold = blackbody(4100.0);
    col += coronaGold * outerHalo * (isReflection ? 1.45 : 0.68);

    if (!isReflection) {
        // Crisp dark lunar disk interior matching sheet_act4.jpg!
        float moonMask = smoothstep(R_MOON + 0.0018, R_MOON - 0.0022, ang);
        vec3 moonCol = srgbToLinear(vec3(0.155, 0.145, 0.142));
        col = mix(col, moonCol, moonMask);
    }

    // Ultra-sharp golden-white diamond corona ring along lunar limb!
    float razorRing = exp(-abs(ang - R_MOON) * 265.0);
    float tightGlow = exp(-abs(ang - R_MOON) * 85.0);
    col += vec3(1.0, 0.95, 0.82) * razorRing * 4.8 + coronaGold * tightGlow * 0.85;
    return col;
}

vec4 act4Waves(vec2 p, float u4, float footprint) {
    vec4 sum = vec4(0.0);
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float ang = 1.42 + (fi - 2.5) * 0.26;
        vec2 dir = vec2(cos(ang), sin(ang));
        float wl = 2.35 * pow(0.68, fi);
        float amp = 0.022 * pow(0.66, fi);
        sum += waterWaveD(p + vec2(fi * 1.1, fi * 0.7), u4 * 1.15, dir, wl, amp, 4.0, footprint);
    }
    return sum;
}

vec3 renderAct4(vec2 coord, float u4, out vec3 dbgOut) {
    gActiveAct = 4;
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;
    vec2 orb = mouseOrbitOffset();

    vec3 ro = vec3(sin(orb.x) * 2.2, 2.02 + orb.y * 1.8, 16.0 - 2.15 * u4);
    vec3 ta = ro + vec3(-sin(orb.x) * 4.0, -0.09 - orb.y * 1.2, -20.0);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.75);
    vec3 sun = normalize(ACT4_SUN_DIR);

    float waterT = rd.y < -0.0008 ? -ro.y / rd.y : -1.0;
    float maxColT = waterT > 0.0 ? min(waterT, 68.0) : 68.0;

    float colT = -1.0;
    int steps = 0;
    float t = 0.15;
    for (int i = ZERO; i < 120; i++) {
        steps++;
        vec3 p = ro + rd * t;
        if (p.y > 7.4 && rd.y >= 0.0) break;
        vec2 d = mapAct4(p);
        if (d.x < 0.0014 * t) {
            colT = t;
            break;
        }
        t += d.x * 0.90;
        if (t > maxColT) break;
    }

    if (colT > 0.0) {
        vec3 p = ro + rd * colT;
        float fp = 2.0 * colT / (iResolution.y * 1.75);
        vec3 n = calcNormal(p, max(0.0025, fp * 0.55));

        float keep = 1.0 - smoothstep(0.03, 0.25, fp);
        float cracks = voronoiBorder(vec2(p.x + p.z, p.y * 0.75) * 2.8, 0.85).x;
        float strata = 0.5 + 0.5 * sin(p.y * 7.5 + fbm(p.xz * 2.5, 3) * 2.4);
        float tex = (0.55 + 0.45 * smoothstep(0.0, 0.16, cracks)) * (0.80 + 0.20 * strata * keep);

        // Softly legible dark basalt rock with warm bronze inner-channel rim & cool twilight fill!
        vec3 basaltAlbedo = srgbToLinear(vec3(0.115, 0.112, 0.118)) * tex;
        float ao = calcAO(p, n, 0.32);

        float innerFace = saturate(-sign(p.x) * n.x);
        float innerEdge = pow(innerFace, 1.3) * smoothstep(7.8, 4.2, abs(p.x));

        vec3 col = basaltAlbedo * hemisphereLight(n, srgbToLinear(vec3(0.30, 0.38, 0.48)), vec3(0.05, 0.05, 0.055)) * ao;
        col += basaltAlbedo * blackbody(3950.0) * innerEdge * (1.85 + 1.35 * exp(-max(p.y - 0.1, 0.0) * 0.45));

        float haze = 1.0 - exp(-colT * 0.015);
        col = mix(col, act4Sky(normalize(vec3(rd.x, max(rd.y, 0.02), rd.z)), false) * 0.45, haze * 0.75);

        dbgOut = n * 0.5 + 0.5;
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(colT * 0.05);
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(MAT_BASALT);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(steps) / 120.0);
        #elif DEBUG_MODE == 5
            dbgOut = vec3(ao, innerFace, 0.25);
        #elif DEBUG_MODE == 6
            dbgOut = vec3(innerEdge);
        #endif
        return col;
    }

    if (waterT > 0.0 && waterT < 160.0) {
        vec3 p = ro + rd * waterT;
        float fp = 2.0 * waterT / (iResolution.y * 1.75);
        vec4 wv = act4Waves(p.xz, u4, fp / max(abs(rd.y), 0.06));
        vec3 n = normalize(vec3(-wv.y * 1.25, 1.0, -wv.z * 1.45));
        vec3 v = -rd;

        float F = fresnelDielectric(max(dot(n, v), 0.0), 1.0, 1.333);
        vec3 refl = reflect(rd, n);
        refl.y = max(refl.y, 0.002);
        vec3 reflCol = act4Sky(refl, true);

        if (abs(refl.x) > 0.015) {
            float wallX = refl.x > 0.0 ? ACT4_CORRIDOR : -ACT4_CORRIDOR;
            float tWall = (wallX - p.x) / refl.x;
            if (tWall > 0.0 && refl.y * tWall < 4.2) {
                reflCol *= srgbToLinear(vec3(0.065, 0.075, 0.090));
            }
        }

        vec3 glint = specularGGX(n, v, sun, 0.065, vec3(0.028)) * blackbody(4100.0) * 2.95;
        vec3 wideGlint = specularGGX(n, v, sun, 0.19, vec3(0.022)) * blackbody(3900.0) * 0.85;

        vec3 deepBody = srgbToLinear(vec3(0.025, 0.038, 0.050));
        vec3 col = deepBody * (1.0 - F) + reflCol * (F * 0.90 + 0.07) + glint + wideGlint;

        float haze = 1.0 - exp(-waterT * 0.009);
        col = mix(col, act4Sky(normalize(vec3(rd.x, 0.015, rd.z)), false) * 0.65, haze * 0.62);

        dbgOut = n * 0.5 + 0.5;
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(waterT * 0.04);
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(9.0);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(steps) / 120.0);
        #elif DEBUG_MODE == 5
            dbgOut = vec3(F, saturate(-wv.w * 2.0), 0.35);
        #elif DEBUG_MODE == 6
            dbgOut = vec3(luminance(glint + wideGlint));
        #endif
        return col;
    }

    vec3 sky = act4Sky(rd, false);
    dbgOut = sky;
    return sky;
}

// =================================================================================================
// MASTER 20.000-SECOND TIMELINE COMPOSITOR & FILMIC ACES COLOR PIPELINE
// =================================================================================================

vec3 finishDisplay(vec3 hdrLinear, vec2 uv, float exposure) {
    vec3 mapped = tonemapACES(max(hdrLinear, vec3(0.0)) * exposure * vignette(uv, 2.45));
    return linearToSrgb(mapped);
}

vec3 renderTimelineSample(vec2 coord) {
    float t = mod(iTime, LOOP_SECONDS);
    if (t < 0.0) t += LOOP_SECONDS;
    float loopPhase = t * OMEGA; // Exact [0, TAU) phase over 20.0s!
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;

    vec3 dbgA = vec3(0.0), dbgB = vec3(0.0);

    if (t < ACT_DURATION - DISSOLVE_DUR) {
        vec3 c1 = renderAct1(coord, t, loopPhase, dbgA);
        #if DEBUG_MODE != 0
            return dbgA;
        #endif
        return finishDisplay(c1, uv, 1.38);
    } else if (t < ACT_DURATION) {
        float w = linearstep(ACT_DURATION - DISSOLVE_DUR, ACT_DURATION, t);
        vec3 c1 = renderAct1(coord, t, loopPhase, dbgA);
        vec3 c2 = renderAct2(coord, t - ACT_DURATION, dbgB);
        #if DEBUG_MODE != 0
            return mix(dbgA, dbgB, w);
        #endif
        return mix(finishDisplay(c1, uv, 1.38), finishDisplay(c2, uv, 1.48), w);
    } else if (t < 2.0 * ACT_DURATION - DISSOLVE_DUR) {
        vec3 c2 = renderAct2(coord, t - ACT_DURATION, dbgA);
        #if DEBUG_MODE != 0
            return dbgA;
        #endif
        return finishDisplay(c2, uv, 1.48);
    } else if (t < 2.0 * ACT_DURATION) {
        float w = linearstep(2.0 * ACT_DURATION - DISSOLVE_DUR, 2.0 * ACT_DURATION, t);
        vec3 c2 = renderAct2(coord, t - ACT_DURATION, dbgA);
        vec3 c3 = renderAct3(coord, t - 2.0 * ACT_DURATION, dbgB);
        #if DEBUG_MODE != 0
            return mix(dbgA, dbgB, w);
        #endif
        return mix(finishDisplay(c2, uv, 1.48), finishDisplay(c3, uv, 1.50), w);
    } else if (t < 3.0 * ACT_DURATION - DISSOLVE_DUR) {
        vec3 c3 = renderAct3(coord, t - 2.0 * ACT_DURATION, dbgA);
        #if DEBUG_MODE != 0
            return dbgA;
        #endif
        return finishDisplay(c3, uv, 1.50);
    } else if (t < 3.0 * ACT_DURATION) {
        float w = linearstep(3.0 * ACT_DURATION - DISSOLVE_DUR, 3.0 * ACT_DURATION, t);
        vec3 c3 = renderAct3(coord, t - 2.0 * ACT_DURATION, dbgA);
        vec3 c4 = renderAct4(coord, t - 3.0 * ACT_DURATION, dbgB);
        #if DEBUG_MODE != 0
            return mix(dbgA, dbgB, w);
        #endif
        return mix(finishDisplay(c3, uv, 1.50), finishDisplay(c4, uv, 1.55), w);
    } else if (t < LOOP_SECONDS - DISSOLVE_DUR) {
        vec3 c4 = renderAct4(coord, t - 3.0 * ACT_DURATION, dbgA);
        #if DEBUG_MODE != 0
            return dbgA;
        #endif
        return finishDisplay(c4, uv, 1.55);
    } else {
        float w = linearstep(LOOP_SECONDS - DISSOLVE_DUR, LOOP_SECONDS, t);
        vec3 c4 = renderAct4(coord, t - 3.0 * ACT_DURATION, dbgA);
        vec3 c1 = renderAct1(coord, t - LOOP_SECONDS, loopPhase, dbgB);
        #if DEBUG_MODE != 0
            return mix(dbgA, dbgB, w);
        #endif
        return mix(finishDisplay(c4, uv, 1.55), finishDisplay(c1, uv, 1.38), w);
    }
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    const int AA = QUALITY >= 3 ? 4 : 1;
    vec3 col = vec3(0.0);
    for (int i = 0; i < AA; i++) {
        vec2 offset = AA > 1 ? aaOffset(i) : vec2(0.0);
        col += renderTimelineSample(fragCoord + offset) / float(AA);
    }
    #if DEBUG_MODE == 0
        col += ditherTPDF(fragCoord, iFrame);
    #endif
    fragColor = vec4(saturate(col), 1.0);
}
