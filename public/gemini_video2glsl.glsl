// GEMINI // VIDEO 2 GLSL — 20.000s Four-Act Seamless Procedural Cinema
// Reconstructed from a 20-second multi-shot Gemini API video as ONE self-contained GLSL fragment shader.
// Zero textures. Zero video frames. Zero baked bitmaps. 100% pure procedural math, optics, and 3D SDF raymarching.
// Built and verified with shader-skills (https://github.com/gokayfem/shader-skills).
//
// Timeline (loops seamlessly at LOOP_SECONDS = 20.000s with exact harmonic periodicity):
//   [00.00s - 05.00s] Act I   — Emerald Lagoon, Fluid Optical Caustics, Volcanic Shoals & Obsidian Torus Monolith
//   [05.00s - 10.00s] Act II  — Sunlit Alpine Canyon, Sculpted Volumetric Cloud Sea & Faceted Cyan Crystal Obelisk
//   [10.00s - 15.00s] Act III — Blue-Hour Downtown Orbital Skyline, Art-Deco Spire & Illuminated Avenues
//   [15.00s - 20.00s] Act IV  — Twilight Basalt Colonnade Channel & Golden Total Solar Eclipse (wraps to Act I)
//
// Interactive controls (standard Shadertoy uniforms only):
//   - Drag mouse on canvas (iMouse) to orbit camera in real 3D space inside any act (persists on Shadertoy too).
//   - #define QUALITY 1|2|3 for Fast (1), Realtime (2), and 4x Supersampled (3) tiers.
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
const float MAT_SIGN     = 8.0;

// Act I constants (calibrated to act1_coast.mp4 camera optics, horizon, ring scale & palette)
const vec3  ACT1_SUN_DIR   = vec3(0.0, 0.110, -0.99393);
const vec3  ACT1_RING_POS  = vec3(0.0, 5.25, -28.0);
const vec2  ACT1_RING_DIM  = vec2(4.05, 0.78);
const vec3  ACT1_WATER_EXT = vec3(0.56, 0.120, 0.142);

// Act II constants (sun from upper-left so left canyon wall is cool slate shadow & right wall is warm alpine gold)
const vec3  ACT2_SUN_DIR   = vec3(-0.805, 0.445, 0.392);
const vec3  ACT2_OBELISK   = vec3(0.12, -0.45, -16.8);

// Act III constants (calibrated to act3_city.mp4 counter-clockwise twilight downtown orbit)
const float ACT3_PARCEL    = 4.2;

// Act IV constants (calibrated to act4_eclipse.mp4 central solar eclipse & basalt colonnade channel)
const vec3  ACT4_SUN_DIR   = vec3(-0.0085, 0.095, -0.99544);
const float ACT4_CORRIDOR  = 4.55;

// Safe guarded atan2 (avoids GLSL ES 3.00 UB when both arguments are 0.0)
float safeAtan(float y, float x) {
    return (x * x + y * y > 1e-10) ? atan(y, x) : 0.0;
}

// Mouse free-look offset (compatible with both studio persistent drag and Shadertoy negative-z release state)
vec2 mouseOrbitOffset() {
    if ((iMouse.z == 0.0 && iMouse.w == 0.0) || iResolution.y < 1.0) return vec2(0.0);
    vec2 cur = iMouse.xy / iResolution.xy - 0.5;
    vec2 clk = abs(iMouse.zw) / iResolution.xy - 0.5;
    return (cur - clk) * vec2(2.6, 1.4);
}

// =================================================================================================
// ACT I — EMERALD LAGOON, SANDBARS, VOLCANIC BOULDER REEFS & OBSIDIAN RING MONOLITH (0.0s .. 5.0s)
// =================================================================================================

// Fast 3x3 rounded volcanic cobble dome field (replaces 50-cell 5x5 smoothVoronoi)
float act1Cobble3x3(vec2 p) {
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    float dMin = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 r = g + 0.78 * hash22(ip + g) + 0.11 - fp;
            dMin = min(dMin, dot(r, r));
        }
    }
    return saturate(1.0 - sqrt(dMin) * 1.15);
}

float act1BoulderField(vec2 p) {
    float macro = act1Cobble3x3(p * 1.38);
    #if QUALITY >= 2
        float med = act1Cobble3x3(p * 2.85 + 4.1);
        return 0.58 * macro + 0.28 * med;
    #else
        return 0.80 * macro;
    #endif
}

// Returns vec2(height, rockinessMask): smooth golden sandbars, wet volcanic cobble reefs, and far headlands
vec2 act1BedInfo(vec2 p) {
    float h = -0.88 + 0.08 * fbm(p * 0.28, 2);
    float rockMask = 0.0;
    float sandRipple = 0.011 * sin(p.x * 5.0 + p.y * 3.2 + 0.8 * gradientNoise(p * 0.8));

    // 1. Diagonal golden sandbar spit entering from lower-right foreground at t = 0.0s..1.4s
    vec2 spA = vec2(1.45, 8.2);
    vec2 spDir = normalize(vec2(0.84, 0.54));
    float proj = clamp(dot(p - spA, spDir), 0.0, 10.5);
    float spitDist = length(p - (spA + spDir * proj));
    float spitMask = exp(-0.26 * spitDist * spitDist);
    h += (0.985 + sandRipple) * spitMask;

    // 2. Smooth golden sandbars emerging at t = 0.0s (mid-left) and t = 3.2..4.5s (left & mid-right)
    vec2 sb0 = (p - vec2(-1.15, 9.2)) * vec2(0.85, 1.35);
    vec2 sb1 = (p - vec2(-1.85, -1.8)) * vec2(0.52, 0.95);
    vec2 sb2 = (p - vec2(2.55, -5.2)) * vec2(0.45, 0.95);
    vec2 sb3 = (p - vec2(1.65, -12.0)) * vec2(0.42, 1.15);
    float sandBars = exp(-0.48 * dot(sb0, sb0))
                   + 1.02 * exp(-0.32 * dot(sb1, sb1))
                   + 1.00 * exp(-0.26 * dot(sb2, sb2))
                   + 0.96 * exp(-0.24 * dot(sb3, sb3));
    h += (0.955 + sandRipple) * sandBars;

    // 3. Flanking dark volcanic boulder reefs framing t = 1.5..3.0s (coherent skip over open water)
    vec2 nl = (p - vec2(-5.45, 5.6)) * vec2(0.28, 0.25);
    vec2 nr = (p - vec2(5.55, 5.2)) * vec2(0.28, 0.25);
    float nearReef = exp(-dot(nl, nl)) + exp(-dot(nr, nr));
    vec2 ml = (p - vec2(-8.6, -5.8)) * vec2(0.22, 0.34);
    vec2 mr = (p - vec2(8.7, -5.6)) * vec2(0.22, 0.34);
    float midReef = exp(-dot(ml, ml)) + exp(-dot(mr, mr));

    float totalReef = nearReef + 0.95 * midReef;
    if (totalReef > 0.004) {
        float sandProtect = 1.0 - saturate(spitMask * 2.2);
        float boulders = act1BoulderField(p);
        h += totalReef * sandProtect * (1.12 + 0.85 * boulders);
        rockMask = saturate(totalReef * 1.95 * sandProtect);
    }

    // 4. Far volcanic headlands framing left & right horizon (coherent skip in foreground)
    vec2 fl = (p - vec2(-22.5, -27.5)) * vec2(0.088, 0.145);
    vec2 fr = (p - vec2(22.8, -27.0)) * vec2(0.088, 0.145);
    float farMask = exp(-dot(fl, fl)) + exp(-dot(fr, fr));
    if (farMask > 0.003) {
        float ridges = 0.58 + 0.56 * ridgedFbm(p * 0.26, 3) + 0.26 * erodedFbm(p * 0.38, 3);
        h += 3.85 * farMask * ridges;
        rockMask = max(rockMask, saturate(farMask * 2.2));
    }

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

// Dedicated 4-tap tetrahedral normal directly on sdAct1Ring (no terrain contamination!)
vec3 act1RingNormal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * sdAct1Ring(p + e * eps);
    }
    return normalize(n);
}

