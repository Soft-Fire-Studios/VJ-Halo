// Shared Campaign Evolved surface family, draft 1. Host: screenspace_general_8tex.
// Named author controls live in the CE8Surface VMT proxy, not in c0_x etc.
// c0..c3 and the two matrix parameters are an internal transport contract.
// See CAMPAIGN_8TEX_SHADERS.md for the carrier and lighting contracts.

sampler2D AlbedoTexture : register(s0);          // sRGB RGB, source opacity A
sampler2D NormalTexture : register(s1);          // Linear tangent-space XYZ
sampler2D SurfaceTexture : register(s2);         // Opacity / roughness / metal / emission
sampler2D PaintMaskTexture : register(s3);       // Linear, ordered RGBA paint weights
#if CE8_LIVE_DETAILS
sampler2D DetailNormalTexture : register(s4);    // Linear RGB, shared native-size patterns
#else
sampler2D EmissionTexture : register(s4);        // sRGB, normalized emission already masked
#endif
#if CE8_DIRECT_PASS
sampler2D ProjectedTexture : register(s5);      // Projected beam/cookie, or white
#else
samplerCUBE EnvironmentTexture : register(s5);  // sRGB cube, ordinary mip chain
#endif
#if CE8_LIVE_DETAILS
sampler2D DetailSurfaceTexture : register(s6);   // G roughness, B metallic; R/A never blended
sampler2D MaterialParameterTexture : register(s7); // RGB-packed parameters plus BRDF LUT
#else
sampler2D FeatureTexture : register(s6);         // R iridescence, G AO; B/A reserved
sampler2D EnvironmentBRDFTexture : register(s7); // Linear split-sum GGX integration RG
#endif

float4 Paint1_NormalStrength : register(c0);
float4 Paint2_RoughnessScale : register(c1);
float4 Paint3_RoughnessBias : register(c2);
float4 Paint4_MetallicScale : register(c3);
float3 EyePosition : register(c10);
#if CE8_DIRECT_PASS
float4 LightPosition_Type : register(c11);
float4 LightColor_Range : register(c12);
float4 LightForward_Near : register(c13);
float4 LightRight_TangentHorizontal : register(c14);
float4 LightUp_TangentVertical : register(c15);
float4 LightAttenuation_Strength : register(c16);
float4 LightMaterialParameters : register(c17); // metallic bias, specular, cutoff, base
float4 LightSurfaceParameters : register(c18);  // paint modes, diffuse gain, cookie, edge
#else
float4 LightPositiveX_MetallicBias : register(c11);
float4 LightNegativeX_EnvironmentTintR : register(c12);
float4 LightPositiveY_EmissionStrength : register(c13);
float4 LightNegativeY_EnvironmentTintB : register(c14);
float4 LightPositiveZ_EnvironmentTintG : register(c15);
float4 LightNegativeZ_BaseStrength : register(c16);
float4 IridescenceParameters : register(c17); // weight, thickness, brightness, saturation
float4 SurfaceParameters : register(c18); // paint mode bits, cutoff, max cube mip, debug view
#endif

