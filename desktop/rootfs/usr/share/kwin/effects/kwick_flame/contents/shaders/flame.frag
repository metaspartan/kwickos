#define KWIN_LEGACY
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform int textureWidth;
uniform int textureHeight;

uniform float uProgress;
uniform float uClock;
uniform float uSeed;
uniform float uStyle;
uniform float uHeight;

varying vec2 texcoord0;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p = p * 2.02 + vec2(17.1, 9.7);
        a *= 0.5;
    }
    return v;
}

float fbm3(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * vnoise(p);
        p = p * 2.1 + vec2(5.3, 11.9);
        a *= 0.5;
    }
    return v;
}

vec3 fireRamp(float h, float blue) {
    vec3 core = vec3(1.0, 0.97, 0.78);
    vec3 yellow = vec3(1.0, 0.72, 0.16);
    vec3 orange = vec3(0.98, 0.34, 0.04);
    vec3 red = vec3(0.55, 0.07, 0.02);
    vec3 smoke = vec3(0.1, 0.06, 0.05);
    vec3 c = mix(core, yellow, smoothstep(0.0, 0.18, h));
    c = mix(c, orange, smoothstep(0.14, 0.42, h));
    c = mix(c, red, smoothstep(0.4, 0.74, h));
    c = mix(c, smoke, smoothstep(0.72, 1.0, h));
    vec3 d = mix(vec3(0.9, 0.97, 1.0), vec3(0.35, 0.72, 1.0), smoothstep(0.0, 0.2, h));
    d = mix(d, vec3(0.1, 0.28, 0.95), smoothstep(0.16, 0.45, h));
    d = mix(d, vec3(0.04, 0.08, 0.35), smoothstep(0.42, 0.76, h));
    d = mix(d, vec3(0.03, 0.05, 0.1), smoothstep(0.74, 1.0, h));
    return mix(c, d, blue);
}

float sparkLayer(vec2 pos, float scale, float speed, float seed, float t, float zone) {
    vec2 g = vec2(pos.x, -pos.y) / scale;
    g.y += t * speed / scale;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = hash(id + seed);
    float h2 = hash(id * 1.7 + seed + 3.1);
    f.x += sin(t * (3.0 + h * 4.0) + h * 6.28) * 0.3;
    float d = length(f - (vec2(h, h2) - 0.5) * 0.5);
    float life = fract(h2 * 7.0 + t * 0.35);
    return smoothstep(0.2, 0.02, d) * step(0.78, h) * (1.0 - life) * zone;
}

