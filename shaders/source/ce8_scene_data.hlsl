// One shared 1024x1024 FP32 texture. Numeric records are point sampled.
float4 CE8ScenePixel(float pixel)
{ return tex2Dlod(CE8SceneTexture,float4((fmod(pixel,1024)+.5)/1024,(floor(pixel/1024)+.5)/1024,0,0)); }
float4 CE8Numeric(float2 uv) {
    float4 result=tex2Dlod(CE8SceneTexture,float4(uv,0,0));
    result.w=tex2Dlod(CE8SceneTexture,float4(uv+float2(1.0/1024,0),0,0)).r;
    return result;
}
float4 CE8ModelData(float field) { return CE8Numeric(SceneIndices.xy+float2(field*2/1024,0)); }
float4 CE8MaterialData(float field) { return CE8Numeric(SceneIndices.zw+float2(field*2/1024,0)); }
float4 CE8LightData(float2 origin,float field) { return CE8Numeric(origin+float2(field*2/1024,0)); }
float2 CE8SceneBRDF(float NoV,float roughness)
{
    float2 at=float2(0,224)+clamp(float2(NoV,roughness)*128,.5,127.5);
    return tex2Dlod(CE8SceneTexture,float4(at/1024,0,0)).rg;
}
#if CE8_HUNTER_PLASMA
float CE8CloudMip(float2 uv,float mip)
{
    float size=exp2(8-mip),origin=768-2*size;
    float2 p=frac(uv)*size-.5,a=floor(p),f=frac(p);
    float2 lo=fmod(a+size,size),hi=fmod(a+1+size,size);
    float base=229376+origin;
    float x=lerp(CE8ScenePixel(base+lo.y*1024+lo.x).r,CE8ScenePixel(base+lo.y*1024+hi.x).r,f.x);
    float y=lerp(CE8ScenePixel(base+hi.y*1024+lo.x).r,CE8ScenePixel(base+hi.y*1024+hi.x).r,f.x);
    return lerp(x,y,f.y);
}
float CE8CloudNoise(float2 uv)
{
    float lod=clamp(log2(max(max(length(ddx(uv)*256),length(ddy(uv)*256)),1)),0,8);
    return lerp(CE8CloudMip(uv,floor(lod)),CE8CloudMip(uv,ceil(lod)),frac(lod));
}
#endif
