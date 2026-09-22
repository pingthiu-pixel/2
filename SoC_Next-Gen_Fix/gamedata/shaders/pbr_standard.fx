// ============================================================================
// SoC Next-Gen Fix - PBR Shaders
// Physically Based Rendering шейдеры для реалистичной графики
// ============================================================================

// ----------------------------------------------------------------------------
// Вершинный шейдер: PBR Standard
// ----------------------------------------------------------------------------

vs_pbr_standard
{
    // Входные данные
    input vertex
    {
        float3 position : POSITION;
        float3 normal   : NORMAL;
        float2 texcoord : TEXCOORD0;
        float3 tangent  : TANGENT;
        float3 binormal : BINORMAL;
    };

    // Выходные данные для пиксельного шейдера
    output pixel
    {
        float4 position : POSITION;
        float2 texcoord : TEXCOORD0;
        float3 worldPos : TEXCOORD1;
        float3 worldNormal : TEXCOORD2;
        float3 worldTangent : TEXCOORD3;
        float3 worldBinormal : TEXCOORD4;
        float3 viewDir : TEXCOORD5;
    };

    // Константы
    cbuffer TransformBuffer
    {
        float4x4 worldMatrix;
        float4x4 viewMatrix;
        float4x4 projectionMatrix;
    };

    void main(in vertex vin, out pixel pout)
    {
        // Преобразование позиции в мировое пространство
        float4 worldPos = mul(float4(vin.position, 1.0f), worldMatrix);
        pout.worldPos = worldPos.xyz;

        // Преобразование нормали в мировое пространство
        pout.worldNormal = normalize(mul(vin.normal, (float3x3)worldMatrix));

        // Преобразование касательных в мировое пространство
        pout.worldTangent = normalize(mul(vin.tangent, (float3x3)worldMatrix));
        pout.worldBinormal = normalize(mul(vin.binormal, (float3x3)worldMatrix));

        // Преобразование позиции в экранное пространство
        float4 viewPos = mul(worldPos, viewMatrix);
        pout.position = mul(viewPos, projectionMatrix);

        // Текстуры координаты
        pout.texcoord = vin.texcoord;

        // Направление взгляда
        pout.viewDir = normalize(cameraPosition - worldPos.xyz);
    }
}

// ----------------------------------------------------------------------------
// Пиксельный шейдер: PBR с картами нормалей и шероховатости
// ----------------------------------------------------------------------------