vec4 act1Waves(vec2 p, float loopPhase, float footprint) {
    vec4 sum = vec4(0.0);
    const int N = QUALITY >= 3 ? 7 : (QUALITY == 2 ? 5 : 3);
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

// Fast analytic horizon sky gradient + sun glow (used for distance fog & base sky)
vec3 act1SkyBase(vec3 rd) {
    vec3 sun = normalize(ACT1_SUN_DIR);
    float up = saturate(rd.y);
    float mu = max(dot(rd, sun), 0.0);

    // Crisp coastal cerulean upper sky grading into warm golden-cream low horizon matching sheet_act1.jpg
    vec3 zenithCol  = srgbToLinear(vec3(0.18, 0.36, 0.54));
    vec3 midSkyCol  = srgbToLinear(vec3(0.38, 0.52, 0.64));
    vec3 horizonCol = srgbToLinear(vec3(0.80, 0.72, 0.56));
    vec3 sky = mixOklab(horizonCol, midSkyCol, smoothstep(0.0, 0.22, up));
    sky = mixOklab(sky, zenithCol, smoothstep(0.18, 0.58, up));

    // Focused golden atmospheric sun bloom centered behind the black obsidian ring (preserves blue sky flanks!)
    sky += srgbToLinear(vec3(1.0, 0.88, 0.66)) * (0.85 * pow(mu, 14.0) + 0.36 * pow(mu, 3.2));
    sky += vec3(1.75, 1.44, 0.98) * smoothstep(0.9962, 0.9995, mu);
    return sky;
}

float act1CloudField(vec2 q, int oct) {
    vec2 w = vec2(gradientNoise(q * 1.35 + 1.7), gradientNoise(q * 1.35 + 5.2)) * 0.22;
    float bill = billowFbm(q * 1.50 + w, oct);
    float base = 0.5 + 0.5 * fbm(q * 1.05 - w * 0.5, oct);
    return bill * 0.60 + base * 0.40;
}

vec3 act1Sky(vec3 rd, float u1, float loopPhase, bool isReflection) {
    vec3 sun = normalize(ACT1_SUN_DIR);
    float mu = max(dot(rd, sun), 0.0);
    vec3 sky = act1SkyBase(rd);

    // Pure procedural puffy sunlit tropical cumulus clouds with rich belly-to-crown contrast
    if (rd.y > 0.012) {
        vec2 dome = vec2(rd.x / max(-rd.z, 0.28), rd.y * 2.25);
        vec2 q = dome * vec2(1.22, 1.75) + vec2(u1 * 0.024 + 0.55, 0.28);
        int oct = (isReflection || QUALITY == 1) ? 2 : 4;
        float shape = act1CloudField(q, oct);

        // Open luminous solar corridor behind the obsidian ring, framing sculpted cumulus clouds across sky
        float flank = smoothstep(0.10, 0.46, abs(dome.x) + max(rd.y - 0.18, 0.0) * 0.82);
        float dens = smoothstep(0.45, 0.65, shape * (0.78 + 0.34 * flank))
                   * flank * smoothstep(0.014, 0.075, rd.y);

        if (dens > 0.005) {
            float lit = 0.55 + 0.35 * smoothstep(0.06, 0.34, rd.y);
            #if QUALITY >= 2
                if (!isReflection) {
                    vec2 toSun = normalize(vec2(0.0, 0.22) - dome + vec2(1e-4));
                    float occShape = act1CloudField(q + toSun * 0.17, 3);
                    float shadow = smoothstep(0.42, 0.66, occShape);
                    lit = saturate((1.0 - shadow * 0.72) * (0.48 + 0.72 * pow(mu, 1.7)) + 0.24 * smoothstep(0.10, 0.38, rd.y));
                }
            #endif

            vec3 cloudBelly = srgbToLinear(vec3(0.32, 0.36, 0.42));
            vec3 cloudCream = srgbToLinear(vec3(0.97, 0.90, 0.78)) * (0.98 + 0.38 * pow(mu, 3.5));
            vec3 silverEdge = srgbToLinear(vec3(1.0, 0.90, 0.70)) * pow(mu, 5.0) * (1.0 - dens) * 0.40;
            sky = mix(sky, mix(cloudBelly, cloudCream, lit) + silverEdge, dens * 0.84);
        }

        // Distant gliding sea birds on exact 20s harmonic loop (skip in blurry reflections)
        if (!isReflection) {
            vec2 birdCenter = vec2(-0.52 + 0.10 * sin(loopPhase), 0.28 + 0.02 * cos(2.0 * loopPhase));
            vec2 buv = (rd.xy / max(-rd.z, 0.2)) - birdCenter;
            for (int b = 0; b < 2; b++) {
                vec2 bp = (buv - vec2(float(b) * 0.055, float(b) * 0.022)) * 90.0;
                float flap = sin(8.0 * loopPhase + float(b) * 1.9) * 0.36;
                float wing = abs(bp.y - abs(bp.x) * (0.35 + flap) + 0.12 * bp.x * bp.x);
                float bird = (1.0 - smoothstep(0.04, 0.16, wing)) * (1.0 - smoothstep(0.62, 1.10, abs(bp.x)));
                sky = mix(sky, srgbToLinear(vec3(0.15, 0.16, 0.17)), bird * 0.70);
            }
        }
    }
    return sky;
}

// Organic curved fluid optical caustics (9-cell domain-warped cellular interference on exact 20s loop)
float act1CausticLayer(vec2 p, float phase) {
    vec2 warp = vec2(
        sin(p.y * 1.40 + phase) + 0.50 * cos(p.x * 1.75 - phase),
        cos(p.x * 1.40 - phase) + 0.50 * sin(p.y * 1.75 + phase)
    ) * 0.24;
    vec2 q = p + warp;
    vec2 ip = floor(q);
    vec2 fp = fract(q);
    float f1 = 8.0;
    float f2 = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 h = hash22(ip + g);
            vec2 pt = 0.5 + 0.38 * sin(phase + TAU * h + vec2(0.0, 1.5708));
            vec2 r = g + pt - fp;
            float d = dot(r, r);
            if (d < f1) {
                f2 = f1;
                f1 = d;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    float edge = sqrt(f2) - sqrt(f1);
    float ridge = 1.0 - smoothstep(0.0, 0.16, edge);
    float glow  = 1.0 - smoothstep(0.0, 0.38, edge);
    return ridge * ridge * 0.85 + glow * glow * 0.24;
}

vec3 shadeAct1Land(vec3 p, vec3 n, vec3 ro, float rockMask, bool submerged, float loopPhase, float footprint) {
    vec3 sun = normalize(ACT1_SUN_DIR);
    vec3 v = normalize(ro - p);
    float fineKeep = 1.0 - smoothstep(0.02, 0.22, footprint);
    float grain = 0.5 + 0.5 * fbm(p.xz * 4.5, 3) * fineKeep;
    float cobble = rockMask > 0.02 ? act1Cobble3x3(p.xz * 2.5) : 0.0;

    // Warm golden honey-tan wet & dry sandbars
    vec3 sandWet  = srgbToLinear(vec3(0.50, 0.38, 0.22));
    vec3 sandDry  = srgbToLinear(vec3(0.74, 0.60, 0.40));
    vec3 sandCol  = mix(sandWet, sandDry, smoothstep(0.004, 0.075, p.y) * (0.75 + 0.25 * grain));

    // Wet dark volcanic basalt cobbles (rich volcanic silhouette with warm rim legibility)
    vec3 rockDark = srgbToLinear(vec3(0.036, 0.035, 0.033));
    vec3 rockLit  = srgbToLinear(vec3(0.118, 0.104, 0.088));
    vec3 rockCol  = mix(rockDark, rockLit, cobble * 0.72 + grain * 0.28);

    float farIsland = 1.0 - smoothstep(-26.0, -18.0, p.z);
    rockCol = mix(rockCol, srgbToLinear(vec3(0.056, 0.070, 0.048)), farIsland * 0.55);

    vec3 albedo = mix(sandCol, rockCol, rockMask);
    float roughness = mix(0.64, 0.56, rockMask);

    vec3 sunRad = vec3(1.95, 1.62, 1.15);
    vec3 col = shadePBR(n, v, sun, albedo, roughness, 0.0) * sunRad;
    // Warm sunlit sky overhead + subtle golden grazing rim on wet boulders
    vec3 skyFill = mix(srgbToLinear(vec3(0.86, 0.78, 0.62)) * 1.42, srgbToLinear(vec3(0.32, 0.42, 0.52)) * 1.02, rockMask);
    col += albedo * hemisphereLight(n, skyFill, vec3(0.055, 0.048, 0.040));
    if (rockMask > 0.05 && !submerged) {
        float rim = pow(1.0 - saturate(dot(n, v)), 3.5) * saturate(n.y * 0.7 + 0.3);
        col += srgbToLinear(vec3(0.95, 0.80, 0.55)) * rim * rockMask * 0.085;
    }

    if (submerged) {
        float depth = max(-p.y, 0.0);
        col *= beerTransmittance(ACT1_WATER_EXT, depth * 1.32);

        float keep = (1.0 - smoothstep(0.04, 0.34, footprint)) * smoothstep(0.015, 0.15, depth);
        if (keep > 0.005) {
            float c1 = act1CausticLayer(p.xz * 0.76, 2.0 * loopPhase);
            #if QUALITY >= 2
                float c2 = act1CausticLayer(p.xz * 1.42 + vec2(4.3, -2.7), -3.0 * loopPhase);
                float caustic = c1 * 0.96 + c2 * 0.36;
            #else
                float caustic = c1 * 1.16;
            #endif
            col += srgbToLinear(vec3(0.62, 0.88, 0.72)) * caustic * keep * 0.74 * exp(-depth * 0.28);
        }
    }
    return col;
}

vec3 shadeAct1Monolith(vec3 p, vec3 n, vec3 rd) {
    vec3 sun = normalize(ACT1_SUN_DIR);
    vec3 v = -rd;
    vec3 albedo = srgbToLinear(vec3(0.022, 0.024, 0.028));
    float rLocal = length(p.xy - ACT1_RING_POS.xy);
    float groove = 1.0 - smoothstep(0.0, 0.05, abs(rLocal - ACT1_RING_DIM.x));
    float rough = mix(0.28, 0.48, groove);

    vec3 col = shadePBR(n, v, sun, albedo, rough, 0.15) * vec3(1.4, 1.18, 0.90);
    float grazing = pow(1.0 - saturate(dot(n, v)), 5.0);
    float innerEdge = 1.0 - smoothstep(ACT1_RING_DIM.x - 0.65, ACT1_RING_DIM.x + 0.15, rLocal);
    col += srgbToLinear(vec3(1.0, 0.88, 0.66)) * grazing * (0.14 + 0.44 * innerEdge);
    col += albedo * hemisphereLight(n, srgbToLinear(vec3(0.24, 0.34, 0.44)), vec3(0.03, 0.05, 0.05));
    return col;
}

vec3 renderAct1(vec2 coord, float u1, float loopPhase, out vec3 dbgOut) {
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;
    vec2 orb = mouseOrbitOffset();

    vec3 ro = vec3(sin(orb.x) * 4.5, 2.22 + orb.y * 2.2, 18.2 - 3.65 * u1);
    vec3 ta = ro + vec3(-sin(orb.x) * 6.0, -1.30 - orb.y * 1.5, -20.0);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.75);

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

    // 2. Coastal heightfield + lagoon sea surface (y = 0) with analytic sky & water plane bounds
    float landT = -1.0;
    float tWater = rd.y < -0.0008 ? -ro.y / rd.y : -1.0;
    float maxTrace = ringT > 0.0 ? min(ringT, 68.0) : 68.0;
    if (tWater > 0.0) maxTrace = min(maxTrace, tWater + 0.05);

    if (!(ro.y > 5.0 && rd.y >= 0.0)) {
        const int LAND_STEPS = QUALITY >= 3 ? 112 : (QUALITY == 2 ? 92 : 64);
        float tPrev = 0.05;
        float tCur = 0.05;
        for (int i = ZERO; i < LAND_STEPS; i++) {
            marchSteps++;
            vec3 p = ro + rd * tCur;
            if (p.y > 5.0 && rd.y >= 0.0) break;
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
            tCur += max(gap * 0.45, 0.032 + 0.014 * tCur);
            if (tCur > maxTrace) break;
        }
    }
    if (landT < 0.0 && tWater > 0.0 && (ringT < 0.0 || tWater < ringT)) {
        landT = tWater;
    }

    if (ringT > 0.0 && (landT < 0.0 || ringT < landT)) {
        vec3 p = ro + rd * ringT;
        vec3 n = act1RingNormal(p, 0.0014 * ringT);
        vec3 col = shadeAct1Monolith(p, n, rd);
        dbgOut = n * 0.5 + 0.5;
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(sdAct1Ring(p + n * 0.35));
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(MAT_MONOLITH);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(marchSteps) / 110.0);
        #elif DEBUG_MODE == 5
            dbgOut = vec3(0.0, 0.0, 1.0);
        #elif DEBUG_MODE == 6
            dbgOut = vec3(max(dot(n, normalize(ACT1_SUN_DIR)), 0.0));
        #endif
        return col;
    }

    // Lazy sky evaluation: full cumulus clouds only evaluated on actual sky pixels!
    if (landT < 0.0) {
        vec3 sky = act1Sky(rd, u1, loopPhase, false);
        dbgOut = sky;
        #if DEBUG_MODE == 4
            dbgOut = debugHeat(float(marchSteps) / 110.0);
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

        vec3 T = beerTransmittance(ACT1_WATER_EXT, path * 1.32);
        vec3 bodyInScatter = srgbToLinear(vec3(0.095, 0.315, 0.270)) * (1.0 - T);
        vec3 body = bottomCol * T + bodyInScatter;

        vec3 refl = reflect(rd, surfN);
        refl.y = abs(refl.y);
        vec3 reflCol = act1Sky(refl, u1, loopPhase, true);

        // Reflect obsidian ring monolith in water
        vec2 rbs = iSphere(p + surfN * 0.03, refl, ACT1_RING_POS, ACT1_RING_DIM.x + ACT1_RING_DIM.y + 0.6);
        if (rbs.y > 0.0) {
            float rt = max(rbs.x, 0.05);
            for (int k = 0; k < 24; k++) {
                float d = sdAct1Ring(p + surfN * 0.03 + refl * rt);
                if (d < 0.02) {
                    reflCol *= 0.055;
                    break;
                }
                rt += d;
                if (rt > rbs.y) break;
            }
        }
        // Multi-distance reflection probes catch BOTH mid-distance reefs AND far volcanic headlands
        float islandDark = 1.0;
        if (refl.y < 0.22) {
            vec3 ip1 = p + refl * 11.0;
            vec3 ip2 = p + refl * 24.0;
            vec3 ip3 = p + refl * 38.0;
            if (act1Bed(ip1.xz) > ip1.y || act1Bed(ip2.xz) > ip2.y || act1Bed(ip3.xz) > ip3.y) {
                islandDark = 0.16;
            }
        }
        reflCol *= islandDark;

        vec3 sun = normalize(ACT1_SUN_DIR);
        float rough = mix(0.055, 0.15, smoothstep(0.02, 0.22, fp));
        vec3 glint = specularGGX(surfN, v, sun, rough, vec3(0.021)) * vec3(1.9, 1.58, 1.12);

        float shallowRim = (1.0 - smoothstep(0.0, 0.055, -bed)) * 0.22 * (1.0 - bedInfo.y);
        col = mix(body * (1.0 - F * 0.85) + reflCol * (F * 0.85) + glint, srgbToLinear(vec3(0.70, 0.66, 0.56)), shallowRim);
        maskVal = saturate(F * 1.5 + shallowRim);
    }

    // Cheap analytic horizon fog (avoids re-evaluating full cumulus cloud dome)
    float fog = 1.0 - exp(-landT * 0.0055);
    col = mix(col, act1SkyBase(normalize(vec3(rd.x, 0.03, rd.z))), fog * 0.55);

    dbgOut = surfN * 0.5 + 0.5;
    #if DEBUG_MODE == 1
        dbgOut = debugDistance(bed * 0.5);
    #elif DEBUG_MODE == 3
        dbgOut = debugIdColor(bed > -0.006 ? MAT_TERRAIN : 8.0);
    #elif DEBUG_MODE == 4
        dbgOut = debugHeat(float(marchSteps) / 110.0);
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

// Fast Lipschitz-well-behaved alpine heightfield (6 octaves at Q2 vs 26 previously: ~4x faster, zero tunneling)
float act2Height(vec2 p) {
    float ax = abs(p.x);
    float canyonWall = pow(max(ax - 1.05, 0.0), 1.04) * 0.43;

    const int E_OCT = QUALITY >= 3 ? 4 : (QUALITY == 2 ? 3 : 2);
    const int R_OCT = QUALITY >= 2 ? 3 : 2;
    float macro  = 0.5 + 0.5 * fbm(p * vec2(0.078, 0.068) + vec2(3.1, 1.7), E_OCT);
    float ridges = ridgedFbm(p * vec2(0.155, 0.125) + vec2(-1.4, 5.2), R_OCT);
    float ledges = 0.07 * sin(canyonWall * 3.4 + macro * 2.4);

    float wallMod = smoothstep(0.7, 4.8, ax);
    float h = -0.52 + canyonWall * (0.58 + 0.44 * macro + 0.42 * ridges) + ledges * wallMod;

    float riverCenter = 1.15 + 0.65 * sin(p.y * 0.18 + 0.4) + 0.28 * sin(p.y * 0.37 + 1.1);
    float riverDist = abs(p.x - riverCenter);
    h -= 0.30 * exp(-riverDist * riverDist * 2.2);

    // Coherent skip of distant mountain backdrop when p.y > -26.0
    if (p.y < -26.0) {
        float farGate = 1.0 - smoothstep(-50.0, -28.0, p.y);
        float farPeaks = 2.6 + 4.8 * ridgedFbm(vec2(p.x * 0.12 + 2.4, p.y * 0.085), 3) + 1.6 * fbm(p * 0.075, 2);
        h += farGate * farPeaks;
    }

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

    float cleavage = 0.024 * sin(q.y * 2.1 + safeAtan(q.z, q.x) * 4.0);
    return (crystal + cleavage) * 0.85;
}

// Dedicated 4-tap tetrahedral normal directly on sdAct2Obelisk (no terrain contamination!)
vec3 act2ObeliskNormal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * sdAct2Obelisk(p + e * eps);
    }
    return normalize(n);
}