// Uniform per-draw quality fades in existing constants; legacy positive
// values mean full quality. Branches skip samples/lobes after fade reaches0.
float LODValue(float value) { return value < 0 ? fmod(-value,8) : value; }
float LODWeight(float value) { return value < 0 ? saturate((floor(-value/8)-1)/255) : 1; }
#define NormalStrength LODValue(Paint1_NormalStrength.w)
#define DetailLOD LODWeight(Paint1_NormalStrength.w)
#if CE8_DIRECT_PASS
#define SpecularLOD LODWeight(LightSurfaceParameters.w)
#else
#define SpecularLOD LODWeight(SurfaceParameters.w)
#endif
#define RoughnessScale Paint2_RoughnessScale.w
#define RoughnessBias Paint3_RoughnessBias.w
#define MetallicScale Paint4_MetallicScale.w
#if CE8_DIRECT_PASS
#define MetallicBias LightMaterialParameters.x
#define SpecularStrength LightMaterialParameters.y
#define AlphaCutoff LightMaterialParameters.z
#define BaseStrength LightMaterialParameters.w
#define PaintBlendModes LightSurfaceParameters.x
#else
#define MetallicBias LightPositiveX_MetallicBias.w
#define EnvironmentTint float3(LightNegativeX_EnvironmentTintR.w, LightPositiveZ_EnvironmentTintG.w, LightNegativeY_EnvironmentTintB.w)
#define EmissionStrength LightPositiveY_EmissionStrength.w
#define BaseStrength LightNegativeZ_BaseStrength.w
#define IridescenceWeight IridescenceParameters.x
#define IridescenceThickness IridescenceParameters.y
#define IridescenceBrightness IridescenceParameters.z
#define IridescenceSaturation IridescenceParameters.w
#define PaintBlendModes SurfaceParameters.x
#define AlphaCutoff SurfaceParameters.y
#define EnvironmentMaxMip SurfaceParameters.z
#define DebugView LODValue(SurfaceParameters.w)
#endif

static const float PI = 3.14159265359;

struct PS_INPUT
{
    float2 uv : TEXCOORD0;
    float3 worldPosition : TEXCOORD1;
    float3 worldNormal : TEXCOORD2;
#if CE8_ATLAS_SURFACE || CE8_ATLAS_BACKGROUND
    float atlasCell : TEXCOORD3;
#endif
    float face : VFACE;
};

#if CE8_ATLAS_SURFACE || CE8_ATLAS_BACKGROUND
float AtlasCellLog(float divisor) { return fmod(floor(PaintBlendModes/divisor),8.0)+5.0; }
float3 AtlasCoordinates(PS_INPUT input,float cellLog)
{
    float cellPixels=exp2(cellLog);
    float gutter=max(1.0,cellPixels/128.0);
    float interior=cellPixels-2.0*gutter;
    float2 dx = ddx(input.uv) * interior;
    float2 dy = ddy(input.uv) * interior;
    float lod = clamp(log2(max(max(length(dx),length(dy)),1.0)),0.0,cellLog);
    float cell = floor(input.atlasCell + 0.5);
    float layout=fmod(floor(PaintBlendModes/256.0),8.0);
    float columns=layout<.5 ? 1.0 : layout<2.5 ? 2.0 : 4.0;
    float rows=layout<1.5 ? 1.0 : layout<3.5 ? 2.0 : 4.0;
    float2 dimensions = cellPixels*float2(columns,rows);
    float2 extent = 1.0/float2(columns,rows);
    float2 origin = float2(fmod(cell,columns),floor(cell/columns)) * extent;
    float2 uv = origin + gutter/dimensions + frac(input.uv) * (interior/dimensions);
    float2 margin = 0.5 * exp2(ceil(lod)) / dimensions;
    return float3(clamp(uv,origin+margin,origin+extent-margin),lod);
}
#endif

float3 SafeNormalize(float3 value, float3 fallback)
{
    float squared = dot(value, value);
    return squared > 1e-12 ? value * rsqrt(max(squared, 1e-12)) : fallback;
}

float3 LinearToSRGB(float3 value)
{
    value = max(value, 0);
    return lerp(12.92 * value, 1.055 * pow(value, 1.0 / 2.4) - 0.055,
        step(0.0031308, value));
}

float BlendMode(float divisor)
{
    // Four exact two-bit enum fields in one small float; no color quantization.
    return fmod(floor(PaintBlendModes / divisor + 0.0001), 4);
}

float3 PaintLayer(float3 background, float3 color, float weight, float mode)
{
    float3 top = background * color; // multiply
    if (mode > 0.5 && mode < 1.5) // overlay, evaluated in the recovered linear space
        top = lerp(2 * background * color, 1 - 2 * (1 - background) * (1 - color),
            step(0.5, background));
    else if (mode > 1.5) // replace
        top = color;
    return lerp(background, top, saturate(weight));
}

