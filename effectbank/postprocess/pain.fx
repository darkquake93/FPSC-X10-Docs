/***************************************************************************************************************
This multi-technique shader provides an automatic adaptive bloom effect based on screen brightness to scale the bloom effect
Shader code by Mark Blosser
email: mjblosser@gmail.com
website: www.mjblosser.com
released under creative commons license by attribution: http://creativecommons.org/licenses/by-sa/3.0/

********************************************************************************************************************/

string Description = "Multi Post-Process Shader by bond1";

/**************UNTWEAKABLES******************************************************************************/

float2 ViewSize : ViewSize;
float time : Time;

/***************BLOOM TWEAKS***************************************************************************/

float PreBloomBoost 
<
	string UIWidget = "slider";
	float UIMax = 4.0;
	float UIMin = 0.0;
	float UIStep = 0.1;
> = 2.0f;

float BloomThreshold 
<
	string UIWidget = "slider";
	float UIMax = 1.0;
	float UIMin = 0.0;
	float UIStep = 0.05;
> = 0.4;

float PostBloomBoost 
<
	string UIWidget = "slider";
	float UIMax = 4.0;
	float UIMin = 0.0;
	float UIStep = 0.1;
> = 2.0f;

float BloomWidth 
<
	string UIWidget = "slider";
	float UIMax = 6.0;
	float UIMin = 1.0;
	float UIStep = 0.1;
> = 2.5f;


//9 sample gauss filter, declare in pixel offsets convert to texel offsets in PS
float4 GaussFilter[9] =
{
    { -1,  -1, 0,  0.0625 },
    { -1,   1, 0,  0.0625 },
    {  1,  -1, 0,  0.0625 },
    {  1,   1, 0,  0.0625 },
    { -1,   0, 0,  0.125  },
    {  1,   0, 0,  0.125  },
    {  0,  -1, 0,  0.125 },
    {  0,   1, 0,  0.125 },
    {  0,   0, 0,  0.25 },
};


//---------------RENDER TARGET TEXTURES--------------------------------------//

//starting scene image
texture frame : RENDERCOLORTARGET
< 
	string ResourceName = "";
	float2 ViewportRatio = {1.0,1.0 };
	
>;

sampler2D frameSamp = sampler_state {
    Texture = < frame >;
    MinFilter = Linear; MagFilter = Linear; MipFilter = Linear;
    AddressU = Clamp; AddressV = Clamp;
};

//2x2 average luminosity texture using point sampling
texture AvgLum2x2Img : RENDERCOLORTARGET 
< 
	string ResourceName = ""; 
	//float2 ViewportRatio = { 0.5, 0.5 };
	int width = 2;
	int height = 2;
>;

sampler2D AvgLum2x2ImgSamp = sampler_state {
    Texture = < AvgLum2x2Img >;
    MinFilter = Point; MagFilter = Point; MipFilter = Point;
    AddressU = Clamp; AddressV = Clamp;
};

//Average scene luminosity stored in 1x1 texture 
texture AvgLumFinal : RENDERCOLORTARGET 
< 
	string ResourceName = ""; 
	//float2 ViewportRatio = { 0.5, 0.5 };
	int width = 1;
	int height = 1;
>;

sampler2D AvgLumFinalSamp = sampler_state {
    Texture = < AvgLumFinal >;
    MinFilter = Point; MagFilter = Point; MipFilter = Point;
    AddressU = Clamp; AddressV = Clamp;
};

//reduce image to 1/8 size for brightpass
texture BrightpassImg : RENDERCOLORTARGET
< 
	string ResourceName = "";
	//float2 ViewportRatio = {0.125,0.125 };
	int width = 512;
	int height = 384;
	
>;

sampler2D BrightpassImgSamp = sampler_state {
    Texture = < BrightpassImg >;
    MinFilter = Linear; MagFilter = Linear; MipFilter = Linear;
    AddressU = Clamp; AddressV = Clamp;
};

//blur texture 1
texture Blur1Img : RENDERCOLORTARGET
< 
	string ResourceName = "";
	//float2 ViewportRatio = {0.125,0.125 };
	int width = 512;
	int height = 384;
	
>;

sampler2D Blur1ImgSamp = sampler_state {
    Texture = < Blur1Img >;
    MinFilter = Anisotropic; MagFilter = Anisotropic; MipFilter = Anisotropic;
    AddressU = Clamp; AddressV = Clamp;
};

//blur texture 2
texture Blur2Img : RENDERCOLORTARGET
< 
	string ResourceName = "";
	//float2 ViewportRatio = {0.125,0.125 };
	int width = 512;
	int height = 384;
	
>;

sampler2D Blur2ImgSamp = sampler_state {
    Texture = < Blur2Img >;
    MinFilter = Linear; MagFilter = Linear; MipFilter = Linear;
    AddressU = Clamp; AddressV = Clamp;
};

//composite
texture CompImg : RENDERCOLORTARGET
< 
	string ResourceName = "";
	//float2 ViewportRatio = {0.125,0.125 };
	
	
>;