ps_pbr_standard
{
    // Входные данные от вершинного шейдера
    input pixel
    {
        float4 position : POSITION;
        float2 texcoord : TEXCOORD0;
        float3 worldPos : TEXCOORD1;
        float3 worldNormal : TEXCOORD2;
        float3 worldTangent : TEXCOORD3;
        float3 worldBinormal : TEXCOORD4;
        float3 viewDir : TEXCOORD5;
    };

    // Текстурные ресурсы
    texture2D albedoMap;
    texture2D normalMap;
    texture2D roughnessMap;
    texture2D metallicMap;
    texture2D aoMap;

    // Сэмплеры
    sampler_state sam_linear
    {
        Texture = <albedoMap>;
        MinFilter = LINEAR;
        MagFilter = LINEAR;
        MipFilter = LINEAR;
        AddressU = WRAP;
        AddressV = WRAP;
    };

    // Константы освещения
    cbuffer LightBuffer
    {
        float3 lightDirection;
        float3 lightColor;
        float lightIntensity;
        float3 ambientColor;
        float ambientIntensity;
    };

    // Константы материала
    cbuffer MaterialBuffer
    {
        float baseRoughness;
        float baseMetallic;
        float4 albedoTint;
    };

    // Выход
    output color
    {
        float4 result : COLOR0;
    };

    // ----------------------------------------------------------------------------
    // Вспомогательные функции PBR
    // ----------------------------------------------------------------------------

    // Функциция распределения микроповерхностей (Cook-Torrance)
    float DistributionGGX(float3 N, float3 H, float roughness)
    {
        float a = roughness * roughness;
        float a2 = a * a;
        float NdotH = max(dot(N, H), 0.0);
        float NdotH2 = NdotH * NdotH;

        float num = a2;
        float denom = (NdotH2 * (a2 - 1.0) + 1.0);
        denom = 3.14159 * denom * denom;

        return num / denom;
    }

    // Геометрическая функция затенения
    float GeometrySchlickGGX(float NdotV, float roughness)
    {
        float r = roughness + 1.0;
        float k = (r * r) / 8.0;

        float num = NdotV;
        float denom = NdotV * (1.0 - k) + k;

        return num / denom;
    }

    float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
    {
        float NdotV = max(dot(N, V), 0.0);
        float NdotL = max(dot(N, L), 0.0);
        float ggx2 = GeometrySchlickGGX(NdotV, roughness);
        float ggx1 = GeometrySchlickGGX(NdotL, roughness);

        return ggx1 * ggx2;
    }

    // Френелевское уравнение Шлика
    float3 FresnelSchlick(float cosTheta, float3 F0)
    {
        return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
    }

    // ----------------------------------------------------------------------------
    // Основная функция пиксельного шейдера
    // ----------------------------------------------------------------------------

    void main(in pixel pin, out color cout)
    {
        // Выборка текстур
        float4 albedo = tex2D(sam_linear, pin.texcoord) * albedoTint;
        float3 normalTS = tex2D(normalMap, pin.texcoord).xyz * 2.0 - 1.0;
        float roughness = tex2D(roughnessMap, pin.texcoord).r * baseRoughness;
        float metallic = tex2D(metallicMap, pin.texcoord).r * baseMetallic;
        float ao = tex2D(aoMap, pin.texcoord).r;

        // Построение матрицы TBN для карт нормалей
        float3x3 TBN = float3x3(
            normalize(pin.worldTangent),
            normalize(pin.worldBinormal),
            normalize(pin.worldNormal)
        );

        // Преобразование нормали из тангенциального пространства в мировое
        float3 N = normalize(mul(normalTS, TBN));

        // Направления света и взгляда
        float3 L = normalize(-lightDirection);
        float3 V = normalize(pin.viewDir);

        // Полунаправление (half vector)
        float3 H = normalize(V + L);

        // Углы
        float NdotL = max(dot(N, L), 0.0);
        float NdotV = max(dot(N, V), 0.0);
        float NdotH = max(dot(N, H), 0.0);
        float VdotH = max(dot(V, H), 0.0);

        // Базовый коэффициент отражения (F0)
        float3 F0 = float3(0.04, 0.04, 0.04);
        F0 = lerp(F0, albedo.rgb, metallic);

        // BRDF составляющие
        float3 F = FresnelSchlick(VdotH, F0);
        float D = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);

        // Specular отражение
        float3 numerator = D * G * F;
        float denominator = 4.0 * NdotV * NdotL + 0.0001;
        float3 specular = numerator / denominator;

        // Diffuse отражение (с учетом энергии)
        float3 kD = (1.0 - F) * (1.0 - metallic);
        float3 diffuse = kD * albedo.rgb / 3.14159;

        // Комбинирование specular и diffuse
        float3 lighting = (diffuse + specular) * lightColor * lightIntensity * NdotL;

        // Ambient освещение с AO
        float3 ambient = ambientColor * ambientIntensity * ao;
        lighting += ambient;

        // Tone mapping (Reinhard)
        lighting = lighting / (lighting + float3(1.0, 1.0, 1.0));

        // Gamma коррекция
        lighting = pow(lighting, float3(1.0/2.2, 1.0/2.2, 1.0/2.2));

        cout.result = float4(lighting, albedo.a);
    }
}

// ============================================================================
// Шейдер: God Rays (Лучи света)
// ============================================================================

