// Authored BSP sun/point/spot specular, summed before the single sRGB conversion.
float3 CE8SceneLighting(float3 position,float3 N,float3 V,float3 albedo,float metallic,float roughness,float3 F0)
{
    float3 result=0;

    float count=CE8ModelData(10).x;
    [loop] for(int i=0;i<16;++i)
    {
        if(i>=count) break;
        float4 ids=CE8ModelData(6+floor(i/4.0));
        float index=dot(ids,1-step(.5,abs(fmod(i,4)-float4(0,1,2,3))));
        float2 origin=(float2(fmod(index,64)*16,floor(index/64))+.5)/1024;
        float4 p=CE8LightData(origin,0),c=CE8LightData(origin,1),f=CE8LightData(origin,2);
        float3 delta=p.xyz-position;
        float distance=max(length(delta),.001),Ldistance=distance;
        float3 L=delta/Ldistance;
        float attenuation=0;
        float3 cookie=1;float diffuseGain=0;
        [branch] if(p.w<-.5) { L=SafeNormalize(-f.xyz,N);attenuation=1; }
        else [branch] if(p.w<1.5)
        {
            float axial=dot(-delta,f.xyz);
            float2 uv=0;
            [loop] for(int axis=0;axis<2;++axis) {
                float4 basis=CE8LightData(origin,3+axis);
                float value=dot(-delta,basis.xyz)/max(2*axial*basis.w,.001);
                if(axis==0) uv.x=value+.5;else uv.y=.5-value;
            }
            float4 a=CE8LightData(origin,5);
            float edge=min(min(uv.x,uv.y),min(1-uv.x,1-uv.y));
            attenuation=saturate(dot(a.xyz,float3(1,1/distance,1/(distance*distance))))
                *saturate((c.w-distance)/max(c.w*.4,.001))*saturate(edge/.02)
                *step(f.w,axial)*step(axial,c.w)*max(SceneProjection.x,0);
            diffuseGain=a.w;
            [branch] if(attenuation>0)
            {
                float4 rect=CE8LightData(origin,6);
                if(rect.z>0)
                {
                    float2 at=rect.xy+clamp(uv*rect.zw,.5,rect.zw-.5);
                    cookie=tex2Dlod(CE8SceneTexture,float4(at/1024,0,0)).rgb;
                }
            }
        }
        else [branch] if(distance<=c.w)
        {
            float4 a=CE8LightData(origin,3);
            attenuation=rcp(max(dot(a.xyz,float3(1,distance,distance*distance)),1e-6));
            [branch] if(p.w>2.5)
            {
                float cosine=dot(-L,f.xyz),exponent=CE8LightData(origin,4).x;
                float cone=saturate((cosine-a.w)/max(f.w-a.w,1e-6));
                attenuation*=step(a.w,cosine)*pow(max(cone,1e-6),max(exponent,0));
            }
        }
        [branch] if(attenuation>0)
        {
            float3 specular=0;
            [branch] if(SpecularLOD>0 && SceneMaterial.z>0) {
#if CE8_HUNTER_WORM
            specular=CE8WormSpecular(N,V,L,F0);
#else
            specular=DirectGGX(N,V,L,roughness,saturate(F0));
#endif
            }
            float3 fresnel=FresnelSchlick(saturate(dot(V,SafeNormalize(V+L,N))),saturate(F0));
            float3 diffuse=albedo*(1-metallic)*(1-fresnel)*(saturate(dot(N,L))/PI)*diffuseGain;
            result+=max((diffuse+specular*SceneMaterial.z*SpecularLOD)*c.rgb*attenuation*cookie,0);
        }
    }
    return result;
}
