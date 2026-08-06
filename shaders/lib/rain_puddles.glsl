/*
 * Procedural wet ground and rain puddles.
 *
 * Puddle basins are stable in world space, while wetness controls their
 * growth/fade and two independent impact fields animate circular ripples.
 */

float puddleHash21(vec2 value) {
    return fract(
        sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123
    );
}

vec2 puddleHash22(vec2 value) {
    return fract(
        sin(vec2(
            dot(value, vec2(127.1, 311.7)),
            dot(value, vec2(269.5, 183.3))
        )) * 43758.5453123
    );
}

float puddleValueNoise(vec2 value) {
    vec2 cell = floor(value);
    vec2 local = fract(value);
    vec2 curve = local * local * (3.0 - 2.0 * local);

    float a = puddleHash21(cell);
    float b = puddleHash21(cell + vec2(1.0, 0.0));
    float c = puddleHash21(cell + vec2(0.0, 1.0));
    float d = puddleHash21(cell + vec2(1.0, 1.0));

    return mix(
        mix(a, b, curve.x),
        mix(c, d, curve.x),
        curve.y
    );
}

float puddleFacetNoise(vec2 value) {
    // Linear interpolation over two triangles produces a continuous field
    // made from planar facets. Unlike smooth value noise, its contours contain
    // natural corners and unequal straight sections—ideal for broken shores.
    vec2 cell = floor(value);
    vec2 local = fract(value);
    float lowerLeft = puddleHash21(cell);
    float lowerRight =
        puddleHash21(cell + vec2(1.0, 0.0));
    float upperLeft =
        puddleHash21(cell + vec2(0.0, 1.0));
    float upperRight =
        puddleHash21(cell + vec2(1.0, 1.0));

    if (local.x + local.y < 1.0) {
        return
            lowerLeft +
            (lowerRight - lowerLeft) * local.x +
            (upperLeft - lowerLeft) * local.y;
    }

    vec2 inverseLocal = 1.0 - local;
    return
        upperRight +
        (upperLeft - upperRight) * inverseLocal.x +
        (lowerRight - upperRight) * inverseLocal.y;
}

float puddleCapsuleDistance(
    vec2 point,
    vec2 segmentStart,
    vec2 segmentEnd
) {
    vec2 relativePoint = point - segmentStart;
    vec2 segment = segmentEnd - segmentStart;
    float segmentLengthSquared = max(dot(segment, segment), 0.0001);
    float alongSegment = clamp(
        dot(relativePoint, segment) / segmentLengthSquared,
        0.0,
        1.0
    );

    return length(relativePoint - segment * alongSegment);
}

