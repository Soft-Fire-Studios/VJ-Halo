// Campaign Evolved Jackal barrier: unlit, two-sided additive energy.
// Native mesh, texture roles and controls: .build/jackal/shield.
// Cooked expression connections are stripped. This layer composition and LDR
// exposure are a Source approximation; no scene refraction or vertex wobble.
sampler2D GlowMask : register(s0);
sampler2D EnergyTexture : register(s1);
sampler2D NoiseTexture : register(s2);
sampler2D DistortionTexture : register(s3);
sampler2D PatternTexture : register(s4);
sampler2D PlasmaTexture : register(s5);
float4 ShieldColor_Brightness : register(c0);
float4 InnerColor_Opacity : register(c1);
float4 Time_Detail_Distortion_Reveal : register(c2);
float4 Eye_ColorPower : register(c3);
float4 EnergyUV : register(c11);
float4 PatternUV_Power_Gain : register(c12);
float4 DistortionUV : register(c13);
float4 NoiseUV : register(c14);
float4 HighlightUV : register(c15);
float4 PlasmaPan : register(c16);
float4 EnergyPower_Gain_Edge_Cutout : register(c17);
float4 Distortion_BaseOpacity_InnerPower_InnerGain : register(c18);

struct PS_INPUT {
    float2 uv : TEXCOORD0;
    float3 worldPosition : TEXCOORD1;
    float3 worldNormal : TEXCOORD2;
};
float2 Pan(float2 uv, float4 control) {
    return uv*control.xy + frac(Time_Detail_Distortion_Reveal.x*control.zw);
}
float4 main(PS_INPUT input) : COLOR {
    float reveal=saturate(Time_Detail_Distortion_Reveal.w);
    clip(reveal-.0001);
    float2 uv=input.uv;
    float2 dx=ddx(uv),dy=ddy(uv);
    // Authored polar UV: V=0 is the outer rim, V=1 the emitter. Red marks
    // the perimeter; blue follows the real weapon notch. Neither is coverage.
    float3 mask=tex2D(GlowMask,saturate(uv)).rgb;
    float detail=Time_Detail_Distortion_Reveal.y;
    float distortionLOD=Time_Detail_Distortion_Reveal.z;
    float energy=.035,pattern=.08,highlight=.15,plasma=.07;
    [branch] if(detail>0) {
        float2 offset=0;
        [branch] if(distortionLOD>0) {
            offset=(tex2Dgrad(DistortionTexture,Pan(uv,DistortionUV),
                dx*DistortionUV.xy,dy*DistortionUV.xy).rg*2-1)*
                Distortion_BaseOpacity_InnerPower_InnerGain.x*distortionLOD;
        }
        float e=tex2Dgrad(EnergyTexture,Pan(uv+offset,EnergyUV),
            dx*EnergyUV.xy,dy*EnergyUV.xy).r;
        float h=tex2Dgrad(PatternTexture,uv*PatternUV_Power_Gain.xy,
            dx*PatternUV_Power_Gain.xy,dy*PatternUV_Power_Gain.xy).r;
        float noise=tex2Dgrad(NoiseTexture,Pan(uv,NoiseUV),dx*NoiseUV.xy,dy*NoiseUV.xy).r;
        float glint=tex2Dgrad(NoiseTexture,Pan(uv+offset,HighlightUV),
            dx*HighlightUV.xy,dy*HighlightUV.xy).r;
        float a=tex2Dgrad(PlasmaTexture,uv+frac(Time_Detail_Distortion_Reveal.x*PlasmaPan.xy),dx,dy).r;
        float b=tex2Dgrad(PlasmaTexture,uv+frac(Time_Detail_Distortion_Reveal.x*PlasmaPan.zw),dx,dy).r;
        energy=lerp(energy,pow(saturate(e),EnergyPower_Gain_Edge_Cutout.x),detail);
        pattern=lerp(pattern,pow(saturate(h),PatternUV_Power_Gain.z)*saturate(noise*3),detail);
        highlight=lerp(highlight,pow(saturate(glint),5),detail);
        plasma=lerp(plasma,abs(a-b),detail);
    }
    float radius=saturate(1-uv.y);
    float center=pow(saturate(uv.y),Distortion_BaseOpacity_InnerPower_InnerGain.z)*
        Distortion_BaseOpacity_InnerPower_InnerGain.w;
    float3 view=normalize(Eye_ColorPower.xyz-input.worldPosition);
    // View rim is emissive Fresnel, not a light/reflection calculation.
    float rim=pow(1-saturate(abs(dot(normalize(input.worldNormal),view))),4);
    float edge=mask.r*EnergyPower_Gain_Edge_Cutout.z*(1+highlight*3)+
        mask.b*EnergyPower_Gain_Edge_Cutout.w;
    float fill=Distortion_BaseOpacity_InnerPower_InnerGain.y+
        energy*EnergyPower_Gain_Edge_Cutout.y+pattern*PatternUV_Power_Gain.w+plasma*.2;
    float3 color=lerp(InnerColor_Opacity.rgb,ShieldColor_Brightness.rgb,pow(radius,Eye_ColorPower.w));
    // Bound color/exposure before multiplying coverage so fades stay smooth.
    float3 emission=1-exp(-max(color,0)*max(ShieldColor_Brightness.w,0));
    float amount=saturate(fill+edge+rim*.25+center);
    float3 srgb=lerp(emission*12.92,1.055*pow(max(emission,0),1/2.4)-.055,step(.0031308,emission));
    float opening=smoothstep(1-reveal-.025,1-reveal+.025,uv.y);
    opening=lerp(opening,1,step(.9999,reveal));
    return float4(srgb,saturate(amount*InnerColor_Opacity.w*opening));
}
