Shader "Unlit/SSRShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Transparent" }
		ZWrite Off
        Pass
        {
			HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
			#pragma enable_d3d11_debug_symbols

			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
				float3 positionWS : TEXCOORD1;
				float4 positionOS : TEXCOORD2;
                float4 vertex : SV_POSITION;
            };

			TEXTURE2D(_MainTex);
			SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;

			TEXTURE2D(_CameraOpaqueTexture);
			SAMPLER(sampler_CameraOpaqueTexture);

			TEXTURE2D(_CameraDepthTexture);
			SAMPLER(sampler_CameraDepthTexture);

			float4x4 _InverseProjectionMatrix;
			float4x4 _InverseViewMatrix;

			float3 GetReflectRay(float3 inputRayDir, float3 planeDir)
			{
				float3 ret = -(2 * dot(inputRayDir, planeDir) * planeDir - inputRayDir);
				return normalize(ret);
			}

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

				o.positionWS = TransformObjectToWorld(v.vertex).xyz;
				o.positionOS = v.vertex.xyzw;
                return o;
            }

			bool IsRayInsect(float3 rayStart, float3 rayDir, float distance, out float2 screenUV)
			{
				float3 stepPos = rayStart + rayDir * distance;
				float3 posToCamera = length(stepPos.xyz - _WorldSpaceCameraPos.xyz);

				float4 screenPos = TransformWorldToHClip(float4(stepPos, 1));
				screenUV = screenPos.xy / screenPos.w;
				screenUV.xy = screenUV.xy * 0.5 + 0.5;

				if (screenUV.x < 0 || screenUV.y < 0 || screenUV.x > 1 || screenUV.y > 1) {
					screenUV = float2(-1, -1);
					return false;
				}

				float depth = LinearEyeDepth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV.xy), _ZBufferParams);
				
				return posToCamera > depth;
			}

			float3 RayTracePixel(float3 rayStart, float3 rayDir)
			{
				float step = 0.01;
				float traviled = 0;
				int limit = 256;

				float x1 = 1;
				float x2 = -1;
				float x3 = 0;

				float2 hitUV;
				/*bool IsHit = IsRayInsect(rayStart, rayDir, limit, hitUV);
				if (!IsHit) {
					return float3(1, 0, 0);
				}*/

				UNITY_LOOP
				for(int l = 1; l < limit; l++)
				{
					traviled += step;

					bool IsHit = IsRayInsect(rayStart, rayDir, traviled, hitUV);

					if (IsHit) {
						return SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, hitUV).xyz;
					}
					if (IsHit) {
						x1 = traviled - step;
						x2 = traviled;
						x3 = 0;

						for (int i = 0; i < 5; i++)
						{
							x3 = (x1 + x2) * 0.5;
							if (IsRayInsect(rayStart, rayDir, x3, hitUV))
							{
								x2 = x3;
							}
							else {
								x1 = x3;
							}
						}
					}
				}

				if (x2 - x1 > 0) {
					return SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, hitUV).xyz;
				}
				return float3(0, 0, 0);
			}

            float4 frag (v2f i) : SV_Target
            {
				float3 normalWS = TransformObjectToWorldDir(float3(0, 1, 0));

				float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);
				float3 reflectDir = GetReflectRay(viewDir, normalWS);
				float3 reflectPos = i.positionWS;

				float3 col = RayTracePixel(reflectPos, reflectDir);

                return float4(col, 1);
            }
            ENDHLSL
        }
    }
}
