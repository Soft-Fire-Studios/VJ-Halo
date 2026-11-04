// Baked normal/surface maps. RGB-packed controls share the BRDF sampler without
// adding texture bindings or using the verified lighting registers.
float4 ParameterBytes(float pixel)
{
    float2 uv=float2((fmod(pixel,256)+.5)/256,(128+floor(pixel/256)+.5)/256);
    return floor(tex2Dlod(MaterialParameterTexture,float4(uv,0,0))*255+.5);
}
float4 LiveParameter(float index)
{
#if CE8_SCENE
    return CE8MaterialData(index);
#elif CE8_FLOAT_PARAMETERS
    float pixel=index*2;
    float2 uv=float2((fmod(pixel,128)+.5)/128,(128+floor(pixel/128)+.5)/256);
    float3 rgb=tex2Dlod(MaterialParameterTexture,float4(uv,0,0)).rgb;
    float a=tex2Dlod(MaterialParameterTexture,float4(uv+float2(1.0/128,0),0,0)).r;
    return float4(rgb,a);
#else
    float3 high=ParameterBytes(index*3).rgb,low=ParameterBytes(index*3+1).rgb;
    float2 fourth=ParameterBytes(index*3+2).rg;
    float4 bits=float4(high*256+low,fourth.x*256+fourth.y);
    float4 negative=floor(bits/32768),exponent=floor(fmod(bits,32768)/1024),mantissa=fmod(bits,1024);
    float4 value=lerp(mantissa*exp2(-24.0),(1+mantissa/1024)*exp2(exponent-15),step(.5,exponent));
    return value*(1-2*negative);
#endif
}

// Tile IDs are integers. Bias the quotient into the middle of its interval:
// SM3 rcp(3) may round down, so nested fmod can wrap 0 to almost 3.
// Preserve the authored fractional UV; only the signed integer tile is wrapped.
float2 CE8WrappedTile(float2 uv,float2 blocks)
{
    float2 tile=floor(uv);
    return tile-floor((tile+.5)/blocks)*blocks;
}

float3 LiveCoordinates(float2 uv, float2 dx, float2 dy, float2 dimensions, float4 rectangle)
{
    float lod=clamp(log2(max(max(length(dx*rectangle.zw),length(dy*rectangle.zw)),1)),
        0,log2(min(rectangle.z,rectangle.w)));
    float2 margin=.5*exp2(ceil(lod));
    float2 pixel=rectangle.xy+clamp(frac(uv)*rectangle.zw,margin,rectangle.zw-margin);
    return float3(pixel/dimensions,lod);
}

float3 NativeCoordinates(float2 uv,float2 dx,float2 dy,float2 dimensions,float2 blocks)
{
    // Native UDIM cells have independent mip chains. Select the cell first and
    // clamp within its own footprint instead of blending into an adjacent tile.
    float2 cell=dimensions/blocks;
    float2 tile=CE8WrappedTile(uv,blocks);
    return LiveCoordinates(uv,dx,dy,dimensions,float4(tile*cell,cell));
}

void CE8LiveBaseUV(float2 uv,float2 blocks,out float2 baseUV,out float2 baseBlocks)
{
    baseUV=uv; baseBlocks=blocks;
    float4 page=LiveParameter(13);
    [branch] if(page.z>.5)
    {
        float2 tile=CE8WrappedTile(uv,blocks);
        float id=tile.y*blocks.x+tile.x;
        float cell=dot(step(abs(LiveParameter(12)-id),.25),float4(0,1,2,3));
        float pageRow=floor((cell+.5)/page.x);
        baseUV=frac(uv)+float2(cell-pageRow*page.x,pageRow);
        baseBlocks=page.xy;
    }
}

// SurfaceEncoding: 0 = legacy ORME, 1 = RGB emission/roughness/metallic.
// Grid Z=2 marks the RGB layout. Legacy 0..1 values retain their old layout.
// Reconstruct opacity only for opaque materials; cutout maps keep all channels.
float4 CE8SurfaceChannels(float4 value,float encoding)
{
    return encoding>1.5 ? float4(1,value.g,value.b,value.r) : value;
}