vs_godrays
{
    input vertex
    {
        float4 position : POSITION;
        float2 texcoord : TEXCOORD0;
    };

    output pixel
    {
        float4 position : POSITION;
        float2 texcoord : TEXCOORD0;
        float4 screenPos : TEXCOORD1;
    };

    cbuffer MatrixBuffer
    {
        float4x4 worldViewProj;
    };

    void main(in vertex vin, out pixel pout)
    {
        pout.position = mul(vin.position, worldViewProj);
        pout.texcoord = vin.texcoord;
        pout.screenPos = pout.position;
    }
}

ps_godrays
{
    input pixel
    {
        float4 position : POSITION;
        float2 texcoord : TEXCOORD0;
        float4 screenPos : TEXCOORD1;
    };

    texture2D depthTexture;
    texture2D lightTexture;

    sampler_state sam_depth
    {
        Texture = <depthTexture>;
        MinFilter = LINEAR;
        MagFilter = LINEAR;
        MipFilter = NONE;
        AddressU = CLAMP;
        AddressV = CLAMP;
    };

    cbuffer GodRayBuffer
    {
        float2 lightScreenPos;
        float exposure;
        float decay;
        float density;
        float weight;
        int samples;
    };

    output color
    {
        float4 result : COLOR0;
    };

    void main(in pixel pin, out color cout)
    {
        // Вектор от текущего пикселя к источнику света
        float2 deltaTexCoord = (pin.texcoord - lightScreenPos);
        deltaTexCoord *= 1.0 / float(samples) * density;

        float illumination = 0.0;
        float2 currentTexCoord = pin.texcoord;
        float sampleWeight = 1.0;

        // Accumulation samples along the ray
        for (int i = 0; i < samples; i++)
        {
            currentTexCoord -= deltaTexCoord;
            
            // Проверка границ
            if (currentTexCoord.x < 0.0 || currentTexCoord.x > 1.0 ||
                currentTexCoord.y < 0.0 || currentTexCoord.y > 1.0)
                break;

            float sample = tex2D(sam_depth, currentTexCoord).r;
            illumination += sample * sampleWeight;
            
            sampleWeight *= decay;
        }

        illumination *= exposure;

        cout.result = float4(illumination, illumination, illumination, 1.0);
    }
}

// ============================================================================
// Шейдер: Wet Surfaces (Мокрые поверхности)
// ============================================================================

ps_wet_surface
{
    input pixel
    {
        float4 position : POSITION;
        float2 texcoord : TEXCOORD0;
        float3 worldNormal : TEXCOORD1;
    };

    texture2D baseTexture;
    texture2D rainMask;

    sampler_state sam_base
    {
        Texture = <baseTexture>;
        MinFilter = LINEAR;
        MagFilter = LINEAR;
        MipFilter = LINEAR;
    };

    cbuffer WetBuffer
    {
        float wetIntensity;
        float3 rainDirection;
        float time;
    };

    output color
    {
        float4 result : COLOR0;
    };

    void main(in pixel pin, out color cout)
    {
        // Базовая текстура
        float4 baseColor = tex2D(sam_base, pin.texcoord);

        // Маска дождя
        float rainMask = tex2D(rainMask, pin.texcoord).r;

        // Эффект капель на поверхности
        float dropPattern = sin(pin.texcoord.x * 50.0 + time) * 
                           cos(pin.texcoord.y * 50.0 + time);
        dropPattern = saturate(dropPattern * 0.5 + 0.5);

        // Усиление контраста для мокрых поверхностей
        float3 wetColor = baseColor.rgb * (1.0 - wetIntensity * 0.3);
        wetColor += wetIntensity * 0.2; // Specular boost

        // Смешивание с эффектом капель
        float3 finalColor = lerp(baseColor.rgb, wetColor, rainMask * wetIntensity);

        // Добавление бликов от капель
        float specularHighlight = dropPattern * rainMask * wetIntensity * 0.5;
        finalColor += specularHighlight;

        cout.result = float4(finalColor, baseColor.a);
    }
}

// ============================================================================
// Конец PBR шейдеров
// ============================================================================
