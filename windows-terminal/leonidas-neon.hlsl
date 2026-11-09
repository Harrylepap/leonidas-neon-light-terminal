// Leonidas - Neon Light : neon glow + twinkling sparkles for Windows Terminal
// Loaded through "experimental.pixelShaderPath"; toggle with Ctrl+Alt+G.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings {
    float  Time;
    float  Scale;
    float2 Resolution;
    float4 Background;
};

// ── Réglages ────────────────────────────────────────────────────────────────
#define GLOW_STRENGTH   0.55   // intensité du halo néon
#define GLOW_RADIUS     3.0    // rayon du halo (px, multiplié par Scale)
#define SPARK_CELL      34.0   // taille de la grille d'étincelles (px)
#define SPARK_DENSITY   0.16   // part des cellules qui portent une étincelle
#define SPARK_STRENGTH  0.85   // éclat max d'une étincelle

static const float3 NEON_PINK   = float3(1.000, 0.180, 0.533);
static const float3 NEON_ORANGE = float3(1.000, 0.478, 0.184);
static const float3 GOLDEN      = float3(0.988, 0.686, 0.090);
static const float3 LAGOON      = float3(0.169, 0.851, 0.910);

float hash21(float2 p) {
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

// Poids d'un pixel pour le halo : couleurs saturées/lumineuses seulement
float glowWeight(float3 c) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float sat = mx - mn;
    return saturate((mx - 0.35) * 1.6) * saturate(sat * 2.0 + 0.25);
}

float3 neonGlow(float2 uv) {
    float2 px = 1.0 / Resolution;
    float r = GLOW_RADIUS * max(Scale, 1.0);
    float3 acc = 0;
    float total = 0;
    [unroll] for (int ring = 1; ring <= 2; ring++) {
        [unroll] for (int i = 0; i < 8; i++) {
            float a = (i + ring * 0.5) * 0.785398;
            float2 o = float2(cos(a), sin(a)) * r * ring * px;
            float3 s = shaderTexture.Sample(samplerState, uv + o).rgb;
            float w = 1.0 / ring;
            acc += s * glowWeight(s) * w;
            total += w;
        }
    }
    return acc / total;
}

float3 sparkles(float2 pos, out float amount) {
    amount = 0;
    float cell = SPARK_CELL * max(Scale, 1.0);
    // slow upward drift, like embers over a neon boulevard
    float2 p = pos + float2(0, Time * 6.0 * Scale);
    float2 id = floor(p / cell);
    float2 f = p - id * cell;

    float h = hash21(id);
    if (h > SPARK_DENSITY) return 0;

    float2 center = (float2(hash21(id + 7.1), hash21(id + 3.7)) * 0.6 + 0.2) * cell;
    float2 d = (f - center) / max(Scale, 1.0);

    float phase = hash21(id + 11.3) * 6.2831;
    float speed = 1.2 + hash21(id + 5.9) * 2.0;
    float tw = pow(saturate(sin(Time * speed + phase)), 6.0);

    float core = exp(-dot(d, d) / 1.6);
    float rays = exp(-abs(d.x) * 0.9) * exp(-d.y * d.y / 0.35)
                + exp(-abs(d.y) * 0.9) * exp(-d.x * d.x / 0.35);
    float shape = saturate(core + rays * 0.45);

    float pick = hash21(id + 19.4);
    float3 col = pick < 0.35 ? NEON_PINK : pick < 0.6 ? NEON_ORANGE : pick < 0.85 ? GOLDEN : LAGOON;

    amount = shape * tw * SPARK_STRENGTH;
    return col;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET {
    float4 color = shaderTexture.Sample(samplerState, tex);

    // 1. Halo néon autour du texte coloré
    float3 glow = neonGlow(tex);
    color.rgb += glow * GLOW_STRENGTH;

    // 2. Étincelles, seulement là où il n'y a pas de texte (lisibilité)
    float3 diff = abs(shaderTexture.Sample(samplerState, tex).rgb - Background.rgb);
    float isBg = 1.0 - saturate(max(diff.r, max(diff.g, diff.b)) * 6.0);
    float amount;
    float3 sc = sparkles(pos.xy, amount);
    amount *= isBg;
    color.rgb = lerp(color.rgb, sc, amount) + sc * amount * 0.35;
    color.a = max(color.a, amount);

    return color;
}
