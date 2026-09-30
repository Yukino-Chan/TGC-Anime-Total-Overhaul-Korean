texture tex0 < string name = "sdf"; >;	// Base texture
texture tex1 < string name = "sdf"; >;	// Base texture

float4x4 WorldViewProjectionMatrix; 
float4	 FlagCoords;

sampler BaseTexture  =
sampler_state
{
    Texture = <tex0>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

sampler MaskTexture  =
sampler_state
{
    Texture = <tex1>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

// TGCNV readability pass. Keep all taps inside this flag's atlas cell.
float4 ReadableFlag( float2 uv )
{
    float2 texel = 1.0 / (float2(128.0, 64.0) * FlagCoords.xy);
    float2 lo = FlagCoords.zw + texel * 0.5;
    float2 hi = FlagCoords.zw + 1.0 / FlagCoords.xy - texel * 0.5;
    float4 color = tex2D( BaseTexture, clamp(uv, lo, hi) );
    // Keep BC1 block errors from being amplified by an unsharp filter.
    // Cloth overlays are now lighter; keep a gentle lift without washing faces out.
    color.rgb += 0.22 * color.rgb * (1.0 - color.rgb) * (1.25 - color.rgb);
    return color;
}

struct VS_INPUT
{
    float4 vPosition  : POSITION;
    float2 vTexCoord  : TEXCOORD0;
    float2 vMaskCoord  : TEXCOORD1;
};

struct VS_OUTPUT
{
    float4  vPosition : POSITION;
    float2  vTexCoord0 : TEXCOORD0;
    float2  vTexCoord1 : TEXCOORD1;
};


VS_OUTPUT OurVertexShader(const VS_INPUT v )
{
	VS_OUTPUT Out = (VS_OUTPUT)0;

	// TGCNV BA ring: the engine sizes this quad to the ring overlay and stretches the mask
	// over it; the mask is drawn for the overlay (71x63), so no vertex growth.
	Out.vPosition = mul(v.vPosition, WorldViewProjectionMatrix);

	Out.vTexCoord1 = v.vMaskCoord;

	// keep the 93:64 flag art undistorted in a 71:63 quad
	Out.vTexCoord0.x = (0.5 + (v.vTexCoord.x - 0.5) * 0.7756)/FlagCoords.x;
	Out.vTexCoord0.x = Out.vTexCoord0.x + FlagCoords.z;
	Out.vTexCoord0.y = v.vTexCoord.y/FlagCoords.y;
	Out.vTexCoord0.y = Out.vTexCoord0.y + FlagCoords.w;

	

	return Out;
}

float4 OurPixelShader( VS_OUTPUT v ) : COLOR
{
	float4 OutColor = ReadableFlag( v.vTexCoord0.xy );
	float4 MaskColor = tex2D( MaskTexture, v.vTexCoord1.xy );
	OutColor.a = MaskColor.a;
	
	return OutColor;
}

float4 PixelShaderOver( VS_OUTPUT v ) : COLOR
{
    float4 OutColor = ReadableFlag( v.vTexCoord0.xy );
    float4 MaskColor = tex2D( MaskTexture, v.vTexCoord1.xy );
    float4 MixColor = float4( 0.1, 0.1, 0.1, 0 );
    OutColor.a = MaskColor.a;
    OutColor += MixColor;
    
    return OutColor;
}

float4 PixelShaderDown( VS_OUTPUT v ) : COLOR
{
    float4 OutColor = ReadableFlag( v.vTexCoord0.xy );
    float4 MaskColor = tex2D( MaskTexture, v.vTexCoord1.xy );
    float4 MixColor = float4( 0.1, 0.1, 0.1, 0 );
    OutColor.a = MaskColor.a;
    OutColor -= MixColor;
    
    return OutColor;
}

float4 PixelShaderDisable( VS_OUTPUT v ) : COLOR
{
    float4 OutColor = ReadableFlag( v.vTexCoord0.xy );
    float4 MaskColor = tex2D( MaskTexture, v.vTexCoord1.xy );
    float Grey = dot( OutColor.rgb, float3( 0.212671f, 0.715160f, 0.072169f ) ); 
    
    OutColor.rgb = Grey;
    OutColor.a = MaskColor.a;
    
    return OutColor;
}

technique tec0
{
	pass p0
	{
		fvf = XYZ | Normal | Diffuse | Tex1;

		LightEnable[0] = false;
		Lighting = False;

		ALPHABLENDENABLE = True;

		Texture[0] = <tex0>;

		ColorOp[0] = Modulate;
		ColorArg1[0] = Texture;
		ColorArg2[0] = current;
  
		ColorOp[1] = Disable;
		AlphaOp[1] = Disable;

		VertexShader = compile vs_1_1 OurVertexShader();
		PixelShader = compile ps_2_0 OurPixelShader();
	}
}

technique down
{
	pass p0
	{
		fvf = XYZ | Tex1;

		LightEnable[0] = false;
		Lighting = False;

		ALPHABLENDENABLE = True;

		Texture[0] = <tex0>;


		ColorOp[0] = Modulate;
		ColorArg1[0] = Texture;
		ColorArg2[0] = current;
  
		ColorOp[1] = Disable;
		AlphaOp[1] = Disable;

//		VertexShaderConstant[4] = (WorldViewProjectionMatrix); // World*View*Proj Matrix

		VertexShader = compile vs_1_1 OurVertexShader();
		PixelShader = compile ps_2_0 PixelShaderDown();
	}
}

technique over
{
	pass p0
	{
		fvf = XYZ | Tex1;

		LightEnable[0] = false;
		Lighting = False;

		ALPHABLENDENABLE = True;

		Texture[0] = <tex0>;


		ColorOp[0] = Modulate;
		ColorArg1[0] = Texture;
		ColorArg2[0] = current;
  
		ColorOp[1] = Disable;
		AlphaOp[1] = Disable;

//		VertexShaderConstant[4] = (WorldViewProjectionMatrix); // World*View*Proj Matrix

		VertexShader = compile vs_1_1 OurVertexShader();
		PixelShader = compile ps_2_0 PixelShaderOver();
	}
}

technique disable
{
	pass p0
	{
		fvf = XYZ | Tex1;

		LightEnable[0] = false;
		Lighting = False;

		ALPHABLENDENABLE = True;

		Texture[0] = <tex0>;


		ColorOp[0] = Modulate;
		ColorArg1[0] = Texture;
		ColorArg2[0] = current;
  
		ColorOp[1] = Disable;
		AlphaOp[1] = Disable;

//		VertexShaderConstant[4] = (WorldViewProjectionMatrix); // World*View*Proj Matrix

		VertexShader = compile vs_1_1 OurVertexShader();
		PixelShader = compile ps_2_0 PixelShaderDisable();
	}
}
