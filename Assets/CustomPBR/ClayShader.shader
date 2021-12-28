Shader "Custom/ClayShader"
{
    Properties
    {
        _LayerOneRoughness("LayerOneRoughness", Range(0,1)) = 0.5
        _LayerOneThickness("LayerOneThickness", Range(0,1)) = 0.5
        _LayerTwoRoughness("LayerTwoRoughness", Range(0,1)) = 0.5
        _BaseReflectivity("Base Reflectivity", Range(0,1)) = 0.5
        _Color("Color", Color) = (1,0.2,0,1)
    }
        SubShader
    {
        Pass
        {
            Tags {"LightMode" = "ForwardBase"}

            CGPROGRAM
            #pragma vertex VertexFunction
            #pragma fragment FragmentFunction

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            struct Input
            {
                float2 UV : TEXCOORD0;
                fixed4 Albedo : ALBEDO;
                float4 Position : SV_POSITION;
                float3 Normal : NORMAL;
                float3 ViewDirection : VIEW_DIRECTION;
                float3 LightDirection : LIGHT_DIRECTION;
            };

            float4 _Color;
            float _BaseReflectivity;
            float _LayerOneRoughness;
            float _LayerOneThickness;
            float _LayerTwoRoughness;

            static const float PI = 3.14159265f;

            Input VertexFunction(appdata_base data)
            {
                Input output;

                output.Position = UnityObjectToClipPos(data.vertex);
                output.UV = data.texcoord;

                float3 worldPos = output.Position.xyz;
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - worldPos.xyz);
                output.ViewDirection = viewDir;

                float3 lightDir = _WorldSpaceLightPos0.xyz;
                output.LightDirection = lightDir;

                half3 worldNormal = UnityObjectToWorldNormal(data.normal);
                output.Normal = worldNormal;

                output.Albedo = _Color;

                return output;
            }

            float DistributionGGX(float3 surfaceNormal, float3 halfwayVector, float roughness)
            {
                float roughnessSquared = roughness * roughness;
                float normalDotHalfway = max(0.0f, dot(surfaceNormal, halfwayVector));
                float normalDotHalfwaySquared = normalDotHalfway * normalDotHalfway;

                float denominator = normalDotHalfwaySquared * (roughnessSquared - 1.0f) + 1.0f;
                denominator = PI * denominator * denominator;

                return roughnessSquared / max(denominator, 0.0000001f);
            }

            float GeometrySchlickGGX(float3 surfaceNormal, float3 lightDirection, float3 viewDirection, float roughness)
            {
                float remappedRoughness = ((roughness + 1.0f) * (roughness + 1.0f)) / 8.0f;
                float inverseRoughness = 1.0f - remappedRoughness;

                float normalDotView = max(0.0f, dot(surfaceNormal, viewDirection));
                float normalDotLight = max(0.0f, dot(surfaceNormal, lightDirection));

                float GGX1 = normalDotView / (normalDotView * inverseRoughness + remappedRoughness);
                float GGX2 = normalDotLight / (normalDotLight * inverseRoughness + remappedRoughness);

                return GGX1 * GGX2;
            }

            float FresnelSchlick(float3 halfwayVector, float3 viewDirection, float baseReflectivity)
            {
                float inverseReflectivity = 1.0f - baseReflectivity;
                float halfwayDotNormal = max(0.0f, dot(halfwayVector, viewDirection));
                return baseReflectivity + (inverseReflectivity * pow(1.0f - halfwayDotNormal, 5));
            }

            float3 CalculateRadiance(float3 lightDirection, float3 position, float3 albedo)
            {
                float distance = length(lightDirection - position);
                float attenuation = 1.0f / distance * distance;
                return albedo * attenuation;
            }

            float3 TorranceSparrow(float NdotL, float NdotV, float NdotH, float VdotH, float3 n, float3 k, float m, out float3 F, out float G)
            {
                float D;
                float tg = sqrt(1 - NdotH * NdotH) / NdotH;
                D = 1 / (m * m * NdotH * NdotH * NdotH * NdotH) * exp(-(tg / m) * (tg / m));

                float q = 1 - VdotH;
                F = ((n - 1) * (n - 1) + 4 * n * q * q * q * q * q + k * k) / ((n + 1) * (n + 1) + k * k);
                
                G = min(1, min(NdotV * (2 * NdotH) / VdotH, NdotL * (2 * NdotH) / VdotH));
                
                return F * D * G / (4 * NdotV);
            }

            float3 CalculatePBRLighting(Input input)
            {
                float3 N = normalize(input.Normal);
                float3 V = normalize(input.ViewDirection);
                float3 L = normalize(input.LightDirection);

                float3 H = normalize(V + L);

                float3 R = reflect(-V, N);
                float3 Lr = -refract(L, N, 1 / 1.3333f);
                float3 Vr = -refract(V, N, 1 / 1.3333f);
                float3 Hr = normalize(Vr + Lr);

                float NdotL = dot(N, L);
                float NdotH = dot(N, H);
                float NdotV = dot(N, V);
                float VdotH = dot(V, H);
                float NdotLr = dot(N, Lr);
                float NdotHr = dot(N, Hr);
                float NdotVr = dot(N, Vr);
                float VrdotHr = dot(Vr, Hr);

                float3 F1, F2;
                float G1, G2;

                float3 f1 = TorranceSparrow(NdotL, NdotV, NdotH, VdotH, _BaseReflectivity, _BaseReflectivity, _LayerOneRoughness, F1, G1);
                float3 f2 = TorranceSparrow(NdotLr, NdotVr, NdotHr, VrdotHr, _BaseReflectivity, _BaseReflectivity, max(_LayerTwoRoughness, _LayerOneRoughness), F2, G2);
                
                f2 += (1 - F2) * max(NdotL, 0) * input.Albedo;

                float3 T12 = 1 - F1;
                float3 T21 = T12;
                float3 t = (1 - G1) + T21 * G1;

                float l = _LayerOneThickness * (1 / NdotLr + 1 / NdotVr);
                float3 sigma = float3(0.0035f, 0.0004f, 0.0f);
                float3 a = exp(-sigma * l);

                float3 envCol = UNITY_LIGHTMODEL_AMBIENT * input.Albedo;

                float3 fr = input.Albedo * (f1 + T12 * f2 * a * t);
                return float4(fr + envCol, 1);
            }

            float4 FragmentFunction(Input input) : SV_Target
            {
                float3 mainColour = CalculatePBRLighting(input);

                return float4(mainColour, 1.0f);
            }
            ENDCG
          }
    }
        Fallback "Diffuse"
}