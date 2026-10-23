// Primary-UV detail layers. RGB-packed controls share the BRDF sampler without
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

float2 PatternMipUV(float2 uv,float2 dimensions,float4 rectangle,float lod)
{
    float scale=exp2(lod);
    float2 extent=max(1,floor(rectangle.zw/scale));
    float2 origin=floor(rectangle.xy/scale);
    return (origin+clamp(frac(uv)*extent,.5,extent-.5))/max(1,floor(dimensions/scale));
}

float4 PatternSample(sampler2D source,float2 uv,float2 dx,float2 dy,float2 dimensions,float4 rectangle)
{
    float lod=clamp(log2(max(max(length(dx*rectangle.zw),length(dy*rectangle.zw)),1)),
        0,log2(min(rectangle.z,rectangle.w)));
    // Sample the two integer mips in sequence so both coordinate expansions
    // and samples need not remain live together under SM3's register limit.
    // NPOT borders keep the same per-mip clamp and interpolation as before.
    float4 result=0;
    [loop] for(int mip=0;mip<2;++mip)
    {
        float level=mip==0 ? floor(lod) : ceil(lod);
        float weight=mip==0 ? 1-frac(lod) : frac(lod);
        float2 at=PatternMipUV(uv,dimensions,rectangle,level);
        result+=tex2Dlod(source,float4(at,0,level))*weight;
    }
    return result;
}

float OverlayScalar(float base,float top)
{
    return base<.5 ? 2*base*top : 1-2*(1-base)*(1-top);
}

float3 ReorientedNormal(float3 base,float3 top)
{
    float3 t=base+float3(0,0,1),u=top*float3(-1,-1,1);
    return SafeNormalize(t*dot(t,u)/max(t.z,1e-5)-u,float3(0,0,1));
}

