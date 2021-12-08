#ifndef CUSTOM_PBR_INCLUDED
#define CUSTOM_PBR_INCLUDED

static const float PI = 3.14159265f;

struct PBRData
{
    float3 AmbientColour;
    
    float3 WorldPosition;
    float3 WorldNormal;
    float3 WorldViewDirection;
    
    float3 Albedo;
    float Roughness;
    float BaseReflectivity;
};

float DistributionGGX(float3 surfaceNormal, float3 halfwayVector, float roughness)
{
    float roughnessSquared = roughness * roughness;
    float normalDotHalfway = dot(surfaceNormal, halfwayVector);
    float normalDotHalfwaySquared = normalDotHalfway * normalDotHalfway;
    
    float denominator = normalDotHalfwaySquared * (roughnessSquared - 1) + 1;
    denominator = PI * denominator * denominator;
    
    return roughnessSquared / max(denominator, 0.0000001);
}

float FresnelSchlick(float3 halfwayVector, float3 viewDirection, float baseReflectivity)
{
    float inverseReflectivity = 1 - baseReflectivity;
    return baseReflectivity + (inverseReflectivity * pow(1.0 - dot(halfwayVector, viewDirection), 5));
}

float GeometrySchlickGGX(float3 surfaceNormal, float3 viewDirection, float3 lightDirection, float roughness)
{
    float remappedRoughness = ((roughness + 1.0) * (roughness + 1.0)) / 8.0;
    float normalDotView = dot(surfaceNormal, viewDirection);
    float normalDotLightDirection = dot(surfaceNormal, lightDirection);
    float inverseRoughness = 1 - remappedRoughness;
    
    return normalDotView / (normalDotView * inverseRoughness + remappedRoughness);
}

float3 PBRCalculation(PBRData data, float3 lightDirection, float3 lightColour, float lightDistanceAttenuation)
{
    float3 H = normalize(data.WorldViewDirection + lightDirection);
    
    float3 radiance = lightColour * lightDistanceAttenuation;
    
    float D = DistributionGGX(data.WorldNormal, H, data.Roughness);
    float G = GeometrySchlickGGX(data.WorldNormal, data.WorldViewDirection, lightDirection, data.Roughness);
    float F = FresnelSchlick(H, data.WorldViewDirection, data.BaseReflectivity);
    
    float specular = D * F * G;
    specular /= 4 * dot(data.WorldViewDirection, data.WorldNormal * dot(lightDirection, data.WorldNormal));

    float diffuseAmount = 1 - F;
    
    return ((diffuseAmount * (data.Albedo / PI)) + specular) * radiance * dot(data.WorldNormal, lightDirection);
}

float3 CalculateCustomPBR(PBRData data)
{
    float3 colour = data.Albedo;
#ifndef SHADERGRAPH_PREVIEW
    Light mainLight = GetMainLight();
    
    float3 Lo = PBRCalculation(data, mainLight.direction, mainLight.color, mainLight.distanceAttenuation);
   
    uint numAdditionalLights = GetAdditionalLightsCount();
    for (uint index = 0; index < numAdditionalLights; index++ )
    {
        Light light = GetAdditionalLight(index, data.WorldPosition, 1);
        Lo += PBRCalculation(data, light.direction, light.color, light.distanceAttenuation);
    }
    
    float3 ambient = data.AmbientColour * data.Albedo;
    colour = ambient + Lo;
    
#endif
    return colour;
}

void CalculateCustomPBR_float(float3 ambientColour, float3 worldPosition, float3 worldNormal, float3 worldViewDirection, float3 albedo, float smoothness, out float3 colour)
{
    PBRData data;
    data.AmbientColour = ambientColour;
    data.WorldPosition = worldPosition;
    data.WorldNormal = worldNormal;
    data.WorldViewDirection = worldViewDirection;
    data.Albedo = albedo;
    data.Roughness = 1 - smoothness;
    data.BaseReflectivity = 0.04;
    
    colour = CalculateCustomPBR(data);
}

#endif