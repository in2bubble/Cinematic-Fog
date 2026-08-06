/* Oxygen Atmosphere - time-of-day authored water surface.
 *
 * Four distinct generated height/flow paintings share one guarded atlas:
 * dawn, noon, dusk and midnight. Each phase has its own scale, direction and
 * animation rhythm, while smooth time blending prevents visible texture pops.
 * Rain intentionally reuses the current time-of-day surface without adding a
 * separate texture, wave layer, color grade or animation.
 */

#ifdef VOXY_WATER
    #define OXYGEN_ATMOSPHERE_WATER_SAMPLE(texSampler, uv) texture(texSampler, uv)
#else
    #define OXYGEN_ATMOSPHERE_WATER_SAMPLE(texSampler, uv) texture2D(texSampler, uv)
#endif

vec2 oxygenAtmosphereWaterAtlasUv(vec2 uv, float styleIndex) {
    vec2 cellOrigin;
    if (styleIndex < 0.5) {
        cellOrigin = vec2(0.0, 0.0);
    } else if (styleIndex < 1.5) {
        cellOrigin = vec2(0.5, 0.0);
    } else if (styleIndex < 2.5) {
        cellOrigin = vec2(0.0, 0.5);
    } else {
        cellOrigin = vec2(0.5, 0.5);
    }

    // Every 1024px tile has an 8px wrapped guard inside a 1040px cell.
    const float atlasGutter = 0.003846153846;
    const float atlasInnerSpan = 0.492307692308;
    return
        cellOrigin +
        vec2(atlasGutter) +
        fract(uv) * atlasInnerSpan;
}

vec4 oxygenAtmosphereWaterMotionProfile(float styleIndex) {
    if (styleIndex < 0.5) {
        // frequency, speed, wave energy, domain-warp size
        return vec4(0.72, 0.58, 0.72, 1.28);
    } else if (styleIndex < 1.5) {
        return vec4(1.02, 1.05, 0.90, 0.82);
    } else if (styleIndex < 2.5) {
        return vec4(0.86, 0.78, 1.05, 1.42);
    } else {
        return vec4(0.58, 0.46, 0.62, 1.05);
    }
}

float oxygenAtmosphereWaterMotionAngle(float styleIndex) {
    if (styleIndex < 0.5) {
        return -0.18;
    } else if (styleIndex < 1.5) {
        return 0.22;
    } else if (styleIndex < 2.5) {
        return 1.05;
    } else {
        return -0.75;
    }
}

float oxygenAtmosphereWaterNightAmount(float waterDayMoment) {
    float moment = mod(waterDayMoment, 1.0);
    return
        smoothstep(0.50, 0.68, moment) *
        (1.0 - smoothstep(0.92, 1.0, moment));
}

