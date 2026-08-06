/* Oxygen Atmosphere - volumetric_clouds_end.glsl
Fast volumetric clouds (for The End) - MakeUp implementation
*/

#include "/lib/end_storm.glsl"

vec3 get_end_cloud(vec3 eyeDirection, vec3 blockColor, float bright, float dither, vec3 base_pos, int samples) {
    float lightningFlash = endStormLightningPulse(frameTimeCounter);
    float lightningGlow =
        endStormLightningGlow(eyeDirection, frameTimeCounter);

    // There is no physical sky in The End. Begin with a deep, nearly black
    // void and let clouds, haze and electrical light provide all structure.
    blockColor = mix(blockColor, END_VOID_COLOR, 0.97);

    #if defined DISTANT_HORIZONS && defined DEFERRED_SHADER
        float d_dh = texture2DLod(dhDepthTex0, gl_FragCoord.xy / vec2(viewWidth, viewHeight), 0.0).r;
        float linear_d_dh = ld_dh(d_dh);
        if (linear_d_dh < 0.9999) {
            return blockColor;
        }
    #endif

    if (eyeDirection.y > 0.012) {
        // A low threshold produces a continuous, heavy ceiling. Multiple
        // scrolling octaves keep it from reading as one repeated texture.
        float umbral = 0.14;
        vec3 cloudColor = vec3(0.150, 0.162, 0.235);
        vec3 darkCloudColor = vec3(0.035, 0.045, 0.078);

        // A continuous distant cloud body replaces the black void behind the
        // detailed raymarched layer. It ensures that gaps read as deeper storm
        // strata rather than holes in the atmosphere.
        vec2 upperBackdropUv =
            eyeDirection.xz * 0.61 +
            base_pos.xz * 0.00016 +
            vec2(
                frameTimeCounter * CLOUD_LOW_FACTOR * 0.42,
                frameTimeCounter * CLOUD_HI_FACTOR * 0.27
            );
        float upperBackdropNoise =
            texture2D(gaux2, upperBackdropUv).r * 0.66 +
            texture2D(
                gaux2,
                upperBackdropUv * 2.37 + vec2(0.19, 0.53)
            ).r * 0.34;
        vec3 upperBackdropColor = mix(
            vec3(0.050, 0.063, 0.105),
            vec3(0.130, 0.150, 0.230),
            smoothstep(0.18, 0.82, upperBackdropNoise)
        );
        upperBackdropColor = mix(
            upperBackdropColor,
            vec3(0.320, 0.380, 0.620),
            lightningGlow * 0.62
        );
        float upperBackdropPresence =
            smoothstep(0.012, 0.16, eyeDirection.y) *
            mix(0.78, 0.94, upperBackdropNoise);
        blockColor = mix(
            blockColor,
            upperBackdropColor,
            upperBackdropPresence
        );

        float view_y_inv = 1.0 / eyeDirection.y;

        float plane_distance_inf = (CLOUD_PLANE - base_pos.y) * view_y_inv;
        vec3 intersection_pos = (eyeDirection * plane_distance_inf) + base_pos;

        float plane_distance_sup = (CLOUD_PLANE_SUP - base_pos.y) * view_y_inv;
        vec3 intersection_pos_sup = (eyeDirection * plane_distance_sup) + base_pos;

        vec3 increment = (intersection_pos_sup - intersection_pos) / samples;
        float increment_dist = length(increment);

        float dif_sup = CLOUD_PLANE_SUP - CLOUD_PLANE_CENTER;
        float dif_inf = CLOUD_PLANE_CENTER - CLOUD_PLANE;
        float dist_aux_coeff = (CLOUD_PLANE_SUP - CLOUD_PLANE) * 0.075;
        float dist_aux_coeff_blur = dist_aux_coeff * 0.4;
        float opacity_dist = dist_aux_coeff * 2.5 * view_y_inv;

        float cloud_value = 0.0;
        float density = 0.0; // Inicializar
        bool first_contact = true;

        intersection_pos += (increment * dither);

        for (int i = 0; i < samples; i++) {
            vec2 primaryUv =
                intersection_pos.xz * 0.00072 +
                vec2(
                    frameTimeCounter * CLOUD_HI_FACTOR * 2.2,
                    frameTimeCounter * CLOUD_LOW_FACTOR * 0.7
                );
            vec2 crossingUv =
                intersection_pos.zx * 0.00131 +
                vec2(
                    -frameTimeCounter * CLOUD_LOW_FACTOR * 1.4,
                    frameTimeCounter * CLOUD_HI_FACTOR * 0.55
                );
            float current_value =
                texture2D(gaux2, primaryUv).r * 0.68 +
                texture2D(gaux2, crossingUv).r * 0.32;

            #if V_CLOUDS == 2 && CLOUD_VOL_STYLE == 0
                current_value +=
                    texture2D(
                        gaux2,
                        intersection_pos.zx * 0.00043 -
                            frameTimeCounter * CLOUD_LOW_FACTOR * 1.8
                    ).r;
                current_value = smoothstep(0.05, 0.95, current_value * 0.5);
            #endif

            current_value = (current_value - umbral) / (1.0 - umbral);

            float surface_inf = CLOUD_PLANE_CENTER - (current_value * dif_inf);
            float surface_sup = CLOUD_PLANE_CENTER + (current_value * dif_sup);

            // --- OPTIMIZACIÓN: Reestructurar la lógica del bucle ---
            float current_opacity = 0.0;
            float cloud_thickness = surface_sup - surface_inf;

            if (intersection_pos.y > surface_inf && intersection_pos.y < surface_sup) {
                // Dentro de la nube
                current_opacity = min(increment_dist, cloud_thickness);
            }
            else if (cloud_thickness > 0.0 && i > 0) {
                // Cerca del borde de la nube (desenfoque)
                float distance_aux = min(abs(intersection_pos.y - surface_inf), abs(intersection_pos.y - surface_sup));
                if (distance_aux < dist_aux_coeff_blur) {
                    // El cálculo original se simplifica a esto, que es más rápido.
                    float blur_factor = 1.0 - (distance_aux / dist_aux_coeff_blur);
                    current_opacity = min(blur_factor * increment_dist, cloud_thickness);
                }
            }
            
            // La lógica de acumulación y primer contacto se gestiona UNA SOLA VEZ.
            if (current_opacity > 0.0) {
                cloud_value += current_opacity;
                if (first_contact) {
                    first_contact = false;
                    density = (surface_sup - intersection_pos.y) / (CLOUD_PLANE_SUP - CLOUD_PLANE);
                }
            }

            intersection_pos += increment;
        }

        cloud_value = clamp(cloud_value / opacity_dist, 0.0, 1.0);
        density = clamp(density, 0.0001, 1.0);

        cloudColor = mix(cloudColor, darkCloudColor, sqrt(density) * 0.90);

        // Lightning blooms inside the cloud mass before the visible channel
        // appears, which makes every strike feel embedded in the storm.
        vec3 chargedCloudColor = vec3(0.46, 0.55, 0.92);
        float internalLightning =
            clamp(
                lightningGlow * 0.92 +
                    lightningFlash *
                        (1.0 - density) *
                        (0.08 + bright * 0.08),
                0.0,
                1.0
            );
        cloudColor = mix(
            cloudColor,
            chargedCloudColor,
            internalLightning
        );

        float cloudPresence =
            cloud_value *
            smoothstep(0.012, 0.16, eyeDirection.y);
        blockColor = mix(blockColor, cloudColor, cloudPresence);
    }

    // A separate low cloud bank closes the horizon and continues slightly
    // beneath it, so distant islands float inside mist rather than below a
    // conventional sky dome.
    vec2 horizonUv =
        eyeDirection.xz * 0.83 +
        base_pos.xz * 0.00022 +
        vec2(
            frameTimeCounter * CLOUD_LOW_FACTOR * 0.65,
            -frameTimeCounter * CLOUD_HI_FACTOR * 0.38
        );
    float horizonNoise =
        texture2D(gaux2, horizonUv).r * 0.70 +
        texture2D(gaux2, horizonUv * 2.13 + 0.37).r * 0.30;
    float horizonShape =
        1.0 - smoothstep(0.025, 0.34, abs(eyeDirection.y + 0.018));
    float horizonCloud =
        smoothstep(0.22, 0.77, horizonNoise) *
        horizonShape;
    vec3 horizonVeilColor = mix(
        vec3(0.045, 0.060, 0.100),
        vec3(0.105, 0.125, 0.195),
        horizonNoise
    );
    horizonVeilColor = mix(
        horizonVeilColor,
        vec3(0.300, 0.360, 0.600),
        lightningGlow * 0.64
    );
    blockColor = mix(
        blockColor,
        horizonVeilColor,
        horizonShape * mix(0.74, 0.90, horizonNoise)
    );
    vec3 horizonCloudColor = mix(
        vec3(0.055, 0.070, 0.120),
        vec3(0.220, 0.250, 0.380),
        lightningGlow * 0.78
    );
    blockColor = mix(
        blockColor,
        horizonCloudColor,
        horizonCloud * 0.82
    );

    // Raymarch a genuine cloud volume beneath the islands. This mirrors the
    // upper storm mechanism: the ray travels through a thick vertical layer,
    // accumulating soft boundaries, internal density and electrical light.
    if(eyeDirection.y < -0.012) {
        const float lowerCloudBottom = -52.0;
        const float lowerCloudCenter = 18.0;
        const float lowerCloudTop = 50.0;

        float lowerViewYInverse = 1.0 / eyeDirection.y;
        float lowerTopDistance =
            (lowerCloudTop - base_pos.y) *
            lowerViewYInverse;
        float lowerBottomDistance =
            (lowerCloudBottom - base_pos.y) *
            lowerViewYInverse;
        vec3 lowerTopPosition =
            eyeDirection * lowerTopDistance + base_pos;
        vec3 lowerBottomPosition =
            eyeDirection * lowerBottomDistance + base_pos;
        vec3 lowerIncrement =
            (lowerBottomPosition - lowerTopPosition) /
            float(samples);
        float lowerIncrementDistance =
            length(lowerIncrement);

        float lowerDifferenceTop =
            lowerCloudTop - lowerCloudCenter;
        float lowerDifferenceBottom =
            lowerCloudCenter - lowerCloudBottom;
        float lowerDistanceCoefficient =
            (lowerCloudTop - lowerCloudBottom) * 0.075;
        float lowerEdgeBlur =
            lowerDistanceCoefficient * 0.48;
        float lowerOpacityDistance =
            lowerDistanceCoefficient *
            2.35 *
            abs(lowerViewYInverse);

        float lowerCloudValue = 0.0;
        float lowerDensity = 0.0;
        bool lowerFirstContact = true;
        vec3 lowerSamplePosition =
            lowerTopPosition +
            lowerIncrement * dither;

        for(int lowerSample = 0; lowerSample < samples; lowerSample++) {
            vec2 lowerPrimaryUv =
                lowerSamplePosition.xz * 0.00072 +
                vec2(
                    frameTimeCounter * CLOUD_LOW_FACTOR * 0.56,
                    -frameTimeCounter * CLOUD_HI_FACTOR * 0.30
                );
            vec2 lowerCrossingUv =
                lowerSamplePosition.zx * 0.00129 +
                vec2(
                    -frameTimeCounter * CLOUD_HI_FACTOR * 0.36,
                    frameTimeCounter * CLOUD_LOW_FACTOR * 0.44
                );
            float lowerCurrentValue =
                texture2D(gaux2, lowerPrimaryUv).r * 0.62 +
                texture2D(gaux2, lowerCrossingUv).r * 0.28 +
                texture2D(
                    gaux2,
                    lowerPrimaryUv * 2.87 + vec2(0.31, 0.17)
                ).r * 0.10;
            lowerCurrentValue =
                smoothstep(0.04, 0.96, lowerCurrentValue);
            lowerCurrentValue =
                (lowerCurrentValue - 0.09) / 0.91;

            float lowerSurfaceBottom =
                lowerCloudCenter -
                lowerCurrentValue *
                    lowerDifferenceBottom;
            float lowerSurfaceTop =
                lowerCloudCenter +
                lowerCurrentValue *
                    lowerDifferenceTop;
            float lowerCloudThickness =
                lowerSurfaceTop -
                lowerSurfaceBottom;
            float lowerCurrentOpacity = 0.0;

            if(
                lowerSamplePosition.y > lowerSurfaceBottom &&
                lowerSamplePosition.y < lowerSurfaceTop
            ) {
                lowerCurrentOpacity = min(
                    lowerIncrementDistance,
                    lowerCloudThickness
                );
            } else if(
                lowerCloudThickness > 0.0 &&
                lowerSample > 0
            ) {
                float lowerEdgeDistance = min(
                    abs(
                        lowerSamplePosition.y -
                        lowerSurfaceBottom
                    ),
                    abs(
                        lowerSamplePosition.y -
                        lowerSurfaceTop
                    )
                );
                if(lowerEdgeDistance < lowerEdgeBlur) {
                    float lowerBlurFactor =
                        1.0 -
                        lowerEdgeDistance /
                            lowerEdgeBlur;
                    lowerCurrentOpacity = min(
                        lowerBlurFactor *
                            lowerIncrementDistance,
                        lowerCloudThickness
                    );
                }
            }

            if(lowerCurrentOpacity > 0.0) {
                lowerCloudValue +=
                    lowerCurrentOpacity;
                if(lowerFirstContact) {
                    lowerFirstContact = false;
                    lowerDensity =
                        (
                            lowerSurfaceTop -
                            lowerSamplePosition.y
                        ) /
                        (
                            lowerCloudTop -
                            lowerCloudBottom
                        );
                }
            }

            lowerSamplePosition += lowerIncrement;
        }

        lowerCloudValue = clamp(
            lowerCloudValue /
                max(lowerOpacityDistance, 0.0001) *
                1.38,
            0.0,
            1.0
        );
        lowerDensity = clamp(
            lowerDensity,
            0.0001,
            1.0
        );

        // A deep background stratum prevents rare density gaps from revealing
        // a flat void, while the raymarched billows retain three-dimensional
        // silhouettes and parallax above it.
        float lowerDeepStratum =
            0.54 +
            texture2D(
                gaux2,
                lowerBottomPosition.xz * 0.00034 +
                    frameTimeCounter *
                        CLOUD_LOW_FACTOR *
                        0.18
            ).r * 0.16;
        lowerCloudValue = max(
            lowerCloudValue,
            lowerDeepStratum
        );

        vec3 lowerCloudColor = mix(
            vec3(0.165, 0.190, 0.280),
            vec3(0.042, 0.057, 0.105),
            sqrt(lowerDensity) * 0.88
        );
        float lowerChargeNoise =
            texture2D(
                gaux2,
                lowerTopPosition.xz * 0.00041 +
                    vec2(
                        endStormHash(
                            floor(
                                frameTimeCounter /
                                9.5
                            ) + 4.0
                        )
                    )
            ).r;
        float lowerElectricalCharge =
            lightningFlash *
            smoothstep(
                0.34,
                0.82,
                lowerChargeNoise
            );
        lowerCloudColor = mix(
            lowerCloudColor,
            vec3(0.430, 0.520, 0.860),
            lowerElectricalCharge * 0.90
        );

        float downwardPresence =
            smoothstep(
                0.012,
                0.16,
                -eyeDirection.y
            );
        blockColor = mix(
            blockColor,
            lowerCloudColor,
            lowerCloudValue *
                downwardPresence
        );
    }

    float bolt =
        endStormLightningBolt(eyeDirection, frameTimeCounter);
    blockColor +=
        vec3(0.58, 0.70, 1.20) *
        bolt *
        4.6;
    blockColor +=
        vec3(0.16, 0.21, 0.38) *
        lightningGlow *
        0.72;

    return blockColor;
}
