;; SoC Next-Gen Fix - Базовый шейдер для X-Ray R3 рендера
;; Формат: .s файл для компиляции через fxc.exe из X-Ray SDK
;; Совместимо с Shader Model 2.0/3.0

;; ============================================================================
;; Вершинный шейдер (Vertex Shader) - SM 2.0
;; ============================================================================

vs_2_0
{
    ;; Входные данные (декларации)
    dcl_position v0      ;; Позиция вершины
    dcl_normal v1        ;; Нормаль
    dcl_texcoord v2      ;; UV координаты
    dcl_color v3         ;; Цвет вершины
    
    ;; Константы (cMatrixPosition, cMatrixTexgen, cMatrixNormal предоставляются движком)
    
    ;; Трансформация позиции в clip space
    m4x4 oPos.xxyz, v0, cMatrixPosition
    
    ;; Генерация текстурных координат для проективных текстур
    m4x4 oT0.xyzz, v0, cMatrixTexgen
    
    ;; Трансформация нормали в world space
    m3x3 oT1.xyz, v1, cMatrixNormal
    
    ;; Передача UV координат
    mov oT2.xy, v2
    
    ;; Передача цвета вершины
    mov oD0, v3
}

;; ============================================================================
;; Пиксельный шейдер (Pixel Shader) - Упрощенное освещение SM 2.0
;; ============================================================================

ps_2_0
{
    ;; Декларация текстурных семплеров
    dcl_2d s0  ;; Base color / Albedo
    dcl_2d s1  ;; Normal map (опционально)
    
    ;; Входные интерполированные данные
    dcl t0.xy      ;; Projective UV
    dcl t1.xyz     ;; Normal (world space)
    dcl t2.xy      ;; Base UV
    dcl v0.xyz     ;; Color
    
    ;; Сэмплинг базовой текстуры
    texld r0, t2, s0
    
    ;; Простое диффузное освещение (Lambert)
    ;; cLightDirection предоставляется движком
    dp3_sat r1.x, t1, cLightDirection
    mad r2.xyz, r0, r1.x, r0
    
    ;; Добавляем ambient компонент (предоставляется движком)
    mad r3.xyz, r2, cAmbientColor, r2
    
    ;; Вывод финального цвета
    mov oC0, r3
}

;; ============================================================================
;; Техники (Techniques) - определяют состояния рендера
;; ============================================================================

technique T0
{
    pass P0
    {
        VertexShader = vs_2_0
        PixelShader = ps_2_0
        
        ;; Состояния рендера
        AlphaBlendEnable = false
        ZWriteEnable = true
        ZEnable = true
        CullMode = CCW
        Lighting = true
    }
}

;; ============================================================================
;; Примечания для разработчиков мода:
;; ============================================================================
;; 
;; Для полноценного PBR в X-Ray требуется:
;; 
;; 1. Модификация r3_base.s из SDK для G-Buffer рендеринга:
;;    - Albedo buffer (цвет без освещения)
;;    - Normal buffer (нормали в world space)  
;;    - Depth buffer (глубина сцены)
;;    - Specular buffer (параметры бликов)
;; 
;; 2. Реализация microfacet модели (GGX/Trowbridge-Reitz):
;;    - NDF (Normal Distribution Function)
;;    - Geometry function (shadowing-masking)
;;    - Fresnel term (Schlick approximation)
;; 
;; 3. Интеграция с системой освещения X-Ray:
;;    - Direct lighting (солнце, источники света)
;;    - Indirect lighting (GI, отраженный свет)
;;    - Ambient occlusion (SSAO/HBAO)
;; 
;; 4. Post-process эффекты в отдельном файле r3_postprocess.s:
;;    - Tone mapping (Reinhard/ACES)
;;    - Bloom (свечение ярких участков)
;;    - God Rays (объемные лучи света)
;;    - Color grading (коррекция цвета)
;; 
;; Рекомендуется использовать готовые реализации из:
;; - X-Ray SDK примеры
;; - Мода Anomaly (открытые шейдеры)
;; - OpenXRay/OGSR Engine
;; 
;; ============================================================================