float puddlePatchField(vec2 worldPosition) {
    // Each candidate is assembled from a core, connected arms, satellite lobes
    // and an optional cut-out. The silhouette is therefore genuinely organic:
    // kidney-shaped, branching, triangular or amoeba-like instead of an ellipse
    // with merely noisy edges.
    vec2 gridPosition = worldPosition * 0.105;
    vec2 baseCell = floor(gridPosition);
    float edgeBreakup =
        puddleValueNoise(worldPosition * 0.42 + vec2(8.3, -21.7));
    float field = 0.0;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 candidateCell = baseCell + vec2(float(x), float(y));
            vec2 randomCenter = puddleHash22(candidateCell);
            vec2 center = candidateCell + randomCenter;
            vec2 delta = gridPosition - center;

            float seed = puddleHash21(candidateCell + 7.31);
            float angle =
                puddleHash21(candidateCell - 13.7) * 6.2831853;
            float cosineAngle = cos(angle);
            float sineAngle = sin(angle);
            vec2 rotatedDelta = vec2(
                cosineAngle * delta.x - sineAngle * delta.y,
                sineAngle * delta.x + cosineAngle * delta.y
            );

            float coverageScale = mix(
                0.76,
                1.28,
                PUDDLE_COVERAGE
            );
            // Bias strongly toward small puddles while retaining rare large
            // basins. The size range is over six-to-one in world space.
            float sizeDistribution = pow(seed, 2.15);
            float radius =
                mix(0.075, 0.70, sizeDistribution) *
                coverageScale;
            float shapeSeed =
                puddleHash21(candidateCell + 31.4);
            vec2 localPosition =
                rotatedDelta / max(radius, 0.001);
            float edgeVariation =
                (edgeBreakup - 0.5) * 0.22;

            float coreRadius = mix(
                0.48,
                0.78,
                puddleHash21(candidateCell + 43.8)
            );
            float corePatch = 1.0 - smoothstep(
                coreRadius - 0.12 + edgeVariation,
                coreRadius + 0.08 + edgeVariation,
                length(localPosition)
            );

            float branchAngle =
                puddleHash21(candidateCell + 81.6) * 6.2831853;
            vec2 branchDirectionA = vec2(
                cos(branchAngle),
                sin(branchAngle)
            );
            float branchTurn = mix(
                1.55,
                3.65,
                puddleHash21(candidateCell - 26.3)
            );
            vec2 branchDirectionB = vec2(
                cos(branchAngle + branchTurn),
                sin(branchAngle + branchTurn)
            );
            vec2 branchDirectionC = vec2(
                cos(branchAngle - 1.15 - shapeSeed * 1.8),
                sin(branchAngle - 1.15 - shapeSeed * 1.8)
            );

            float reachA = mix(
                0.48,
                0.96,
                puddleHash21(candidateCell + 19.7)
            );
            float reachB = mix(
                0.34,
                0.82,
                puddleHash21(candidateCell - 57.1)
            );
            float reachC = mix(
                0.42,
                1.05,
                puddleHash21(candidateCell + 106.2)
            );
            float lobeRadiusA = mix(
                0.24,
                0.53,
                puddleHash21(candidateCell + 2.6)
            );
            float lobeRadiusB = mix(
                0.20,
                0.47,
                puddleHash21(candidateCell + 61.9)
            );
            float lobeRadiusC = mix(
                0.17,
                0.42,
                puddleHash21(candidateCell - 92.4)
            );

            vec2 lobeCenterA = branchDirectionA * reachA;
            vec2 lobeCenterB = branchDirectionB * reachB;
            vec2 lobeCenterC = branchDirectionC * reachC;
            float lobeA = 1.0 - smoothstep(
                lobeRadiusA - 0.10 + edgeVariation,
                lobeRadiusA + 0.07 + edgeVariation,
                length(localPosition - lobeCenterA)
            );
            float lobeB = 1.0 - smoothstep(
                lobeRadiusB - 0.09 - edgeVariation * 0.5,
                lobeRadiusB + 0.07 - edgeVariation * 0.5,
                length(localPosition - lobeCenterB)
            );
            float lobeC = 1.0 - smoothstep(
                lobeRadiusC - 0.08 + edgeVariation * 0.7,
                lobeRadiusC + 0.06 + edgeVariation * 0.7,
                length(localPosition - lobeCenterC)
            );

            float bridgeA = 1.0 - smoothstep(
                lobeRadiusA * 0.62,
                lobeRadiusA * 0.92,
                puddleCapsuleDistance(
                    localPosition,
                    vec2(0.0),
                    lobeCenterA
                )
            );
            float bridgeB = 1.0 - smoothstep(
                lobeRadiusB * 0.58,
                lobeRadiusB * 0.88,
                puddleCapsuleDistance(
                    localPosition,
                    vec2(0.0),
                    lobeCenterB
                )
            );
            float thirdBranchEnabled = smoothstep(
                0.34,
                0.61,
                puddleHash21(candidateCell + 139.8)
            );
            float patch = max(
                corePatch,
                max(
                    max(lobeA, bridgeA),
                    max(lobeB, bridgeB)
                )
            );
            patch = max(
                patch,
                max(
                    lobeC,
                    1.0 - smoothstep(
                        lobeRadiusC * 0.55,
                        lobeRadiusC * 0.86,
                        puddleCapsuleDistance(
                            localPosition,
                            vec2(0.0),
                            lobeCenterC
                        )
                    )
                ) * thirdBranchEnabled
            );

            // Some candidates lose a bite from one side. This creates crescents
            // and concave shorelines that a union of round lobes cannot produce.
            vec2 notchCenter =
                -branchDirectionA *
                mix(
                    0.34,
                    0.72,
                    puddleHash21(candidateCell + 154.7)
                );
            float notchRadius = mix(
                0.20,
                0.39,
                puddleHash21(candidateCell - 118.5)
            );
            float notch = 1.0 - smoothstep(
                notchRadius - 0.07,
                notchRadius + 0.06,
                length(localPosition - notchCenter)
            );
            float notchEnabled = smoothstep(
                0.46,
                0.70,
                shapeSeed
            );
            patch *= 1.0 - notch * notchEnabled * 0.64;

            float cellEnabled = smoothstep(
                0.40 - PUDDLE_COVERAGE * 0.24,
                0.58 - PUDDLE_COVERAGE * 0.17,
                puddleHash21(candidateCell - 4.9)
            );

            field = max(field, patch * cellEnabled);
        }
    }

    // A second, higher-frequency population fills the scale gap with rare
    // one-to-two block puddles and prevents a repeated single-size silhouette.
    float smallBroad = puddleValueNoise(
        worldPosition * 0.31 + vec2(41.7, -18.3)
    );
    float smallBreakup = puddleValueNoise(
        worldPosition * 0.67 + vec2(-9.2, 54.1)
    );
    float smallField = smoothstep(
        0.75 - PUDDLE_COVERAGE * 0.12,
        0.89 - PUDDLE_COVERAGE * 0.06,
        smallBroad * 0.76 + smallBreakup * 0.24
    );

    return max(field, smallField);
}

