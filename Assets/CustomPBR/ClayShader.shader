Shader "Custom/ClayShader"
{
    Properties
    {
        _BumpTexture("Texture", 2D) = "white" {}
        _LayerOneRoughness("LayerOneRoughness", Range(0,1)) = 0.5
        _LayerOneThickness("LayerOneThickness", Float) = 0.5
        _LayerTwoRoughness("LayerTwoRoughness", Range(0,1)) = 0.5
        _BaseReflectivity("Base Reflectivity", Range(0,1)) = 0.5
        _FingerprintStrength("Fingerprint Strength", Range(0,1)) = 0.5
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

            sampler2D _BumpTexture;
            float4 _BumpTexture_ST;

            float4 _Color;
            float _BaseReflectivity;
            float _LayerOneRoughness;
            float _LayerOneThickness;
            float _LayerTwoRoughness;
            float _FingerprintStrength;

            static const float PI = 3.14159265f;
            static const float3 ABSORBTION_COEFFICIENT = float3(0.0035f, 0.0004f, 0.0f);

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

            float3 TorranceSparrow(float NdotL, float NdotV, float NdotH, float VdotH, float3 normal, float3 reflectivity, float roughness, out float3 fresnel, out float geometry)
            {
                float tg = sqrt(1 - NdotH * NdotH) / NdotH;
                float distribution = 1 / (roughness * roughness * NdotH * NdotH * NdotH * NdotH) * exp(-(tg / roughness) * (tg / roughness));

                float q = 1 - VdotH;
                fresnel = ((normal - 1) * (normal - 1) + 4 * normal * q * q * q * q * q + reflectivity * reflectivity) / ((normal + 1) * (normal + 1) + reflectivity * reflectivity);
                
                geometry = min(1, min(NdotV * (2 * NdotH) / VdotH, NdotL * (2 * NdotH) / VdotH));
                
                return fresnel * distribution * geometry / (4 * NdotV);
            }

            float3 CalculatePBRLighting(Input input)
            {
                float3 surfaceNormal = normalize(input.Normal);
                float3 viewDirection = normalize(input.ViewDirection);
                float3 lightDirection = normalize(input.LightDirection);

                float3 halfwayVector = normalize(viewDirection + lightDirection);

                float3 R = reflect(-viewDirection, surfaceNormal);
                float3 refractedLightDirection = -refract(lightDirection, surfaceNormal, 1 / 1.3333f);
                float3 refractedViewDirection = -refract(viewDirection, surfaceNormal, 1 / 1.3333f);
                float3 refractedHalfwayVector = normalize(refractedViewDirection + refractedLightDirection);

                float NdotL = dot(surfaceNormal, lightDirection);
                float NdotH = dot(surfaceNormal, halfwayVector);
                float NdotV = dot(surfaceNormal, viewDirection);
                float VdotH = dot(viewDirection, halfwayVector);
                float NdotLr = dot(surfaceNormal, refractedLightDirection);
                float NdotHr = dot(surfaceNormal, refractedHalfwayVector);
                float NdotVr = dot(surfaceNormal, refractedViewDirection);
                float VrdotHr = dot(refractedViewDirection, refractedHalfwayVector);

                float3 layerOneFresnel, layerTwoFresnel;
                float layerOneGeometry, layerTwoGeometry;

                float3 layerOneFr = TorranceSparrow(NdotL, NdotV, NdotH, VdotH, _BaseReflectivity, _BaseReflectivity, _LayerOneRoughness, layerOneFresnel, layerOneGeometry);
                float3 layerTwoFr = TorranceSparrow(NdotLr, NdotVr, NdotHr, VrdotHr, _BaseReflectivity, _BaseReflectivity, max(_LayerTwoRoughness, _LayerOneRoughness), layerTwoFresnel, layerTwoGeometry);
                
                layerTwoFr += (1 - layerTwoFresnel) * max(NdotL, 0) * input.Albedo;

                float3 layerOneDiffuse = 1 - layerOneFresnel;
                float3 layerOneTotalReflection = (1 - layerOneGeometry) + layerOneDiffuse * layerOneGeometry;

                float absorptionPathLength = _LayerOneThickness * (1 / NdotLr + 1 / NdotVr);
                float3 absorption = exp(-ABSORBTION_COEFFICIENT * absorptionPathLength);

                float3 ambient = UNITY_LIGHTMODEL_AMBIENT * input.Albedo;

                float3 finalColour = input.Albedo * (layerOneFr + layerOneDiffuse * layerTwoFr * absorption * layerOneTotalReflection);

                float2 newUV = TRANSFORM_TEX(input.UV, _BumpTexture);
                fixed4 col = tex2D(_BumpTexture, newUV) * _FingerprintStrength;
                finalColour += col;

                return float4(finalColour + ambient, 1);
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