float3 PaintSurface(float3 background, float4 weights)
{
    // These are ordered layers, not normalized mutually-exclusive categories.
    float3 value = background * BaseStrength;
    value = PaintLayer(value, Paint1_NormalStrength.rgb, weights.r, BlendMode(1));
    value = PaintLayer(value, Paint2_RoughnessScale.rgb, weights.g, BlendMode(4));
    value = PaintLayer(value, Paint3_RoughnessBias.rgb, weights.b, BlendMode(16));
    value = PaintLayer(value, Paint4_MetallicScale.rgb, weights.a, BlendMode(64));
    return max(value, 0);
}

float3 SurfaceNormal(PS_INPUT input, float3 tangentNormal)
{
    float3 N = SafeNormalize(input.worldNormal, float3(0, 0, 1));
    N *= input.face < 0 ? -1 : 1;
    [branch] if (NormalStrength <= 0) return N;
    float3 dp1 = ddx(input.worldPosition), dp2 = ddy(input.worldPosition);
    float2 duv1 = ddx(input.uv), duv2 = ddy(input.uv);
    float3 perpendicular2 = cross(dp2, N), perpendicular1 = cross(N, dp1);
    float3 T = perpendicular2 * duv1.x + perpendicular1 * duv2.x;
    float3 B = perpendicular2 * duv1.y + perpendicular1 * duv2.y;
    float scale2 = max(dot(T, T), dot(B, B));
    // The cofactors carry signed screen area. A Y-down projection reverses
    // both axes on front faces; length normalization alone leaves relief
    // inverted. Remove that area sign, preserving mirrored UV handedness.
    // Checked against the original Combat Evolved authored tangent buffers.
    float orientation = dot(cross(dp1, dp2), N) < 0 ? -1 : 1;
    float reciprocal = orientation * rsqrt(max(scale2, 1e-16));
    float3 mapped = (T * tangentNormal.x + B * tangentNormal.y) * reciprocal
        + N * tangentNormal.z;
    return scale2 > 1e-16 ? SafeNormalize(mapped, N) : N;
}

#if !CE8_DIRECT_PASS
float3 SourceLightCube(float3 N)
{
    float3 x = N.x >= 0 ? LightPositiveX_MetallicBias.rgb : LightNegativeX_EnvironmentTintR.rgb;
    float3 y = N.y >= 0 ? LightPositiveY_EmissionStrength.rgb : LightNegativeY_EnvironmentTintB.rgb;
    float3 z = N.z >= 0 ? LightPositiveZ_EnvironmentTintG.rgb : LightNegativeZ_BaseStrength.rgb;
    return max(x * N.x * N.x + y * N.y * N.y + z * N.z * N.z, 0);
}

float Luminance(float3 color) { return dot(color, float3(0.2126, 0.7152, 0.0722)); }

#endif

float3 FresnelSchlick(float cosine, float3 F0)
{
    return F0 + (1 - F0) * pow(1 - saturate(cosine), 5);
}

#if !CE8_DIRECT_PASS
float3 ThinFilm(float cosine)
{
    // Portable spectral approximation; not the stripped original Unreal graph.
    float transmitted = sqrt(max(0, 1 - (1 - cosine * cosine) / (1.38 * 1.38)));
    float thicknessNm = 180 + clamp(IridescenceThickness, 0, 4) * 600;
    float3 phase = 4 * PI * 1.38 * thicknessNm * transmitted / float3(650, 530, 460);
    float3 spectrum = 0.5 + 0.5 * cos(phase);
    spectrum /= max(max(spectrum.r, max(spectrum.g, spectrum.b)), 1e-6);
    return lerp(Luminance(spectrum).xxx, spectrum, saturate(IridescenceSaturation))
        * max(IridescenceBrightness, 0);
}
#endif

