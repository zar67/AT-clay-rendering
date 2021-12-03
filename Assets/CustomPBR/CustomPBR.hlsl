#ifndef CUSTOM_PBR_INCLUDED
#define CUSTOM_PBR_INCLUDED

struct PBRData
{
    float3 WorldPosition;
    float3 WorldNormal;
    float3 WorldViewDirection;
    
    float3 Albedo;
    float Smoothness;
};

float DistributionGGX(float3 surfaceNormal, float3 halfwayVector, float roughness)
{
    float roughnessSquared = roughness * roughness;
    float roughnessSquaredSquared = roughnessSquared * roughnessSquared;
    float normalDotHalfway = dot(surfaceNormal, halfwayVector);
    float normalDotHalfwaySquared = normalDotHalfway * normalDotHalfway;
    
    float denominator = normalDotHalfwaySquared * (roughnessSquaredSquared - 1) + 1;
    denominator = 3.14159265359 * denominator * denominator;
    
    return roughnessSquaredSquared / max(denominator, 0.0000001);
}

float FresnelSchlick(float3 halfwayVector, float3 viewDirection, float baseReflectivity)
{
    float inverseReflectivity = 1 - baseReflectivity;
    return baseReflectivity + (inverseReflectivity * pow(1.0 - dot(halfwayVector, viewDirection), 5));
}

float GeometrySchlickGGX(float3 surfaceNormal, float3 viewDirection, float3 lightDirection, float roughness)
{
    float remappedRoughness = ((roughness + 1) * (roughness + 1)) / 8;
    float normalDotView = dot(surfaceNormal, viewDirection);
    float normalDotLightDirection = dot(surfaceNormal, lightDirection);
    float inverseRoughness = 1 - remappedRoughness;
    
    return normalDotView / (normalDotView * inverseRoughness + remappedRoughness);
}

#ifndef SHADERGRAPH_PREVIEW
float3 PBRCalculation(PBRData data, Light light)
{
    float3 H = normalize(data.WorldViewDirection + light.direction);
    
    float3 radiance = light.color * light.distanceAttenuation;
    
    float D = DistributionGGX(data.WorldNormal, H, data.Smoothness);
    float G = GeometrySchlickGGX(data.WorldNormal, data.WorldViewDirection, light.direction, data.Smoothness);
    float F = FresnelSchlick(H, data.WorldViewDirection, 0.02);
    
    float specular = D * F * G;
    specular /= 4 * dot(data.WorldViewDirection, data.WorldNormal * dot(light.direction, data.WorldNormal));

    float diffuseAmount = 1 - F;
    
    return ((diffuseAmount * (data.Albedo / 3.14159265359)) + specular) * radiance * dot(data.WorldNormal, light.direction);
}
#endif

float3 CalculateCustomPBR(PBRData data)
{
    float3 colour = data.Albedo;
#ifndef SHADERGRAPH_PREVIEW
    Light mainLight = GetMainLight();
    
    float3 Lo = PBRCalculation(data, mainLight);
   
    uint numAdditionalLights = GetAdditionalLightsCount();
    for (uint index = 0; index < numAdditionalLights; index++ )
    {
        Light light = GetAdditionalLight(index, data.WorldPosition, 1);
        Lo += PBRCalculation(data, light);
    }
    
    float3 ambient = float3(0.03, 0.03, 0.03) * data.Albedo;
    colour = ambient + Lo;
    
    colour = colour / (colour + float3(1.0, 1.0, 1.0));
    colour = pow(colour, float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2));
    
#endif
    return colour;
}

void CalculateCustomPBR_float(float3 worldPosition, float3 worldNormal, float3 worldViewDirection, float3 albedo, float smoothness, out float3 colour)
{
    PBRData data;
    data.WorldPosition = worldPosition;
    data.WorldNormal = worldNormal;
    data.WorldViewDirection = worldViewDirection;
    data.Albedo = albedo;
    data.Smoothness = smoothness;
    
    colour = CalculateCustomPBR(data);
}

#endif