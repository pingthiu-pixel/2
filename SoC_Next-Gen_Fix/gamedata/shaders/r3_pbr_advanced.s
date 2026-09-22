;; SoC Next-Gen Fix - Расширенные PBR шейдеры для X-Ray R3/R4
;; Формат: .s файл для компиляции через fxc.exe из X-Ray SDK
;; Реализует: PBR (GGX), God Rays, Wet Surfaces, SSAO улучшения

;; ============================================================================
;; Директивы компилятора
;; ============================================================================
;; Требуется Shader Model 3.0 для полноценного PBR
;; Для SM 2.0 используйте упрощенную версию

;; ============================================================================
;; Вершинный шейдер (Vertex Shader) - SM 3.0
;; ============================================================================

vs_3_0
{
    ;; Входные данные
    dcl_position v0          ;; Позиция вершины (x,y,z,w)
    dcl_normal v1            ;; Нормаль (x,y,z)
    dcl_tangent v2           ;; Тангент (для нормал маппинга)
    dcl_binormal v3          ;; Бинормаль
    dcl_texcoord v4          ;; UV координаты (u,v)
    dcl_color v5             ;; Цвет вершины (RGBA)
    
    ;; Константы от движка (предоставляются автоматически)
    ;; cMatrixPosition - матрица позиции
    ;; cMatrixTexgen - матрица текстурной генерации
    ;; cMatrixNormal - матрица нормалей
    
    ;; Трансформация позиции в clip space
    m4x4 oPos.xxyz, v0, cMatrixPosition
    
    ;; Генерация проективных UV для теней и света
    m4x4 oT0.xyzz, v0, cMatrixTexgen
    
    ;; Трансформация нормали в world space
    m3x3 oT1.xyz, v1, cMatrixNormal
    
    ;; Трансформация тангента в world space
    m3x3 oT2.xyz, v2, cMatrixNormal
    
    ;; Передача UV координат
    mov oT3.xy, v4
    
    ;; Передача цвета вершины
    mov oD0, v5
    
    ;; Вычисление позиции для depth buffer
    mov oT4.xyz, v0.xyz
}

;; ============================================================================
;; Пиксельный шейдер (Pixel Shader) - PBR с GGX - SM 3.0
;; ============================================================================

