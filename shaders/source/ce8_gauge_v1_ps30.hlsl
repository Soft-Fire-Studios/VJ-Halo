// CE native weapon UI inputs and recovered controls, rendered without lighting.
// The cooked expression links are absent. Heat fill, exposure and scanline
// composition are explicitly reconstructed; no claim of identical UE code.
sampler2D GaugeTexture : register(s0);
sampler2D MaskTexture : register(s1);
sampler2D DetailTexture : register(s2);
float4 Mode_Value_Time_Detail : register(c0);
float4 Tint_Brightness : register(c1);
float4 ColorA_Opacity : register(c2);
float4 ColorB_Clip : register(c3);
float4 ColorC_PackedScale : register(c11);
float4 ColorD_RotationSpeed : register(c12);
float4 Gains_ScanlineLow : register(c13);
float4 UVTransform : register(c14);
float4 Spent_Glow_HeatSoftness : register(c15);
struct PS_INPUT {float2 uv:TEXCOORD0;float3 worldPosition:TEXCOORD1;float3 worldNormal:TEXCOORD2;};
float3 Linear(float3 c) {return lerp(c/12.92,pow(max((c+.055)/1.055,0),2.4),step(.04045,c));}
float3 OutputColor(float3 c) {
    // Bounded exposure keeps native HDR tint ratios without white clipping.
    c=max(c,0);c/=max(1,max(c.r,max(c.g,c.b)));
    return lerp(c*12.92,1.055*pow(c,1/2.4)-.055,step(.0031308,c));
}
float4 main(PS_INPUT input):COLOR {
    float2 uv=input.uv*UVTransform.xy+UVTransform.zw;
    float2 dx=ddx(uv),dy=ddy(uv);
    // Native display sections retain integer UDIM offsets; each UI map repeats.
    uv=frac(uv);
    float mode=Mode_Value_Time_Detail.x,value=saturate(Mode_Value_Time_Detail.y);
    float detail=Mode_Value_Time_Detail.w,alpha=1;
    float3 emission=0;
    [branch] if(mode<.5) { // Plasma Rifle's additive heat glyph.
        float mask=tex2Dgrad(MaskTexture,uv,dx,dy).r;
        float3 warm=ColorC_PackedScale.rgb;
        float edge=0;
        [branch] if(detail>0) {
            warm=lerp(warm,Linear(tex2Dgrad(GaugeTexture,uv,dx,dy).rgb),detail);
            edge=tex2Dgrad(DetailTexture,uv,dx,dy).r*detail;
        }
        float fill=smoothstep(1-uv.y-Spent_Glow_HeatSoftness.z,1-uv.y+Spent_Glow_HeatSoftness.z,value)*step(.0001,value);
        float3 hot=lerp(warm,ColorB_Clip.rgb,value*value);
        // SRC_ALPHA additive blending applies glyph coverage once, through alpha.
        emission=lerp(ColorA_Opacity.rgb,hot,fill)+edge*ColorA_Opacity.rgb;
        alpha=mask;
    } else if(mode<1.5) { // Needler: native per-needle thresholds in packed R.
        float3 background=0;
        [branch] if(detail>0)
            background=Linear(tex2Dgrad(GaugeTexture,uv,dx,dy).rgb)*detail;
        float2 packedUV=(uv-.5)/ColorC_PackedScale.w+.5;
        float3 packed=tex2Dgrad(MaskTexture,packedUV,dx/ColorC_PackedScale.w,dy/ColorC_PackedScale.w).rgb;
        // Native BC7 G contains a small floor outside cells; R=0 means no cell.
        packed.gb*=sign(packed.r);
        float active=step(packed.r,value)*step(.0001,value);
        float intensity=lerp(Spent_Glow_HeatSoftness.x,1,active);
        // The broad screen stays readable at distance. Extra bloom disappears.
        float glow=0;
        [branch] if(detail>0) glow=packed.b*Spent_Glow_HeatSoftness.y*detail;
        emission=background+ColorA_Opacity.rgb*(packed.g+glow)*intensity;
    } else if(mode<2.5) { // Needle Rifle ammunition rings; native CPD Ammo Scale.
        // Camera distance must never change the phase of the authored rotation.
        float angle=Mode_Value_Time_Detail.z*ColorD_RotationSpeed.w*6.2831853;
        float sn=sin(angle),cs=cos(angle);float2 q=uv-.5;
        float2 r=float2(q.x*cs-q.y*sn,q.x*sn+q.y*cs)+.5;
        float2 rx=float2(dx.x*cs-dx.y*sn,dx.x*sn+dx.y*cs);
        float2 ry=float2(dy.x*cs-dy.y*sn,dy.x*sn+dy.y*cs);
        float ring=tex2Dgrad(GaugeTexture,r,rx,ry).r;
        float spent=1-value;
        float3 color=lerp(ColorA_Opacity.rgb,ColorC_PackedScale.rgb,saturate(spent*3));
        color=lerp(color,ColorD_RotationSpeed.rgb,saturate(spent*3-1));
        color=lerp(color,ColorB_Clip.rgb,saturate(spent*3-2));
        emission=color*ring;alpha=ring;
    } else if(mode<3.5) { // Authored static colored display, no fabricated digits.
        emission=Linear(tex2Dgrad(GaugeTexture,uv,dx,dy).rgb);
    } else if(mode<4.5) { // Fuel Rod native packed background/crosshair/glow.
        float3 mask=tex2Dgrad(GaugeTexture,uv,dx,dy).rgb;
        emission=ColorA_Opacity.rgb*(1-mask.r)*Gains_ScanlineLow.x+
            ColorB_Clip.rgb*mask.b*Gains_ScanlineLow.y+
            ColorC_PackedScale.rgb*(1-mask.g)*Gains_ScanlineLow.z;
        [branch] if(detail>0) {
            float scan=lerp(Gains_ScanlineLow.w,1,.5+.5*sin(uv.y*804.2477-Mode_Value_Time_Detail.z*5));
            emission*=lerp(1,scan,detail);
        }
    } else if(mode<5.5) { // Plasma Rifle layered static UI, channels retain native tint roles.
        float3 mask=tex2Dgrad(GaugeTexture,uv,dx,dy).rgb;
        emission=mask.r*ColorA_Opacity.rgb*Gains_ScanlineLow.x+
            mask.g*ColorB_Clip.rgb*Gains_ScanlineLow.y+
            mask.b*ColorC_PackedScale.rgb*Gains_ScanlineLow.z;
    } else { // Native constant emissive geometry: no texture or lighting reads.
        emission=ColorA_Opacity.rgb;
    }
    clip(alpha-ColorB_Clip.w);
    emission*=max(Tint_Brightness.rgb,0)*max(Tint_Brightness.w,0);
    return float4(OutputColor(emission),saturate(alpha*ColorA_Opacity.w));
}
