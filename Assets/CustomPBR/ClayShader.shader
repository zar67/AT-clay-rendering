Shader "Custom/ClayShader"
{
    Properties
    {
        [Header(Properties)]
        _BaseColour("Base Colour", 2D) = "white" {}
        _F0("Base Reflectivity", Range(0,1)) = 0.5

        [Header(Top Layer)]
        _L1Roughness("Roughness", Range(0,1)) = 0.5
        _L1Thickness("Thickness", Range(0, 10)) = 0.5

        [Header(Bottom Layer)]
        _L2Roughness("Roughness", Range(0,1)) = 0.5

        [Header(Fingerprints)]
        _FingerprintTexture("Fingerprint Texture", 2D) = "white" {}
        _FingerprintStrength("Fingerprint Strength", Range(0,1)) = 0.5

        [Header(Bumps and Indents)]
        _BumpMap("Bumpmap", 2D) = "bump" {}
        _BumpStrength("Bump Strength", Range(0,1)) = 0.5
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
                float4 Position : SV_POSITION;
                float3 Normal : NORMAL;
                float3 ViewDirection : VIEW_DIRECTION;
                float3 LightDirection : LIGHT_DIRECTION;
            };

            sampler2D _BaseColour;
            float4 _BaseColour_ST;

            float _F0;

            float _L1Roughness;
            float _L1Thickness;

            float _L2Roughness;

            sampler2D _FingerprintTexture;
            float4 _FingerprintTexture_ST;
            float _FingerprintStrength;

            sampler2D _BumpMap;
            float4 _BumpMap_ST;
            half _BumpStrength;

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

                return output;
            }

            float3 Fresnel(float VdotH, float3 normal, float3 reflectivity, float roughness)
            {
                float q = 1 - VdotH;
                return ((normal - 1) * (normal - 1) + 4 * normal * q * q * q * q * q + reflectivity * reflectivity) / ((normal + 1) * (normal + 1) + reflectivity * reflectivity);
            }

            float Geometry(float NdotV, float NdotH, float VdotH, float NdotL)
            {
                return  min(1, min(NdotV * (2 * NdotH) / VdotH, NdotL * (2 * NdotH) / VdotH));
            }

            float3 TorranceSparrow(float NdotL, float NdotV, float NdotH, float VdotH, float3 normal, float3 reflectivity, float roughness)
            {
                float tg = sqrt(1 - NdotH * NdotH) / NdotH;
                float distribution = 1 / (roughness * roughness * NdotH * NdotH * NdotH * NdotH) * exp(-(tg / roughness) * (tg / roughness));

                float q = 1 - VdotH;
                float3 fresnel = Fresnel(VdotH, normal, reflectivity, roughness);

                float geometry = Geometry(NdotV, NdotH, VdotH, NdotL);
                
                return fresnel * distribution * geometry / (4 * NdotV);
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

                // Base Colour
                float2 baseColourUV = TRANSFORM_TEX(input.UV, _BaseColour);
                fixed4 baseColour = tex2D(_BaseColour, baseColourUV);

                // Top Layer
                float3 f1 = Fresnel(VdotH, _F0, _F0, _L1Roughness);
                float g1 = Geometry(NdotV, NdotH, VdotH, NdotL);
                float3 fr1 = TorranceSparrow(NdotL, NdotV, NdotH, VdotH, _F0, _F0, _L1Roughness);

                // Bottom Layer
                float3 f2 = Fresnel(VrdotHr, _F0, _F0, _L2Roughness);
                float g2 = Geometry(NdotVr, NdotHr, VrdotHr, NdotLr);
                float3 fr2 = TorranceSparrow(NdotLr, NdotVr, NdotHr, VrdotHr, _F0, _F0, _L2Roughness);
                fr2 += (1 - f2) * max(NdotL, 0) * baseColour;

                // Frensel Transmission and Internal Reflection
                float3 t12 = 1 - f1;
                float t21 = t12;
                float3 t = (1 - g1) + t21 * g1;

                // Absorption
                float l = _L1Thickness * (1 / NdotLr + 1 / NdotVr);
                float3 a = exp(-ABSORBTION_COEFFICIENT * l);

                float3 finalColour = baseColour * (fr1 + t12 * fr2 * a * t);

                // Fingerprints
                float2 newUV = TRANSFORM_TEX(input.UV, _FingerprintTexture);
                fixed4 fingerprints = tex2D(_FingerprintTexture, newUV) * _FingerprintStrength;
                finalColour += fingerprints;

                // Ambient
                float3 ambient = UNITY_LIGHTMODEL_AMBIENT;
                finalColour += ambient;

                return float4(finalColour, 1);
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