vec3 act2SkyBase(vec3 rd) {
    vec3 sun = normalize(ACT2_SUN_DIR);
    float up = saturate(rd.y);
    // Crisp alpine cerulean sky grading to pale airy mist-blue at canyon gap matching sheet_act2.jpg
    vec3 zenith = srgbToLinear(vec3(0.20, 0.43, 0.64));
    vec3 horiz  = srgbToLinear(vec3(0.62, 0.74, 0.80));
    vec3 col = mixOklab(horiz, zenith, pow(max(up, 1e-5), 0.56));
    float mu = max(dot(rd, sun), 0.0);
    col += vec3(0.13, 0.12, 0.10) * pow(mu, 4.0);
    return col;
}

vec3 act2Sky(vec3 rd) {
    vec3 col = act2SkyBase(rd);
    if (rd.y > 0.025) {
        vec2 cp = rd.xz / (rd.y + 0.28);
        float base = 0.5 + 0.5 * fbm(cp * vec2(0.55, 1.35) + vec2(1.8, -1.2), 3);
        float wisp = 0.5 + 0.5 * fbm(cp * vec2(1.45, 2.60) + vec2(-2.3, 3.1), 2);
        float puff = smoothstep(0.46, 0.78, base * 0.68 + wisp * 0.36);
        vec3 cloudCol = mix(srgbToLinear(vec3(0.74, 0.80, 0.86)), srgbToLinear(vec3(0.95, 0.96, 0.95)), wisp);
        col = mix(col, cloudCol, puff * 0.48 * smoothstep(0.03, 0.26, rd.y));
    }
    return col;
}

