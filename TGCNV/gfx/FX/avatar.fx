float4x4 ViewProjectionMatrix;
float4x4 WorldMatrix;
float3 CameraPosition;
float4x4 matBones[45] : Bones;
float3 LightDirection;
float Time;
float4 TextureOffset;
float4 PrimaryColor   = float4(0.8, 0.0, 0, 1);
float4 SecondaryColor = float4(0.0, 0.7, 0, 1);

float FOW = 1.0;

// debug flags
//#define DEBUG_ONLY_SPECULAR
//#define DEBUG_ONLY_DIFFUSE
//#define DEBUG_ONLY_COLORMAP
//#define DEBUG_SHOW_SPECULARMAP
//#define DEBUG_SHOW_TEXCOORDS
#define DEBUG_SHOW_NORMALMAP

// select lighting model to use
#define LIGHTMODEL_WRAP
//#define LIGHTMODEL_HALFLAMBERT
//#define LIGHTMODEL_PHONG

const int SKINNING_INFLUENCES = 2;

float SPECULAR_POWER = 20;
float SPECULARITY = 1.25;
const float WRAP = 0.7;
const float AMBIENT = 0.0;
const float INTENSITY = 1.75;
const float3 LIGHT_OFFSET = float3(-250, -500, 200);
//float3 LIGHT_OFFSET = float3(0, 0, 100);

const float TRACK_SPEED = 2.5;

// Flag specific
const float ANIMATION_SPEED = 0.3;
const float INTENSITY_FLAG = 0.9;
const float3 LIGHT_OFFSET_FLAG = float3(-250, -500, 100);
const float FLAG_GRAYNESS = 0.3;
float SPECULAR_POWER_FLAG = 10;
float SPECULARITY_FLAG = 0.1;

texture tex0 : DiffuseTexture;
sampler2D DiffuseMap = 
sampler_state 
{
    texture = <tex0>;
    AddressU  = Wrap;        
    AddressV  = Wrap;
    MipFilter = Linear;
    MagFilter = Linear;
	MinFilter = Anisotropic;
    
    MaxAnisotropy = 4;
};

texture tex1 : Texture1;
sampler2D SpecularMap = 
sampler_state 
{
    texture = <tex1>;
    AddressU  = Wrap;        
    AddressV  = Wrap;
    MipFilter = Linear;
    MinFilter = Linear;
    MagFilter = Linear;
};

sampler2D NormalMap = 
sampler_state 
{
    texture = <tex1>;
    AddressU  = Wrap;        
    AddressV  = Wrap;
    MipFilter = Linear;
    MagFilter = Linear;
	MinFilter = Linear;
};

struct VS_INPUT
{
    float4 vPosition   : POSITION;
    float3 vNormal     : NORMAL;
	float4 vTangent    : TANGENT;
	float2 vTexCoord0  : TEXCOORD0;
	float4 boneIndices : BLENDINDICES;
    float4 boneWeights : BLENDWEIGHT;
};

struct VS_OUTPUT
{
    float4 vPosition  : POSITION;
	float2 vTexCoord0 : TEXCOORD0;
	float3 Normal     : TEXCOORD1;
	float3 LightDirection : TEXCOORD2;
	float3 EyeVec : TEXCOORD3;
};


float3 ApplyFOWColor( float3 c ) 
{
	const float3 GREYIFY = float3( 0.212671, 0.715160, 0.072169 );
	float Grey = dot( c.rgb, GREYIFY );
	return lerp( Grey.rrr * 0.4, c.rgb, FOW > 0.5 ? 1.0 : 0.5 );
}