void CE8LiveEmissionInputs(PS_INPUT input,out float3 textureColor,out float4 surface)
{
    float2 dx=ddx(input.uv),dy=ddy(input.uv),uv,blocks;
    float4 grid=LiveParameter(0);
    CE8LiveBaseUV(input.uv,grid.xy,uv,blocks);
    float3 at=NativeCoordinates(uv,dx,dy,LiveParameter(5).xy,blocks);
    surface=CE8SurfaceChannels(tex2Dlod(SurfaceTexture,float4(at.xy,0,at.z)),grid.z);
    if(AlphaCutoff>=0) clip(surface.r-AlphaCutoff);
    textureColor=1;
    // Single/tri-color masks usually need no diffuse texture sample at all.
    [branch] if(LiveParameter(14).w<.5 || LiveParameter(18).y>0)
    {
        at=NativeCoordinates(uv,dx,dy,LiveParameter(4).xy,blocks);
        textureColor=tex2Dlod(AlbedoTexture,float4(at.xy,0,at.z)).rgb;
    }
}

void CE8LiveSurface(PS_INPUT input,out float4 base,out float4 surface,
    out float4 paint,out float3 normal)
{
    float2 dx=ddx(input.uv),dy=ddy(input.uv);
    float4 grid=LiveParameter(0),sizes=LiveParameter(4),sizes2=LiveParameter(5);
    // Static details are already baked into these independently mipmapped cells.
    float2 baseUV,baseBlocks;
    CE8LiveBaseUV(input.uv,grid.xy,baseUV,baseBlocks);
    float3 coord=NativeCoordinates(baseUV,dx,dy,sizes.xy,baseBlocks);
    base=tex2Dlod(AlbedoTexture,float4(coord.xy,0,coord.z));
    coord=NativeCoordinates(baseUV,dx,dy,sizes.zw,baseBlocks);
    normal=float3(0,0,1);
    [branch] if (NormalStrength > 0)
    {
        normal=tex2Dlod(NormalTexture,float4(coord.xy,0,coord.z)).rgb*2-1;
        // NormalEncoding: 0 = RGB888, 1 = ATI2N XY. Both retain normal LOD.
        [branch] if (grid.w > 1.5)
            normal.z=sqrt(saturate(1-dot(normal.xy,normal.xy)));
        normal=SafeNormalize(normal,float3(0,0,1));
    }
    coord=NativeCoordinates(baseUV,dx,dy,sizes2.xy,baseBlocks);
    surface=CE8SurfaceChannels(tex2Dlod(SurfaceTexture,float4(coord.xy,0,coord.z)),grid.z);
    coord=NativeCoordinates(baseUV,dx,dy,sizes2.zw,baseBlocks);
    float4 mask=tex2Dlod(PaintMaskTexture,float4(coord.xy,0,coord.z));
    float4 counts=LiveParameter(2);
#if CE8_FLOAT_PARAMETERS
    paint=0;
    [branch] if(counts.y>0)
    {
        float4 opacities=LiveParameter(6);
        [branch] if(counts.z>=0)
        {
            float4 codes=floor(counts.z/float4(1,4,16,64));codes=fmod(codes,4);
            float4 routes=float4(dot(mask,saturate(1-abs(codes.x-float4(0,1,2,3)))),
                dot(mask,saturate(1-abs(codes.y-float4(0,1,2,3)))),
                dot(mask,saturate(1-abs(codes.z-float4(0,1,2,3)))),
                dot(mask,saturate(1-abs(codes.w-float4(0,1,2,3)))));
            float4 masked=fmod(floor(counts.w/float4(1,2,4,8)),2);
            paint=lerp(1.0.xxxx,routes,masked)*opacities;
        }
        else
        {
            paint=float4(dot(mask,LiveParameter(8)),dot(mask,LiveParameter(9)),
                dot(mask,LiveParameter(10)),dot(mask,LiveParameter(11)));
            paint=lerp(1.0.xxxx,paint,LiveParameter(7))*opacities;
        }
    }
#else
    float4 opacities=LiveParameter(6),masked=LiveParameter(7);
    paint=float4(dot(mask,LiveParameter(8)),dot(mask,LiveParameter(9)),
        dot(mask,LiveParameter(10)),dot(mask,LiveParameter(11)));
    paint=lerp(1.0.xxxx,paint,masked)*opacities;
#endif
    // Authored opacity and emission remain exclusively in the native surface.
}