// Fast sculpted billowing valley cloud density (1-octave 3D + 2-octave 2D billow = ~4x faster than original 7-octave 3D!)
float act2MistDensity(vec3 p, float u2, bool cheapShadow) {
    float foreLift = 0.95 * smoothstep(-2.0, 12.0, p.z) * (1.0 - 0.14 * u2);
    float topY = 2.85 + foreLift + 0.52 * sin(p.x * 0.30 + 0.5) + 0.38 * cos(p.z * 0.22);
    float hNorm = (p.y - (-0.85)) / (topY - (-0.85));
    if (hNorm <= 0.0 || hNorm >= 1.0) return 0.0;
    float prof = smoothstep(0.0, 0.14, hNorm) * (1.0 - smoothstep(0.22, 1.0, hNorm));

    // Gentle window opening over lower-right glacial stream as camera glides forward (t = 7..9.5s)
    float streamWindow = smoothstep(1.0, 3.6, u2) * exp(-dot2((p.xz - vec2(1.8, 3.0)) * vec2(0.28, 0.15))) * 0.72;
    vec3 q = p * vec3(0.24, 0.44, 0.22) + vec3(u2 * 0.055, 0.0, -u2 * 0.14);

    float billow;
    if (cheapShadow) {
        billow = 0.54 + 0.46 * gradientNoise(q);
    } else {
        float n3 = 0.5 + 0.5 * gradientNoise(q);
        float b2 = billowFbm(q.xz * 1.85 + vec2(2.1, -1.4) + 0.38 * q.y, 2);
        billow = 0.42 * n3 + 0.58 * b2;
    }
    float raw = billow * prof * (1.0 - streamWindow) - 0.17;
    return saturate(raw * 3.4) * 1.50;
}

vec3 renderAct2(vec2 coord, float u2, out vec3 dbgOut) {
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;
    vec2 orb = mouseOrbitOffset();

    vec3 ro = vec3(0.05 + sin(orb.x) * 4.0, 4.75 - 0.14 * u2 + orb.y * 2.5, 17.2 - 2.35 * u2);
    vec3 ta = ro + vec3(-sin(orb.x) * 5.0, -0.58 - orb.y * 1.4, -20.0);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.72);
    vec3 sun = normalize(ACT2_SUN_DIR);

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

    // 2. Canyon heightfield march with tighter near-ridge stepping (eliminates floating ridge tunneling!)
    float terT = -1.0;
    float tPrev = 0.1, tCur = 0.1;
    float maxT = obT > 0.0 ? min(obT, 78.0) : 78.0;
    const int TER_STEPS = QUALITY >= 3 ? 104 : (QUALITY == 2 ? 84 : 60);
    for (int i = ZERO; i < TER_STEPS; i++) {
        steps++;
        vec3 p = ro + rd * tCur;
        // Early out once ray clearly rises above canyon walls & far peaks
        if (p.y > 11.5 + abs(p.x) * 0.85 && rd.y > 0.25) break;
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
        tCur += max(gap * 0.31, 0.022 + 0.011 * tCur);
        if (tCur > maxT) break;
    }

    float sceneT = 80.0;
    vec3 col;
    vec3 nrm = vec3(0.0, 1.0, 0.0);
    float matId = 0.0;

    if (obT > 0.0 && (terT < 0.0 || obT < terT)) {
        sceneT = obT;
        matId = MAT_CRYSTAL;
        vec3 p = ro + rd * obT;
        nrm = act2ObeliskNormal(p, 0.0016 * obT);
        vec3 v = -rd;
        float ndv = saturate(dot(nrm, v));
        float F = fresnelDielectric(ndv, 1.0, 1.58);

        // Luminous aquamarine-cyan quartz crystal with glowing internal fracture filaments
        vec2 cUv = vec2(safeAtan(p.z - ACT2_OBELISK.z, p.x - ACT2_OBELISK.x) * 2.4, p.y * 0.92);
        float veins1 = pow(1.0 - smoothstep(0.0, 0.085, voronoiBorder(cUv * 1.85, 0.92).x), 1.8);
        float veins2 = pow(1.0 - smoothstep(0.0, 0.065, voronoiBorder(cUv * 3.6 + 3.1, 0.88).x), 2.0);
        float edgeRim = pow(1.0 - ndv, 3.0);
        float baseEnergy = exp(-max(p.y - 0.1, 0.0) * 0.38);

        vec3 darkQuartz = srgbToLinear(vec3(0.025, 0.15, 0.22));
        vec3 cyanGlow   = srgbToLinear(vec3(0.22, 0.94, 1.0)) * (1.55 * veins1 + 0.72 * veins2 + 1.05 * edgeRim + 0.85 * baseEnergy);
        vec3 reflCol    = act2SkyBase(reflect(rd, nrm));
        vec3 sunSpec    = specularGGX(nrm, v, sun, 0.09, vec3(0.055)) * vec3(2.8, 2.5, 2.1);

        col = darkQuartz + cyanGlow + reflCol * F * 0.55 + sunSpec;
    } else if (terT > 0.0) {
        sceneT = terT;
        matId = MAT_TERRAIN;
        vec3 p = ro + rd * terT;
        float fp = 2.0 * terT / (iResolution.y * 1.72);
        nrm = act2TerrainNormal(p.xz, max(0.009, fp * 0.65));

        float riverCenter = 1.15 + 0.65 * sin(p.z * 0.18 + 0.4) + 0.28 * sin(p.z * 0.37 + 1.1);
        float isRiver = (1.0 - smoothstep(0.18, 0.42, abs(p.x - riverCenter))) * (1.0 - smoothstep(-0.30, 0.20, p.y));

        float detailKeep = 1.0 - smoothstep(0.03, 0.30, fp);
        float strata = 0.5 + 0.5 * sin(p.y * 7.2 + fbm(p.xz * 0.85, 3) * 3.4);
        float rockGrain = 0.5 + 0.5 * fbm(p.xz * 6.5, 3) * detailKeep;

        // Subtle high-frequency rock micro-bump in shading normal (zero march cost!)
        vec2 bumpG = vec2(
            gradientNoise(p.xz * 2.6 + vec2(0.0, p.y * 0.8)),
            gradientNoise(p.xz * 2.6 + vec2(4.7, p.y * 0.8))
        ) * 0.14 * detailKeep;
        nrm = normalize(nrm + vec3(bumpG.x, 0.0, bumpG.y));

        vec3 charcoalRock = srgbToLinear(vec3(0.052, 0.055, 0.060));
        vec3 goldenCliff  = srgbToLinear(vec3(0.36, 0.26, 0.16));
        vec3 rock = mix(charcoalRock, goldenCliff, saturate(rockGrain * 0.60 + strata * 0.40));

        float pineNoise = 0.5 + 0.5 * fbm(p.xz * 8.5, 2);
        float pines = smoothstep(0.3, 1.8, p.y) * (1.0 - smoothstep(3.2, 4.9, p.y))
                    * smoothstep(0.38, 0.76, nrm.y) * smoothstep(0.34, 0.54, pineNoise);
        rock = mix(rock, srgbToLinear(vec3(0.018, 0.032, 0.022)), pines * 0.88);

        // Snow concentrated on upper alpine ridges & high couloirs so lower canyon stays dark slate & bronze
        float couloir = fbm(p.xz * 0.95, 3);
        float farSnowBoost = 1.0 - smoothstep(-48.0, -24.0, p.z);
        float snowLine = 5.45 - 1.55 * farSnowBoost - 0.80 * couloir;
        float snow = smoothstep(snowLine - 0.50, snowLine + 0.80, p.y)
                   * smoothstep(0.42, 0.74, nrm.y + 0.14 * strata);
        vec3 albedo = mix(rock, srgbToLinear(vec3(0.84, 0.87, 0.90)), saturate(snow));

        const int SH_STEPS = QUALITY >= 3 ? 6 : (QUALITY == 2 ? 4 : 3);
        float sh = 1.0;
        for (int s = 1; s <= SH_STEPS; s++) {
            float st = 0.72 * float(s) * float(s);
            vec3 sp = p + nrm * 0.09 + sun * st;
            float gh = sp.y - act2Height(sp.xz);
            sh = min(sh, saturate(0.5 + gh * 0.75));
        }

        vec3 sunColor = vec3(3.05, 2.40, 1.65);
        col = shadePBR(nrm, -rd, sun, albedo, mix(0.85, 0.52, snow), 0.0) * sunColor * sh;
        // Cool slate-blue ambient skylight keeps shadowed left canyon moody & grounded like sheet_act2.jpg
        col += albedo * hemisphereLight(nrm, srgbToLinear(vec3(0.16, 0.27, 0.42)) * 1.15, vec3(0.025, 0.030, 0.038));

        vec3 toOb = (ACT2_OBELISK + vec3(0.0, 2.6, 0.0)) - p;
        float obDist2 = dot(toOb, toOb) + 4.0;
        col += albedo * vec3(0.12, 1.25, 1.45) * (8.5 / obDist2) * saturate(dot(nrm, normalize(toOb)) * 0.5 + 0.5);

        if (isRiver > 0.01) {
            vec3 waterN = normalize(vec3(0.07 * sin(p.x * 9.0 + p.z * 5.0), 1.0, 0.07 * cos(p.z * 8.0)));
            float Fw = fresnelDielectric(saturate(dot(waterN, -rd)), 1.0, 1.333);
            vec3 streamCol = mix(srgbToLinear(vec3(0.08, 0.14, 0.19)), act2SkyBase(reflect(rd, waterN)), Fw * 0.80 + 0.22);
            col = mix(col, streamCol, isRiver * 0.88);
        }
    } else {
        col = act2Sky(rd);
    }

    // 3. Slab-clipped Volumetric Cloud Sea (all steps concentrated strictly inside y in [-0.9, 4.35]!)
    // Uses static spatial IGN (no iFrame) so clouds never shimmer/boil at 60Hz, plus 1-tap directional self-shadowing.
    float mistCap = min(sceneT, 46.0);
    float tSlabLo = -1.0;
    float tSlabHi = -1.0;
    if (abs(rd.y) > 1e-4) {
        float tA = (-0.90 - ro.y) / rd.y;
        float tB = (4.35 - ro.y) / rd.y;
        tSlabLo = max(min(tA, tB), 0.1);
        tSlabHi = min(max(tA, tB), mistCap);
    } else if (ro.y > -0.90 && ro.y < 4.35) {
        tSlabLo = 0.1;
        tSlabHi = mistCap;
    }

    vec3 volRad = vec3(0.0);
    vec3 volTrans = vec3(1.0);
    if (tSlabHi > tSlabLo) {
        const int MSTEPS = QUALITY >= 3 ? 22 : (QUALITY == 2 ? 15 : 10);
        float dt = (tSlabHi - tSlabLo) / float(MSTEPS);
        float mt = tSlabLo + dt * interleavedGradientNoise(floor(coord));
        for (int i = 0; i < MSTEPS; i++) {
            vec3 mp = ro + rd * mt;
            float sig = act2MistDensity(mp, u2, false);
            if (sig > 0.004) {
                float topLit = smoothstep(0.4, 3.2, mp.y);
                float rightSun = smoothstep(-3.0, 7.5, mp.x);
                // Foreground valley lies in deep canyon wall shadow; sunlit mid-valley brightens toward obelisk!
                float valleySun = 1.0 - smoothstep(-6.0, 11.0, mp.z);
                float sunLit = 1.0;
                #if QUALITY >= 2
                    float sigSun = act2MistDensity(mp + sun * 1.15, u2, true);
                    sunLit = exp(-sigSun * 2.15);
                #endif
                float lightMix = saturate(sunLit * (0.45 * topLit + 0.35 * rightSun + 0.35 * valleySun) + 0.10 * topLit);
                vec3 mistShadow = srgbToLinear(vec3(0.11, 0.15, 0.20));
                vec3 mistMid    = srgbToLinear(vec3(0.36, 0.41, 0.46));
                vec3 mistSunlit = srgbToLinear(vec3(0.68, 0.72, 0.75));
                vec3 mistHi = mix(mistMid, mistSunlit, valleySun * 0.80 + rightSun * 0.20);
                vec3 inScat = mix(mistShadow, mistHi, lightMix);
                // Luminous cyan energy glow radiating from the crystal obelisk base into surrounding clouds
                float dOb2 = dot2(mp - (ACT2_OBELISK + vec3(0.0, 1.8, 0.0))) + 3.0;
                inScat += srgbToLinear(vec3(0.18, 0.92, 1.0)) * (6.2 / dOb2);
                volumeStep(volRad, volTrans, vec3(sig), sig * inScat, dt);
                if (volTrans.x < 0.02) break;
            }
            mt += dt;
        }
        col = col * volTrans + volRad;
    }

    if (matId > 0.5) {
        float haze = 1.0 - exp(-sceneT * 0.0062);
        col = mix(col, act2SkyBase(normalize(vec3(rd.x, max(rd.y, 0.04), rd.z))), haze * 0.50);
    }

    vec3 obCenter = ACT2_OBELISK + vec3(0.0, 4.2, 0.0);
    vec3 toCenter = obCenter - ro;
    float projT = dot(toCenter, rd);
    if (projT > 0.0 && projT < sceneT + 2.5) {
        vec3 closest = ro + rd * projT - obCenter;
        float glowDist = length(vec2(closest.x * 1.8, max(abs(closest.y) - 4.0, 0.0)));
        col += srgbToLinear(vec3(0.14, 0.82, 0.96)) * exp(-glowDist * 1.55) * 0.24;
    }

    dbgOut = nrm * 0.5 + 0.5;
    #if DEBUG_MODE == 1
        dbgOut = debugDistance(sceneT * 0.05);
    #elif DEBUG_MODE == 3
        dbgOut = matId > 0.5 ? debugIdColor(matId) : vec3(0.05, 0.08, 0.14);
    #elif DEBUG_MODE == 4
        dbgOut = debugHeat(float(steps) / 130.0);
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
    // Smooth gradual tapering out into low-rise suburbs (no abrupt ocean-like cutoff!)
    b.x *= mix(1.04, 0.14, smoothstep(1.8, 16.5, distCore));
    return b;
}