VS_OUTPUT SkinnedAvatarVS(const VS_INPUT v )
{
	VS_OUTPUT Out = (VS_OUTPUT)0;
		
	float4 skinnedPosition = (float4)0;
	float4 skinnedNormal   = (float4)0;
	
	float4 vPosition = float4(v.vPosition.xyz, 1.0);
		
	// skinning
	for( int i = 0; i < SKINNING_INFLUENCES; ++i )
    {
    	float4x4 mat = matBones[ v.boneIndices[i] ];

		float4 offset = mul( vPosition, mat ) * v.boneWeights[i];
		skinnedPosition += offset;
		
		offset = mul( normalize(v.vNormal), mat )  * v.boneWeights[i];
		skinnedNormal += offset;
	}
	
	Out.LightDirection = -normalize(skinnedPosition - CameraPosition + LIGHT_OFFSET );
	Out.EyeVec = -normalize(skinnedPosition - (CameraPosition) );
	
	Out.vPosition = mul(skinnedPosition, ViewProjectionMatrix );
	Out.vTexCoord0 = v.vTexCoord0;
	Out.Normal  = normalize(skinnedNormal);

	return Out;
}

float4 SkinnedAvatarPS( VS_OUTPUT In ) : COLOR
{
	float4 vColor = tex2D( DiffuseMap, In.vTexCoord0 );
	float3 vSpecColor = tex2D( SpecularMap, In.vTexCoord0 ).rgb;
	//return float4(vSpecColor.rrr,1);
	float3 vNormal = normalize(In.Normal);

	// get base color
	vColor.rgb = lerp(vColor.rgb, 
	                  vColor.rgb * (PrimaryColor.rgb * vSpecColor.g), 
					  vSpecColor.g);

	vColor.rgb = lerp(vColor.rgb,  
	                  vColor.rgb * (SecondaryColor.rgb * vSpecColor.b), 
					  vSpecColor.b);

	float3 L = normalize(In.LightDirection);
	float3 E = normalize(In.EyeVec);
    //float3 halfVec = L; // light is in camera so no need for normalize(EyeVec + L);
	float3 halfVec = normalize(E + L);
	float  NdotL = max(0 , dot(vNormal,L));
	
	#ifdef LIGHTMODEL_WRAP
	float diffuse = saturate((NdotL + WRAP) / (1 + WRAP)) * INTENSITY;
	#endif
	#ifdef LIGHTMODEL_HALFLAMBERT
	float diffuse = pow(0.5 * NdotL + 0.5, 2) * INTENSITY; 
	#endif
	#ifdef LIGHTMODEL_PHONG
	float diffuse = NdotL * INTENSITY + AMBIENT;
	#endif
	
	//diffuse = 0;
	//vColor.rgb = float3(0.2,0,0);
    float NDotH = dot(vNormal, halfVec);
	float vMax = saturate(NDotH );
	//float  specular = 0;
	//if( vMax != 0 )
		float specular = pow( vMax, SPECULAR_POWER );
 	
    //if( NdotL <= 0 )
    //{
     //   specular = 0;
    //}
	
	specular *= vSpecColor.r * SPECULARITY; // mask
		
	//return float4(NdotL.xxx, 1 );
	
	return float4( ApplyFOWColor(vColor.rgb * diffuse + specular), 1 );
}


float2 GetTexCoordsInAtlas(float2 TexCoord)
{
	return float2( (TexCoord.x / TextureOffset.x) + TextureOffset.z,
	               (TexCoord.y / TextureOffset.y) + TextureOffset.w );
}

VS_OUTPUT SkinnedAvatarVSFlag(const VS_INPUT v )
{
	VS_OUTPUT Out = (VS_OUTPUT)0;
	
	float4 skinnedPosition = (float4)0;
	float4 skinnedNormal   = (float4)0;
	float4 skinnedTangent  = (float4)0;
	
	float4 vPosition = float4(v.vPosition.xyz, 1.0);

	// skinning
	for( int i = 0; i < SKINNING_INFLUENCES; ++i )
    {
    	float4x4 mat = matBones[ v.boneIndices[i] ];

		float4 offset = mul( vPosition, mat ) * v.boneWeights[i];
		skinnedPosition += offset;
		
		offset = mul( normalize(v.vNormal), mat )  * v.boneWeights[i];
		skinnedNormal += offset;

		offset = mul( normalize(v.vTangent), mat ) * v.boneWeights[i];
		skinnedTangent += offset;
	}
	
	skinnedNormal  = normalize(skinnedNormal);
	skinnedTangent = normalize(skinnedTangent);
	float3 binormal = cross(skinnedTangent.xyz, skinnedNormal.xyz ) * v.vTangent.w;
	normalize(binormal);
	
	// transform light direction into tangent space
	float3x3 matTBN = float3x3(skinnedTangent.xyz, 
	                           binormal,
							   skinnedNormal.xyz);
	Out.LightDirection = mul(matTBN, -normalize(skinnedPosition - CameraPosition + LIGHT_OFFSET_FLAG ));
	Out.EyeVec = mul(matTBN, -normalize(skinnedPosition - (CameraPosition) ));
	
	Out.vPosition = mul(skinnedPosition, ViewProjectionMatrix );
	Out.vTexCoord0 = v.vTexCoord0;
	
	return Out;
}

