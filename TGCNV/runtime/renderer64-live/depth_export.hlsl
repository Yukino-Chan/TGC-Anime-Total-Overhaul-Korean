Texture2D<float> SourceDepth : register(t0);
float4 DepthVS(uint id:SV_VertexID):SV_Position {
    float2 uv=float2((id<<1)&2,id&2);
    return float4(uv*float2(2,-2)+float2(-1,1),0,1);
}
float DepthPS(float4 position:SV_Position):SV_Target {
    return SourceDepth.Load(int3(uint2(position.xy),0));
}