#if !defined VOXY_WATER && !defined OXYGEN_ATMOSPHERE_WATER_DISTANT_SURFACE
vec4 oxygenAtmosphereWaterRainImpactField(
    vec2 worldPosition,
    float time
) {
    // One evolving impact per world-space cell. Neighbor evaluation allows
    // every expanding ring to cross cell boundaries without a square seam.
    const float cellScale = 0.62;
    vec2 scaledPosition =
        worldPosition * cellScale;
    vec2 baseCell = floor(scaledPosition);
    vec2 impactSlope = vec2(0.0);
    float impactHighlight = 0.0;
    float impactShadow = 0.0;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 cell =
                baseCell + vec2(float(x), float(y));
            float seed =
                hash12(cell + vec2(17.31, -9.17));
            float cycleTime =
                time * (0.52 + seed * 0.24) +
                seed * 9.73;
            float cycleIndex = floor(cycleTime);
            float age = fract(cycleTime);
            vec2 cycleSalt =
                vec2(
                    cycleIndex * 19.17,
                    cycleIndex * -7.31
                );
            vec2 randomCenter = vec2(
                hash12(
                    cell +
                    cycleSalt +
                    vec2(3.11, 27.41)
                ),
                hash12(
                    cell +
                    cycleSalt.yx +
                    vec2(-14.73, 5.37)
                )
            );
            vec2 center =
                cell + 0.12 + randomCenter * 0.76;
            vec2 delta =
                scaledPosition - center;
            float distanceToImpact = length(delta);
            vec2 radialDirection =
                delta / max(distanceToImpact, 0.018);

            float radius =
                age * 0.80;
            float pixelWidth = clamp(
                fwidth(distanceToImpact),
                0.012,
                0.060
            );
            float brightRing =
                1.0 -
                smoothstep(
                    0.026 + pixelWidth,
                    0.062 + pixelWidth * 1.45,
                    abs(distanceToImpact - radius)
                );
            float darkRing =
                1.0 -
                smoothstep(
                    0.034 + pixelWidth,
                    0.082 + pixelWidth * 1.55,
                    abs(
                        distanceToImpact -
                        radius -
                        0.062
                    )
                );
            float lifetime =
                smoothstep(0.0, 0.035, age) *
                (1.0 - smoothstep(0.68, 0.96, age));
            brightRing *= lifetime;
            darkRing *= lifetime * 0.72;

            // A small raised bubble exists only at the instant of impact,
            // before collapsing into the expanding capillary ring.
            float bubbleLife =
                1.0 - smoothstep(0.025, 0.17, age);
            float bubbleRadius =
                0.035 + age * 0.16;
            float bubbleRim =
                1.0 -
                smoothstep(
                    0.018 + pixelWidth,
                    0.050 + pixelWidth,
                    abs(
                        distanceToImpact -
                        bubbleRadius
                    )
                );
            bubbleRim *= bubbleLife;
            float impactCore =
                (1.0 -
                    smoothstep(
                        0.0,
                        0.095,
                        distanceToImpact
                    )) *
                (1.0 -
                    smoothstep(0.0, 0.085, age));

            float radialWave =
                brightRing -
                darkRing * 0.68 +
                bubbleRim * 0.58;
            impactSlope +=
                radialDirection * radialWave;
            impactHighlight = max(
                impactHighlight,
                brightRing +
                    bubbleRim * 0.88 +
                    impactCore * 0.72
            );
            impactShadow = max(
                impactShadow,
                darkRing
            );
        }
    }

    return vec4(
        impactSlope,
        clamp(impactHighlight, 0.0, 1.0),
        clamp(impactShadow, 0.0, 1.0)
    );
}
#endif

vec3 oxygenAtmosphereWaterStyleSample(
    vec2 p,
    float time,
    float styleIndex
) {
    vec2 uvA;
    vec2 uvB;
    float slopeAWeight;
    float slopeBWeight;
    float heightAWeight;

    if (styleIndex < 0.5) {
        // Dawn: long, slow diagonal ribbons.
        vec2 basisB = mat2(
             0.9397, -0.3420,
             0.3420,  0.9397
        ) * p;
        uvA =
            p * vec2(0.0150, 0.0115) +
            vec2(time * 0.0024, time * 0.0012);
        uvB =
            basisB * vec2(0.0260, 0.0200) +
            vec2(-time * 0.0014, time * 0.0028);
        slopeAWeight = 0.52;
        slopeBWeight = 0.25;
        heightAWeight = 0.68;
    } else if (styleIndex < 1.5) {
        // Noon: the most readable flow, still soft beneath the cloud cover.
        vec2 basisB = mat2(
             0.8192, -0.5736,
             0.5736,  0.8192
        ) * p;
        uvA =
            p * 0.0205 +
            vec2(time * 0.0065, time * 0.0038);
        uvB =
            basisB * 0.0360 +
            vec2(-time * 0.0042, time * 0.0074);
        slopeAWeight = 0.58;
        slopeBWeight = 0.32;
        heightAWeight = 0.64;
    } else if (styleIndex < 2.5) {
        // Dusk: curved opposing currents with a gentle rotating character.
        vec2 basisA = mat2(
             0.7071, -0.7071,
             0.7071,  0.7071
        ) * p;
        vec2 basisB = mat2(
             0.2588,  0.9659,
            -0.9659,  0.2588
        ) * p;
        uvA =
            basisA * vec2(0.0175, 0.0210) +
            vec2(-time * 0.0032, time * 0.0048);
        uvB =
            basisB * vec2(0.0300, 0.0250) +
            vec2(time * 0.0041, time * 0.0020);
        slopeAWeight = 0.50;
        slopeBWeight = 0.29;
        heightAWeight = 0.61;
    } else {
        // Midnight: sparse broad swells with restrained fine ripples.
        vec2 basisB = mat2(
             0.9659,  0.2588,
            -0.2588,  0.9659
        ) * p;
        uvA =
            p * vec2(0.0115, 0.0140) +
            vec2(-time * 0.0012, time * 0.0018);
        uvB =
            basisB * vec2(0.0220, 0.0180) +
            vec2(time * 0.0020, -time * 0.0011);
        slopeAWeight = 0.43;
        slopeBWeight = 0.22;
        heightAWeight = 0.72;
    }

    vec3 authoredA = OXYGEN_ATMOSPHERE_WATER_SAMPLE(
        noisetex,
        oxygenAtmosphereWaterAtlasUv(uvA, styleIndex)
    ).rgb;
    vec3 authoredB = OXYGEN_ATMOSPHERE_WATER_SAMPLE(
        noisetex,
        oxygenAtmosphereWaterAtlasUv(uvB, styleIndex)
    ).rgb;
    vec2 slope =
        (authoredA.rg * 2.0 - 1.0) * slopeAWeight +
        (authoredB.rg * 2.0 - 1.0) * slopeBWeight;
    float height =
        authoredA.b * heightAWeight +
        authoredB.b * (1.0 - heightAWeight);
    return vec3(slope, height);
}

