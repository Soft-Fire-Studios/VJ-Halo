// Shared StudioModel vertex program for Campaign Evolved's 8tex materials.
// Draw-time material overrides preserve the original model's GPU-skinned stream.
// Tangents are reconstructed from derivatives in the PS: the carrier does not
// provide a dedicated, configurable tangent vertex-format contract.
// Do not set $softwareskin 1. This program is for StudioModels, not world brushes.
#define COMPRESSED_VERTS 1
#include "common_vs_fxc.h"

struct VS_INPUT
{
    float4 position : POSITION0;
    float4 weights : BLENDWEIGHT0;
    float4 bones : BLENDINDICES0;
    float4 normal : NORMAL0;
    float4 uv : TEXCOORD0;
    float4 positionFlex : POSITION1;
    float3 normalFlex : NORMAL1;
};

struct VS_OUTPUT
{
    float4 position : POSITION;
    float2 uv : TEXCOORD0;
    float3 worldPosition : TEXCOORD1;
    float3 worldNormal : TEXCOORD2;
#if CE8_ATLAS_SURFACE
    float atlasCell : TEXCOORD3;
#endif
};

VS_OUTPUT main(VS_INPUT input)
{
    VS_OUTPUT output = (VS_OUTPUT)0;
    float3 position = input.position.xyz;
    float3 normal;
    DecompressVertex_Normal(input.normal, normal);
    ApplyMorph(input.positionFlex.xyz, input.normalFlex, position, normal);
    SkinPositionAndNormal(true, float4(position, 1), normal,
        input.weights, input.bones, output.worldPosition, output.worldNormal);
    output.worldNormal = normalize(output.worldNormal);
    output.position = mul(float4(output.worldPosition, 1), cViewProj);
    output.uv = input.uv.xy; // Preserve native signed tile coordinates exactly.
#if CE8_ATLAS_SURFACE
    // Each triangle has one cell. The unwrapped authored UV is restored before
    // normal derivatives or texture addressing; no fractional UV interpolation.
    output.atlasCell = floor(input.uv.x / 32.0);
    output.uv.x = input.uv.x - output.atlasCell * 32.0 - 16.0;
#endif
    return output;
}
