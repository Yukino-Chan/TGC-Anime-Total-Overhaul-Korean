Texture2D<float4> Color : register(t0);
Texture2D<float> Depth : register(t1);
RWBuffer<uint> Bounds : register(u0);
groupshared uint Left, Top, Right, Bottom;
[numthreads(16,16,1)]
void RegionCS(uint3 id:SV_DispatchThreadID,uint lane:SV_GroupIndex) {
    uint width,height; Color.GetDimensions(width,height);
    if(lane==0){Left=width;Top=height;Right=0;Bottom=0;}
    GroupMemoryBarrierWithGroupSync();
    if(id.x<width && id.y<height){
        // Include every non-clear sample, including depth-only writes.
        if(any(Color.Load(int3(id.xy,0)) != 0) || Depth.Load(int3(id.xy,0)) != 1){
            InterlockedMin(Left,id.x);InterlockedMin(Top,id.y);
            InterlockedMax(Right,id.x+1);InterlockedMax(Bottom,id.y+1);
        }
    }
    GroupMemoryBarrierWithGroupSync();
    if(lane==0 && Right!=0){
        InterlockedMin(Bounds[0],Left);InterlockedMin(Bounds[1],Top);
        InterlockedMax(Bounds[2],Right);InterlockedMax(Bounds[3],Bottom);
    }
}

