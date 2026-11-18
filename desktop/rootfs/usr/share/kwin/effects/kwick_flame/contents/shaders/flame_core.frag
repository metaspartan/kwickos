#version 140
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform int textureWidth;
uniform int textureHeight;

uniform float uProgress;
uniform float uClock;
uniform float uSeed;
uniform float uFrameL;
uniform float uFrameR;
uniform float uFrameB;
uniform float uFrameT;
uniform float uLogW;
uniform float uLogH;
uniform float uOver;
uniform float uStyle;
uniform float uHeight;

in vec2 texcoord0;
out vec4 fragColor;

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
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

float fbm2(vec2 p) {
    return 0.6667 * vnoise(p) + 0.3333 * vnoise(p * 2.03 + vec2(17.1, 9.7));
}

float fbm3(vec2 p) {
    float v = 0.5714 * vnoise(p);
    v += 0.2857 * vnoise(p * 2.03 + vec2(17.1, 9.7));
    return v + 0.1429 * vnoise(p * 4.11 + vec2(5.3, 11.9));
}

vec3 blackbody(float T, float blue) {
    float k = mix(7.0, mix(30.0, 66.0, blue), T * T);
    float g = clamp(0.39008158 * log(k) - 0.63184144, 0.0, 1.0);
    float b = clamp(0.54320679 * log(max(k - 10.0, 1.0)) - 1.19625409, 0.0, 1.0);
    vec3 fire = vec3(1.0, g, b);
    vec3 gas = vec3(0.08 + 0.9 * b * b, 0.25 * g + 0.6 * b, 1.0);
    float I = clamp(1.6 * T * sqrt(T), 0.0, 1.0);
    return mix(fire, gas, blue) * I;
}

float sparks(vec2 P, float cell, float speed, float seed, float t) {
    vec2 g = vec2(P.x, P.y - t * speed) / cell;
    vec2 id = floor(g);
    float h = hash(id + seed);
    float h2 = hash(id.yx + seed * 1.37 + 3.1);
    vec2 c = vec2(0.5 + 0.35 * sin(t * (2.0 + 3.0 * h) + h2 * 6.283), 0.15 + 0.7 * h2);
    float r = length((fract(g) - c) * cell);
    float life = 1.0 - fract(h * 5.3 + t * 0.45);
    return smoothstep(1.7, 0.4, r) * step(0.84, h) * life * life;
}

vec3 legacyRamp(float a) {
    vec3 c = mix(vec3(1.0, 0.92, 0.55), vec3(1.0, 0.5, 0.08), smoothstep(0.0, 0.25, a));
    c = mix(c, vec3(0.9, 0.2, 0.03), smoothstep(0.2, 0.55, a));
    c = mix(c, vec3(0.5, 0.05, 0.02), smoothstep(0.5, 0.85, a));
    return mix(c, vec3(0.38, 0.03, 0.01), smoothstep(0.85, 1.0, a));
}

vec4 finish(vec3 rgb, float a) {
    rgb += (hash(gl_FragCoord.xy + fract(uClock * 7.0) * 61.0) - 0.5) / 255.0;
    a = clamp(a, 0.0, 1.0);
    rgb = clamp(rgb, vec3(0.0), vec3(a));
    return nitsToDestinationEncoding(sourceEncodingToNitsInDestinationColorspace(vec4(rgb, a)));
}