float4 SkinnedAvatarPSFlag( VS_OUTPUT In ) : COLOR
{
	float t = frac(Time * ANIMATION_SPEED);
	float2 NormalCoord = float2(In.vTexCoord0.x - t, In.vTexCoord0.y );
	
	//return float4(PrimaryColor.rgb,1);
	//return float4(tex2D( NormalMap, NormalCoord ).rgb, 1.0);     // normals
	
	float4 vColor = tex2D( DiffuseMap, GetTexCoordsInAtlas(In.vTexCoord0) );
	//float3 vSpecColor = tex2D( SpecularMap, In.vTexCoord0 ).rgb;
	float3 vNormal = normalize( tex2D( NormalMap, NormalCoord ).rgb * 2.0 - 1 );
	//float3 vNormal = float3(0,0,1);
		
	float3 L = normalize(In.LightDirection);
	float3 E = normalize(In.EyeVec);
	float3 halfVec = normalize(E + L);
	float  NdotL = dot(vNormal, L);
	
	//return float4(E.rgb, 1);
	
	#ifdef LIGHTMODEL_WRAP
	float diffuse = saturate((saturate(NdotL) + WRAP) / (1 + WRAP)) * INTENSITY_FLAG;
	#endif
	#ifdef LIGHTMODEL_HALFLAMBERT
	float diffuse = pow(0.5 * saturate(NdotL) + 0.5, 2) * INTENSITY_FLAG; 
	#endif
	#ifdef LIGHTMODEL_PHONG
	float diffuse = saturate(NdotL) * INTENSITY_FLAG + AMBIENT;
	#endif
	
	    
 	float  specular = pow( saturate( dot(vNormal, halfVec) ), SPECULAR_POWER_FLAG );
    if( NdotL <= 0 )
    {
       specular = 0;
    }
	
	specular *= SPECULARITY_FLAG; // mask
		
	//return float4(NdotL.xxx, 1 );
	//return float4(vColor.rgb * diffuse + specular, 1 );

	vColor.rgb = vColor.rgb  * saturate(diffuse) +  float3(0.0,0.0,0.0);
	float Grey = dot( vColor.rgb, float3( 0.212671f, 0.715160f, 0.072169f ) );
	return float4(lerp( vColor.rgb, Grey.rrr, FLAG_GRAYNESS ) + specular, vColor.a);
}

float4 SkinnedAvatarPSShadow( VS_OUTPUT In ) : COLOR
{
	
	float4 vColor = tex2D( DiffuseMap, In.vTexCoord0 );
	return vColor;
}

float4 SkinnedAvatarPSSmoke( VS_OUTPUT In ) : COLOR
{
	float t = frac(Time * ANIMATION_SPEED);
	float vAlpha = tex2D( DiffuseMap, In.vTexCoord0 ).a;
	float4 vColor = tex2D( DiffuseMap, float2(In.vTexCoord0.x, In.vTexCoord0.y + t ) );
	vColor.a =  vAlpha;
	return vColor;
}

float4 SkinnedAvatarPSTracks( VS_OUTPUT In ) : COLOR
{
	float t = frac(Time * TRACK_SPEED);
	float2 Tex = float2(In.vTexCoord0.x, In.vTexCoord0.y + t);
	float4 vColor = tex2D( DiffuseMap, Tex );
	
	return float4(vColor.rgb, vColor.a); // normal
}

