Shader "Custom/ClayShader"
{
    Properties
    {
        _Roughness("Roughness", Range(0,1)) = 0.5
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
            float _Roughness;

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

            float FresnelSchlick(float3 halfwayVector, float3 surfaceNormal, float baseReflectivity)
            {
                float inverseReflectivity = 1.0f - baseReflectivity;
                float halfwayDotNormal = max(0.0f, dot(halfwayVector, surfaceNormal));
                return baseReflectivity + (inverseReflectivity * pow(1.0f - halfwayDotNormal, 5));
            }

            float3 CalculatePBRLighting(Input input)
            {
                float3 N = normalize(input.Normal);
                float3 V = normalize(input.ViewDirection);
                float3 L = normalize(input.LightDirection);

                float3 H = normalize(L + V);

                float3 F0 = float3(_BaseReflectivity, _BaseReflectivity, _BaseReflectivity);

                float distance = length(input.LightDirection - input.Position);
                float attenuation = 1.0f / distance * distance;
                float3 radiance = input.Albedo * attenuation;

                float D = DistributionGGX(N, normalize(L + N), _Roughness);
                float G = GeometrySchlickGGX(N, L, V, _Roughness);
                float3 F = FresnelSchlick(H, N, F0);

                float specular = D * F * G;
                specular /= 4.0f * dot(V, N) * dot(L, N);

                float diffuseAmount = 1.0f - F;

                float3 diffuse = diffuseAmount * input.Albedo / PI;

                float3 ambient = UNITY_LIGHTMODEL_AMBIENT * input.Albedo;

                return ambient + (diffuseAmount + specular) * radiance * dot(N, L);
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