vec4 oxygenAtmosphereWaterSurfaceData(
    vec3 worldPos,
    float waterDayMoment,
    float rainImpactMask
) {
    vec2 p = worldPos.xy;
    float time = frameTimeCounter;
    float waterNight =
        oxygenAtmosphereWaterNightAmount(waterDayMoment);
    float daylightMask =
        1.0 -
        step(
            0.50,
            mod(waterDayMoment, 1.0)
        );
    float dayRain =
        rainStrength * daylightMask;

    // Rain keeps the active time-of-day texture and motion language. Only its
    // playback becomes modestly faster: +20% by day and +10% at midnight.
    float rainAnimationSpeed =
        1.0 +
        rainStrength *
            mix(0.20, 0.10, waterNight);
    float animatedTime =
        time * rainAnimationSpeed;

    // Bright overcast fog can expose normal-map repetition as static bands.
    // Apply one uniform daytime-rain reduction across the entire water plane;
    // a distance-based fade would create a visible circle around the player.
    float waveVisibility =
        mix(1.0, 0.60, dayRain);

    // Minecraft's day moment is dawn=0.0, noon=0.25, dusk=0.5 and
    // midnight=0.75. Blend across the complete cycle instead of switching.
    float waterCycle = mod(waterDayMoment, 1.0) * 4.0;
    float styleA = floor(waterCycle);
    float styleB = mod(styleA + 1.0, 4.0);
    float styleBlend = smoothstep(
        0.12,
        0.88,
        fract(waterCycle)
    );
    vec4 motionProfile = mix(
        oxygenAtmosphereWaterMotionProfile(styleA),
        oxygenAtmosphereWaterMotionProfile(styleB),
        styleBlend
    );
    float flowAngle = mix(
        oxygenAtmosphereWaterMotionAngle(styleA),
        oxygenAtmosphereWaterMotionAngle(styleB),
        styleBlend
    );
    float frequencyScale = motionProfile.x;
    float speedScale = motionProfile.y;

    float flowCos = cos(flowAngle);
    float flowSin = sin(flowAngle);
    mat2 flowRotation = mat2(
        flowCos, -flowSin,
        flowSin,  flowCos
    );
    vec2 warpDirA =
        flowRotation * vec2(0.8192, 0.5735);
    vec2 warpDirB =
        flowRotation * vec2(-0.4472, 0.8944);
    vec2 warp = vec2(
        sin(
            dot(p, warpDirA) *
                0.043 * frequencyScale +
            animatedTime * 0.055 * speedScale
        ),
        cos(
            dot(p, warpDirB) *
                0.051 * frequencyScale -
            animatedTime * 0.047 * speedScale
        )
    );
    warp *=
        1.65 *
        motionProfile.w;
    vec2 q = p + warp;

    vec3 authoredData = mix(
        oxygenAtmosphereWaterStyleSample(p, animatedTime, styleA),
        oxygenAtmosphereWaterStyleSample(p, animatedTime, styleB),
        styleBlend
    );
    vec2 authoredSlope =
        authoredData.rg * waveVisibility;
    float authoredHeight = authoredData.b;

    vec2 directionA =
        flowRotation * vec2(0.9239, 0.3827);
    vec2 directionB =
        flowRotation * vec2(-0.3420, 0.9397);
    vec2 directionC =
        flowRotation * vec2(0.6157, -0.7880);
    vec2 directionD =
        flowRotation * vec2(0.1736, 0.9848);

    float phaseA =
        dot(q, directionA) *
            0.205 * frequencyScale +
        animatedTime * 0.180 * speedScale;
    float phaseB =
        dot(q, directionB) *
            0.147 * frequencyScale -
        animatedTime * 0.125 * speedScale +
        1.70;
    float phaseC =
        dot(q, directionC) *
            0.315 * frequencyScale +
        animatedTime * 0.235 * speedScale +
        3.10;
    float phaseD =
        dot(p, directionD) *
            0.610 * frequencyScale -
        animatedTime * 0.320 * speedScale +
        0.80;

    float waveA = sin(phaseA);
    float waveB = sin(phaseB);
    float waveC = sin(phaseC);
    float waveD = sin(phaseD);

    vec2 slope =
        directionA * cos(phaseA) * 0.205 * 0.46 +
        directionB * cos(phaseB) * 0.147 * 0.34 +
        directionC * cos(phaseC) * 0.315 * 0.15 +
        directionD * cos(phaseD) * 0.610 * 0.035;
    slope =
        slope *
            (0.42 * motionProfile.z) *
            waveVisibility +
        authoredSlope;

    float broadShape =
        waveA * 0.50 +
        waveB * 0.31 +
        waveC * 0.14 +
        waveD * 0.05;
    float crossing = 1.0 - smoothstep(
        0.08,
        0.58,
        abs(waveA - waveB * 0.82)
    );
    float authoredRibbon = smoothstep(
        0.57,
        0.88,
        authoredHeight
    );
    float ribbon = max(
        crossing * smoothstep(-0.15, 0.88, waveC),
        authoredRibbon * 0.82
    );

    float impactHighlight = 0.0;
    float impactShadow = 0.0;
    #if !defined VOXY_WATER && !defined OXYGEN_ATMOSPHERE_WATER_DISTANT_SURFACE
        float impactStrength =
            rainStrength *
            clamp(rainImpactMask, 0.0, 1.0);
        if (impactStrength > 0.002) {
            vec4 rainImpact =
                oxygenAtmosphereWaterRainImpactField(
                    p,
                    animatedTime
                );
            slope +=
                rainImpact.xy *
                impactStrength *
                PUDDLE_RIPPLE_STRENGTH *
                0.105;
            impactHighlight =
                rainImpact.z *
                impactStrength *
                PUDDLE_RAIN_RINGS;
            impactShadow =
                rainImpact.w *
                impactStrength *
                PUDDLE_RAIN_RINGS;
            ribbon = max(
                ribbon,
                impactHighlight * 0.82
            );
        }
    #endif

    float pigment =
        0.85 +
        authoredHeight * 0.20 +
        broadShape * 0.032 +
        ribbon * 0.036 +
        impactHighlight * 0.060 -
        impactShadow * 0.028;

    return vec4(
        slope,
        clamp(pigment, 0.85, 1.08),
        clamp(ribbon, 0.0, 1.0)
    );
}