/////////////////////////////////////////////////////

technique Standard
{
	pass p0
	{
		MipMapLodBias[0] = -1.0;
		
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 SkinnedAvatarPS();
	}
}


technique Flag
{
	pass p0
	{
		VertexShader = compile vs_2_0 SkinnedAvatarVSFlag();
		PixelShader = compile ps_2_0 SkinnedAvatarPSFlag();
	}
}

technique Shadow
{
	pass p0
	{
		ZENABLE = True;
		ALPHABLENDENABLE = True;
		ALPHATESTENABLE = False;
		ZWRITEENABLE = False;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 SkinnedAvatarPSShadow();
	}
}

technique Smoke
{
	pass p0
	{
		ZENABLE = True;
		ZWRITEENABLE = False;
		ALPHABLENDENABLE = True;
		ALPHATESTENABLE = False;
		
		//SrcBlend = SRCALPHA;
		//DestBlend = ONE;
		
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 SkinnedAvatarPSSmoke();
	}
}

technique TexAnim
{
	pass p0
	{
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 SkinnedAvatarPSTracks();
	}
}
// TGCNV_STRIKE_MATERIALS_BEGIN
// Source palette: locally installed HOI4 vehicles/carpet_bomb.asset.
// Overlapping flash/fire/smoke use continuous opacity curves per impact.
// Existing actor techniques are deliberately untouched.

// Each owned explosion binds its own normalized age through PrimaryColor.a.
// Native SetVector uploads this immediately before each material draw. Global
// Time is intentionally unused: pausing also freezes every layer's opacity.
// Pass the per-draw age through the vertex stage so D3DX9's effect
// preshader does not try to evaluate smoothstep curves as CPU expressions.
struct TGCNV_STRIKE_VS_OUTPUT
{
    float4 vPosition : POSITION;
    float2 vTexCoord0 : TEXCOORD0;
    float age : TEXCOORD1;
};
TGCNV_STRIKE_VS_OUTPUT TGCNVStrikeVS(const VS_INPUT v)
{
    VS_OUTPUT skinned = SkinnedAvatarVS(v);
    TGCNV_STRIKE_VS_OUTPUT Out;
    Out.vPosition = skinned.vPosition;
    Out.vTexCoord0 = skinned.vTexCoord0;
    Out.age = PrimaryColor.a;
    return Out;
}

float4 TGCNVStrikeFlashPS(TGCNV_STRIKE_VS_OUTPUT In) : COLOR
{
    float age = saturate(In.age);
    float4 color = tex2D(DiffuseMap, In.vTexCoord0);
    color.rgb = ApplyFOWColor(color.rgb * float3(1.0, 0.901961, 0.627451));
    color.a *= 0.862745 * (1.0 - smoothstep(0.015, 0.14, age));
    return color;
}

float4 TGCNVStrikeFirePS(TGCNV_STRIKE_VS_OUTPUT In) : COLOR
{
    float age = saturate(In.age);
    float4 color = tex2D(DiffuseMap, In.vTexCoord0);
    color.rgb = ApplyFOWColor(color.rgb * float3(1.0, 0.581854, 0.120319));
    color.a *= 0.799040 * smoothstep(0.0, 0.035, age)
        * (1.0 - smoothstep(0.07, 0.32, age));
    return color;
}

float4 TGCNVStrikeSmokePS(TGCNV_STRIKE_VS_OUTPUT In) : COLOR
{
    float age = saturate(In.age);
    float4 color = tex2D(DiffuseMap, In.vTexCoord0);
    float tint = smoothstep(0.22, 0.85, age);
    color.rgb = ApplyFOWColor(color.rgb * lerp(float3(0.282941, 0.282941, 0.217647),
        float3(0.402478, 0.402478, 0.321983), tint));
    color.a *= 0.66 * smoothstep(0.045, 0.22, age)
        * (1.0 - smoothstep(0.25, 1.0, age));
    return color;
}