vec2 mapAct3(vec3 p) {
    if (length(p.xz) > 74.0) {
        return vec2(p.y, MAT_STREET);
    }
    vec2 id = domRepeatId(p.xz, vec2(ACT3_PARCEL));
    vec2 local = p.xz - id * ACT3_PARCEL;
    vec2 res = vec2(p.y, MAT_STREET);

    for (int dz = -1; dz <= 1; dz++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 cell = id + vec2(float(dx), float(dz));
            float cellDist = length(cell);
            if (cellDist > 16.5) continue;
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
            } else if (b.w > 5.5) {
                // Raised 3D illuminated rooftop parapet sign box (replaces flat wall sticker)
                float signBox = sdBox(q - vec3(0.0, b.x + 0.28, 0.0), vec3(b.y * 0.82, 0.26, b.z * 0.82));
                if (signBox < d) { d = signBox; mat = MAT_SIGN; }
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

vec3 act3Normal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * mapAct3(p + e * eps).x;
    }
    return normalize(n);
}

float act3AO(vec3 p, vec3 n, float scale) {
    const int AO_TAPS = QUALITY >= 3 ? 5 : (QUALITY == 2 ? 4 : 3);
    float occ = 0.0;
    float weight = 1.0;
    for (int i = ZERO; i < AO_TAPS; i++) {
        float h = 0.01 + scale * float(i) / float(AO_TAPS - 1);
        float d = mapAct3(p + h * n).x;
        occ += (h - d) * weight;
        weight *= 0.95;
    }
    return saturate(1.0 - 3.0 * occ / max(scale / 0.12, 1e-3));
}

// Pure procedural world-space blue-hour sky (sunset naturally orbits right -> center -> left with zero clamping!)
vec3 act3SkyGradient(vec3 rd, vec3 sunsetDir, float u3) {
    float up = saturate(rd.y);
    // Rich royal-cobalt blue-hour sky grading into luminous cerulean twilight horizon (matching sheet_act3.jpg!)
    vec3 zenith  = srgbToLinear(vec3(0.028, 0.155, 0.385));
    vec3 midSky  = srgbToLinear(vec3(0.125, 0.320, 0.560));
    vec3 baseHor = srgbToLinear(vec3(0.28, 0.44, 0.60));
    vec3 col = mixOklab(baseHor, midSky, smoothstep(0.0, 0.20, up));
    col = mixOklab(col, zenith, smoothstep(0.14, 0.58, up));

    // Safe horizontal direction normalization (no zero-vector or Y-tilt bug)
    vec2 rdh = rd.xz;
    rdh = dot(rdh, rdh) > 1e-8 ? normalize(rdh) : vec2(0.0, -1.0);
    vec2 sunh = normalize(sunsetDir.xz);
    float azAlign = max(dot(rdh, sunh), 0.0);

    // Crisp peach-amber sunset ribbon hugging the twilight horizon
    float duskWeight = 0.30 + 0.70 * smoothstep(0.25, 1.55, abs(u3 - 2.0));
    float bandH = exp(-max(rd.y - 0.004, 0.0) * 10.5) * smoothstep(-0.03, 0.006, rd.y);
    vec3 warmPeach = srgbToLinear(vec3(0.99, 0.68, 0.42));
    vec3 paleGold  = srgbToLinear(vec3(0.96, 0.87, 0.76));
    col += mix(warmPeach, paleGold, smoothstep(0.008, 0.095, rd.y)) * bandH * pow(azAlign, 2.35) * 1.25 * duskWeight;
    return col;
}

