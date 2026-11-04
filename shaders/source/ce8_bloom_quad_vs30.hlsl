// Bloom drawCopy supplies explicit clip-space vertices; never use DrawScreenQuad here.
struct VS_INPUT { float3 position : POSITION; float2 uv : TEXCOORD0; };
struct VS_OUTPUT { float4 position : POSITION; float2 uv : TEXCOORD0; };
VS_OUTPUT main(VS_INPUT input)
{
    VS_OUTPUT output;
    output.position=float4(input.position,1);
    output.uv=input.uv;
    return output;
}