sampler2D CompImgSamp = sampler_state {
    Texture = < CompImg >;
    MinFilter = Linear; MagFilter = Linear; MipFilter = Linear;
    AddressU = Clamp; AddressV = Clamp;
};

//composite
texture BlendImg : RENDERCOLORTARGET
< 
	string ResourceName = "";
	//float2 ViewportRatio = {0.125,0.125 };
	
	
>;

sampler2D BlendImgSamp = sampler_state {
    Texture = < BlendImg >;
    MinFilter = Linear; MagFilter = Linear; MipFilter = Linear;
    AddressU = Clamp; AddressV = Clamp;
};


//-------------STRUCTS-------------------------------------------------------------

struct input 
{
	float4 pos : POSITION;
	float2 uv : TEXCOORD0;
};
 
struct output {

	float4 pos: POSITION;
	float2 uv: TEXCOORD0;

};

/*********************COMMON VERTEX SHADER************************************************/

output VS( input IN ) 
{
	output OUT;

	//quad needs to be shifted by half a pixel.
    //Go here for more info: http://www.sjbrown.co.uk/?article=directx_texels
    
	float4 oPos = float4( IN.pos.xy + float2( -1.0f/ViewSize.x, 1.0f/ViewSize.y ),0.0,1.0 );
	OUT.pos = oPos;

	float2 uv = (IN.pos.xy + 1.0) / 2.0;
	uv.y = 1 - uv.y; 
	OUT.uv = uv;
	
	return OUT;	
}

/*******************PIXEL SHADERS****************************************************/

//takes original frame image and outputs to 2x2
float4 PSReduce( output IN, uniform sampler2D srcTex ) : COLOR
{
    float4 color = 0;    
    color= tex2D( srcTex, IN.uv );    
    return color;    
}

//-----------------computes average luminosity for scene-----------------------------
float4 PSGlareAmount( output IN, uniform sampler2D srcTex ) : COLOR
{
    float4 GlareAmount = 0;
    
    //sample texture 4 times with offset texture coordinates
    float4 color1= tex2D( srcTex, IN.uv + float2(-0.5, -0.5) );
    float4 color2= tex2D( srcTex, IN.uv + float2(-0.5, 0.5) );
    float4 color3= tex2D( srcTex, IN.uv + float2(0.5, -0.5) );
    float4 color4= tex2D( srcTex, IN.uv + float2(0.5, 0.5) );
    
    //average these samples
    float3 AvgColor = saturate(color1.xyz * 0.25 + color2.xyz * 0.25 + color3.xyz * 0.25 + color4.xyz * 0.25);
    
    //exxagerate values to make effect more evident
    AvgColor = 8*AvgColor*AvgColor;
    
    //convert to luminance
    AvgColor = dot(float3(0.3,0.59,0.11), AvgColor);
    
    GlareAmount.xyz = AvgColor;
    
    //interpolation value to blend with previous frames
    GlareAmount.w = 0.03;
       
    return GlareAmount;    
}


//-------------brightpass pixel shader, removes low luminance pixels--------------------------
float4 PSBrightpass( output IN, uniform sampler2D srcTex, uniform sampler2D srcTex2  ) : COLOR
{
    float4 screen = tex2D(srcTex, IN.uv);  //original screen texture;
    float4 glaretex = tex2D(srcTex2, IN.uv);  //glareamount from 1x1 in previous pass;
    
    //remove low luminance pixels, keeping only brightest
    float3 Brightest = saturate(screen.xyz - BloomThreshold) * PreBloomBoost;
    //Brightest.xyz = pow(Brightest.xyz,2) * 2;
    
    //apply glare adaption
    //float3 adapt = Brightest.xyz * (1-glaretex.xyz);
    
    float4 color = float4(Brightest.xyz, 1);
    
    return color;    
}

float4 PSBlur( output IN, uniform sampler2D srcTex ) : COLOR
{
    float4 color = float4(0,0,0,0);
    
    //inverse view for correct pixel to texel mapping
    float2 ViewInv = float2( 1/ViewSize.x,1/ViewSize.y);   
    
    //sample and output average colors using gauss filter samples
    for(int i=0;i<9;i++)
    
    {
    //float4 col = GaussFilter[i].w * tex2D(srcTex,IN.uv + float2(GaussFilter[i].x * ViewInv.x*width, GaussFilter[i].y *ViewInv.y*width));  
    float4 col = GaussFilter[i].w * tex2D(srcTex,IN.uv + float2(GaussFilter[i].x * ViewInv.x*BloomWidth, GaussFilter[i].y *ViewInv.y*BloomWidth));  
    color+=col;
    }
    return color;
}