vec3 act3Sky(vec3 rd, vec3 sunsetDir, float u3) {
    vec3 col = act3SkyGradient(rd, sunsetDir, u3);
    // Subtle distant coastal mountain range along horizon only (avoids zenith atan evaluation!)
    if (rd.y > -0.02 && rd.y < 0.035) {
        float az = safeAtan(rd.z, rd.x);
        float farRidge = 0.005 + 0.012 * fbm(vec2(az * 6.5, 1.5), 3);
        if (rd.y < farRidge) {
            float softEdge = 1.0 - smoothstep(farRidge - 0.004, farRidge, rd.y);
            col = mix(col, srgbToLinear(vec3(0.16, 0.22, 0.32)), 0.42 * softEdge);
        }
    }
    return col;
}

vec3 shadeAct3Ground(vec2 xz, vec3 rd, vec3 sunsetDir, float u3, float distT) {
    vec2 cellLocal = domRepeat(xz, vec2(ACT3_PARCEL));
    float fp = max(2.0 * distT / (iResolution.y * 1.78), 0.02);

    float roadX = smoothstep(1.38, 1.56, abs(cellLocal.x));
    float roadZ = smoothstep(1.38, 1.56, abs(cellLocal.y));
    float road = max(roadX, roadZ);

    vec3 col = srgbToLinear(vec3(0.018, 0.026, 0.040));

    // Asymmetric illuminated downtown arterial avenues (primary bright avenue left of hero spire!)
    float mainAve = 0.85 * exp(-abs(xz.x + ACT3_PARCEL * 0.5) * 0.72)
                  + 0.36 * exp(-abs(xz.x - ACT3_PARCEL * 0.5) * 0.72)
                  + 0.55 * exp(-abs(xz.y + ACT3_PARCEL * 0.5) * 0.72)
                  + 0.40 * exp(-abs(xz.y - ACT3_PARCEL * 0.5) * 0.72);
    float lampPool = 0.55 + 0.45 * cos(xz.y * 1.8) * cos(xz.x * 1.8);
    vec3 streetGlow = srgbToLinear(vec3(0.98, 0.78, 0.48)) * road * (0.06 + 0.44 * mainAve) * (0.62 + 0.38 * lampPool);

    if (fp < 0.90) {
        // Strict GLSL ES 3.00 defined quadratic Gaussian (replaces UB pow(neg, 2.0)!)
        float dA = (cellLocal.x - 1.78) * 7.0;
        float dB = (cellLocal.x + 1.78) * 7.0;
        float laneA = exp(-dA * dA);
        float laneB = exp(-dB * dB);
        float carsA = pow(max(sin(xz.y * 1.15 - u3 * 3.2), 0.0), 14.0);
        float carsB = pow(max(sin(xz.y * 1.05 + u3 * 2.9 + 2.0), 0.0), 14.0);
        streetGlow += vec3(1.15, 0.84, 0.44) * laneA * carsA * roadX;
        streetGlow += vec3(1.10, 0.18, 0.10) * laneB * carsB * roadX;
    }

    // Dense twilight metropolitan sprawl & glowing highway arteries stretching all the way to the horizon
    float gridRoad = max(
        smoothstep(0.80, 0.96, abs(fract(xz.x / ACT3_PARCEL) * 2.0 - 1.0)),
        smoothstep(0.80, 0.96, abs(fract(xz.y / ACT3_PARCEL) * 2.0 - 1.0))
    );
    float highway = max(
        exp(-abs(xz.x + 12.6) * 0.14) + exp(-abs(xz.x - 16.8) * 0.14) + exp(-abs(xz.x + 33.6) * 0.11),
        exp(-abs(xz.y + 14.7) * 0.14) + exp(-abs(xz.y - 25.2) * 0.11)
    );
    float diagArtery = exp(-abs(xz.x * 0.65 - xz.y * 0.76 + 18.0) * 0.12);
    float farSparkle  = hash12(floor(xz * 0.78));
    float farSparkle2 = hash12(floor(xz * 0.34) + 19.3);
    float cluster = 0.35 + 0.65 * fbm(xz * 0.032, 2);
    vec3 warmUrban = srgbToLinear(vec3(0.98, 0.78, 0.48));
    vec3 coolUrban = srgbToLinear(vec3(0.76, 0.90, 1.00));
    vec3 farColor  = mix(warmUrban, coolUrban, step(0.56, farSparkle));
    float farFade  = smoothstep(14.0, 42.0, distT);
    vec3 farLights = (farColor * (step(0.50, farSparkle) * 0.72 + step(0.66, farSparkle2) * 0.46)
                   + warmUrban * (gridRoad * 0.18 + (highway + 0.7 * diagArtery) * 0.36)) * cluster * farFade;

    // Deep blue-hour urban ground keeping dramatic night-city contrast right up to the glowing horizon
    col = mix(col, srgbToLinear(vec3(0.018, 0.028, 0.046)), farFade * 0.70);
    col += streetGlow * exp(-distT * 0.0085) + farLights * exp(-distT * 0.0024);
    float haze = 1.0 - exp(-max(distT - 55.0, 0.0) * 0.0048);
    vec3 horizonHaze = act3SkyGradient(normalize(vec3(rd.x, 0.015, rd.z)), sunsetDir, u3) * 0.30;
    return mix(col, horizonHaze, saturate(haze * 0.60));
}

