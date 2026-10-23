// One light pass, up to sixteen selected sources. s5 is a shared FP32 sheet:
// eight texels per light in its first 64 rows; native-size beam images below.
// Constants retain all material controls. No per-material light RTs.
bool CE8IsLightBatch() { return LightSurfaceParameters.z < -0.5; }

float4 CE8LightRecord(float index, float field)
{
    float pixel=index*8+field;
    return tex2Dlod(ProjectedTexture,float4((fmod(pixel,1024)+.5)/1024,
        (floor(pixel/1024)+.5)/1024,0,0));
}

float CE8LightIndex(int index)
{
    float4 ids=index<4 ? LightPosition_Type : index<8 ? LightColor_Range
        : index<12 ? LightForward_Near : LightRight_TangentHorizontal;
    float component=fmod(index,4);
    return dot(ids,1-step(.5,abs(component-float4(0,1,2,3))));
}

float CE8LightBatchCoverage(float3 position)
{
    // Reject only outside the UNION of the selected lights. Per-light clip()
    // would incorrectly erase another source's contribution in the same pass.
    [loop] for(int i=0;i<16;++i)
    {
        if(i>=LightUp_TangentVertical.x) break;
        float index=CE8LightIndex(i);
        float4 p=CE8LightRecord(index,0),c=CE8LightRecord(index,1);
        if(p.w<-.5) return 1;
        float3 delta=position-p.xyz;
        float distance=max(length(delta),.001);
        if(p.w>.5 && p.w<1.5)
        {
            float4 f=CE8LightRecord(index,2),r=CE8LightRecord(index,3),u=CE8LightRecord(index,4);
            float axial=dot(delta,f.xyz);
            float2 uv=float2(dot(delta,r.xyz),-dot(delta,u.xyz));
            uv/=max(2*axial*float2(r.w,u.w),.001);uv+=.5;
            if(axial>=f.w && axial<=c.w && distance<c.w && all(uv>=0) && all(uv<=1)) return 1;
        }
        else if(distance<=c.w)
        {
            if(p.w<2.5) return 1;
            float outer=CE8LightRecord(index,3).w;
            if(dot(delta/distance,CE8LightRecord(index,2).xyz)>=outer) return 1;
        }
    }
    return 0;
}

float3 CE8BatchedLighting(float3 position,float3 N,float3 V,float3 albedo,
    float roughness,float metallic,float3 F0)
{
    float3 result=0;
    [loop] for(int i=0;i<16;++i)
    {
        if(i>=LightUp_TangentVertical.x) break;
        float index=CE8LightIndex(i);
        float4 p=CE8LightRecord(index,0),c=CE8LightRecord(index,1);
        float3 fromLight=position-p.xyz;
        float distance=max(length(fromLight),.001),range=max(c.w,.001);
        float3 L=-fromLight/distance,cookie=1;
        float attenuation=0;
        float4 a=CE8LightRecord(index,5);
        float4 flags=CE8LightRecord(index,7);
        if(p.w<-.5)
        {
            L=SafeNormalize(-CE8LightRecord(index,2).xyz,N);
            attenuation=1;
        }
        else if(p.w>1.5)
        {
            attenuation=step(distance,range)/max(dot(a.xyz,float3(1,distance,distance*distance)),1e-6);
            if(p.w>2.5)
            {
                float4 f=CE8LightRecord(index,2);
                float outer=CE8LightRecord(index,3).w;
                float exponent=CE8LightRecord(index,4).w;
                float cosine=dot(-L,f.xyz);
                float cone=saturate((cosine-outer)/max(f.w-outer,1e-6));
                attenuation*=step(outer,cosine)*pow(max(cone,1e-6),max(exponent,0));
            }
        }
        else if(p.w>.5)
        {
            float4 f=CE8LightRecord(index,2),r=CE8LightRecord(index,3),u=CE8LightRecord(index,4);
            float axial=dot(fromLight,f.xyz);
            float2 uv=float2(dot(fromLight,r.xyz),-dot(fromLight,u.xyz));
            uv/=max(2*axial*float2(r.w,u.w),.001);
            uv+=.5;
            float edge=min(min(uv.x,uv.y),min(1-uv.x,1-uv.y));
            attenuation=saturate(dot(a.xyz,float3(1,1/distance,1/(distance*distance))))
                *saturate((range-distance)/max(range*.4,.001))
                *saturate(edge/max(LODValue(LightSurfaceParameters.w),.001))
                *step(f.w,axial)*step(axial,range)*step(0,edge);
            [branch] if(flags.y>.5 && attenuation>0)
            {
                float4 rect=CE8LightRecord(index,6);
                float2 at=rect.xy+clamp(uv*rect.zw,.5,rect.zw-.5);
                cookie=tex2Dlod(ProjectedTexture,float4(at/1024,0,0)).rgb;
            }
        }
        else
        {
            float falloff=saturate(1-distance/range);
            attenuation=falloff*falloff;
        }
        float strength=a.w<.5 ? 1 : a.w<1.5 ? LightUp_TangentVertical.w
            : a.w<2.5 ? LightUp_TangentVertical.z : LightUp_TangentVertical.y;
        [branch] if(attenuation>0 && strength>0)
        {
            float3 H=SafeNormalize(V+L,N);
            float3 fresnel=FresnelSchlick(saturate(dot(V,H)),saturate(F0));
            float3 diffuse=albedo*(1-metallic)*(1-fresnel)*(saturate(dot(N,L))/PI)*flags.x;
            float3 specular=0;
            [branch] if(SpecularLOD>0 && SpecularStrength>0)
            {
#if CE8_HUNTER_WORM
                specular=CE8WormSpecular(N,V,L,F0)*SpecularStrength*SpecularLOD;
#else
                specular=DirectGGX(N,V,L,roughness,saturate(F0))*SpecularStrength*SpecularLOD;
#endif
            }
            result+=max((diffuse+specular)*max(c.rgb,0)*attenuation*strength*cookie,0);
        }
    }
    return result;
}