#undef OXYGEN_ATMOSPHERE_WATER_SAMPLE

vec3 oxygenAtmosphereWaterNormal(vec4 surfaceData) {
    float normalHeight =
        max(WATER_TURBULENCE, 0.18) * 1.30;
    return normalize(vec3(-surfaceData.xy, normalHeight));
}

vec3 oxygenAtmosphereWaterTimeColor() {
    #if defined OXYGEN_ATMOSPHERE_STYLE && !defined NETHER && !defined THE_END
        return oxygenAtmosphereWaterSurfacePalette(
            rainStrength
        );
    #else
        return WATER_COLOR;
    #endif
}

vec3 oxygenAtmosphereWaterTimeColorVoxy(
    float dayMixerV,
    float nightMixerV,
    float dayMomentV
) {
    #if defined OXYGEN_ATMOSPHERE_STYLE && !defined NETHER && !defined THE_END
        vec3 waterColor = dayBlendVoxy(
            vec3(0.052, 0.112, 0.122),
            vec3(0.038, 0.124, 0.142),
            vec3(0.026, 0.074, 0.138),
            dayMixerV,
            nightMixerV,
            dayMomentV
        );
        vec3 rainWaterColor = dayBlendVoxy(
            vec3(0.046, 0.104, 0.120),
            vec3(0.040, 0.108, 0.128),
            vec3(0.030, 0.082, 0.148),
            dayMixerV,
            nightMixerV,
            dayMomentV
        );
        return mix(
            waterColor,
            rainWaterColor,
            rainStrength * 0.58
        );
    #else
        return WATER_COLOR;
    #endif
}