void main() {
    vec2 size = vec2(float(textureWidth), float(textureHeight));
    float hs = max(uHeight, 0.3);
    float styleId = floor(uStyle + 0.5);
    float inferno = float(styleId > 0.5 && styleId < 1.5);
    vec2 mg = vec2(clamp(0.3 * size.x, 90.0, 340.0), clamp(0.85 * size.y, 220.0, 560.0)) * hs * (1.0 + 0.3 * inferno);
    vec2 S = 1.0 + 2.0 * mg / size;
    vec2 tc = (texcoord0 - 0.5) * S + 0.5;
    vec2 pxp = (tc - 0.5) * size;
    float ember = float(styleId > 1.5 && styleId < 2.5);
    float blue = float(styleId > 2.5);
    float plumeAmt = mix(mix(1.0, 1.25, inferno), 0.3, ember);
    float flareW = mix(mix(0.24, 0.55, inferno), 0.06, ember);
    float densGain = mix(mix(1.0, 1.35, inferno), 0.55, ember);
    float sparkGain = mix(mix(1.0, 1.4, inferno), 3.2, ember);
    float tongueScale = mix(1.0, 0.7, inferno);
    float turb = mix(mix(1.0, 1.6, inferno), 0.7, ember);

    float p = clamp(uProgress, 0.0, 1.0);
    p = p * p * (3.0 - 2.0 * p);
    float t = uClock;

    vec2 inWin = step(vec2(0.0), tc) * step(tc, vec2(1.0));
    float inside = inWin.x * inWin.y;
    vec2 ctc = clamp(tc, 0.0, 1.0);
    float outDist = abs(tc.x - ctc.x) * size.x / size.y;

    float scale = 150.0;
    vec2 np = vec2(tc.x * size.x, (1.0 - tc.y) * size.y) / scale + vec2(uSeed, uSeed * 0.37);

    float height = tc.y;

    vec2 warp = vec2(fbm3(np * 1.3 + vec2(0.0, -t * 2.4)), fbm3(np * 1.3 + vec2(7.7, -t * 2.9))) - 0.5;
    warp *= turb;
    float n = fbm(np + warp * 0.9 + vec2(0.0, -t * 1.7));
    float n2 = fbm3(np * 2.6 + warp * 1.4 + vec2(t * 0.6, -t * 3.4));

    float s = height + (n - 0.5) * 0.4 + (fbm3(np * 3.4 + warp) - 0.5) * 0.07;
    float front = mix(-0.22, 1.28, p);
    float d = s - front;

    float nearFront = exp(-abs(d) * 9.0) * inside;
    vec2 shimmer = vec2(warp.x, warp.y * 0.5) * 0.035 * nearFront * smoothstep(0.0, 0.06, p) * (1.0 - smoothstep(0.94, 1.0, p));
    vec4 src = texture2D(sampler, clamp(tc + vec2(shimmer.x, -shimmer.y), 0.001, 0.999)) * inside;
    float a0 = src.a;
    vec3 base = src.rgb;

    float alive = smoothstep(-0.012, 0.02, d);
    float charZone = smoothstep(0.1, 0.0, d);
    float charT = smoothstep(0.075, 0.012, d) * 0.88;
    vec3 body = base * mix(vec3(1.0), vec3(0.05, 0.03, 0.025), charT);
    body = mix(body, base * vec3(0.9, 0.55, 0.38), smoothstep(0.35, 0.1, d) * 0.45 * (1.0 - charT));
    float crack = smoothstep(0.34, 0.56, fbm3(np * 5.0 + uSeed)) * charZone;
    body += fireRamp(0.28 + 0.5 * (1.0 - n2), blue) * crack * 0.65 * smoothstep(0.1, 0.0, d) * a0;

    float rimW = 0.032;
    float rim = exp(-pow((d - 0.006) / rimW, 2.0));
    float rimHot = exp(-pow((d - 0.002) / (rimW * 0.45), 2.0));
    vec3 rimCol = mix(fireRamp(0.22 + 0.25 * n2, blue), fireRamp(0.0, blue), rimHot);
    float rimI = (0.55 + 0.9 * n2) * rim * (0.75 + 0.5 * sin(t * 18.0 + n * 12.0)) * inside;

    float colN = fbm3(vec2(np.x * 1.1, uSeed));
    float colN2 = fbm3(vec2(np.x * 3.1, uSeed + 4.0));
    float frontCol = clamp(front, -0.05, 1.05) + (0.5 - colN) * 0.34 + (0.5 - colN2) * 0.08;
    float act = smoothstep(0.02, 0.14, p) * (1.0 - smoothstep(0.88, 1.0, p));
    float plumeH = (0.4 + 1.45 * pow(sin(3.14159 * p), 0.7)) * plumeAmt * hs;
    float hAF = height - frontCol;
    float qq = hAF / max(plumeH, 0.05);
    float side = outDist / flareW;
    vec2 pl = vec2(tc.x * size.x / size.y * 2.4 * tongueScale, hAF * 1.1);
    float tongue = fbm(pl * vec2(1.0, 0.75) * 1.6 + vec2(warp.x * 2.2, -t * 5.4 + uSeed));
    float lick = fbm3(pl * vec2(2.4, 1.3) + vec2(warp.y * 2.0, -t * 8.0));
    float dens = clamp((tongue * 1.75 + lick * 0.4 - 0.12) * densGain - qq * 0.85 - side * 1.0, 0.0, 1.0);
    dens *= step(0.0, hAF) * smoothstep(0.0, 0.03, hAF + 0.03);
    float topDist = max(tc.y - 1.0, 0.0) * size.y / max(mg.y, 1.0);
    float sideDist = max(max(-tc.x, tc.x - 1.0), 0.0) * size.x / max(mg.x, 1.0);
    float edgeFade = (1.0 - smoothstep(0.7, 1.0, topDist)) * (1.0 - smoothstep(0.7, 1.0, sideDist));
    dens *= edgeFade * act;
    float colH = clamp(qq * 0.85 + (1.0 - dens) * 0.45 + (0.5 - n2) * 0.22 + side * 0.3, 0.0, 1.0);
    vec3 flameCol = fireRamp(colH, blue);
    float flameA = dens * 0.78;

    float afterGlow = smoothstep(-0.2, 0.0, d) * step(d, 0.0) * inside;
    float hole = smoothstep(0.45, 0.62, fbm3(np * 3.2 + vec2(0.0, -t))) * afterGlow;
    float residue = afterGlow * hole * (0.5 + 0.5 * n2);
    vec3 residueCol = fireRamp(0.4 + 0.5 * (1.0 - afterGlow), blue);

    float smokeN = fbm3(np * 1.0 + vec2(0.0, -t * 1.6));
    float smokeZone = smoothstep(plumeH * 0.45, plumeH * 1.35, hAF) * (1.0 - smoothstep(plumeH * 1.35, plumeH * 2.1, hAF));
    smokeZone *= edgeFade * (1.0 - min(side, 1.0) * 0.5) * act;
    float smokeA = smokeZone * smoothstep(0.4, 0.65, smokeN) * 0.38;
    vec3 smokeCol = mix(vec3(0.13, 0.1, 0.09), vec3(0.08, 0.1, 0.16), blue);

    float sz = smoothstep(-0.5, 0.0, d) * (1.0 - smoothstep(plumeH * 0.4, plumeH * 1.6, hAF)) * (1.0 - min(side, 1.0) * 0.35);
    sz *= (1.0 - smoothstep(0.7, 1.0, topDist)) * (1.0 - smoothstep(0.7, 1.0, sideDist)) * smoothstep(0.03, 0.14, p) * (1.0 - smoothstep(0.9, 0.99, p));
    float sp = sparkLayer(pxp, 9.0, 130.0 * (1.0 + p), uSeed, t * 3.0, sz);
    sp += sparkLayer(pxp, 15.0, 200.0, uSeed + 9.0, t * 3.4, sz) * 0.8;
    sp += sparkLayer(pxp, 22.0, 290.0, uSeed + 21.0, t * 2.6, sz) * 0.7 * sparkGain;
    sp *= min(sparkGain, 1.5);
    vec3 sparkCol = fireRamp(0.04 + 0.2 * hash(floor(pxp / 3.0)), blue);

    vec3 rgb = body * alive;
    float outA = a0 * alive;

    rgb = rgb * (1.0 - flameA) + flameCol * flameA * 1.15;
    outA = outA * (1.0 - flameA) + flameA;

    float glowOn = clamp(a0 * 3.0, 0.0, 1.0);
    rgb += rimCol * rimI * 0.85 * glowOn;
    outA = max(outA, clamp(rimI * 0.7, 0.0, 1.0) * glowOn);

    rgb += residueCol * residue * 0.9 * glowOn;
    outA = max(outA, residue * 0.8 * glowOn);

    float sA = smokeA * (1.0 - outA);
    rgb += smokeCol * sA;
    outA += sA;

    rgb += sparkCol * sp * 1.4;
    outA = max(outA, clamp(sp, 0.0, 1.0));

    vec4 outColor = vec4(min(rgb, vec3(1.6)), clamp(outA, 0.0, 1.0));
    outColor.rgb = min(outColor.rgb, vec3(outColor.a + 0.55 * clamp(rimI + residue + sp + dens, 0.0, 1.0)));
    gl_FragColor = outColor;
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
