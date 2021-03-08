Shader "Unlit/SSRShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		_SkyBoxCubeMap("SkyBox", Cube) = ""{}
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

			#define MAX_TRACE_DIS 500
			#define MAX_IT_COUNT 200         
			#define EPSION 0.1

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
				float4 vsRay	  : TEXCOORD4;
                float4 vertex : SV_POSITION;
            };

			TEXTURE2D(_MainTex);
			SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;

			TEXTURE2D(_CameraOpaqueTexture);
			SAMPLER(sampler_CameraOpaqueTexture);

			TEXTURE2D(_CameraDepthTexture);
			SAMPLER(sampler_CameraDepthTexture);

			TEXTURECUBE(_SkyBoxCubeMap);
			SAMPLER(sampler_SkyBoxCubeMap);

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

				float4 screenPos = TransformObjectToHClip(v.vertex);
				screenPos.xyz /= screenPos.w;
				screenPos.xy = screenPos.xy * 0.5 + 0.5;

				o.positionCS = screenPos;
				o.positionCS.y = 1 - o.positionCS.y;

				float zFar = _ProjectionParams.z;
				float4 cameraRay = float4(float3(o.positionCS.xy * 2.0 - 1.0, 1) * zFar, zFar);
				cameraRay = mul(unity_CameraInvProjection, cameraRay);
				//cameraRay = cameraRay / cameraRay.w;

				float4 cameraRayOrigin = float4(o.positionCS.xy * 2.0 - 1.0, 0, 1.0);
				cameraRayOrigin = mul(unity_CameraInvProjection, cameraRayOrigin);
				cameraRayOrigin = cameraRayOrigin / cameraRayOrigin.w;

				o.vsRay = cameraRay;
                return o;
            }

			float2 PosToUV(float3 vpos)
			{
				float4 proj_pos = mul(unity_CameraProjection, float4(vpos, 1));
				float3 screenPos = proj_pos.xyz / proj_pos.w;
				return float2(screenPos.x, screenPos.y) * 0.5 + 0.5;
			}

			int compareWithDepth(float3 vpos, out bool isInside, out float outputDepth)
			{
				float2 uv = PosToUV(vpos);
				float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
				depth = LinearEyeDepth(depth, _ZBufferParams);
				isInside = uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1;
				outputDepth = depth;
				return -vpos.z >= depth;
			}

			bool rayTrace(float3 o, float3 r, out float3 hitp)
			{
				float3 start = o;
				float3 end = o;
				float outputDepth;
				float stepSize = 0.15;//MAX_TRACE_DIS / MAX_IT_COUNT;

				UNITY_LOOP
					for (int i = 1; i <= MAX_IT_COUNT; ++i)
					{
						end = o + r * stepSize * i;
						if (length(end - start) > MAX_TRACE_DIS)
							return false;

						bool isInside = true;
						int diff = compareWithDepth(end, isInside, outputDepth);
						if (isInside)
						{
							if (abs(outputDepth - (-1 * end.z)) < 0.1)
							{
								hitp = end;
								return true;
							}
						}
						else
						{
							return false;
						}
					}
				return false;
			}

            float4 frag (v2f i) : SV_Target
            {
				float4 screenPos = i.positionCS;
			/*	float4 screenPos = TransformObjectToHClip(i.positionOS);
				screenPos.xyz /= screenPos.w;
				screenPos.xy = screenPos.xy * 0.5 + 0.5;
				screenPos.y = 1 - screenPos.y;
				
				float4 cameraRay = float4(screenPos.xy * 2.0 - 1.0, 1, 1.0);
				cameraRay = mul(unity_CameraInvProjection, cameraRay);
				i.vsRay = cameraRay / cameraRay.w;*/

				//世界空间射线
				/*float3 normalWS = TransformObjectToWorldDir(float3(0, 1, 0));
				

				float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);
				float3 reflectDir = reflect(viewDir, normalWS);
				float3 reflectPos = i.positionWS;

				float3 col = RayTracePixel(reflectPos, reflectDir);*/

				float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, screenPos.xy);
				depth = Linear01Depth(depth, _ZBufferParams);
			

				float3 wsNormal = float3(0, 1, 0);    //世界坐标系下的法线
				float3 vsNormal = (TransformWorldToViewDir(wsNormal));    //将转换到view space

				float3 vsRayOrigin = (i.vsRay) * depth;
				float3 reflectionDir = normalize(reflect(vsRayOrigin, vsNormal));

				float3 hitp = 0;
				float3 col = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, screenPos.xy).xyz;
				if (rayTrace(vsRayOrigin, reflectionDir, hitp))
				{
					float2 tuv = PosToUV(hitp);
					float3 hitCol = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, tuv).xyz;

					col += hitCol;
				}
				else {
					float3 viewPosToWorld = normalize(i.positionOS.xyz - _WorldSpaceCameraPos.xyz);
					float3 reflectDir = reflect(viewPosToWorld, wsNormal);
					col = SAMPLE_TEXTURECUBE(_SkyBoxCubeMap, sampler_SkyBoxCubeMap, reflectDir);
				}

                return float4(col, 1);
            }
            ENDHLSL
        }
    }
}