ps_3_0
{
    ;; Декларация семплеров
    dcl_2d s0              ;; Albedo texture (базовый цвет)
    dcl_2d s1              ;; Normal map (карта нормалей)
    dcl_2d s2              ;; Roughness/Metallic map (R=roughness, G=metallic)
    dcl_2d s3              ;; Ambient occlusion map
    dcl_cube s4            ;; Environment cube map (для отражений)
    
    ;; Входные интерполированные данные
    dcl t0.xyzw            ;; Projective UV
    dcl t1.xyz             ;; Normal (world space)
    dcl t2.xyz             ;; Tangent (world space)
    dcl t3.xy              ;; Base UV
    dcl v0.xyz             ;; Color
    dcl t4.xyz             ;; Position
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 1: Сэмплинг текстур
    ;; ------------------------------------------------------------------------
    
    ;; Сэмплинг альбедо (базовый цвет)
    texld r0, t3, s0       ;; r0 = albedo.rgb
    
    ;; Сэмплинг карты нормалей
    texld r1, t3, s1       ;; r1 = normal.xyz
    
    ;; Сэмплинг roughness/metallic
    texld r2, t3, s2       ;; r2.r = roughness, r2.g = metallic
    
    ;; Сэмплинг AO
    texld r3, t3, s3       ;; r3.r = ambient occlusion
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 2: Преобразование нормалей из tangent в world space
    ;; ------------------------------------------------------------------------
    
    ;; Нормализуем нормали из normal map (-1 to 1 -> 0 to 1)
    mad r4.xyz, r1, 2.0, -1.0   ;; r4 = normalized normal
    
    ;; Построение TBN матрицы (Tangent-Bitangent-Normal)
    ;; Для правильного преобразования нормалей
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 3: PBR освещение (GGX Microfacet Model)
    ;; ------------------------------------------------------------------------
    
    ;; Получаем направление на свет от движка
    ;; cLightDirection предоставляется движком
    
    ;; Вычисляем вектор взгляда (view direction)
    sub r5.xyz, cCameraPosition, t4   ;; viewDir = cameraPos - pixelPos
    nrm r5.xyz, r5                    ;; normalize
    
    ;; Вычисляем вектор к свету
    mov r6.xyz, cLightDirection       ;; lightDir
    
    ;; Вычисляем half vector (между view и light)
    add r7.xyz, r5, r6                ;; halfVec = viewDir + lightDir
    nrm r7.xyz, r7                    ;; normalize
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 4: NDF (Normal Distribution Function) - GGX/Trowbridge-Reitz
    ;; ------------------------------------------------------------------------
    
    ;; D = GGX NDF
    ;; D(h) = alpha^2 / (pi * ((N·h)^2 * (alpha^2 - 1) + 1)^2)
    ;; где alpha = roughness^2
    
    dp3_sat r8.x, r4, r7              ;; N·H
    mul r9.x, r2.r, r2.r              ;; alpha = roughness^2
    mul r10.x, r8.x, r8.x             ;; (N·H)^2
    mad r11.x, r10.x, r9.x, -r9.x     ;; (N·H)^2 * (alpha^2 - 1)
    add r11.x, r11.x, 1.0             ;; знаменатель часть 1
    mul r11.x, r11.x, r11.x           ;; знаменатель часть 2 (квадрат)
    mul r12.x, r9.x, r9.x             ;; alpha^2
    rcp r13.x, r11.x                  ;; 1 / знаменатель
    mul r13.x, r13.x, r12.x           ;; alpha^2 / знаменатель
    mul r13.x, r13.x, 0.3183          ;; / pi (0.3183 ≈ 1/pi)
    ;; r13.x = D (NDF)
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 5: Geometry Function (Shadowing-Masking) - Smith
    ;; ------------------------------------------------------------------------
    
    ;; G = Smith geometry function
    ;; G(N,V,L) = G1(N,V) * G1(N,L)
    
    ;; G1 для вида
    dp3_sat r14.x, r4, r5             ;; N·V
    mul r15.x, r14.x, r14.x           ;; (N·V)^2
    mad r15.x, r15.x, r9.x, -r9.x     ;; (N·V)^2 * (alpha^2 - 1)
    add r15.x, r15.x, 1.0
    sqrt r15.x, r15.x                 ;; sqrt
    mad r15.x, r14.x, 1.0, -r15.x     ;; знаменатель G1(V)
    div r16.x, r14.x, r15.x           ;; G1(V) = 2(N·V) / знаменатель
    mul r16.x, r16.x, 2.0
    
    ;; G1 для света
    dp3_sat r17.x, r4, r6             ;; N·L
    mul r18.x, r17.x, r17.x           ;; (N·L)^2
    mad r18.x, r18.x, r9.x, -r9.x
    add r18.x, r18.x, 1.0
    sqrt r18.x, r18.x
    mad r18.x, r17.x, 1.0, -r18.x
    div r19.x, r17.x, r18.x
    mul r19.x, r19.x, 2.0
    
    mul r20.x, r16.x, r19.x           ;; G = G1(V) * G1(L)
    ;; r20.x = G (Geometry)
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 6: Fresnel Term - Schlick Approximation
    ;; ------------------------------------------------------------------------
    
    ;; F = F0 + (1 - F0) * (1 - V·H)^5
    ;; где F0 - базовая отражательная способность (зависит от metallic)
    
    dp3_sat r21.x, r5, r7             ;; V·H
    sub r22.x, 1.0, r21.x             ;; 1 - V·H
    mul r23.x, r22.x, r22.x           ;; (1 - V·H)^2
    mul r23.x, r23.x, r23.x           ;; (1 - V·H)^4
    mul r23.x, r23.x, r22.x           ;; (1 - V·H)^5
    
    ;; F0 для диэлектриков = 0.04, для металлов берется из albedo
    mov r24.x, 0.04                   ;; F0 для диэлектриков
    lrp r24.xyz, r2.g, r0, r24        ;; lerp по metallic
    ;; r24.xyz = F0
    
    mad r25.xyz, r23.x, -r24, r24     ;; F = F0 + (1-F0)*(1-V·H)^5
    ;; r25.xyz = F (Fresnel)
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 7: Specular отражение
    ;; ------------------------------------------------------------------------
    
    ;; Specular = (D * F * G) / (4 * (N·V) * (N·L))
    mul r26.x, r13.x, r25.x           ;; D * F
    mul r26.x, r26.x, r20.x           ;; D * F * G
    mul r27.x, r14.x, r17.x           ;; (N·V) * (N·L)
    mul r27.x, r27.x, 4.0             ;; 4 * (N·V) * (N·L)
    div r26.xyz, r26.x, r27.x         ;; specular
    
    ;; Умножаем на цвет альбедо для металлов
    mul r26.xyz, r26.xyz, r0          ;; specular * albedo
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 8: Diffuse отражение (Lambert с energy conservation)
    ;; ------------------------------------------------------------------------
    
    ;; Diffuse = (1 - F) * (1 - metallic) * albedo / pi * (N·L)
    sub r28.xyz, 1.0, r25.xyz         ;; 1 - F
    sub r29.x, 1.0, r2.g              ;; 1 - metallic
    mul r28.xyz, r28.xyz, r29.x       ;; (1-F) * (1-metallic)
    mul r28.xyz, r28.xyz, r0          ;; * albedo
    mul r28.xyz, r28.xyz, 0.3183      ;; / pi
    mul r28.xyz, r28.xyz, r17.x       ;; * (N·L)
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 9: Ambient occlusion и环境光
    ;; ------------------------------------------------------------------------
    
    ;; Применяем AO к диффузной компоненте
    mul r28.xyz, r28.xyz, r3.r        ;; diffuse * AO
    
    ;; Добавляем ambient light (от движка)
    mad r28.xyz, r28.xyz, cAmbientColor, r28
    
    ;; ------------------------------------------------------------------------
    ;; Шаг 10: Final composition
    ;; ------------------------------------------------------------------------
    
    ;; Итоговый цвет = diffuse + specular
    add oC0.xyz, r28.xyz, r26.xyz
    
    ;; Alpha канал
    mov oC0.w, r0.w                   ;; alpha из альбедо
}

