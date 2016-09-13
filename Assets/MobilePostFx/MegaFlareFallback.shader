Shader "Hidden/MegaFlareFallback" {
	Properties {
		_MainTex ("Base (RGB)", 2D) = "white" {}
		_DirtTex ("Dirt (RGB)", 2D) = "black" {}
		_Parameters ("Size/Core", Vector) = (0.1, 0.1, 0.1, 0.1)
		_Parameters2 ("Anamorphic/Distance/Offset", Vector) = (0.0, 0.0, 0.0, 0.0)
		_Parameters3 ("Primary/Size/Cull", Vector) = (0.0, 1.0, 1.0, 1.0)
		_Parameters4 ("Inner/Outer", Vector) = (0.0, 1.0, 0.0, 1.0)
		_Color ("Color", Color) = (1,1,1,1)
		_InnerColor ("Inner Color", Color) = (1,1,1,1)
		_OuterColor ("Outer Color", Color) = (1,1,1,1)
	}
	
	CGINCLUDE
// Upgrade NOTE: excluded shader from OpenGL ES 2.0 because it uses non-square matrices
#pragma glsl
#pragma target 3.0
	
		#include "UnityCG.cginc"

		sampler2D _MainTex;
		uniform half4 _MainTex_TexelSize;
		sampler2D _DirtTex;
		
		sampler2D _CameraDepthTexture;
		float4 _CameraDepthTexture_ST;

		uniform half4 _Parameters;
		uniform half4 _Parameters2;
		uniform half4 _Parameters3;
		uniform half4 _Parameters4;
		uniform half4 _Color;
		uniform half4 _InnerColor;
		uniform half4 _OuterColor;

		struct appdata_flare {
			float4 vertex : POSITION;
			half2 texcoord : TEXCOORD0;
			half2 texcoord2 : TEXCOORD1;
		};
		struct appdata_flareOnCPU {
			float4 vertex : POSITION;
			half4 color : COLOR;
			half2 texcoord : TEXCOORD0;
			half2 texcoord2 : TEXCOORD1;
		};

		struct v2f_flare {
			half4 pos : SV_POSITION;
			half2 uv : TEXCOORD0;
			
			fixed4 color : TEXCOORD1;
			fixed4 screenPos : TEXCOORD2;
		};

		static const half2 DepthSamples[4] = {
			half2(1,0),
			half2(-1,0),
			half2(0,1),
			half2(0,-1)
		};
		
		float2 rotate2D (float2 p, float angle)
		{
			float x = p.x*cos(angle) - p.y*sin(angle);
			float y = p.x*sin(angle) + p.y*cos(angle);
			return float2(x,y);
		}
	
		
		v2f_flare vertCPURaycastedFlare (appdata_flareOnCPU v)
		{
			v2f_flare o;

			float anamorphic = _Parameters2.x;
			float primary = _Parameters3.x;
			float2 cull = _Parameters3.zw;
			float2 regionSizes = _Parameters4.xy;
			float2 regionScales = _Parameters4.zw;
			float3 innerColor = _InnerColor.rgb * _InnerColor.a;
			float3 outerColor = _OuterColor.rgb * _OuterColor.a;
			
			
			float occlusionX = v.color.x;
			float occlusionY = v.color.y;
			
			float2 scale = 1;
			scale.x *= saturate(1-occlusionX) * saturate(1-occlusionY*0.5);
			scale.y *= saturate(1-occlusionY) * saturate(1-occlusionX*0.5);

			o.pos = mul (UNITY_MATRIX_MV, v.vertex);

			float4 centerInScreenPos = mul (UNITY_MATRIX_P, o.pos);
			centerInScreenPos.xy /= centerInScreenPos.w;
			float l = length (centerInScreenPos.xy);
			float2 regions = l;
			regions.y = 1.0 - (regions.y - 1.0);
			regions /= regionSizes;
			regions = saturate(regions);

			float2 pos = (v.texcoord * 2.0 - 1.0) * _Parameters.xy * lerp(1.0, scale, _Parameters3.y) * lerp (regionScales.x, 1.0, regions.x) * lerp (regionScales.y, 1.0, regions.y);
			pos += _Parameters2.zw;
			
			float2 offset = -(1-primary) * (1-anamorphic) * o.pos.xy * length(o.pos.xy) * _Parameters2.y;
			
			// offset from center defines rotation
			float rotation = atan(offset.y / (offset.x + 1e-6)); // NOTE: appraently atan2 doesn't work as expected in DirextX11 or ARB OpenGL OLD: atan2 (offset.y, offset.x);
			pos = rotate2D (pos, rotation) + offset;
			pos.x -= (1-primary) * (anamorphic) * centerInScreenPos.x * _Parameters2.y;

			o.pos.xy += pos;

			o.pos = mul (UNITY_MATRIX_P, o.pos);
			o.screenPos.xy = o.pos.xy/o.pos.w * 0.5 + 0.5;
			o.screenPos.zw = o.pos.xy/o.pos.w * cull.xy * 2.0;
			o.uv = v.texcoord;
			
			o.color = _Color * lerp (length(scale), 1.0, _Parameters3.y);
			o.color.rgb *= lerp (innerColor, float3(1,1,1), regions.x) * lerp (outerColor, float3(1,1,1), regions.y);
					
			return o; 
		}
		
		#define DIRT(color) color *= tex2D (_DirtTex, i.screenPos.xy) + 1.0
		#define CULL(color) color *= saturate(length(i.screenPos.zw)-1)
		
		fixed4 fragFlare ( v2f_flare i ) : COLOR
		{
			fixed4 color = tex2D(_MainTex, i.uv) * i.color;
			return color;
		}
		
		fixed4 fragFlareWithDirt ( v2f_flare i ) : COLOR
		{
			fixed4 color = tex2D(_MainTex, i.uv) * i.color;
			DIRT (color);
			return color;
		}

		fixed4 fragFlareWithCull ( v2f_flare i ) : COLOR
		{
			fixed4 color = tex2D(_MainTex, i.uv) * i.color;
			CULL (color);
			return color;
		}

		fixed4 fragFlareWithDirtAndCull ( v2f_flare i ) : COLOR
		{
			fixed4 color = tex2D(_MainTex, i.uv) * i.color;
			DIRT (color);
			CULL (color);
			return color;
		}

	ENDCG
	
	SubShader {
		ZTest Always Cull Off ZWrite Off Blend One One
		Fog { Mode off }
		//Cull Off
		//ZWrite Off
	
	// 4
	Pass {
	
		CGPROGRAM
		#pragma vertex vertCPURaycastedFlare
		#pragma fragment fragFlare
		#pragma fragmentoption ARB_precision_hint_fastest 
		
		ENDCG
		
		}
	// 5
	Pass {
	
		CGPROGRAM
		#pragma vertex vertCPURaycastedFlare
		#pragma fragment fragFlareWithDirt
		#pragma fragmentoption ARB_precision_hint_fastest 
		
		ENDCG
		
		}
	// 6
	Pass {
	
		CGPROGRAM
		#pragma vertex vertCPURaycastedFlare
		#pragma fragment fragFlareWithCull
		#pragma fragmentoption ARB_precision_hint_fastest 
		
		ENDCG
		
		}
	// 7
	Pass {
	
		CGPROGRAM
		#pragma vertex vertCPURaycastedFlare
		#pragma fragment fragFlareWithDirtAndCull
		#pragma fragmentoption ARB_precision_hint_fastest 
		
		ENDCG
		
		}
	}
}