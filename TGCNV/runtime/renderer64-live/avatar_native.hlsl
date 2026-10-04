// BA subset: GPU register storage copied verbatim from validated native capture; FOW is already resolved.
cbuffer Frame : register(b0) {
    column_major float4x4 ViewProjectionMatrix;
    column_major float4x4 matBones[45];
    float3 CameraPosition; float FOW;
    float4 LightOffset;
};
Texture2D<float4> DiffuseTexture : register(t0);
Texture2D<float4> MaskTexture : register(t1);
SamplerState DiffuseSampler : register(s0);
SamplerState MaskSampler : register(s1);
struct Input {float3 position:POSITION;float3 normal:NORMAL;float4 tangent:TANGENT;float2 uv:TEXCOORD0;uint4 ids:BLENDINDICES;float4 weights:BLENDWEIGHT;};
struct Output {float4 position:SV_Position;float2 uv:TEXCOORD0;float3 normal:TEXCOORD1;float3 light:TEXCOORD2;float3 eye:TEXCOORD3;};
Output VSMain(Input v){
    float4 p=0,n=0;const float4 source=float4(v.position,1);const float4 norm=float4(normalize(v.normal),0);
    [unroll] for(uint i=0;i<2;++i){p+=mul(source,matBones[v.ids[i]])*v.weights[i];n+=mul(norm,matBones[v.ids[i]])*v.weights[i];}
    Output o;o.position=mul(p,ViewProjectionMatrix);
    o.uv=v.uv;o.normal=normalize(n).xyz;o.light=-normalize(p.xyz-CameraPosition+LightOffset.xyz);o.eye=-normalize(p.xyz-CameraPosition);return o;
}
// Match the captured ps_2_0 constants and evaluation stages explicitly.
// Recomputing 1/(.48-.40) in the newer compiler produced 12.500003 instead of 12.5.
float3 ApplyFOWColor(float3 color){
    float grey=dot(color,float3(.212670997,.715160012,.0721689984));
    float3 delta=mad(grey,-.400000006,color);
    float base=grey*.400000006;
    return mad(FOW,delta,base);
}
float4 PSToon(Output input):SV_Target{
    float mask=MaskTexture.Sample(MaskSampler,input.uv).a;
    float3 base=DiffuseTexture.Sample(DiffuseSampler,input.uv).rgb;
    float3 L=normalize(input.light),N=normalize(input.normal),E=normalize(input.eye);
    float ramp=mad(dot(N,L),.5,.5);
    ramp=mad(mask-.5,.5,ramp);
    ramp=saturate((ramp-.400000006)*12.5);
    float curve=mad(-2,ramp,3)*(ramp*ramp);
    float3 shade=mad(curve,float3(.25,.25,.109999999),float3(.800000012,.800000012,.939999998));
    float rim=1-saturate(dot(N,E));rim*=rim;rim*=rim;
    float3 rim_color=rim*float3(.193599999,.209000006,.219999999);
    float3 color=mad(base,shade,rim_color);
    return float4(ApplyFOWColor(color),1);
}
float4 PSFace(Output input):SV_Target{
    float4 base=DiffuseTexture.Sample(DiffuseSampler,input.uv);clip(base.a-.5);
    float3 N=normalize(input.normal),L=normalize(input.light);
    float ramp=saturate(mad(dot(N,L),.5,.319999993)*8.33333302);
    float curve=mad(-2,ramp,3)*(ramp*ramp);
    float3 shade=mad(curve,float3(.150000006,.170000002,.0900000036),float3(.899999976,.879999995,.959999979));
    return float4(ApplyFOWColor(base.rgb*shade),1);
}
float4 PSHalo(Output input):SV_Target{
    float4 base=DiffuseTexture.Sample(DiffuseSampler,input.uv);return float4(ApplyFOWColor(base.rgb*1.20+.10),1);
}
// Diagnostic triangle identity, used only for Toon geometry with no alpha clip.
float4 PSPrimitive(Output input):SV_Target{
    float id=floor(input.uv.x+.5);float lo=id-floor(id/256)*256;float middle=floor(id/256);float high=floor(middle/256);
    return float4(lo/255,(middle-high*256)/255,high/255,1);
}