void main() {
    vec2 tc = texcoord0;
    vec2 logSize = vec2(max(uLogW, 1.0), max(uLogH, 1.0));
    float dev = max(float(textureWidth) / logSize.x, 0.5);
    float Wf = max((uFrameR - uFrameL) * logSize.x, 1.0);
    float Hf = max((uFrameT - uFrameB) * logSize.y, 1.0);
    vec2 P = (tc - vec2(uFrameL, uFrameB)) * logSize;
    float ov = max(uOver, 0.0);
    float t = uClock;
    float styleId = floor(uStyle + 0.5);
    float legacy = float(styleId > 3.5);
    float p = clamp(uProgress, 0.0, 1.0);
    float pp = legacy > 0.5 ? p : p * p * (3.0 - 2.0 * p);
    bool inTex = tc.y >= 0.0 && tc.y <= 1.0;
    bool inFrame = P.x >= 0.0 && P.x <= Wf && P.y >= 0.0 && P.y <= Hf;
    bool inBand = P.x >= 0.0 && P.x <= Wf && P.y >= 0.0 && P.y <= Hf + ov;
    float hs = max(uHeight, 0.3);
    float Apx = clamp(0.07 * Hf, 14.0, 46.0);
    float charW = 26.0;
    float f0 = -(Apx + charW + 24.0);
    float f1 = Hf + Apx + 24.0;
    float fpx = mix(f0, f1, pp);

    vec4 shade = vec4(0.0);
    if (!inFrame) {
        shade = inTex ? texture(sampler, clamp(tc, 0.0, 1.0)) : vec4(0.0);
        vec2 Pc = clamp(P, vec2(0.0), vec2(Wf, Hf));
        float shK = smoothstep(-Apx - 14.0, Apx + 10.0, Pc.y - fpx) * (1.0 - smoothstep(0.75, 1.0, pp));
        if (legacy > 0.5) {
            shK = smoothstep(-0.06, 0.04, Pc.y / Hf - mix(-0.04, 1.04, pp)) * (1.0 - smoothstep(0.8, 1.0, pp));
        }
        shade *= shK;
        if (!inBand) {
            if (shade.a <= 0.0) {
                discard;
            }
            fragColor = nitsToDestinationEncoding(sourceEncodingToNitsInDestinationColorspace(shade));
            return;
        }
    }

    vec4 src = inTex ? texture(sampler, clamp(tc, 0.0, 1.0)) : vec4(0.0);
    float edgeAA = 0.75 / dev;

    if (legacy > 0.5) {
        float Hl = Hf;
        float frontL = mix(-0.04, 1.04, pp);
        float riseMax = min(0.5 * Hl, 220.0) * hs;
        float fy = frontL * Hl;
        if (P.y > fy + riseMax * 1.3 + 70.0 || P.y < fy - 50.0) {
            vec4 keep = inFrame ? (P.y < fy - 50.0 ? vec4(0.0) : src) : shade;
            if (keep.a <= 0.0) {
                discard;
            }
            fragColor = nitsToDestinationEncoding(sourceEncodingToNitsInDestinationColorspace(keep));
            return;
        }
        float body = inFrame ? 1.0 : 0.0;
        float wob = (fbm2(vec2(P.x / 90.0, t * 0.8 + uSeed)) - 0.5) * 0.025;
        float dl = P.y / Hl - frontL - wob;
        float aliveL = smoothstep(-0.003, 0.012, dl) * body;
        vec3 rgbL = src.rgb * aliveL * body;
        float aL = src.a * aliveL * body;
        float activeL = smoothstep(0.0, 0.02, pp) * (1.0 - smoothstep(0.97, 1.0, pp));
        float hot = exp(-pow((dl - 0.004) / 0.014, 2.0)) * body * activeL;
        float glowL = exp(-pow((dl - 0.01) / 0.07, 2.0)) * activeL * body;
        rgbL += vec3(1.0, 0.85, 0.4) * hot * 1.1 * src.a;
        rgbL += vec3(1.0, 0.4, 0.06) * glowL * 0.5 * src.a;
        aL = max(aL, hot * 0.8 * src.a);
        float accA = 0.0;
        float ageSum = 0.0;
        float cell = 22.0;
        float life = 0.62;
        float dtE = life / 8.0;
        float col0 = floor(P.x / cell);
        for (int sl = 0; sl < 8; sl++) {
            float m = floor(pp / dtE) - float(sl);
            for (int dc = -3; dc <= 3; dc++) {
                float c = col0 + float(dc);
                float h1 = hash(vec2(c, m) + uSeed);
                float h2 = hash(vec2(c * 1.3, m * 0.7) + 5.0 + uSeed);
                float h3 = hash(vec2(m, c) + 9.0);
                float te = (m + h1) * dtE;
                float a = (pp - te) / life;
                float x0 = (c + h2) * cell;
                if (te < 0.0 || te > 1.0 || a < 0.0 || a > 1.0 || x0 < 0.0 || x0 > Wf) {
                    continue;
                }
                float y0 = mix(-0.04, 1.04, te) * Hl;
                float rise = pow(a, 0.6) * riseMax * (0.8 + 0.45 * h3);
                float tb = (vnoise(vec2(h1 * 17.0 + a * 3.0, t * 2.2 + h2 * 9.0)) - 0.5) * 70.0 * a;
                vec2 pos = vec2(x0 + tb + sin(a * 6.0 + h1 * 6.28) * 14.0 * a, y0 + rise);
                float rad = cell * (0.75 + 0.9 * h3) * (1.2 - 0.32 * a) * (1.0 + 0.15 * sin(t * 18.0 + h1 * 40.0));
                vec2 dv = vec2(P.x - pos.x, (P.y - pos.y) * 0.5) / rad;
                float w = exp(-dot(dv, dv) * 1.5) * (1.0 - pow(a, 2.2)) * (0.8 + 0.4 * h2);
                accA += w;
                ageSum += w * a;
            }
        }
        float avgAge = ageSum / max(accA, 0.001);
        float tongue = 0.7 + 0.6 * fbm2(vec2(P.x / 38.0, P.y / 110.0 - t * 5.5 + uSeed));
        float clip = (1.0 - smoothstep(Hf + 0.25 * ov, Hf + ov, P.y)) * smoothstep(0.0, 6.0, P.x) * smoothstep(0.0, 6.0, Wf - P.x);
        float cover = (1.0 - exp(-accA * 2.6 * tongue)) * clip;
        float core = 1.0 - exp(-accA * 0.55);
        vec3 fcol = legacyRamp(clamp(avgAge * 1.35 + 0.04 - core * 0.1, 0.0, 1.0));
        vec3 rgbF = rgbL * (1.0 - cover * 0.85) + fcol * cover * 0.95 + vec3(1.0, 0.8, 0.35) * pow(core, 3.0) * 0.3 * cover;
        float aF = max(aL, cover * 0.97);
        if (!inFrame) {
            rgbF += shade.rgb * (1.0 - cover);
            aF = aF + shade.a * (1.0 - aF);
        }
        aF = max(aF, max(rgbF.r, max(rgbF.g, rgbF.b)));
        fragColor = finish(rgbF, aF);
        return;
    }

    float inferno = float(styleId > 0.5 && styleId < 1.5);
    float ember = float(styleId > 1.5 && styleId < 2.5);
    float blue = float(styleId > 2.5 && styleId < 3.5);
    float plumeK = mix(mix(mix(1.0, 1.3, inferno), 0.38, ember), 0.85, blue);
    float densK = mix(mix(1.0, 1.25, inferno), 0.65, ember);
    float tempK = mix(mix(1.0, 1.08, inferno), 0.72, ember);
    float sparkK = mix(mix(mix(1.0, 1.5, inferno), 3.0, ember), 0.5, blue);
    float plumeH = clamp(0.2 * Hf, 48.0, 150.0) * hs * plumeK;
    float act = smoothstep(0.0, 0.1, pp) * (1.0 - smoothstep(0.88, 1.0, pp));
    float upper = max(plumeH * 1.55 * step(0.001, act), charW * 3.0) + 4.0;

    float dHi = P.y + Apx - fpx;
    float dLo = P.y - Apx - fpx;
    if (dHi < -16.0) {
        if (shade.a <= 0.0) {
            discard;
        }
        fragColor = nitsToDestinationEncoding(sourceEncodingToNitsInDestinationColorspace(shade));
        return;
    }
    if (dLo > upper) {
        vec4 keep = inFrame ? src : shade;
        if (keep.a <= 0.0) {
            discard;
        }
        fragColor = nitsToDestinationEncoding(sourceEncodingToNitsInDestinationColorspace(keep));
        return;
    }

    vec2 sd = vec2(uSeed, uSeed * 0.37);
    float en = fbm2(P / 92.0 + sd + vec2(0.0, -t * 0.22));
    float d = P.y + (en - 0.5) * 2.0 * Apx - fpx;
    float body = inFrame ? 1.0 : 0.0;
    float edgeOn = smoothstep(0.0, 0.03, pp) * (1.0 - smoothstep(0.985, 1.0, pp));

    float w = vnoise(vec2(P.x, d) / 46.0 + sd + vec2(3.7, -t * 2.1));
    float fadeU = smoothstep(upper, upper * 0.5, d);
    float heatN = exp(-max(d, 0.0) / 44.0) * act * fadeU;
    vec2 shimmer = vec2(w - 0.5, 0.0) * 2.2 * heatN * body;
    if (heatN > 0.02 && inFrame) {
        src = texture(sampler, clamp(tc + shimmer / logSize, 0.0, 1.0));
    }
    src *= body;

    float detail = vnoise(P / 7.0 + sd * 3.0);
    float scorch = smoothstep(charW * 3.0, charW * 0.4, d);
    float charT = smoothstep(charW, 0.0, d) * (0.82 + 0.18 * detail);
    vec3 surf = src.rgb * mix(vec3(1.0), vec3(0.86, 0.6, 0.42), scorch * 0.5 * edgeOn);
    surf = mix(surf, src.a * vec3(0.035, 0.025, 0.02), charT * edgeOn);
    float alive = smoothstep(-edgeAA, edgeAA, d);
    float vein = 1.0 - abs(2.0 * vnoise(P / 11.0 + sd * 1.7) - 1.0);
    vein = vein * vein;
    vein = vein * vein * charT;
    float hot = exp(-max(d, 0.0) / 5.5) * (0.65 + 0.5 * detail) * (0.85 + 0.15 * sin(t * 17.0 + w * 9.0));
    vec3 rgb = surf * alive;
    rgb += blackbody(0.55 + 0.4 * hot, blue) * (hot * 1.1 + vein * 0.7) * src.a * alive * edgeOn;
    rgb += blackbody(0.5, blue) * exp(-max(d, 0.0) / 38.0) * 0.22 * src.rgb * act * fadeU;
    float a = src.a * alive;

    float flake = smoothstep(0.78, 0.86, vnoise(P / 2.6 + sd * 5.0)) * smoothstep(-11.0, -1.0, d) * (1.0 - alive) * edgeOn;
    rgb += blackbody(0.45 + 0.35 * smoothstep(-11.0, 0.0, d), blue) * flake * src.a;
    a += flake * src.a * 0.85;

    if (!inFrame) {
        rgb = shade.rgb;
        a = shade.a;
    }

    float side = min(P.x, Wf - P.x);
    float env = plumeH * (0.55 + 0.85 * vnoise(vec2(P.x / 58.0 + uSeed, t * 1.25))) * mix(0.55, 1.0, smoothstep(0.0, 48.0, side));
    float turb = mix(mix(1.0, 1.4, inferno), 0.7, ember);
    vec2 q = vec2(P.x, max(d, 0.0)) / 64.0;
    float n = fbm3(vec2(q.x + (w - 0.5) * 0.9 * turb, q.y * 0.55 - t * 2.4) + sd);
    n += 0.16 * (vnoise(vec2(q.x * 3.1 + (w - 0.5) * 1.6 * turb, q.y * 2.2 - t * 6.5) + sd * 2.3) - 0.5);
    float hr = max(d, 0.0) / env;
    float dens = smoothstep(0.0, 0.42, (n - 0.17 - 0.62 * hr) * densK);
    dens *= smoothstep(-3.0, 5.0, d) * act;
    dens *= smoothstep(0.0, 6.0, side) * (1.0 - smoothstep(Hf + 0.2 * ov, Hf + ov, P.y));
    float T = clamp(dens * (1.0 - 0.62 * hr) * (0.7 + 0.5 * n) * tempK, 0.0, 1.0);
    vec3 fcol = blackbody(T, blue);
    float fa = smoothstep(0.02, 0.6, dens) * 0.94;
    rgb = rgb * (1.0 - fa) + fcol * fa;
    a = a * (1.0 - fa) + fa;

    float smoke = smoothstep(0.55, 1.0, hr) * (1.0 - smoothstep(1.0, 1.35, hr)) * (1.0 - smoothstep(plumeH * 1.2, plumeH * 1.5, d)) * smoothstep(0.45, 0.7, n) * 0.22 * act * (1.0 - ember);
    smoke *= smoothstep(0.0, 12.0, side) * (1.0 - smoothstep(Hf + 0.2 * ov, Hf + ov, P.y));
    rgb = rgb * (1.0 - smoke) + mix(vec3(0.07, 0.05, 0.045), vec3(0.04, 0.05, 0.09), blue) * smoke;
    a = a * (1.0 - smoke) + smoke;

    float sz = smoothstep(-2.0, 10.0, d) * (1.0 - smoothstep(plumeH * 0.45, plumeH * 1.45, d)) * act;
    sz *= smoothstep(0.0, 4.0, side) * (1.0 - smoothstep(Hf + 0.5 * ov, Hf + ov, P.y));
    if (sz > 0.0) {
        float sp = sparks(P + sd * 40.0, 13.0, 95.0, uSeed, t) + 0.8 * sparks(P + sd * 70.0, 21.0, 150.0, uSeed + 9.0, t * 1.1);
        sp = clamp(sp * sz * sparkK, 0.0, 1.0);
        vec3 sc = blackbody(0.6 + 0.3 * hash(floor(P / 3.0)), blue);
        rgb = rgb * (1.0 - sp) + sc * sp;
        a = a * (1.0 - sp) + sp;
    }

    a = max(a, max(rgb.r, max(rgb.g, rgb.b)));
    fragColor = finish(rgb, a);
}