vec4 puddleImpactTexture(
    vec2 worldPosition,
    float cellScale,
    float timeOffset
) {
    vec2 scaledPosition = worldPosition * cellScale;
    vec2 baseCell = floor(scaledPosition);
    vec2 normalTexture = vec2(0.0);
    float brightTexture = 0.0;
    float darkTexture = 0.0;

    // Evaluate neighboring cells so rings cross tile boundaries seamlessly.
    // The result behaves like an animated normal/albedo rain texture without
    // requiring a large atlas or resource-pack dependency.
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 cell = baseCell + vec2(float(x), float(y));
            vec2 center =
                cell + puddleHash22(cell) * 0.70 + 0.15;
            vec2 delta = scaledPosition - center;
            float distanceToImpact = length(delta);
            float randomPhase = puddleHash21(cell + 17.0);
            float age = fract(
                frameTimeCounter * (0.38 + randomPhase * 0.32) *
                (0.65 + PUDDLE_WATER_MOTION * 0.65) +
                randomPhase +
                timeOffset
            );
            float radius = age * 0.78;
            float pixelWidth = max(fwidth(distanceToImpact), 0.018);

            float brightRing =
                1.0 - smoothstep(
                    0.030 + pixelWidth,
                    0.070 + pixelWidth * 1.5,
                    abs(distanceToImpact - radius)
                );
            float darkRing =
                1.0 - smoothstep(
                    0.035 + pixelWidth,
                    0.085 + pixelWidth * 1.5,
                    abs(distanceToImpact - radius - 0.060)
                );
            float lifetime =
                (1.0 - age) *
                (1.0 - smoothstep(0.62, 0.80, radius));

            brightRing *= lifetime;
            darkRing *= lifetime * 0.72;

            float impactFlash =
                (1.0 - smoothstep(0.0, 0.13, age)) *
                exp(-distanceToImpact * 15.0);
            float waveSlope =
                (brightRing - darkRing * 0.68) +
                impactFlash * 0.55;
            normalTexture +=
                delta / max(distanceToImpact, 0.025) *
                waveSlope;

            brightTexture = max(
                brightTexture,
                brightRing + impactFlash
            );
            darkTexture = max(darkTexture, darkRing);
        }
    }

    return vec4(
        normalTexture,
        clamp(brightTexture, 0.0, 1.0),
        clamp(darkTexture, 0.0, 1.0)
    );
}