// Retained for compatible legacy model definitions; current impacts use the
// smoke submesh of one persistent layered actor through their entire life.
float4 TGCNVStrikeDissipatePS(TGCNV_STRIKE_VS_OUTPUT In) : COLOR
{
    float age = saturate(In.age);
    float4 color = tex2D(DiffuseMap, In.vTexCoord0);
    float tint = smoothstep(0.22, 0.85, age);
    color.rgb = ApplyFOWColor(color.rgb * lerp(float3(0.282941, 0.282941, 0.217647),
        float3(0.402478, 0.402478, 0.321983), tint));
    color.a *= 0.66 * smoothstep(0.045, 0.22, age)
        * (1.0 - smoothstep(0.25, 1.0, age));
    return color;
}

technique TGCNVStrikeFlash
{
    pass p0
    {
        ZENABLE = True;
        ZWRITEENABLE = False;
        ALPHABLENDENABLE = True;
        ALPHATESTENABLE = False;
        SrcBlend = SRCALPHA;
        DestBlend = ONE;
        CullMode = CCW;
        VertexShader = compile vs_2_0 TGCNVStrikeVS();
        PixelShader = compile ps_2_0 TGCNVStrikeFlashPS();
    }
}

technique TGCNVStrikeFire
{
    pass p0
    {
        ZENABLE = True;
        ZWRITEENABLE = False;
        ALPHABLENDENABLE = True;
        ALPHATESTENABLE = False;
        SrcBlend = SRCALPHA;
        DestBlend = ONE;
        CullMode = CCW;
        VertexShader = compile vs_2_0 TGCNVStrikeVS();
        PixelShader = compile ps_2_0 TGCNVStrikeFirePS();
    }
}

technique TGCNVStrikeSmoke
{
    pass p0
    {
        ZENABLE = True;
        ZWRITEENABLE = False;
        ALPHABLENDENABLE = True;
        ALPHATESTENABLE = False;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        CullMode = CCW;
        VertexShader = compile vs_2_0 TGCNVStrikeVS();
        PixelShader = compile ps_2_0 TGCNVStrikeSmokePS();
    }
}

technique TGCNVStrikeDissipate
{
    pass p0
    {
        ZENABLE = True;
        ZWRITEENABLE = False;
        ALPHABLENDENABLE = True;
        ALPHATESTENABLE = False;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        CullMode = CCW;
        VertexShader = compile vs_2_0 TGCNVStrikeVS();
        PixelShader = compile ps_2_0 TGCNVStrikeDissipatePS();
    }
}
// TGCNV_STRIKE_MATERIALS_END

// TGCNV_NUCLEAR_MATERIALS_BEGIN
float4 TGCNVNuclearSmokePS(TGCNV_STRIKE_VS_OUTPUT In) : COLOR {
 float age=saturate(In.age); float4 color=tex2D(DiffuseMap,In.vTexCoord0);
 color.rgb=ApplyFOWColor(color.rgb * float3(.49,.49,.49)); color.a *= 0.62 * smoothstep(.025,.22,age) * (1.0-smoothstep(.50,1.0,age)); return color;
}
technique TGCNVNuclearSmoke { pass p0 {
 ZENABLE=True; ZWRITEENABLE=False; ALPHABLENDENABLE=True; ALPHATESTENABLE=False; SrcBlend=SRCALPHA; DestBlend=INVSRCALPHA; CullMode=CCW;
 VertexShader=compile vs_2_0 TGCNVStrikeVS(); PixelShader=compile ps_2_0 TGCNVNuclearSmokePS();
} }
float4 TGCNVNuclearFirePS(TGCNV_STRIKE_VS_OUTPUT In) : COLOR {
 float age=saturate(In.age); float4 color=tex2D(DiffuseMap,In.vTexCoord0);
 color.rgb=ApplyFOWColor(color.rgb * float3(1.0,.588,.392)); color.a *= 0.65 * (1.0-smoothstep(.04,.36,age)); return color;
}
technique TGCNVNuclearFire { pass p0 {
 ZENABLE=True; ZWRITEENABLE=False; ALPHABLENDENABLE=True; ALPHATESTENABLE=False; SrcBlend=SRCALPHA; DestBlend=ONE; CullMode=CCW;
 VertexShader=compile vs_2_0 TGCNVStrikeVS(); PixelShader=compile ps_2_0 TGCNVNuclearFirePS();
} }
float4 TGCNVNuclearFlashPS(TGCNV_STRIKE_VS_OUTPUT In) : COLOR {
 float age=saturate(In.age); float4 color=tex2D(DiffuseMap,In.vTexCoord0);
 color.rgb=ApplyFOWColor(color.rgb * float3(1.0,.863,.725)); color.a *= 0.35 * (1.0-smoothstep(.005,.20,age)); return color;
}
technique TGCNVNuclearFlash { pass p0 {
 ZENABLE=True; ZWRITEENABLE=False; ALPHABLENDENABLE=True; ALPHATESTENABLE=False; SrcBlend=SRCALPHA; DestBlend=ONE; CullMode=CCW;
 VertexShader=compile vs_2_0 TGCNVStrikeVS(); PixelShader=compile ps_2_0 TGCNVNuclearFlashPS();
} }
// TGCNV_NUCLEAR_MATERIALS_END
// TGCNV_BA_TOON_BEGIN
// Blue Archive chibi actors (#WIP/ba_3d_20260929). Cel shading with the BA
// mask (tex1 alpha = shadow bias), cool lavender shadows and a soft sky rim.
static const float3 BA_SHADOW = float3(0.80, 0.80, 0.94);
static const float3 BA_LIGHT = float3(1.05, 1.05, 1.05);
static const float3 BA_RIM = float3(0.88, 0.95, 1.00);