//combine adaptive bloom texture with original scene image
float4 PSPresent( output IN, uniform sampler2D srcTex, uniform sampler2D srcTex2, uniform sampler2D srcTex3 ) : COLOR
{
    float4 color = float4(0,0,0,0);
    
    //sample screen texture and bloom texture
    float4 ScreenMap=tex2D(srcTex, IN.uv);
    float4 BloomMap=tex2D(srcTex2, IN.uv);
    float4 BlendMap=tex2D(srcTex3, IN.uv);



  //vignette
  float2 vpos = (IN.uv - float2(.5,.5)) *3 ;
  //vpos.x = vpos.x * -1.5 - 0; //can also scale and shift horizontally
  float dist = (dot(vpos, vpos)) ;
  dist =  1-0.2 * dist;
  
  float pulsing =1;



    ScreenMap +=tex2D(srcTex, (IN.uv*0.99f)+0.005f)*(1-dist)*float4(1,0.35,0.35,1);
    ScreenMap +=tex2D(srcTex, (IN.uv*0.98f)+0.01f)*(1-dist)*float4(1,0.30,0.30,1);
    ScreenMap +=tex2D(srcTex, (IN.uv*0.97f)+0.015f)*(1-dist)*float4(1,0.25,0.25,1);
    ScreenMap +=tex2D(srcTex, (IN.uv*0.96f)+0.02f)*(1-dist)*float4(1,0.20,0.20,1);
    ScreenMap +=tex2D(srcTex, (IN.uv*0.95f)+0.025f)*(1-dist)*float4(1,0.15,0.15,1)*pulsing;
    ScreenMap +=tex2D(srcTex, (IN.uv*0.94f)+0.03f)*(1-dist)*float4(1,0.1,0.1,1)*pulsing;
    ScreenMap +=tex2D(srcTex, (IN.uv*0.93f)+0.035f)*(1-dist)*float4(1,0.05,0.05,1)*pulsing;
    ScreenMap +=tex2D(srcTex, (IN.uv*0.92f)+0.04f)*(1-dist)*float4(1,0.0,0.0,1)*pulsing;
    
    
    //technique 1: just add results
    
    float Luminance = dot(ScreenMap.xyz, float3(0.3, 0.59, 0.11));
    //float3 mod = lerp(PostBloomBoost,0,AmtMap.x);
    //float3 final = ScreenMap + 0.25*ScreenMap*mod + mod*BloomMap;
    //float3 final = .1*ScreenMap  +.3*BloomMap+ .9*BlendMap;
    
    //final  = lerp(final, ScreenMap+final*.1, Luminance);
    //float3 final = BloomMap;
    
    //technique 2: add results based scene pixel brightness
    //float Luminance = dot(ScreenMap.xyz, float3(0.3, 0.59, 0.11));
    //float4 MaxAmount= ScreenMap + BloomMap;
    //float3 final=lerp(MaxAmount*1.0, ScreenMap, Luminance);
    
    //technique 3: inverse multiplication
    //float3 final=0.15*((ScreenMap.xyz + BloomMap.xyz * (1-ScreenMap.xyz)))+.9*BlendMap;
      float3 final=0.50*((ScreenMap.xyz + BloomMap.xyz * (1-ScreenMap.xyz)))+.4*BlendMap;
    //float3 final = .1*ScreenMap  +.3*BloomMap+ .9*BlendMap;  //or just add results 
    
    color = float4(final,1);
    
    return color;
        
}

//-----------No effect pixel shader---------------------------------------------
float4 PSnone( output IN,uniform sampler2D srcTex  ) : COLOR0 
{
	// sample the source
	float4 cTextureScreen = tex2D( srcTex, IN.uv);
	
	return float4(cTextureScreen);
} 

//-----------No effect pixel shader---------------------------------------------
float4 TexQuadDimmerPS(output IN,uniform sampler2D srcTex   ) : COLOR0 
{
	// sample the source
	float4 cTextureScreen = tex2D( srcTex,  IN.uv);
	
	return float4(cTextureScreen);
} 



/*********************TECHNIQUES**********************************************************************/

technique bloom
<
	//specify where we want the original image to be put
	string RenderColorTarget = "frame";
>
{
	
	
	
	//3. remove low luminance pixels keeping only brightest for blurring in next pass
	pass Brightpass
	<
		string RenderColorTarget = "BrightpassImg";
	>
	{
		ZEnable = False;
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PSBrightpass( frameSamp, AvgLumFinalSamp );		
	}
	
	//4. blur texture and save in Blur1Img
	pass Blur1
	<
		string RenderColorTarget = "Blur1Img";
	>
	{
		ZEnable = False;
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PSBlur( BrightpassImgSamp );		
	}
	
	//5. repeat blur texture and save in Blur2Img
	pass Blur2
	<
		string RenderColorTarget = "Blur2Img";
	>
	{
		ZEnable = False;
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PSBlur( Blur1ImgSamp );		
	}
	
	//6. repeat blur again
	pass Blur3
	<
		string RenderColorTarget = "Blur1Img";
	>
	{
		ZEnable = False;
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PSBlur( Blur2ImgSamp );		
	}
	

	//composite the scene image with the bloom and blend images
	pass Comp
	<
		string RenderColorTarget = "CompImg";
	>
	{
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PSPresent( frameSamp, Blur1ImgSamp, BlendImgSamp );
	}


	//retain this image in "BlendImg" to remix back into scene
	pass RetainComp
	<
		string RenderColorTarget = "BlendImg";
	>
	{
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PSnone( CompImgSamp );
	}
	
	
	//display final result
	pass Display
	<
		string RenderColorTarget = "";
	>
	{
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 TexQuadDimmerPS(BlendImgSamp  );
	}
}