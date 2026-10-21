// Combat Evolved Hunter material reconstruction. Original asset provenance and
// the limits of recovered graph wiring are in research/ce8_hunter/*/EVIDENCE.md.
// No native flesh/debug pass is involved. No height is inferred from normal Z
// or from the worm packed B channel (which correlates with roughness).

float2 CE8HunterEnvironmentBRDF(float NoV, float roughness)
{
    // Analytic split-sum approximation frees s7 for an original material input.
    float4 r = roughness * float4(-1,-.0275,-.572,.022) + float4(1,.0425,1.04,-.04);
    float a = min(r.x*r.x, exp2(-9.28*NoV))*r.x+r.y;
    return max(float2(-1.04,1.04)*a+r.zw, 0);
}

float LinearWave(float phase) { return 1-abs(frac(phase)*2-1); }

#if CE8_HUNTER_WORM
// c0 RGB fixed flesh tint; c1 XYZ detail tile U/V and crawl phase;
// c2 XY slime/normal-detail strength; c3 XYZ two specular powers and blend.
void CE8HunterSurface(PS_INPUT input, inout float4 base, inout float4 surface,
    inout float4 paint, inout float4 features, inout float3 tangentNormal)
{
    float crawlPhase=Paint2_RoughnessScale.z;
    float2 crawlOffset=lerp(float2(crawlPhase,0),float2(0,crawlPhase),saturate(Paint3_RoughnessBias.z));
    float2 detailUV = input.uv*Paint2_RoughnessScale.xy + crawlOffset;
    float3 detailColor = tex2D(AlbedoTexture, detailUV).rgb;
    float2 detailDx=ddx(detailUV),detailDy=ddy(detailUV);
    [branch] if (DetailLOD > 0)
    {
    float4 normalRoughness = tex2Dgrad(FeatureTexture, detailUV,detailDx,detailDy); // Original Worm Normal/Roughness
    float2 xy = normalRoughness.rg*2-1;
    float3 detailNormal = float3(xy, sqrt(saturate(1-dot(xy,xy))));
    detailNormal.xy *= Paint3_RoughnessBias.y * DetailLOD;
    if (NormalStrength <= 0) detailNormal = float3(0,0,1);
    tangentNormal = SafeNormalize(float3(tangentNormal.xy+detailNormal.xy,
        max(tangentNormal.z*detailNormal.z,.001)),float3(0,0,1));
    surface.g = lerp(surface.g,normalRoughness.b,saturate(Paint3_RoughnessBias.y)*DetailLOD);
    }
    base.rgb = detailColor*Paint1_NormalStrength.rgb;
    surface.b = 0; // Flesh is dielectric; the Hunter atlas B is not a flesh metal override.
    paint = float4(1,0,0,0);
    features = float4(0,1,0,1);
}
float3 CE8WormSpecular(float3 N, float3 V, float3 L, float3 F0)
{
    float2 powers = max(Paint4_MetallicScale.xy,1);
    float2 roughness = clamp(pow(2/(powers+2),.25),.045,1);
    return lerp(DirectGGX(N,V,L,roughness.x,saturate(F0)),
        DirectGGX(N,V,L,roughness.y,saturate(F0)),saturate(Paint4_MetallicScale.z))
        * max(Paint3_RoughnessBias.x,0);
}
#elif CE8_HUNTER_PLASMA
// c0 plasma tint, c1 glass tint/glow intensity, c2 flow phase/wave phase/tile/
// emissive multiplier, c3 influence/wave amount/distortion/base contrast.
// Base-only c17 contains the three noise height ratios and glow power.
void CE8HunterSurface(PS_INPUT input, inout float4 base, inout float4 surface,
    inout float4 paint, inout float4 features, inout float3 tangentNormal)
{
    // Minor's explicit Use Metalness for Glass Mask selects ORME B. Preserve
    // it for glass selection while the shared lighting treats glass as dielectric.
    base.rgb *= lerp(1.0.xxx,Paint2_RoughnessScale.rgb,saturate(surface.b));
    paint = 0;
    features = float4(0,1,0,1);
}
#if !CE8_DIRECT_PASS
// Original Minor profile. These recovered constants are material-specific;
// the missing expression ordering is reconstructed, not recovered GPU code.
static const float GlassFresnelExponent = .16601499915122986;
static const float GlassFresnelMultiplier = 1.0074779987335205;
static const float InnerGlowFresnelExponent = .009999999776482582;
static const float InnerGlowFresnelMultiplier = 50.0;
float CE8PlasmaGlassFresnel(float mask,float NoV)
{
    return lerp(1,GlassFresnelMultiplier*pow(saturate(1-NoV),GlassFresnelExponent),saturate(mask));
}
float3 CE8PlasmaEmission(PS_INPUT input, float4 surface, float NoV)
{
    float2 uv = input.uv*Paint3_RoughnessBias.z;
    float phase=Paint3_RoughnessBias.x;
    float wave=LinearWave(Paint3_RoughnessBias.y);
    float amount=Paint4_MetallicScale.y;
    // Reconstructed flow wiring: independent grayscale sources are sampled as
    // scalar fields, not misread as stored RG velocity vectors.
    float seed=tex2D(PaintMaskTexture,input.uv).r; // Original LowResBlurredNoise, UV0
    float2 drift=float2(phase,amount*(wave-.5));
    float low=tex2D(EmissionTexture,uv+drift).r; // Native PlasmaNoise: T_Noise5
    float n1=tex2D(FeatureTexture,uv-drift.yx+seed*.05).r; // PlasmaNoise2: Billow
    float n2=tex2D(EnvironmentBRDFTexture,uv+drift.yx+low*.05).r; // PlasmaNoise3: Clouds
    float3 heights=SurfaceParameters.xyz;
    float pattern=saturate((low+heights.x)+(n1+heights.y)+(n2+heights.z));
    pattern=pow(max(pattern,.0001),max(IridescenceParameters.w,.01));
    float baseMask=pow(saturate(surface.a),max(Paint4_MetallicScale.w,.01));
    float flow=saturate(Paint4_MetallicScale.x);
    float inner=pow(saturate(1-NoV),InnerGlowFresnelExponent)*InnerGlowFresnelMultiplier;
    float3 radiance=baseMask*(IridescenceParameters.rgb*max(Paint3_RoughnessBias.w,0)
        + Paint1_NormalStrength.rgb*pattern*flow*max(Paint2_RoughnessScale.w,0)
          *(1+saturate(surface.b)*inner));
    // This carrier's output is LDR. Compress only emissive radiance, preserving
    // its hue; the original HDR/eye-adaptation graph is not available here.
    return 1-exp(-max(radiance,0)*max(EmissionStrength,0));
}
#endif
#endif