float3 DirectGGX(float3 N, float3 V, float3 L, float roughness, float3 F0)
{
    float3 H = SafeNormalize(V + L, N);
    float NoV = max(saturate(dot(N, V)), 1e-4);
    float NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float a2 = pow(roughness, 4);
    float denominator = NoH * NoH * (a2 - 1) + 1;
    float D = a2 / max(PI * denominator * denominator, 1e-8);
    float k = (roughness + 1) * (roughness + 1) / 8;
    float visibility = 1 / max(4 * (NoV * (1 - k) + k) * (NoL * (1 - k) + k), 1e-6);
    return FresnelSchlick(saturate(dot(V, H)), F0) * D * visibility * NoL;
}

#if CE8_HUNTER_WORM || CE8_HUNTER_PLASMA
#include "ce8_hunter_material.hlsl"
#endif
#if CE8_LIVE_DETAILS
#include "ce8_live_details.hlsl"
#endif

#if CE8_DIRECT_PASS
void CE8LightTransport(float3 worldPosition, float3 N, out float3 L,
    out float attenuation, out float3 cookie)
{
    float3 fromLight = worldPosition - LightPosition_Type.xyz;
    float distance = max(length(fromLight), 0.001);
    float range = max(LightColor_Range.w, 0.001);
    L = -fromLight / distance;
    cookie = 1;
    // Types: -1 authored sun, 0 tool point, 1 projector, 2/3 authored point/spot.
    // Only light transport differs. The CE material lobes below remain shared.
    if (LightPosition_Type.w < -0.5)
    {
        L = SafeNormalize(-LightForward_Near.xyz, N);
        attenuation = 1;
    }
    else if (LightPosition_Type.w > 1.5)
    {
        clip(range - distance);
        attenuation = rcp(max(dot(LightAttenuation_Strength.xyz,
            float3(1, distance, distance*distance)), 1e-6));
        if (LightPosition_Type.w > 2.5)
        {
            float coneCosine = dot(-L, LightForward_Near.xyz);
            float inner = LightForward_Near.w;
            float outer = LightRight_TangentHorizontal.w;
            float cone = saturate((coneCosine - outer) / max(inner - outer, 1e-6));
            clip(coneCosine - outer);
            attenuation *= pow(max(cone, 1e-6), max(LightUp_TangentVertical.w, 0));
        }
    }
    else if (LightPosition_Type.w > 0.5)
    {
        float axial = dot(fromLight, LightForward_Near.xyz);
        clip(axial - LightForward_Near.w);
        clip(range - axial);
        float2 uv = float2(dot(fromLight, LightRight_TangentHorizontal.xyz),
            -dot(fromLight, LightUp_TangentVertical.xyz));
        uv /= max(2 * axial * float2(LightRight_TangentHorizontal.w, LightUp_TangentVertical.w), 0.001);
        uv += 0.5;
        clip(min(min(uv.x, uv.y), min(1-uv.x, 1-uv.y)));
        float edge = min(min(uv.x, uv.y), min(1-uv.x, 1-uv.y));
        float edgeFade = saturate(edge / max(LODValue(LightSurfaceParameters.w), 0.001));
        // Match Source's flashlight attenuation and final 40% range fade.
        attenuation = saturate(dot(LightAttenuation_Strength.xyz, float3(1, 1/distance, 1/(distance*distance))));
        attenuation *= saturate((range - distance) / max(range * 0.4, 0.001)) * edgeFade;
        if (LightSurfaceParameters.z > 0.5) cookie = tex2D(ProjectedTexture, uv).rgb;
    }
    else
    {
        float falloff = saturate(1 - distance / range);
        attenuation = falloff * falloff;
    }
}
#endif