vec3 renderAct3(vec2 coord, float u3, out vec3 dbgOut) {
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;
    vec2 orb = mouseOrbitOffset();

    float orbitAng = 0.78 - 0.39 * u3 + orb.x;
    float camR = 27.5;
    vec3 ro = vec3(sin(orbitAng) * camR, 11.2 + orb.y * 4.0, cos(orbitAng) * camR);
    vec3 ta = vec3(-0.35, 7.45, 0.0);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.78);

    vec3 sunsetDir = normalize(vec3(0.0, 0.06, -1.0));

    float hitT = -1.0;
    float hitMat = 0.0;
    int steps = 0;
    float t = 0.2;
    const int CITY_STEPS = QUALITY >= 3 ? 180 : (QUALITY == 2 ? 148 : 108);
    for (int i = ZERO; i < CITY_STEPS; i++) {
        steps++;
        vec3 p = ro + rd * t;
        if (p.y > 20.0 && rd.y >= 0.0) break;
        vec2 d = mapAct3(p);
        if (d.x < 0.0014 * t) {
            hitT = t;
            hitMat = d.y;
            break;
        }
        t += d.x * 0.95;
        if (t > 130.0) break;
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
                    dbgOut = debugHeat(float(steps) / 150.0);
                #elif DEBUG_MODE == 5
                    dbgOut = vec3(0.15);
                #elif DEBUG_MODE == 6
                    dbgOut = vec3(0.1);
                #endif
                return gCol;
            }
        }
        vec3 sky = act3Sky(rd, sunsetDir, u3);
        dbgOut = sky;
        return sky;
    }

    vec3 p = ro + rd * hitT;
    if (hitMat > 5.5 && hitMat < 6.5) {
        vec3 gCol = shadeAct3Ground(p.xz, rd, sunsetDir, u3, hitT);
        dbgOut = vec3(0.5, 1.0, 0.5);
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(hitT * 0.04);
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(MAT_STREET);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(steps) / 150.0);
        #elif DEBUG_MODE == 5
            dbgOut = vec3(0.2);
        #elif DEBUG_MODE == 6
            dbgOut = vec3(0.15);
        #endif
        return gCol;
    }

    vec3 n = act3Normal(p, max(0.002, hitT * 0.00035));
    vec2 id = domRepeatId(p.xz, vec2(ACT3_PARCEL));
    vec4 b = act3TowerProfile(id);
    float variation = hash12(id + 13.0);
    float fp = 2.0 * hitT / (iResolution.y * 1.78 * max(abs(dot(n, -rd)), 0.18));

    bool isRoof = n.y > 0.55;
    vec3 albedo = mix(srgbToLinear(vec3(0.032, 0.042, 0.058)), srgbToLinear(vec3(0.068, 0.066, 0.064)), variation);
    vec3 emission = vec3(0.0);
    float winMask = 0.0;

    if (hitMat > 7.5) {
        // Raised 3D glowing cyan-blue rooftop parapet sign
        albedo = srgbToLinear(vec3(0.04, 0.07, 0.10));
        if (!isRoof) {
            float signTrim = smoothstep(0.04, 0.16, p.y - b.x) * (1.0 - smoothstep(0.42, 0.52, p.y - b.x));
            emission = srgbToLinear(vec3(0.10, 0.80, 1.0)) * (1.65 * signTrim + 0.35);
            winMask = signTrim;
        }
    } else if (hitMat > 4.5 && hitMat < 5.5) {
        // Intricate Art-Deco Chevron Lattice Crown with dark steel ribs & warm-white architectural uplights
        float uCoord = abs(n.x) > abs(n.z) ? p.z : p.x;
        float diagA = abs(sin((uCoord + p.y * 0.45) * 9.0));
        float diagB = abs(sin((uCoord - p.y * 0.45) * 9.0));
        float lattice = smoothstep(0.22, 0.65, min(diagA, diagB));
        float spireGlow = smoothstep(b.x + 3.6, b.x + 4.4, p.y);
        albedo = srgbToLinear(vec3(0.08, 0.085, 0.095));
        emission = srgbToLinear(vec3(1.0, 0.96, 0.88)) * mix(1.50 * lattice + 0.22, 1.40, spireGlow);
        winMask = max(lattice, spireGlow);
    } else if (!isRoof && p.y > 0.65) {
        vec2 facade = vec2(abs(n.x) > abs(n.z) ? p.z : p.x, p.y);
        vec2 grid = facade / vec2(0.28, 0.38);
        winMask = facadeWindowMask(grid, vec2(0.64, 0.58), vec2(fp * 3.4, fp * 2.5));

        vec2 cellFloor = floor(grid + 0.5);
        float rnd = hash13(vec3(cellFloor, variation * 91.0));
        float floorBand = hash12(vec2(cellFloor.y, variation * 37.0));
        float occupied = step(0.73, rnd * 0.58 + floorBand * 0.50);
        float keep = 1.0 - smoothstep(0.26, 1.10, fp / 0.28);
        occupied = mix(0.16, occupied, keep);

        // Steel-blue twilight curtain-wall sky reflections
        vec3 glassRefl = act3SkyGradient(reflect(rd, n), sunsetDir, u3) * 0.34;
        albedo = mix(albedo, vec3(0.008, 0.016, 0.028) + glassRefl, winMask);

        // Mix of warm amber office floors & crisp cool-white/daylight office windows matching sheet_act3.jpg
        float lampHue = hash12(cellFloor + 7.1);
        vec3 warmLamp = mix(srgbToLinear(vec3(0.99, 0.72, 0.32)), srgbToLinear(vec3(1.0, 0.93, 0.78)), lampHue);
        vec3 coolLamp = srgbToLinear(vec3(0.76, 0.88, 1.0));
        vec3 lampCol  = mix(warmLamp, coolLamp, step(0.68, lampHue) * 0.75);
        emission = winMask * occupied * lampCol * 0.95;

        if (b.w > 4.5 && b.w < 5.5) {
            vec2 localXZ = p.xz - id * ACT3_PARCEL;
            float cornerStrip = (1.0 - smoothstep(0.03, 0.15, abs(abs(localXZ.x) - (b.y - 0.06))))
                              * (1.0 - smoothstep(0.03, 0.15, abs(abs(localXZ.y) - (b.z - 0.06))));
            emission += srgbToLinear(vec3(0.10, 0.88, 1.0)) * cornerStrip * 2.4;
        }
    } else if (isRoof) {
        // Matte gravel/concrete rooftop with subtle darker HVAC center (zero specular white blowout!)
        vec2 localXZ = abs(p.xz - id * ACT3_PARCEL);
        float parapet = smoothstep(b.y - 0.16, b.y - 0.02, localXZ.x) + smoothstep(b.z - 0.16, b.z - 0.02, localXZ.y);
        albedo = mix(srgbToLinear(vec3(0.035, 0.044, 0.058)), srgbToLinear(vec3(0.075, 0.085, 0.10)), saturate(parapet));
    }

    float ao = act3AO(p, n, 0.35);
    float surfRough = isRoof ? 0.86 : mix(0.62, 0.24, winMask);
    float surfMetal = isRoof ? 0.0 : mix(0.05, 0.22, winMask);
    vec3 col = shadePBR(n, -rd, normalize(vec3(sunsetDir.x, 0.20, sunsetDir.z)), albedo, surfRough, surfMetal) * vec3(0.26, 0.24, 0.26);
    col += albedo * hemisphereLight(n, srgbToLinear(vec3(0.18, 0.34, 0.58)), vec3(0.020, 0.024, 0.030)) * ao;
    col += albedo * srgbToLinear(vec3(0.95, 0.65, 0.30)) * exp(-p.y * 0.34) * 0.18;
    col += emission;

    float haze = 1.0 - exp(-hitT * 0.0055);
    col = mix(col, act3SkyGradient(normalize(vec3(rd.x, max(rd.y, 0.015), rd.z)), sunsetDir, u3) * 0.34, haze * 0.45);

    dbgOut = n * 0.5 + 0.5;
    #if DEBUG_MODE == 1
        dbgOut = debugDistance(hitT * 0.04);
    #elif DEBUG_MODE == 3
        dbgOut = debugIdColor(hitMat + mod(abs(id.x * 3.0 + id.y), 4.0));
    #elif DEBUG_MODE == 4
        dbgOut = debugHeat(float(steps) / 150.0);
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

// Fast staggered basalt column height profile (replaces per-cell fbm inside 3x3 march loop)
float act4ColumnHeight(vec2 cell, float worldX) {
    float ax = abs(worldX);
    if (ax < ACT4_CORRIDOR - 0.15) return -4.0;
    float outward = saturate((ax - (ACT4_CORRIDOR - 0.15)) / 7.8);
    float rnd = hash12(cell * 1.7 + 5.0);
    float rnd2 = hash12(cell * 0.73 + 17.0);
    float cluster = 0.5 + 0.5 * sin(cell.x * 0.62 + cell.y * 0.38) * cos(cell.y * 0.44 - cell.x * 0.28);
    // Terraced inner-ledge basalt pillars stepping up to rugged outer monoliths (matching sheet_act4.jpg)
    return 0.95 + 3.45 * pow(outward, 0.72) * (0.58 + 0.55 * cluster) + 1.45 * rnd * (0.55 + 0.45 * rnd2);
}

vec2 mapAct4(vec3 p) {
    const float CELL = 1.50;
    float channelClear = ACT4_CORRIDOR - 0.90 - abs(p.x);
    if (channelClear > 0.35) {
        return vec2(min(channelClear, p.y + 1.5), MAT_BASALT);
    }

    // Staggered hexagonal-like row packing gives distinct vertical basalt monoliths with visible light slits!
    float rowIdx = floor(p.z / CELL + 0.5);
    float dMin = 1e5;

    for (int dz = -1; dz <= 1; dz++) {
        float cz = rowIdx + float(dz);
        float rowShift = 0.5 * CELL * mod(abs(cz), 2.0);
        float colIdx = floor((p.x - rowShift) / CELL + 0.5);
        for (int dx = -1; dx <= 1; dx++) {
            float cx = colIdx + float(dx);
            vec2 cell = vec2(cx, cz);
            float baseX = cx * CELL + rowShift;
            float h = act4ColumnHeight(cell, baseX);
            if (h < -2.0) continue;

            vec2 jitter = (hash22(cell + 11.0) - 0.5) * 0.24;
            vec3 q = p - vec3(baseX + jitter.x, 0.0, cz * CELL + jitter.y);
            // Distinct individual basalt pillar radii (0.43..0.55 on 1.50 spacing = crisp gaps between monoliths!)
            float rad = 0.43 + 0.12 * hash12(cell + 31.0);
            float hexD = sdHexPrism((q - vec3(0.0, h * 0.5 - 0.5, 0.0)).xzy, vec2(rad, h * 0.5 + 0.5));
            float boxD = sdRoundBox(q - vec3(0.0, h * 0.5 - 0.5, 0.0), vec3(rad * 0.92, h * 0.5 + 0.5, rad * 0.92), 0.055);
            float colD = mix(hexD, boxD, 0.42);
            dMin = min(dMin, colD);
        }
    }

    // Hoisted 3D rock displacement evaluated ONCE (only near column surfaces) instead of 9x inside the loop!
    if (dMin < 0.28) {
        float rockDisp = 0.044 * fbm(p * 2.1, 2, 2.03, 0.50) + 0.015 * sin(p.y * 5.2 + p.z * 0.7);
        dMin = (dMin + rockDisp) * 0.88;
    }

    float unvisited = 1.45 * CELL;
    return vec2(min(dMin, unvisited), MAT_BASALT);
}

vec3 act4Normal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * mapAct4(p + e * eps).x;
    }
    return normalize(n);
}

float act4AO(vec3 p, vec3 n, float scale) {
    const int AO_TAPS = QUALITY >= 3 ? 5 : (QUALITY == 2 ? 4 : 3);
    float occ = 0.0;
    float weight = 1.0;
    for (int i = ZERO; i < AO_TAPS; i++) {
        float h = 0.01 + scale * float(i) / float(AO_TAPS - 1);
        float d = mapAct4(p + h * n).x;
        occ += (h - d) * weight;
        weight *= 0.95;
    }
    return saturate(1.0 - 3.0 * occ / max(scale / 0.12, 1e-3));
}

