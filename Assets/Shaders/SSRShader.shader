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

#define MAX_TRACE_DIS 50
#define MAX_IT_COUNT 50         
#define EPSION 0.1

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
				float4 positionCS : TEXCOORD3;
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
			float4x4 _Camera_INV_VP;

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
				o.positionCS = TransformObjectToHClip(v.vertex);
				o.positionCS.xyz / o.positionCS.w;
				o.positionCS.xy = o.positionCS.xy * 0.5 + 0.5;
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

				float depth = LinearEyeDepth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV.xy).r, _ZBufferParams);
				
				return posToCamera >= depth && (posToCamera - depth) <= 1;
			}

			float3 RayTracePixel(float3 rayStart, float3 rayDir)
			{
				float step = 0.001;
				float traviled = 0;
				int limit = 256;

				float x1 = 1;
				float x2 = -1;
				float x3 = 0;

				float2 hitUV;

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

			float2 PosToUV(float3 vpos)
			{
				float4 proj_pos = mul(unity_CameraProjection, float4(vpos, 1));
				float3 screenPos = proj_pos.xyz / proj_pos.w;
				return float2(screenPos.x, screenPos.y) * 0.5 + 0.5;
			}

			bool compareWithDepth(float3 vpos, out bool isInside)
			{
				float2 uv = PosToUV(vpos);
				float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
				depth = LinearEyeDepth(depth, _ZBufferParams);
				isInside = uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1;
				return vpos.z > depth;
			}

			bool RayTraceInViewSpace(float3 o, float3 r, out float3 hitp)
			{
				float3 start = o;
				float3 end = o;
				float stepSize = 0.15;//MAX_TRACE_DIS / MAX_IT_COUNT;
				UNITY_LOOP
				for (int i = 1; i <= MAX_IT_COUNT; ++i)
				{
					end = o + r * stepSize * i;
					if (length(end - start) > 100)
						return false;

					bool isInside = true;
					bool ret = compareWithDepth(end, isInside);
					if (ret)
					{
						hitp = end;
						return true;
					}
				}
				return false;
			}

            float4 frag (v2f i) : SV_Target
            {
				//世界空间射线
				float3 normalWS = TransformObjectToWorldDir(float3(0, 1, 0));
				

				float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);
				float3 reflectDir = reflect(viewDir, normalWS);
				float3 reflectPos = i.positionWS;

				float3 col = RayTracePixel(reflectPos, reflectDir);

				//屏幕空间射线
				//相机空间射线起点
				float4 rayDirVS = mul(unity_CameraInvProjection, float4(i.positionCS.xy * 2 - 1, 1, 1));
				float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv);
				depth = LinearEyeDepth(depth, _ZBufferParams);
				//相机空间法线
				float3 normalVS = TransformWorldToViewDir(normalWS);
				//相机空间内碰撞点
				float3 view_pos = rayDirVS.xyz / rayDirVS.w * depth;
				//相机空间反射向量
				float3 reflectedRay = reflect(normalize(view_pos), normalVS);

				float3 hitp = 0;
				col = 0;
				if (RayTraceInViewSpace(view_pos, reflectedRay, hitp))
				{
					float2 tuv = PosToUV(hitp);
					float3 hitCol = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, tuv).xyz;
					col = hitCol;
				}

                return float4(col, 1);
            }
            ENDHLSL
        }
    }
}