float4 BAToonPS( VS_OUTPUT In ) : COLOR
{
	float4 base = tex2D( DiffuseMap, In.vTexCoord0 );
	float bias = tex2D( SpecularMap, In.vTexCoord0 ).a - 0.5;
	float3 N = normalize( In.Normal );
	float3 L = normalize( In.LightDirection );
	float3 E = normalize( In.EyeVec );
	float lit = smoothstep( 0.40, 0.48, dot( N, L ) * 0.5 + 0.5 + bias * 0.5 );
	float3 col = base.rgb * lerp( BA_SHADOW, BA_LIGHT, lit );
	float rim = pow( 1.0 - saturate( dot( N, E ) ), 4.0 );
	col += BA_RIM * rim * 0.22;
	return float4( ApplyFOWColor( col ), 1.0 );
}

float4 BAFacePS( VS_OUTPUT In ) : COLOR
{
	float4 base = tex2D( DiffuseMap, In.vTexCoord0 );
	clip( base.a - 0.5 );
	float3 N = normalize( In.Normal );
	float3 L = normalize( In.LightDirection );
	float lit = smoothstep( 0.18, 0.30, dot( N, L ) * 0.5 + 0.5 );
	float3 col = base.rgb * lerp( float3( 0.90, 0.88, 0.96 ), BA_LIGHT, lit );
	return float4( ApplyFOWColor( col ), 1.0 );
}

float4 BAHaloPS( VS_OUTPUT In ) : COLOR
{
	float4 base = tex2D( DiffuseMap, In.vTexCoord0 );
	float3 col = base.rgb * 1.20 + 0.10;
	return float4( ApplyFOWColor( col ), 1.0 );
}

technique BAToon0
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon1
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon2
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon3
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon4
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon5
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon6
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon7
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon8
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon9
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon10
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAToon11
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAToonPS();
	}
}

technique BAFace0
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAFacePS();
	}
}

technique BAFace1
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAFacePS();
	}
}

technique BAFace2
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAFacePS();
	}
}

technique BAFace3
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAFacePS();
	}
}

technique BAFace4
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAFacePS();
	}
}

technique BAFace5
{
	pass p0
	{
		MipMapLodBias[0] = -0.5;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAFacePS();
	}
}

technique BAHalo0
{
	pass p0
	{
		CullMode = None;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAHaloPS();
	}
}

technique BAHalo1
{
	pass p0
	{
		CullMode = None;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAHaloPS();
	}
}

technique BAHalo2
{
	pass p0
	{
		CullMode = None;
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 BAHaloPS();
	}
}
// TGCNV_BA_TOON_END