#if !CE8_DIRECT_PASS
float3 CE8EmissionGain(float3 color)
{
    // Preserve authored HDR values. Exposure and coverage are applied later;
    // neither the tint nor its intensity is normalized to unit brightness.
    return color*EmissionStrength;
}

float3 CE8LiveEmission(float3 textureColor,float mask)
{
    float3 result=0;
    [branch] if(mask>0 && EmissionStrength>0)
    {
        float4 first=LiveParameter(15);
        // Native CVW subtracts its authored threshold after filtering ORME alpha.
        mask=saturate(mask-first.w);
        float4 tint=LiveParameter(14),settings=LiveParameter(18);
        float3 gain=CE8EmissionGain(1.0.xxx);
        float3 textureFade=textureColor;
        [branch] if(tint.w>.5)
        {
            gain=CE8EmissionGain(tint.rgb);
            [branch] if(tint.w>1.5)
            {
                float4 middle=LiveParameter(16),last=LiveParameter(17);
                // Recovered from CER DXIL plus compiled preshader bindings.
                // Only mask weights are bounded; HDR tint RGB stays intact.
                float t=saturate(pow(mask,middle.w)*(1+2*last.w)-last.w);
                gain=lerp(first.rgb,middle.rgb,saturate(2*t));
                gain=CE8EmissionGain(lerp(gain,last.rgb,saturate(2*t-1)));
            }
            textureFade=lerp(1.0.xxx,textureColor,saturate(settings.y));
        }
        // Preserve authored HDR intensity and the independent coverage fade.
        result=gain*textureFade*mask*max(settings.x,0);
    }
    return result;
}

float3 CE8CompositeEmission(float3 lighting,float3 emission)
{
    // HDR -> LDR presentation AFTER authored palette, coverage and intensity.
    // Reinhard's x/(1+x) shoulder uses one RGB scale to retain emission hue.
    // Composite in linear light: zero emission leaves all lighting unchanged;
    // a bright emitter smoothly fills the display range without channel clips.
    // Algebraically lerp(lighting, emission/peak, peak/(1+peak)), safe at zero.
    float peak=max(max(emission.r,emission.g),max(emission.b,0));
    return (lighting+emission)/(1+peak);
}

float2 LiveBRDFTexel(float2 pixel)
{
    float2 uv=(pixel*float2(2,1)+.5)/256;
    float3 a=tex2Dlod(MaterialParameterTexture,float4(uv,0,0)).rgb;
    float b=tex2Dlod(MaterialParameterTexture,float4(uv+float2(1.0/256,0),0,0)).r;
    return float2(a.r*256+a.g,a.b*256+b)*(255.0/65535.0);
}
float2 CE8LiveBRDF(float NoV,float roughness)
{
#if CE8_SCENE
    return CE8SceneBRDF(NoV,roughness);
#elif CE8_FLOAT_PARAMETERS
    return tex2Dlod(MaterialParameterTexture,float4(clamp(float2(NoV,roughness)*128,.5,127.5)/float2(128,256),0,0)).rg;
#else
    // Parameter rows are point sampled. Manually bilinear-filter only the LUT.
    float2 p=saturate(float2(NoV,roughness))*128-.5;
    float2 a=floor(p),f=frac(p);
    float2 lo=clamp(a,0,127),hi=clamp(a+1,0,127);
    float2 x=lerp(LiveBRDFTexel(lo),LiveBRDFTexel(float2(hi.x,lo.y)),f.x);
    float2 y=lerp(LiveBRDFTexel(float2(lo.x,hi.y)),LiveBRDFTexel(hi),f.x);
    return lerp(x,y,f.y);
#endif
}
#endif
