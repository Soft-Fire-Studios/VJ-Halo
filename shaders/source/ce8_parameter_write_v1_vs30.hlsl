#include "common_vs_fxc.h"
struct VS_INPUT {float4 position:POSITION;float2 uv:TEXCOORD0;};
struct VS_OUTPUT {float4 position:POSITION;float2 uv:TEXCOORD0;};
VS_OUTPUT main(VS_INPUT input)
{
    VS_OUTPUT output;
    output.position=mul(input.position,cViewProj);
    output.uv=input.uv;
    return output;
}
