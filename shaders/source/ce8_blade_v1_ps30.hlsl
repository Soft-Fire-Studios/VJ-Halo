// Default Campaign Evolved EnergySword. Eight native inputs; no lighting pass.
// Recovered parameters/texture roles: .build/weapons/energy_sword/blade.
// Cooked expression links are absent: layer composition and LDR exposure below
// are the Source approximation, not a claim of identical Unreal shader code.
sampler2D BladeMask : register(s0);
sampler2D FlowMap : register(s1);
sampler2D EnergyTexture : register(s2);
sampler2D Energy2Texture : register(s3);
sampler2D DistortionTexture : register(s4);
sampler2D NoiseTexture : register(s5);
sampler2D TopNoiseTexture : register(s6);
sampler2D PlasmaTexture : register(s7);
float4 EnergyColor_Brightness : register(c0);
float4 DarkColor_Opacity : register(c1);
float4 Time_Detail_Flow_Reveal : register(c2);
float4 Energy_Gain2_Power2_Gain3 : register(c3);
float4 EnergyUV : register(c11); // scale U/V, pan U/V, cycles per second
float4 Energy2UV : register(c12);
float4 DistortionUV : register(c13);
float4 NoiseUV : register(c14);
float4 TopNoiseUV : register(c15);
float4 PlasmaUV : register(c16);
float4 OpacityMin_Power_Noise_Edge : register(c17);
float4 Distortion_Flow_Power3_TopPower : register(c18);

struct PS_INPUT {
    float2 uv : TEXCOORD0;
    float3 worldPosition : TEXCOORD1;
    float3 worldNormal : TEXCOORD2;
};
float2 Pan(float2 uv, float4 control) {
    return uv * control.xy + frac(Time_Detail_Flow_Reveal.x * control.zw);
}
float4 main(PS_INPUT input) : COLOR {
    float2 dx=ddx(input.uv),dy=ddy(input.uv);
    float3 mask = tex2D(BladeMask, saturate(input.uv)).rgb;
    // Blue is the silhouette, red the hot edge, green the inner energy shape.
    float coverage = saturate(mask.b);
    float reveal = Time_Detail_Flow_Reveal.w;
    float revealMask = smoothstep(1-reveal-.025,1-reveal+.025,input.uv.y) * step(.0001,reveal);
    coverage *= lerp(revealMask,1,step(.9999,reveal));
    clip(coverage-.002);
    float detail = Time_Detail_Flow_Reveal.y;
    float flowLOD = Time_Detail_Flow_Reveal.z;
    float wave = .3, wave2 = .04, plasma = .02, opacityNoise = .55;
    float2 uv = input.uv;
    // Uniform branches eliminate actual texture fetches beyond the cutoffs.
    [branch] if (detail > 0) {
        float2 offset = 0;
        [branch] if (flowLOD > 0) {
            float2 flow = tex2Dgrad(FlowMap,saturate(uv),dx,dy).rg * 2-1;
            float2 distort = tex2Dgrad(DistortionTexture,Pan(uv,DistortionUV),dx*DistortionUV.xy,dy*DistortionUV.xy).rg * 2-1;
            offset = (flow*Distortion_Flow_Power3_TopPower.y +
                distort*Distortion_Flow_Power3_TopPower.x) * flowLOD;
        }
        float energy = tex2Dgrad(EnergyTexture,Pan(uv+offset,EnergyUV),dx*EnergyUV.xy,dy*EnergyUV.xy).r;
        // Native second layer rotates -0.25 turns about the UV center.
        float2 rotated = float2(uv.y,1-uv.x);
        float energy2 = tex2Dgrad(Energy2Texture,Pan(rotated+offset,Energy2UV),float2(dx.y,-dx.x)*Energy2UV.xy,float2(dy.y,-dy.x)*Energy2UV.xy).r;
        float energy3 = tex2Dgrad(PlasmaTexture,Pan(uv+offset,PlasmaUV),dx*PlasmaUV.xy,dy*PlasmaUV.xy).r;
        float noise = tex2Dgrad(NoiseTexture,Pan(uv,NoiseUV),dx*NoiseUV.xy,dy*NoiseUV.xy).r;
        float top = tex2Dgrad(TopNoiseTexture,Pan(uv,TopNoiseUV),dx*TopNoiseUV.xy,dy*TopNoiseUV.xy).r;
        wave = lerp(wave,energy,detail);
        wave2 = lerp(wave2,pow(saturate(energy2),Energy_Gain2_Power2_Gain3.z)*
            Energy_Gain2_Power2_Gain3.y,detail);
        plasma = lerp(plasma,pow(saturate(energy3),Distortion_Flow_Power3_TopPower.z)*
            Energy_Gain2_Power2_Gain3.w,detail);
        opacityNoise = lerp(opacityNoise,saturate(noise*OpacityMin_Power_Noise_Edge.z)*
            (1-.35*pow(saturate(top),Distortion_Flow_Power3_TopPower.w)),detail);
    }
    float fill = wave*Energy_Gain2_Power2_Gain3.x + wave2 + plasma;
    float edge = mask.r*OpacityMin_Power_Noise_Edge.w;
    float3 emission = DarkColor_Opacity.rgb + EnergyColor_Brightness.rgb *
        (fill*(.35+mask.g) + edge);
    // Bounded LDR exposure replaces Unreal's HDR eye adaptation, never map light.
    emission = 1-exp(-max(emission,0)*EnergyColor_Brightness.w);
    float3 srgb = lerp(emission*12.92,1.055*pow(max(emission,0),1/2.4)-.055,
        step(.0031308,emission));
    float alpha = coverage * max(OpacityMin_Power_Noise_Edge.x,
        pow(saturate(opacityNoise+mask.r),OpacityMin_Power_Noise_Edge.y));
    return float4(srgb,saturate(alpha*DarkColor_Opacity.w));
}