void CE8LiveSurface(PS_INPUT input,out float4 base,out float4 surface,
    out float4 paint,out float3 normal)
{
    float2 dx=ddx(input.uv),dy=ddy(input.uv);
    float4 grid=LiveParameter(0),sizes=LiveParameter(4),sizes2=LiveParameter(5);
    // Page only the base maps. Authored UVs continue to drive detail tiling,
    // derivatives and tangent orientation, including negative/repeated UVs.
    float2 baseUV=input.uv,baseBlocks=grid.xy;
    float4 page=LiveParameter(13);
    [branch] if(page.z>.5)
    {
        float2 tile=CE8WrappedTile(input.uv,grid.xy);
        float id=tile.y*grid.x+tile.x;
        float cell=dot(step(abs(LiveParameter(12)-id),.25),float4(0,1,2,3));
        float pageRow=floor((cell+.5)/page.x);
        baseUV=frac(input.uv)+float2(cell-pageRow*page.x,pageRow);
        baseBlocks=page.xy;
    }
    float3 coord=NativeCoordinates(baseUV,dx,dy,sizes.xy,baseBlocks);
    base=tex2Dlod(AlbedoTexture,float4(coord.xy,0,coord.z));
    coord=NativeCoordinates(baseUV,dx,dy,sizes.zw,baseBlocks);
    normal=float3(0,0,1);
    [branch] if (NormalStrength > 0)
        normal=SafeNormalize(tex2Dlod(NormalTexture,float4(coord.xy,0,coord.z)).rgb*2-1,float3(0,0,1));
    coord=NativeCoordinates(baseUV,dx,dy,sizes2.xy,baseBlocks);
    surface=tex2Dlod(SurfaceTexture,float4(coord.xy,0,coord.z));
    coord=NativeCoordinates(baseUV,dx,dy,sizes2.zw,baseBlocks);
    float4 mask=tex2Dlod(PaintMaskTexture,float4(coord.xy,0,coord.z));
    float4 counts=LiveParameter(2);
    // Zero count skips every layer before its parameter/pattern reads.
    counts.x = DetailLOD > 0 ? counts.x : 0;
#if CE8_SCENE
    [unroll] for(int i=0;i<8;++i)
#else
    [loop] for(int i=0;i<8;++i)
#endif
    {
#if CE8_FLOAT_PARAMETERS
        [branch] if(i<counts.x)
#else
        if(i>=counts.x)break;
#endif
        {
        float at=20+i*7;
#if CE8_FLOAT_PARAMETERS
#if CE8_SCENE
        float4 weightData=CE8MaterialData(200+i);
#else
        float4 weightData=tex2Dlod(MaterialParameterTexture,float4((i+.5)/128,132.5/256,0,0));
#endif
        float selected=dot(mask,saturate(1-abs(weightData.x-float4(0,1,2,3))));
        [branch] if(weightData.x<0)selected=dot(mask,LiveParameter(at));
        float weight=saturate(lerp(1,selected,weightData.y)*weightData.z)*(weightData.w*2-1);
#else
        float4 selector=LiveParameter(at),tiling=LiveParameter(at+1);
        float4 blend=LiveParameter(at+5),flags=LiveParameter(at+6);
        float weight=saturate(lerp(1,dot(mask,selector),blend.w)*blend.x)*tiling.w;
#endif
        // ShaderCompile's SM3 lowering increments a for-loop twice on continue.
        // Keep one loop increment even when this pixel does not use the layer.
        weight *= DetailLOD;
        [branch] if(weight>0)
        {
#if CE8_FLOAT_PARAMETERS
        float4 tiling=LiveParameter(at+1),blend=LiveParameter(at+5),flags=LiveParameter(at+6);
#endif
        float4 strengths=LiveParameter(at+2);
        float4 atlasSizes=LiveParameter(1);
        float sine,cosine;sincos(tiling.z*PI/180,sine,cosine);
        float2 u=input.uv*tiling.xy;
        float2 layerUV=float2(cosine*u.x-sine*u.y,sine*u.x+cosine*u.y)+flags.zw;
        float2 uDx=dx*tiling.xy,uDy=dy*tiling.xy;
        float2 layerDx=float2(cosine*uDx.x-sine*uDx.y,sine*uDx.x+cosine*uDx.y);
        float2 layerDy=float2(cosine*uDy.x-sine*uDy.y,sine*uDy.x+cosine*uDy.y);
        float3 detailNormal=float3(0,0,1);
        float2 detailSurface=float2(.5,0);
        if(strengths.x>=0)
        {
            float pattern=100+strengths.x*3;
            [branch] if(strengths.y!=0 && NormalStrength>0)
            {
                float4 normalRect=LiveParameter(pattern);
                detailNormal=PatternSample(DetailNormalTexture,layerUV,layerDx,layerDy,atlasSizes.xy,normalRect).rgb*2-1;
                detailNormal.xy*=strengths.y;
                // Rotate the sampled slope back into the base tangent frame.
                float2 n=detailNormal.xy;
                detailNormal.xy=float2(cosine*n.x+sine*n.y,-sine*n.x+cosine*n.y)*sign(tiling.xy);
                detailNormal=SafeNormalize(detailNormal,float3(0,0,1));
            }
        }
        // Finish normal composition before the surface sample to release its
        // temporaries; the direct pass must retain early light-reject data.
        float3 topNormal=blend.y>.5 ? ReorientedNormal(normal,detailNormal) : detailNormal;
        normal=SafeNormalize(lerp(normal,topNormal,weight),float3(0,0,1));
        [branch] if(strengths.x>=0 && (flags.x>0 || flags.y>0))
        {
            float4 surfaceRect=LiveParameter(101+strengths.x*3);
            detailSurface=PatternSample(DetailSurfaceTexture,layerUV,layerDx,layerDy,atlasSizes.zw,surfaceRect).gb;
        }
        float4 remap=LiveParameter(at+3),material=LiveParameter(at+4);
        float rough=lerp(remap.x,remap.z,detailSurface.x);
        float metal=lerp(remap.w,material.x,detailSurface.y);
        if(material.w>.5 && material.w<1.5)
        {
            rough=detailSurface.x<.5 ? lerp(remap.x,remap.y,detailSurface.x*2)
                : lerp(remap.y,remap.z,detailSurface.x*2-1);
            metal=material.z;
        }
        else if(material.w>1.5 && material.w<2.5){rough=material.y;metal=material.z;}
        if(blend.z>.5)rough=OverlayScalar(surface.g,rough);
        surface.g=lerp(surface.g,rough,saturate(weight*strengths.z*flags.x));
        surface.b=lerp(surface.b,metal,saturate(weight*strengths.w*flags.y));
        }
        }
    }
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
float3 CE8LiveEmission(float3 textureColor,float mask)
{
    float3 result=0;
    [branch] if(mask>0 && EmissionStrength>0)
    {
        float4 tint=LiveParameter(14),settings=LiveParameter(18);
        float3 color=1;
        float3 textureFade=textureColor;
        [branch] if(tint.w>.5)
        {
            color=tint.rgb;
            [branch] if(tint.w>1.5)
            {
                // CE's packed palette is in ORME A, not the color/detail mask.
                // Tenths are a documented reconstruction, exposed as BandWidth.
                float band=clamp(floor(mask/max(settings.z,.001)+.5),1,3);
                color=LiveParameter(14+band).rgb;
            }
            textureFade=lerp(1.0.xxx,textureColor,saturate(settings.y));
        }
        // Bound the authored HDR color BEFORE applying pixel coverage. Including
        // the mask (or texture) in this divisor cancels its fade and amplifies
        // tiny compression residuals into flat, fully lit blocks.
        float3 gain=max(color,0)*max(EmissionStrength,0)*max(settings.x,0);
        gain/=max(1,max(gain.r,max(gain.g,gain.b)));
        result=gain*textureFade*mask;
    }
    return result;
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