vec3 act4Sky(vec3 rd, bool isReflection) {
    vec3 sun = normalize(ACT4_SUN_DIR);
    float up = saturate(rd.y);

    // Luminous slate-cerulean twilight sky grading to warm golden-peach eclipse horizon (matches sheet_act4.jpg)
    vec3 skyTop = srgbToLinear(vec3(0.15, 0.26, 0.38));
    vec3 skyMid = srgbToLinear(vec3(0.26, 0.35, 0.44));
    vec3 skyHor = srgbToLinear(vec3(0.58, 0.49, 0.38));
    vec3 col = mixOklab(skyHor, skyMid, smoothstep(0.0, 0.17, up));
    col = mixOklab(col, skyTop, smoothstep(0.15, 0.62, up));

    float cosAng = clamp(dot(rd, sun), -1.0, 1.0);
    float ang = acos(cosAng);
    const float R_MOON = 0.076;

    vec3 rightV = normalize(cross(vec3(0.0, 1.0, 0.0), sun));
    vec3 upV = cross(sun, rightV);
    vec2 local = vec2(dot(rd, rightV), dot(rd, upV));
    float theta = safeAtan(local.y, local.x);
    float streamers = 0.88 + 0.12 * fbm(vec2(theta * 5.0, ang * 14.0), 2);

    float outerHalo = exp(-max(ang - R_MOON, 0.0) * 12.8) * streamers;
    vec3 coronaGold = blackbody(3950.0);
    col += coronaGold * outerHalo * (isReflection ? 1.45 : 0.64);

    if (!isReflection) {
        // Atmospheric smoky-amber lunar disk interior matching sheet_act4.jpg
        float moonMask = 1.0 - smoothstep(R_MOON - 0.0020, R_MOON + 0.0018, ang);
        vec3 moonCol = srgbToLinear(vec3(0.30, 0.24, 0.18));
        col = mix(col, moonCol, moonMask);
    }

    // Crisp razor-thin golden diamond corona ring along lunar limb (tightened to match sheet_act4.jpg)
    float razorRing = exp(-abs(ang - R_MOON) * 340.0);
    float tightGlow = exp(-abs(ang - R_MOON) * 115.0);
    col += vec3(1.0, 0.90, 0.66) * razorRing * 4.0 + coronaGold * tightGlow * 0.62;
    return col;
}

vec4 act4Waves(vec2 p, float u4, float footprint) {
    vec4 sum = vec4(0.0);
    const int N = QUALITY >= 3 ? 6 : (QUALITY == 2 ? 5 : 4);
    for (int i = 0; i < N; i++) {
        float fi = float(i);
        float ang = 1.48 + (fi - 2.0) * 0.22;
        vec2 dir = vec2(cos(ang), sin(ang));
        float wl = 2.85 * pow(0.69, fi);
        float amp = 0.020 * pow(0.66, fi);
        sum += waterWaveD(p + vec2(fi * 1.1, fi * 0.7), u4 * 1.10, dir, wl, amp, 4.0, footprint);
    }
    return sum;
}

vec3 renderAct4(vec2 coord, float u4, out vec3 dbgOut) {
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
    const int BASALT_STEPS = QUALITY >= 3 ? 116 : (QUALITY == 2 ? 96 : 72);
    for (int i = ZERO; i < BASALT_STEPS; i++) {
        steps++;
        vec3 p = ro + rd * t;
        if (p.y > 7.2 && rd.y >= 0.0) break;
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
        vec3 n = act4Normal(p, max(0.0028, fp * 0.55));

        float keep = 1.0 - smoothstep(0.03, 0.25, fp);
        // Vertical basalt cleavage & horizontal volcanic fracture strata (replaces diagonal cobble Voronoi!)
        float horizStrata = 0.5 + 0.5 * sin(p.y * 6.5 + fbm(p.xz * 1.8, 2) * 2.6);
        float stoneGrain  = 0.5 + 0.5 * fbm(vec2(p.x * 2.4 + p.z * 2.4, p.y * 1.6), 3);
        float tex = (0.72 + 0.28 * stoneGrain * keep) * (0.82 + 0.18 * horizStrata * keep);

        // Weathered dark charcoal-slate volcanic basalt with clear twilight readability & warm eclipse gold rims
        vec3 basaltAlbedo = srgbToLinear(vec3(0.092, 0.095, 0.102)) * tex;
        float ao = act4AO(p, n, 0.34);

        float innerFace = saturate(-sign(p.x) * n.x);
        float eclipseFace = saturate(dot(n, sun) * 0.7 + 0.3);
        float innerEdge = pow(innerFace, 1.35) * (1.0 - smoothstep(4.2, 8.6, abs(p.x)));
        float topRim = smoothstep(0.45, 0.95, n.y);

        vec3 col = basaltAlbedo * hemisphereLight(n, srgbToLinear(vec3(0.32, 0.43, 0.56)) * 1.25, vec3(0.055, 0.062, 0.072)) * (0.25 + 0.75 * ao);
        // Golden eclipse grazing light catching inner basalt facets, vertical edges & weathered tops
        vec3 goldLight = blackbody(4000.0);
        col += basaltAlbedo * goldLight * innerEdge * (2.60 + 1.65 * exp(-max(p.y - 0.1, 0.0) * 0.42));
        col += basaltAlbedo * goldLight * eclipseFace * (0.48 + 0.42 * topRim) * ao;

        float haze = 1.0 - exp(-colT * 0.015);
        col = mix(col, act4Sky(normalize(vec3(rd.x, max(rd.y, 0.02), rd.z)), false) * 0.52, haze * 0.70);

        dbgOut = n * 0.5 + 0.5;
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(colT * 0.05);
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(MAT_BASALT);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(steps) / 100.0);
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
        vec3 n = normalize(vec3(-wv.y * 1.15, 1.0, -wv.z * 1.35));
        vec3 v = -rd;

        float F = fresnelDielectric(max(dot(n, v), 0.0), 1.0, 1.333);
        vec3 refl = reflect(rd, n);
        refl.y = max(refl.y, 0.002);
        vec3 reflCol = act4Sky(refl, true);

        // Soft physically-matched basalt colonnade reflection occlusion (rich glossy stone reflections, never pitch black!)
        if (abs(refl.x) > 0.015) {
            float wallX = refl.x > 0.0 ? (ACT4_CORRIDOR + 0.15) : -(ACT4_CORRIDOR + 0.15);
            float tWall = (wallX - p.x) / refl.x;
            if (tWall > 0.0) {
                float hitH = refl.y * tWall;
                float wallShadow = 1.0 - smoothstep(2.2, 5.2, hitH);
                vec3 wallReflTint = mix(vec3(1.0), vec3(0.11, 0.13, 0.17), wallShadow);
                reflCol *= wallReflTint;
            }
        }

        // Shimmering liquid-gold eclipse reflection path across broad twilight ocean swells
        vec3 glint = specularGGX(n, v, sun, 0.072, vec3(0.032)) * blackbody(4100.0) * 3.1;
        vec3 wideGlint = specularGGX(n, v, sun, 0.21, vec3(0.025)) * blackbody(3900.0) * 0.90;

        vec3 deepBody = srgbToLinear(vec3(0.026, 0.044, 0.064));
        vec3 col = deepBody * (1.0 - F * 0.88) + reflCol * (F * 0.88 + 0.11) + glint + wideGlint;

        float haze = 1.0 - exp(-waterT * 0.009);
        col = mix(col, act4Sky(normalize(vec3(rd.x, 0.015, rd.z)), false) * 0.72, haze * 0.62);

        dbgOut = n * 0.5 + 0.5;
        #if DEBUG_MODE == 1
            dbgOut = debugDistance(waterT * 0.04);
        #elif DEBUG_MODE == 3
            dbgOut = debugIdColor(9.0);
        #elif DEBUG_MODE == 4
            dbgOut = debugHeat(float(steps) / 100.0);
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

// Single call-site per act eliminates 3x monolithic shader inlining bloat
vec3 evalAct(int actIdx, vec2 coord, float localT, float loopPhase, out vec3 dbgOut, out float exposure) {
    if (actIdx == 0) {
        exposure = 1.28;
        return renderAct1(coord, localT, loopPhase, dbgOut);
    } else if (actIdx == 1) {
        exposure = 1.42;
        return renderAct2(coord, localT, dbgOut);
    } else if (actIdx == 2) {
        exposure = 1.40;
        return renderAct3(coord, localT, dbgOut);
    } else {
        exposure = 1.48;
        return renderAct4(coord, localT, dbgOut);
    }
}

vec3 renderTimelineSample(vec2 coord) {
    float t = mod(iTime, LOOP_SECONDS);
    if (t < 0.0) t += LOOP_SECONDS;
    float loopPhase = t * OMEGA; // Exact [0, TAU) phase over 20.0s
    vec2 uv = (2.0 * coord - iResolution.xy) / iResolution.y;

    int actA = clamp(int(floor(t / ACT_DURATION)), 0, 3);
    float localA = t - float(actA) * ACT_DURATION;
    float dissolveStart = ACT_DURATION - DISSOLVE_DUR;
    float w = localA > dissolveStart ? linearstep(dissolveStart, ACT_DURATION, localA) : 0.0;
    int actB = (actA + 1) & 3;
    float localB = localA - ACT_DURATION;

    vec3 outCol = vec3(0.0);
    for (int pass = ZERO; pass < 2; pass++) {
        if (pass == 1 && w <= 0.0) break;
        int actIdx = pass == 0 ? actA : actB;
        float localT = pass == 0 ? localA : localB;
        vec3 dbg = vec3(0.0);
        float expVal = 1.45;
        vec3 hdr = evalAct(actIdx, coord, localT, loopPhase, dbg, expVal);
        #if DEBUG_MODE != 0
            vec3 res = dbg;
        #else
            vec3 res = finishDisplay(hdr, uv, expVal);
        #endif
        outCol = pass == 0 ? res : mix(outCol, res, w);
    }
    return outCol;
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
