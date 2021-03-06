#extension GL_EXT_shader_texture_lod: enable
#extension GL_OES_standard_derivatives : enable

precision highp float;

#define PI 3.1415926

#define LIGHT_MAX_COUNT 16
#define LIGHT_TYPE_NULL 1
#define LIGHT_TYPE_AMBIENT 2
#define LIGHT_TYPE_DIRECTIONAL 3
#define LIGHT_TYPE_POINT 4

#define PI 3.1415926

uniform vec3 uCameraPosition;

uniform int uLightType[LIGHT_MAX_COUNT];
uniform vec3 uLightColor[LIGHT_MAX_COUNT];
uniform float uLightIntensity[LIGHT_MAX_COUNT];
uniform vec3 uLightPosition[LIGHT_MAX_COUNT];

uniform vec3 uMaterialAlbedoColor;
uniform float uMaterialRoughness;
uniform float uMaterialMetallic;

uniform samplerCube uSpecularMap;
uniform samplerCube uDiffuseMap;

uniform sampler2D uBRDFLUT;

varying vec2 vUV;
varying vec3 vNormal;
varying vec3 vPosition;

struct PBRInfo
{
    vec3 N;
    vec3 V;
    vec3 baseColor;
    float roughness;
    float metallic;
};

struct PBRLightInfo
{
    vec3 color;
    vec3 L;
    float intensity;
};

vec3 L_direct(PBRInfo info, PBRLightInfo light){
    
    float NDotL = clamp(dot(info.N, light.L), 0.0, 1.0);
    float NDotV = clamp(dot(info.N, info.V), 0.0, 1.0);

    vec3 F0 = mix(vec3(0.04), info.baseColor, info.metallic);
    vec3 ks = F0 + (1.0 - F0) * pow(1.0 - NDotV, 5.0);
    vec3 kd = 1.0 - ks;
    kd *= 1.0 - info.metallic;

    vec3 diffuse = kd * info.baseColor / PI;

    vec3 H = normalize(light.L + info.V);
    float NDotH = clamp(dot(info.N, H), 0.0, 1.0);

    float roughness = info.roughness;

    float D = (roughness * roughness) / max(0.001, PI * pow(NDotH * NDotH * (roughness * roughness - 1.0) + 1.0 , 2.0));
    
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float G1 = NDotV / max(0.001, NDotV * (1.0 - k) + k);
    float G2 = NDotL / max(0.001, NDotL * (1.0 - k) + k);
    float G = G1 * G2;

    vec3 specular = vec3(D * G1 * G2) * ks / max(0.001, NDotL * NDotV * PI * 4.0);

    vec3 Li = light.color * light.intensity;

    return (diffuse + specular) * NDotL * Li;
}

vec3 L_env(PBRInfo info){

    float NdotV = clamp(dot(info.N, info.V), 0.0, 1.0);

    vec3 diffuseLight = textureCube(uDiffuseMap, info.N).rgb;
    vec3 diffuseColor = info.baseColor * ( 1.0 - 0.04 ) * ( 1.0 - info.metallic );
    vec3 diffuse = diffuseLight * diffuseColor;

    vec3 R = -normalize(reflect(info.V, info.N));
    vec3 specularLight = textureCubeLodEXT(uSpecularMap, R, info.roughness * 8.0).rgb;

    vec3 specularColor = mix(vec3(0.04), info.baseColor, info.metallic);

    vec2 brdf = texture2D(uBRDFLUT, vec2(NdotV, 1.0 - info.roughness)).rg;

    vec3 specular = specularLight * (specularColor * brdf.x + brdf.y);
    
    return diffuse + specular;
}

vec3 L(){

    vec3 fragColor = vec3(0.0, 0.0, 0.0);

    PBRInfo pbrInputs = PBRInfo(
        normalize(vNormal),
        normalize(uCameraPosition - vPosition),
        uMaterialAlbedoColor,
        uMaterialRoughness * uMaterialRoughness,
        uMaterialMetallic
    );

    for(int i = 0; i < LIGHT_MAX_COUNT; i++){

        int type = uLightType[i];

        if(type == LIGHT_TYPE_DIRECTIONAL){

            fragColor += L_direct(
                pbrInputs,
                PBRLightInfo(
                    uLightColor[i],
                    normalize(uLightPosition[i]),
                    uLightIntensity[i]
                )
            );
        }else if(type == LIGHT_TYPE_POINT){

            float dir = length(uLightPosition[i] - vPosition);

            fragColor += L_direct(
                pbrInputs,
                PBRLightInfo(
                    uLightColor[i],
                    normalize(uLightPosition[i]-vPosition),
                    uLightIntensity[i] / (dir * dir)
                )
            );
        }
    }

    fragColor += L_env(pbrInputs);

    fragColor = pow(fragColor, vec3(1.0/2.2));

    return fragColor;
}


void main() {

    gl_FragColor = vec4(L(), 1.0);
    
}