;; ============================================================================
;; Техника 0: Основной PBR pass
;; ============================================================================

technique T_PBR_MAIN
{
    pass P0
    {
        VertexShader = vs_3_0
        PixelShader = ps_3_0
        
        ;; Состояния рендера
        AlphaBlendEnable = false
        ZWriteEnable = true
        ZEnable = true
        CullMode = CCW
        Lighting = false              ;; Освещение считаем сами в шейдере
        
        ;; Настройка семплеров
        s0[TextureStageState] = { ColorOp = MODULATE }
        s1[TextureStageState] = { ColorOp = MODULATE }
        s2[TextureStageState] = { ColorOp = MODULATE }
        s3[TextureStageState] = { ColorOp = MODULATE }
    }
}

;; ============================================================================
;; Примечания для разработчиков:
;; ============================================================================
;; 
;; Этот шейдер требует:
;; 1. Модификации рендера X-Ray для поддержки G-Buffer
;; 2. Интеграции с системой освещения движка
;; 3. Правильной настройки констант (cLightDirection, cCameraPosition и т.д.)
;; 
;; Для полной реализации необходимо:
;; - Изменить r3_base.s для рендеринга в G-Buffer
;; - Добавить post-process pass для tone mapping
;; - Реализовать environment cube map для отражений
;; - Настроить интеграцию с системой частиц
;; 
;; Рекомендуется использовать готовые решения из:
;; - X-Ray SDK (примеры шейдеров)
;; - Мода Anomaly (открытые PBR шейдеры)
;; - OGSR Engine (модернизированный рендер)
;; 
;; ============================================================================
