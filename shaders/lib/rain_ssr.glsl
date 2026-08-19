/*
 * Shared screen-space reflection trace for rain streaks and terrain puddles.
 * The opaque depth copy avoids reflecting translucent water or the weather
 * geometry back into itself.
 */

vec3 rainSSRProject(vec3 viewPosition) {
    vec4 projected = gbufferProjection * vec4(viewPosition, 1.0);
    projected.xyz /= projected.w;
    return projected.xyz * 0.5 + 0.5;
}

vec3 rainSSRViewPosition(vec2 screenPosition, float depth) {
    vec4 clipPosition = vec4(
        screenPosition * 2.0 - 1.0,
        depth * 2.0 - 1.0,
        1.0
    );
    vec4 viewPosition = gbufferProjectionInverse * clipPosition;
    return viewPosition.xyz / viewPosition.w;
}

float rainSSRSceneDepth(vec2 screenPosition) {
    // The weather pass only exposes the stable opaque depth copy. Composite
    // additionally exposes complete depth, including a visible player model.
    float opaqueDepth = texture2D(depthtex1, screenPosition).r;

    #ifdef GBUFFER_WEATHER
        return opaqueDepth;
    #else
        float completeDepth = texture2D(depthtex0, screenPosition).r;
        return min(opaqueDepth, completeDepth);
    #endif
}

vec4 traceRainSSR(
    vec3 rayOrigin,
    vec3 rayDirection,
    float jitter
) {
    vec3 previousMarchPosition =
        rayOrigin + rayDirection * 0.12;
    vec3 marchPosition = previousMarchPosition;
    vec3 screenPosition = rainSSRProject(marchPosition);
    float previousDifference = 0.0;
    bool hasPreviousDifference = false;
    bool foundHit = false;
    vec3 frontPosition = previousMarchPosition;
    vec3 backPosition = previousMarchPosition;
    float hitConfidence = 0.0;

    // Exponential travel reaches nearby vegetation and buildings tens of
    // blocks away. The old linear march stopped after only a few blocks.
    for (int i = 0; i < PUDDLE_SSR_STEPS; i++) {
        float marchDistance = min(
            52.0,
            0.22 +
            (
                exp2(
                    (float(i) + jitter * 0.55) * 0.56
                ) -
                1.0
            ) * 0.32
        );
        marchPosition =
            rayOrigin + rayDirection * marchDistance;

        screenPosition = rainSSRProject(marchPosition);

        if (
            screenPosition.x <= 0.001 ||
            screenPosition.x >= 0.999 ||
            screenPosition.y <= 0.001 ||
            screenPosition.y >= 0.999 ||
            screenPosition.z <= 0.0 ||
            screenPosition.z >= 1.0
        ) {
            hitConfidence = 0.0;
            break;
        }

        float sceneDepth = rainSSRSceneDepth(screenPosition.xy);
        vec3 sceneViewPosition = rainSSRViewPosition(
            screenPosition.xy,
            sceneDepth
        );
        // Compare linear view-space distances. Comparing projected depth made
        // thin grass ribbons and distant objects too easy to skip because the
        // depth distribution is strongly non-linear near the far plane.
        float rayViewDepth = -marchPosition.z;
        float sceneViewDepth = -sceneViewPosition.z;
        float depthDifference = rayViewDepth - sceneViewDepth;
        float immediateThickness =
            0.10 + length(marchPosition) * 0.012;

        if (
            sceneDepth < 0.9998 &&
            (
                (
                    hasPreviousDifference &&
                    depthDifference >= 0.0 &&
                    previousDifference < 0.0
                ) ||
                (
                    !hasPreviousDifference &&
                    depthDifference >= 0.0 &&
                    depthDifference < immediateThickness
                )
            )
        ) {
            frontPosition = hasPreviousDifference ?
                previousMarchPosition : rayOrigin;
            backPosition = marchPosition;
            foundHit = true;
            break;
        }

        previousMarchPosition = marchPosition;
        previousDifference = depthDifference;
        hasPreviousDifference = true;
    }

    // Binary refinement turns the coarse crossing into a stable surface hit.
    if (foundHit) {
        for (int refinementStep = 0; refinementStep < 4; refinementStep++) {
            vec3 middlePosition =
                (frontPosition + backPosition) * 0.5;
            vec3 middleScreenPosition =
                rainSSRProject(middlePosition);
            float middleSceneDepth = rainSSRSceneDepth(
                middleScreenPosition.xy
            );
            vec3 middleSceneViewPosition = rainSSRViewPosition(
                middleScreenPosition.xy,
                middleSceneDepth
            );
            float middleDifference =
                (-middlePosition.z) - (-middleSceneViewPosition.z);

            if (middleDifference >= 0.0) {
                backPosition = middlePosition;
            } else {
                frontPosition = middlePosition;
            }
        }

        marchPosition =
            (frontPosition + backPosition) * 0.5;
        screenPosition = rainSSRProject(marchPosition);
        float finalSceneDepth =
            rainSSRSceneDepth(screenPosition.xy);
        vec3 finalSceneViewPosition =
            rainSSRViewPosition(
                screenPosition.xy,
                finalSceneDepth
            );
        float viewThickness = abs(
            finalSceneViewPosition.z -
            marchPosition.z
        );
        float allowedThickness =
            0.16 + length(marchPosition) * 0.018;
        hitConfidence =
            (
                1.0 -
                smoothstep(
                    allowedThickness,
                    allowedThickness * 3.2,
                    viewThickness
                )
            ) *
            step(finalSceneDepth, 0.9998);
    }

    float borderX =
        smoothstep(0.0, 0.055, screenPosition.x) *
        smoothstep(0.0, 0.055, 1.0 - screenPosition.x);
    float borderY =
        smoothstep(0.0, 0.065, screenPosition.y) *
        smoothstep(0.0, 0.065, 1.0 - screenPosition.y);
    hitConfidence *= borderX * borderY;

    return vec4(
        texture2D(
            gaux1,
            clamp(
                screenPosition.xy,
                vec2(0.002),
                vec2(0.998)
            )
        ).rgb,
        hitConfidence
    );
}