float4 main(PS_INPUT input) : COLOR0
{
#if CE8_EARLY_LIGHT_TRANSPORT
    // Reject pixels outside the beam before evaluating the tiled material.
    float3 L, cookie;
    float attenuation;
    CE8LightTransport(input.worldPosition, SafeNormalize(input.worldNormal, float3(0,0,1)),
        L, attenuation, cookie);
#endif
#if CE8_LIVE_DETAILS
    float4 surface, base, paint;
    float3 tangentNormal;
    CE8LiveSurface(input, base, surface, paint, tangentNormal);
    float4 features = float4(1,1,0,0);
#else
#if CE8_ATLAS_SURFACE
    float3 albedoAtlas=AtlasCoordinates(input,AtlasCellLog(2048.0));
    float3 maskAtlas=AtlasCoordinates(input,AtlasCellLog(1048576.0));
#define ALBEDO_SAMPLE tex2Dlod(AlbedoTexture,float4(albedoAtlas.xy,0,albedoAtlas.z))
#define PAINT_SAMPLE tex2Dlod(PaintMaskTexture,float4(maskAtlas.xy,0,maskAtlas.z))
#else
#define ALBEDO_SAMPLE tex2D(AlbedoTexture,input.uv)
#define PAINT_SAMPLE tex2D(PaintMaskTexture,input.uv)
#endif
#if CE8_ATLAS_SURFACE || CE8_ATLAS_BACKGROUND
    float3 normalAtlas=AtlasCoordinates(input,AtlasCellLog(16384.0));
    float3 surfaceAtlas=AtlasCoordinates(input,AtlasCellLog(131072.0));
    float4 surface=tex2Dlod(SurfaceTexture,float4(surfaceAtlas.xy,0,surfaceAtlas.z));
    float3 tangentNormal=float3(0,0,1);
    [branch] if (NormalStrength > 0)
        tangentNormal=tex2Dlod(NormalTexture,float4(normalAtlas.xy,0,normalAtlas.z)).rgb*2-1;
#else
    float4 surface=tex2D(SurfaceTexture,input.uv);
    float3 tangentNormal=float3(0,0,1);
    [branch] if (NormalStrength > 0) tangentNormal=tex2D(NormalTexture,input.uv).rgb*2-1;
#endif
    float4 base = ALBEDO_SAMPLE;
    float4 paint = PAINT_SAMPLE;
    float4 features = tex2D(FeatureTexture,input.uv);
#endif
#if CE8_HUNTER_WORM || CE8_HUNTER_PLASMA
    CE8HunterSurface(input, base, surface, paint, features, tangentNormal);
#endif
    // R is opacity in this source's ORME, not ambient occlusion.
#if !CE8_HUNTER_PLASMA
    if (AlphaCutoff >= 0) clip(surface.r - AlphaCutoff);
#endif
#if CE8_HUNTER_WORM || CE8_HUNTER_PLASMA
    float3 albedo = max(base.rgb * BaseStrength, 0);
#else
    float3 albedo = PaintSurface(base.rgb, paint);
#endif
#if CE8_HUNTER_PLASMA
    float roughness = clamp(surface.g, 0.045, 1);
    float metallic = 0;
#else
    float roughness = clamp(surface.g * RoughnessScale + RoughnessBias, 0.045, 1);
    float metallic = saturate(surface.b * MetallicScale + MetallicBias);
#endif
    // At the far LOD, metallic parts use a cheap diffuse approximation so
    // removing their reflected lobe does not turn fully metallic surfaces black.
    metallic *= SpecularLOD;
    tangentNormal.xy *= NormalStrength;
    tangentNormal = SafeNormalize(tangentNormal, float3(0, 0, 1));
    float3 N = SurfaceNormal(input, tangentNormal);
    float3 V = SafeNormalize(EyePosition - input.worldPosition, N);
    float NoV = max(saturate(dot(N, V)), 1e-4);
    float3 F0 = lerp(0.04.xxx, albedo, metallic);
#if CE8_DIRECT_PASS
#if !CE8_EARLY_LIGHT_TRANSPORT
    float3 L, cookie;
    float attenuation;
    CE8LightTransport(input.worldPosition, N, L, attenuation, cookie);
#endif
    float3 H = SafeNormalize(V + L, N);
    float3 fresnel = FresnelSchlick(saturate(dot(V, H)), saturate(F0));
    float3 diffuse = albedo * (1 - metallic) * (1 - fresnel)
        * (saturate(dot(N, L)) / PI) * LightSurfaceParameters.y;
    float3 specular = 0;
    [branch] if (SpecularLOD > 0 && SpecularStrength > 0)
    {
#if CE8_HUNTER_WORM
        specular = CE8WormSpecular(N, V, L, F0) * SpecularStrength * SpecularLOD;
#else
        specular = DirectGGX(N, V, L, roughness, saturate(F0)) * SpecularStrength * SpecularLOD;
#endif
    }
    float3 radiance = max(LightColor_Range.rgb, 0) * max(attenuation, 0)
        * max(LightAttenuation_Strength.w, 0) * cookie;
    // The additive pass enables hardware sRGB writes/blending and emits linear RGB.
    return float4(max((diffuse + specular) * radiance, 0), 1);
#else
    float3 F = FresnelSchlick(NoV, saturate(F0));
    float3 diffuse = albedo * (1 - metallic) * (1 - F) * SourceLightCube(N)
        * saturate(features.g);
    float3 reflected = 0;
    [branch] if (SpecularLOD > 0 && any(EnvironmentTint > 0))
    {
#if CE8_HUNTER_WORM || CE8_HUNTER_PLASMA
    float3 film = 1;
#else
    float filmWeight = saturate(IridescenceWeight * features.r * metallic);
    float3 film = lerp(1.0.xxx, ThinFilm(NoV), filmWeight);
#endif
    float3 R = reflect(-V, N);
#if CE8_HUNTER_PLASMA
    float environmentMip = roughness * max(Paint4_MetallicScale.z,0);
#else
    float environmentMip = roughness * max(EnvironmentMaxMip,0);
#endif
    float3 environment = texCUBElod(EnvironmentTexture,
        float4(R, environmentMip)).rgb;
#if CE8_LIVE_DETAILS
    float2 integrated = CE8LiveBRDF(NoV, roughness);
#elif CE8_HUNTER_WORM || CE8_HUNTER_PLASMA
    float2 integrated = CE8HunterEnvironmentBRDF(NoV, roughness);
#else
    float2 integrated = tex2Dlod(EnvironmentBRDFTexture, float4(NoV, roughness,0,0)).rg;
#endif
    // Ordinary Source cube mips are not GGX-prefiltered radiance.
    reflected = environment * (saturate(F0) * integrated.x + integrated.y)
        * max(EnvironmentTint, 0) * saturate(features.g) * film * SpecularLOD;
#if CE8_HUNTER_PLASMA
    reflected *= CE8PlasmaGlassFresnel(surface.b,NoV);
#endif
    }
    // EmissionTexture already includes its native mask: do not multiply ORME A twice.
#if CE8_LIVE_DETAILS
    float3 emission = CE8LiveEmission(base.rgb,surface.a);
#elif CE8_ATLAS_SURFACE
    float3 emission=floor(PaintBlendModes/8388608.0)>.5 ? base.rgb*surface.a
        : tex2Dlod(EmissionTexture,float4(surfaceAtlas.xy,0,surfaceAtlas.z)).rgb;
    emission*=max(EmissionStrength,0);
#else
    float3 emission = tex2D(EmissionTexture,input.uv).rgb * max(EmissionStrength, 0);
#endif
#if CE8_HUNTER_PLASMA
    emission = CE8PlasmaEmission(input, surface, NoV);
#elif CE8_HUNTER_WORM
    emission = 0; // The shared Hunter atlas glow mask is not a worm emission mask.
#endif
    float3 result = diffuse + reflected + emission;

    if (DebugView > 0.5 && DebugView < 1.5) result = albedo;
    else if (DebugView < 2.5 && DebugView > 1.5) result = roughness.xxx;
    else if (DebugView < 3.5 && DebugView > 2.5) result = metallic.xxx;
    else if (DebugView < 4.5 && DebugView > 3.5) result = N * 0.5 + 0.5;
    else if (DebugView < 5.5 && DebugView > 4.5) result = paint.rgb;
    else if (DebugView < 6.5 && DebugView > 5.5) result = emission;
    else if (DebugView < 7.5 && DebugView > 6.5) result = paint.aaa;
    // Explicit LDR preview conversion. No guessed engine HDR/fog registers.
    return float4(LinearToSRGB(result), 1);
#endif
}
