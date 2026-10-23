// Expand existing packed VTF controls to RGB-only FP32 scene records.
sampler2D Packed : register(s0);
float4 Bytes(float pixel)
{
    float2 uv=float2((fmod(pixel,256)+.5)/256,(128+floor(pixel/256)+.5)/256);
    return floor(tex2Dlod(Packed,float4(uv,0,0))*255+.5);
}
float4 Parameters(float index)
{
    float3 high=Bytes(index*3).rgb,low=Bytes(index*3+1).rgb;
    float2 fourth=Bytes(index*3+2).rg;
    float4 bits=float4(high*256+low,fourth.x*256+fourth.y);
    float4 sign=floor(bits/32768),e=floor(fmod(bits,32768)/1024),m=fmod(bits,1024);
    return lerp(m*exp2(-24.0),(1+m/1024)*exp2(e-15),step(.5,e))*(1-2*sign);
}
float4 Mode:register(c0);
float4 main(float2 uv:TEXCOORD0):COLOR0
{
    if(Mode.x>3.5) return float4(tex2Dlod(Packed,float4(uv,0,0)).rg,0,1);
    if(Mode.x<.5) {
        float pixel=floor(uv.x*320);float4 row=Parameters(floor(pixel*.5));
        return float4(fmod(pixel,2)<.5?row.rgb:float3(row.w,0,0),1);
    }
    if(Mode.x>1.5) {
        float3 value=tex2Dlod(Packed,float4(uv,0,Mode.y)).rgb;
        if(Mode.x>2.5) value=lerp(value/12.92,pow(max((value+.055)/1.055,0),2.4),step(.04045,value));
        return float4(value,1);
    }
    float2 pixel=floor(uv*128);
    float2 at=(pixel*float2(2,1)+.5)/256;
    float3 a=tex2Dlod(Packed,float4(at,0,0)).rgb;
    float b=tex2Dlod(Packed,float4(at+float2(1.0/256,0),0,0)).r;
    return float4(float2(a.r*256+a.g,a.b*256+b)*(255.0/65535.0),0,1);
}
