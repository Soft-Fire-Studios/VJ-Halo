// Raw framebuffer transport. The source is already display-encoded; do not
// apply lighting, tonemapping, gamma or scene brightness extraction here.
sampler2D Source : register(s0);
float4 Settings : register(c0); // x: copy/composite gain; zero clears stencil exterior.
float4 main(float2 uv : TEXCOORD0) : COLOR0
{
    float4 color=tex2D(Source,uv);
    return float4(color.rgb*Settings.x,color.a);
}
