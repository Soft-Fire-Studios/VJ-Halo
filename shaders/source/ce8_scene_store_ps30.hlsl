// Keep numeric payload out of render alpha: the carrier rejects alpha<=0.
float4 R0:register(c0);float4 R1:register(c1);float4 R2:register(c2);float4 R3:register(c3);
float4 main(float2 uv:TEXCOORD0):COLOR0 {
 float pixel=floor(uv.x*8),i=floor(pixel*.5);
 float4 row=i<1?R0:i<2?R1:i<3?R2:R3;
 return float4(fmod(pixel,2)<.5?row.rgb:float3(row.w,0,0),1);
}