vec3 applyRainPuddles(
    vec3 sceneColor,
    vec2 screenPosition,
    float surfaceDepth,
    float terrainSkyExposure
) {
    if (
        surfaceDepth >= 0.9998 ||
        rainStrength <= 0.005 && wetness <= 0.005
    ) {
        return sceneColor;
    }

    vec3 viewPosition =
        rainSSRViewPosition(screenPosition, surfaceDepth);
    vec3 viewNormal = normalize(
        cross(dFdx(viewPosition), dFdy(viewPosition))
    );

    if (dot(viewNormal, -viewPosition) < 0.0) {
        viewNormal = -viewNormal;
    }

    vec3 worldNormal = normalize(
        mat3(gbufferModelViewInverse) * viewNormal
    );
    float horizontalSurface =
        smoothstep(0.82, 0.965, worldNormal.y);
    float skyExposure =
        smoothstep(0.54, 0.93, terrainSkyExposure);

    float opaqueDepth =
        texture2D(depthtex1, screenPosition).r;
    float solidSurface =
        1.0 - smoothstep(
            0.00008,
            0.0015,
            abs(surfaceDepth - opaqueDepth)
        );

    float viewDistance = length(viewPosition);
    float distanceFade =
        1.0 - smoothstep(58.0, 105.0, viewDistance);

    float rainAccumulation = clamp(
        max(rainStrength, wetness * 0.92),
        0.0,
        1.0
    );
    float wetSurface =
        horizontalSurface *
        skyExposure *
        solidSurface *
        distanceFade *
        smoothstep(0.04, 0.62, rainAccumulation);

    if (wetSurface <= 0.002) {
        return sceneColor;
    }

    vec3 worldPosition =
        (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz +
        cameraPosition;
    float fillThreshold = mix(0.86, 0.42, rainAccumulation);

    // Keep the basin and its interior fixed in world space. Only the threshold
    // that extracts the shoreline is displaced below; this makes individual
    // edge sections advance and retreat without dragging the whole puddle.
    float patchField = puddlePatchField(worldPosition.xz);
    float shorelineAnimationTime =
        frameTimeCounter *
        (0.38 + PUDDLE_WATER_MOTION * 0.22);
    float shorelineBroadNoise = puddleValueNoise(
        worldPosition.xz * 0.19 + vec2(-37.1, 14.8)
    );
    float shorelineFineNoise = puddleValueNoise(
        worldPosition.xz * 0.73 + vec2(22.6, -46.3)
    );
    float shorelineFacetCoarse = puddleFacetNoise(
        worldPosition.xz * 0.36 + vec2(71.2, -33.8)
    );
    float shorelineFacetMedium = puddleFacetNoise(
        worldPosition.xz * 0.94 + vec2(-18.4, 92.7)
    );
    float shorelineFacetFine = puddleFacetNoise(
        worldPosition.xz * 2.05 + vec2(44.9, 16.3)
    );
    float jaggedShoreline =
        (shorelineFacetCoarse - 0.5) * 0.20 +
        (shorelineFacetMedium - 0.5) * 0.14 +
        (shorelineFacetFine - 0.5) * 0.070;
    float shorelinePhaseA =
        dot(worldPosition.xz, vec2(0.91, -0.57)) +
        shorelineAnimationTime * 2.10 +
        shorelineBroadNoise * 4.0;
    float shorelinePhaseB =
        dot(worldPosition.xz, vec2(-1.42, 1.08)) -
        shorelineAnimationTime * 1.57 +
        shorelineFineNoise * 5.2;
    float shorelinePhaseC =
        dot(worldPosition.xz, vec2(2.35, 1.74)) +
        shorelineAnimationTime * 2.73 -
        shorelineBroadNoise * 3.1;
    float shorelineDisplacement =
        (
            sin(shorelinePhaseA) * 0.46 +
            sin(shorelinePhaseB) * 0.34 +
            sin(shorelinePhaseC) * 0.20
        ) *
        (0.055 + PUDDLE_WATER_MOTION * 0.065) *
        rainAccumulation;
    float shorelineThreshold =
        fillThreshold +
        (shorelineBroadNoise - 0.5) * 0.17 +
        (shorelineFineNoise - 0.5) * 0.075 +
        jaggedShoreline +
        shorelineDisplacement;
    float shorelineFeather =
        0.22 +
        shorelineFineNoise * 0.050 +
        min(fwidth(patchField) * 1.8, 0.16);

    // Two overlapping masks form a deep body and a very shallow moving film.
    // The film advances and retreats farther than the body, removing the
    // single static contour that previously outlined every puddle.
    float puddleCoreMask = smoothstep(
        shorelineThreshold,
        shorelineThreshold + shorelineFeather,
        patchField
    );
    float puddleFilmMask = smoothstep(
        shorelineThreshold - 0.21,
        shorelineThreshold + shorelineFeather + 0.14,
        patchField
    );
    float puddleMask = mix(
        puddleFilmMask,
        puddleCoreMask,
        0.62
    ) * wetSurface;
    float dampShoreMask = smoothstep(
        shorelineThreshold - 0.36,
        shorelineThreshold + 0.18,
        patchField
    ) * wetSurface;
    float shorelineBand = clamp(
        (puddleFilmMask - puddleCoreMask) * 2.65,
        0.0,
        1.0
    );
    vec2 shorelineSurfaceSlope = (
        vec2(0.847, -0.531) * cos(shorelinePhaseA) * 0.46 +
        vec2(-0.796, 0.605) * cos(shorelinePhaseB) * 0.34 +
        vec2(0.804, 0.595) * cos(shorelinePhaseC) * 0.20
    ) *
    shorelineBand *
    (0.42 + PUDDLE_WATER_MOTION * 0.48) *
    rainAccumulation;

    // The damp halo visually opens the puddle into its ground instead of
    // drawing a sharp bright border around an isolated decal.
    sceneColor *= mix(
        vec3(1.0),
        vec3(0.79, 0.83, 0.88),
        dampShoreMask * 0.24
    );

    if (puddleMask <= 0.003) {
        return sceneColor;
    }

    float waterTime =
        frameTimeCounter * (0.035 + PUDDLE_WATER_MOTION * 0.035);
    vec2 flowingNoiseA = texture2D(
        noisetex,
        worldPosition.xz * 0.072 +
        vec2(waterTime, -waterTime * 0.63)
    ).rg - 0.5;
    vec2 flowingNoiseB = texture2D(
        noisetex,
        worldPosition.xz * 0.117 +
        vec2(-waterTime * 0.71, waterTime * 0.48) +
        vec2(0.37, 0.19)
    ).rg - 0.5;
    vec2 waterFlow =
        (flowingNoiseA + flowingNoiseB * 0.68) *
        PUDDLE_WATER_MOTION;

    // Continuous capillary waves travel with the same slowly changing wind
    // direction as the rain. They remain present between discrete impacts.
    float puddleWindAngle =
        frameTimeCounter * 0.021 +
        sin(frameTimeCounter * 0.037) * 0.42 +
        sin(frameTimeCounter * 0.011 + 1.7) * 0.24;
    vec2 puddleWindDirection = vec2(
        cos(puddleWindAngle),
        sin(puddleWindAngle)
    );
    vec2 puddleCrossDirection = vec2(
        -puddleWindDirection.y,
        puddleWindDirection.x
    );
    float windWavePhaseA =
        dot(worldPosition.xz, puddleWindDirection) * 3.4 +
        frameTimeCounter * 2.15 +
        waterFlow.x * 2.8;
    float windWavePhaseB =
        dot(worldPosition.xz, normalize(
            puddleWindDirection * 0.62 +
            puddleCrossDirection * 0.78
        )) * 5.1 +
        frameTimeCounter * 2.85 +
        waterFlow.y * 3.2;
    float windWavePhaseC =
        dot(worldPosition.xz, puddleCrossDirection) * 2.25 -
        frameTimeCounter * 1.37;
    float windWaveA = sin(windWavePhaseA);
    float windWaveB = sin(windWavePhaseB);
    float windWaveC = sin(windWavePhaseC);
    vec2 windWaveSlope = (
        puddleWindDirection * cos(windWavePhaseA) * 0.58 +
        normalize(
            puddleWindDirection * 0.62 +
            puddleCrossDirection * 0.78
        ) * cos(windWavePhaseB) * 0.29 +
        puddleCrossDirection * cos(windWavePhaseC) * 0.13
    ) *
    PUDDLE_WIND_WAVES *
    rainStrength;
    float windWaveTexture = clamp(
        windWaveA * 0.52 +
        windWaveB * 0.31 +
        windWaveC * 0.17,
        -1.0,
        1.0
    );

    vec4 rainTextureA =
        puddleImpactTexture(worldPosition.xz, 0.58, 0.0);
    vec4 rainTextureB =
        puddleImpactTexture(worldPosition.xz + 11.7, 0.91, 0.43);
    vec2 impactRipple =
        rainTextureA.xy +
        rainTextureB.xy * 0.58;
    float rainRingHighlight = clamp(
        rainTextureA.z + rainTextureB.z * 0.68,
        0.0,
        1.0
    );
    float rainRingShadow = clamp(
        rainTextureA.w + rainTextureB.w * 0.62,
        0.0,
        1.0
    );

    impactRipple *=
        PUDDLE_RIPPLE_STRENGTH *
        rainStrength *
        puddleMask *
        0.115;
    vec2 ripple =
        impactRipple +
        waterFlow * 0.055 * puddleMask +
        windWaveSlope * 0.026 * puddleMask +
        shorelineSurfaceSlope * 0.034;

    vec3 rippleWorldNormal = normalize(
        vec3(
            worldNormal.x + ripple.x,
            max(worldNormal.y, 0.65),
            worldNormal.z + ripple.y
        )
    );
    vec3 rippleViewNormal = normalize(
        mat3(gbufferModelView) * rippleWorldNormal
    );

    vec3 viewDirection = normalize(viewPosition);
    vec3 reflectionDirection = reflect(
        viewDirection,
        rippleViewNormal
    );

    float nightPhase =
        step(0.5, dayMoment) * nightMixer;
    float daylightPhase =
        (1.0 - step(0.5, dayMoment)) * dayMixer;
    vec3 temporalWaterTint = dayBlend(
        vec3(0.31, 0.29, 0.28),
        vec3(0.40, 0.48, 0.57),
        vec3(0.045, 0.062, 0.095)
    );
    float fresnel = pow(
        1.0 - clamp(
            dot(-viewDirection, rippleViewNormal),
            0.0,
            1.0
        ),
        5.0
    );

    // The body is animated shallow water: a darkened wet substrate, a subtle
    // blue volume tint, and a small refracted read of the opaque scene.
    vec2 waterDistortion =
        rippleViewNormal.xy *
        vec2(pixelSizeX, pixelSizeY) *
        (2.0 + PUDDLE_WATER_MOTION * 3.0);
    vec3 refractedGround = texture2D(
        gaux1,
        clamp(
            screenPosition + waterDistortion,
            vec2(0.002),
            vec2(0.998)
        )
    ).rgb;

    float animatedShimmer =
        0.5 +
        0.5 * sin(
            dot(worldPosition.xz, vec2(1.73, -1.19)) +
            waterTime * 31.0 +
            waterFlow.x * 8.0
        );
    float sceneLuma = dot(
        sceneColor,
        vec3(0.2126, 0.7152, 0.0722)
    );
    float environmentExposure =
        0.10 +
        sqrt(clamp(sceneLuma, 0.0, 1.0)) *
        mix(0.90, 0.62, nightPhase);
    vec3 skyReflection = mix(
        temporalWaterTint,
        directLightColor,
        0.28 + daylightPhase * 0.10
    ) * environmentExposure;
    vec3 rainyEnvironmentColor = mix(
        temporalWaterTint,
        mix(
            HORIZON_SKY_RAIN_COLOR,
            ZENITH_SKY_RAIN_COLOR,
            0.48 + animatedShimmer * 0.08
        ),
        0.34 * (1.0 - nightPhase)
    );
    rainyEnvironmentColor *= environmentExposure;

    // Keep the terrain texture readable under shallow water and derive the
    // tint from current time-of-day light instead of a fixed foreign color.
    vec3 wetGroundResponse = mix(
        vec3(0.84, 0.89, 0.95),
        vec3(0.76, 0.82, 0.91),
        nightPhase
    );
    vec3 saturatedGround =
        sceneColor * wetGroundResponse;
    vec3 refractedWaterBase =
        refractedGround *
        mix(
            vec3(0.91, 0.96, 1.00),
            vec3(0.78, 0.85, 0.94),
            nightPhase
        );
    vec3 puddleBody = mix(
        saturatedGround,
        refractedWaterBase,
        0.22 + PUDDLE_WATER_MOTION * 0.055
    );
    puddleBody = mix(
        puddleBody,
        rainyEnvironmentColor,
        0.050 + animatedShimmer * 0.020
    );

    // Visible albedo rings make the animation readable even when SSR has no
    // valid hit. A soft dark outer ring gives each impact real water depth.
    vec3 rainRingColor = mix(
        rainyEnvironmentColor,
        max(directLightColor, vec3(0.10)),
        0.38
    );
    float visibleRingHighlight =
        rainRingHighlight *
        PUDDLE_RAIN_RINGS *
        rainStrength *
        puddleMask;
    float visibleRingShadow =
        rainRingShadow *
        PUDDLE_RAIN_RINGS *
        rainStrength *
        puddleMask;
    puddleBody *=
        1.0 - visibleRingShadow * 0.115;
    puddleBody +=
        rainRingColor *
        visibleRingHighlight *
        (0.12 + sceneLuma * 0.10);

    // The traveling waves also carry an albedo texture, so their motion stays
    // visible without relying on a reflection hit.
    float windWaveCrest = smoothstep(
        0.18,
        0.92,
        windWaveTexture
    ) *
    PUDDLE_WIND_WAVES *
    rainStrength *
    puddleMask;
    float windWaveTrough = smoothstep(
        0.12,
        0.88,
        -windWaveTexture
    ) *
    PUDDLE_WIND_WAVES *
    rainStrength *
    puddleMask;
    puddleBody *=
        1.0 - windWaveTrough * 0.035;
    puddleBody +=
        rainRingColor *
        windWaveCrest *
        (0.018 + sceneLuma * 0.018);

    // A broad planar scene read gives the water a stable reflection even when
    // the SSR ray leaves the screen or misses thin geometry. SSR can then add
    // precise nearby detail instead of being the entire puddle appearance.
    vec2 planarReflectionUV = clamp(
        vec2(screenPosition.x, 1.0 - screenPosition.y) +
        rippleViewNormal.xy * vec2(0.018, 0.026) +
        waterFlow * vec2(pixelSizeX, pixelSizeY) * 3.0,
        vec2(0.002),
        vec2(0.998)
    );
    vec3 planarSceneReflection =
        texture2D(gaux1, planarReflectionUV).rgb;
    float planarReflectionLuma = dot(
        planarSceneReflection,
        vec3(0.2126, 0.7152, 0.0722)
    );
    float reflectedLumaLimit =
        sceneLuma * mix(1.55, 1.16, nightPhase) +
        mix(0.050, 0.012, nightPhase);
    planarSceneReflection *= min(
        1.0,
        reflectedLumaLimit /
        max(planarReflectionLuma, 0.001)
    );
    float planarReflectionWeight =
        (0.30 + fresnel * 0.16) *
        smoothstep(0.04, 0.24, screenPosition.y) *
        (1.0 - smoothstep(0.94, 0.998, screenPosition.y));
    vec3 broadReflection = mix(
        skyReflection,
        planarSceneReflection,
        planarReflectionWeight
    );

    // The broad reflection remains translucent so the animated shallow-water
    // texture, rings and traveling waves are still visible underneath.
    float skySheen =
        (0.045 + fresnel * 0.18 + animatedShimmer * 0.015) *
        PUDDLE_REFLECTION *
        puddleMask;
    puddleBody = mix(
        puddleBody,
        broadReflection,
        skySheen
    );

    // Trace the actual reflected scene throughout the visible puddle body.
    // Water animation perturbs the normal; broad reflection is only a fallback
    // for rays that leave the screen.
    vec4 screenReflection = vec4(0.0);
    float rippleGlint =
        clamp(length(impactRipple) * 5.0, 0.0, 1.0);
    #if PUDDLE_SSR_GLINTS == 1 && REFLECTION == 1 && SSR_TYPE > 0
        if (puddleMask > 0.055) {
            float jitter = puddleHash21(
                gl_FragCoord.xy + float(frameCounter)
            );
            screenReflection = traceRainSSR(
                viewPosition + rippleViewNormal * 0.055,
                reflectionDirection,
                jitter
            );
        }
    #endif

    float bodyLuma = dot(
        puddleBody,
        vec3(0.2126, 0.7152, 0.0722)
    );
    float reflectedLuma = dot(
        screenReflection.rgb,
        vec3(0.2126, 0.7152, 0.0722)
    );
    float brightSceneHighlight = smoothstep(
        bodyLuma * 0.90 + 0.025,
        bodyLuma * 1.65 + 0.16,
        reflectedLuma
    );
    float ssrGlintAmount =
        screenReflection.a *
        brightSceneHighlight *
        (0.045 + fresnel * 0.13 + rippleGlint * 0.17) *
        PUDDLE_REFLECTION *
        puddleMask;
    puddleBody +=
        screenReflection.rgb * ssrGlintAmount;

    // A valid hit contributes the building/terrain image directly. It remains
    // translucent so the animated shallow-water body is still visible.
    float ssrBodyAmount =
        screenReflection.a *
        (
            0.30 +
            fresnel * 0.40 +
            windWaveCrest * 0.090 +
            rippleGlint * 0.070
        ) *
        PUDDLE_REFLECTION *
        puddleMask;
    puddleBody = mix(
        puddleBody,
        screenReflection.rgb,
        ssrBodyAmount
    );

    float fallbackReflectionAmount =
        (1.0 - screenReflection.a) *
        (0.050 + fresnel * 0.14) *
        PUDDLE_REFLECTION *
        puddleMask;
    puddleBody = mix(
        puddleBody,
        broadReflection,
        fallbackReflectionAmount
    );
    puddleBody +=
        broadReflection *
        animatedShimmer *
        rippleGlint *
        0.050 *
        PUDDLE_RIPPLE_STRENGTH;

    return mix(sceneColor, puddleBody, puddleMask);
}