vec3 oxygenAtmosphereWaterPigment(vec3 baseColor, vec4 surfaceData) {
    vec3 surfaceColor = baseColor * surfaceData.z;
    vec3 ribbonColor =
        baseColor * 1.16 +
        vec3(0.006, 0.012, 0.013);
    return mix(
        surfaceColor,
        ribbonColor,
        surfaceData.w * 0.16
    );
}

vec3 oxygenAtmosphereWaterEnvironmentLighting(
    vec3 realLight,
    vec3 skyReflection,
    vec3 baseColor,
    vec4 surfaceData,
    float waterDayMoment,
    float visibleSky
) {
    vec3 pigment =
        oxygenAtmosphereWaterPigment(baseColor, surfaceData);
    vec3 litWater = realLight * pigment;

    #if defined OXYGEN_ATMOSPHERE_STYLE && !defined NETHER && !defined THE_END
        float nightAmount =
            oxygenAtmosphereWaterNightAmount(waterDayMoment);
        float skyAccess =
            clamp(visibleSky, 0.0, 1.0);
        vec3 minimumEnvironment = mix(
            vec3(0.030, 0.064, 0.078),
            vec3(0.042, 0.092, 0.172),
            nightAmount
        );
        vec3 environmentColor =
            max(skyReflection, minimumEnvironment);
        float environmentWeight =
            0.038 +
            nightAmount * 0.175 +
            rainStrength *
                (0.026 + nightAmount * 0.030);
        environmentWeight *=
            mix(0.48, 1.0, skyAccess);
        environmentWeight *=
            0.86 + surfaceData.w * 0.18;
        litWater +=
            environmentColor * environmentWeight;

        vec3 minimumWater =
            baseColor *
            mix(0.18, 0.72, nightAmount) *
            mix(0.46, 1.0, skyAccess);
        minimumWater +=
            vec3(0.002, 0.006, 0.015) *
            rainStrength *
            nightAmount;
        litWater = max(litWater, minimumWater);
    #endif

    return litWater;
}

float oxygenAtmosphereWaterReflectionFresnel(
    float fresnel,
    vec4 surfaceData,
    float waterDayMoment,
    float visibleSky
) {
    float adjustedFresnel = clamp(
        fresnel *
            (0.96 + surfaceData.w * 0.16),
        0.0,
        1.0
    );

    #if defined OXYGEN_ATMOSPHERE_STYLE && !defined NETHER && !defined THE_END
        float nightAmount =
            oxygenAtmosphereWaterNightAmount(waterDayMoment);
        float minimumReflection =
            0.018 +
            nightAmount * 0.095 +
            rainStrength *
                (0.025 + nightAmount * 0.020);
        minimumReflection *=
            mix(
                0.55,
                1.0,
                clamp(visibleSky, 0.0, 1.0)
            );
        adjustedFresnel =
            max(adjustedFresnel, minimumReflection);
    #endif

    return adjustedFresnel;
}
