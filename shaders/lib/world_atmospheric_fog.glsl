/*
Clean-room analytical world atmosphere.

The implementation is original to this fork and is built from standard
participating-media techniques documented in public graphics literature:
depth reconstruction, exponential height density and Beer-Lambert extinction.
No source code, constants, assets or function structure from another shaderpack
are used here.
*/

float worldFogHash(vec3 p) {
    return fract(sin(dot(p, vec3(17.13, 91.71, 43.37))) * 43758.23);
}

float worldFogValueNoise(vec3 p) {
    vec3 cell = floor(p);
    vec3 local = fract(p);
    local = local * local * (3.0 - 2.0 * local);

    float n000 = worldFogHash(cell);
    float n100 = worldFogHash(cell + vec3(1.0, 0.0, 0.0));
    float n010 = worldFogHash(cell + vec3(0.0, 1.0, 0.0));
    float n110 = worldFogHash(cell + vec3(1.0, 1.0, 0.0));
    float n001 = worldFogHash(cell + vec3(0.0, 0.0, 1.0));
    float n101 = worldFogHash(cell + vec3(1.0, 0.0, 1.0));
    float n011 = worldFogHash(cell + vec3(0.0, 1.0, 1.0));
    float n111 = worldFogHash(cell + vec3(1.0, 1.0, 1.0));

    float lower = mix(mix(n000, n100, local.x), mix(n010, n110, local.x), local.y);
    float upper = mix(mix(n001, n101, local.x), mix(n011, n111, local.x), local.y);
    return mix(lower, upper, local.z);
}

vec3 worldFogPlayerPosition(vec2 uv, float depth) {
    vec4 clipPosition = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 playerPosition = worldFogInverseViewProjection * clipPosition;
    return playerPosition.xyz / max(abs(playerPosition.w), 0.00001);
}

float worldFogHeightIntegral(vec3 playerPosition, float viewDistance) {
    float densityAtCamera = exp(
        -WORLD_FOG_HEIGHT_FALLOFF * (cameraPosition.y - WORLD_FOG_ALTITUDE)
    );
    densityAtCamera = clamp(densityAtCamera, 0.02, 8.0);

    float verticalTravel = WORLD_FOG_HEIGHT_FALLOFF * playerPosition.y;
    float integralCorrection = 1.0;

    if (abs(verticalTravel) > 0.001) {
        integralCorrection = (1.0 - exp(-verticalTravel)) / verticalTravel;
    }

    return viewDistance * densityAtCamera * max(integralCorrection, 0.0);
}

vec3 applyWorldAtmosphericFog(
    vec3 sceneColor,
    vec2 uv,
    float sceneDepth,
    vec3 atmosphericColor,
    float outdoorVisibility,
    float phaseDensity,
    float fogHorizon,
    vec3 lodPlayerPosition,
    float lodMask
) {
    // lodMask is 1 where the pixel shows a Distant Horizons LOD. Vanilla depth
    // reads 1.0 there, so the LOD position replaces the reconstruction.
    vec3 playerPosition = mix(
        worldFogPlayerPosition(uv, sceneDepth),
        lodPlayerPosition,
        lodMask
    );
    float skyMask = step(0.9999, sceneDepth) * (1.0 - lodMask);
    float reconstructedDistance = length(playerPosition);
    vec3 viewDirection = playerPosition / max(reconstructedDistance, 0.00001);

    // Sky depth and very distant geometry must converge to the same ray length.
    // Keeping this continuous removes the bright one-pixel depth seam at the
    // horizon when terrain switches between geometry and sky during movement.
    // fogHorizon is the vanilla far plane, or the LOD render distance when
    // Distant Horizons extends the visible world.
    float viewDistance = min(reconstructedDistance, fogHorizon);
    float farContinuity = smoothstep(
        fogHorizon * 0.72,
        fogHorizon * 0.98,
        viewDistance
    );
    farContinuity = max(farContinuity, skyMask);
    viewDistance = mix(viewDistance, fogHorizon, farContinuity);
    playerPosition = viewDirection * viewDistance;

    if (viewDistance < 2.0) {
        return sceneColor;
    }

    float heightIntegral = worldFogHeightIntegral(playerPosition, viewDistance);

    // A broad, low-frequency density field. Its coordinates are absolute world
    // coordinates, so player translation cannot drag the pattern across view.
    float noiseProbeDistance = min(viewDistance * 0.48, 72.0);
    vec3 worldMidpoint = cameraPosition + viewDirection * noiseProbeDistance;
    vec3 slowAdvection = frameTimeCounter * vec3(0.010, 0.0015, -0.006);
    float broadVariation = worldFogValueNoise(
        (worldMidpoint + slowAdvection) * vec3(0.020, 0.035, 0.020)
    );
    float densityVariation = mix(0.72, 1.28, smoothstep(0.18, 0.82, broadVariation));

    // Procedural variation is useful in the world but unstable at a silhouette
    // where depth alternates between far terrain and sky. Fade it to uniform
    // density before reaching that boundary.
    densityVariation = mix(densityVariation, 1.0, farContinuity);

    float weatherBoost = mix(0.96, 1.38, rainStrength);
    float opticalDepth =
        WORLD_FOG_DENSITY *
        heightIntegral *
        densityVariation *
        weatherBoost *
        outdoorVisibility *
        phaseDensity;

    float fogOpacity = 1.0 - exp(-max(opticalDepth, 0.0));
    fogOpacity *= smoothstep(4.0, 18.0, viewDistance);
    fogOpacity = min(fogOpacity, mix(0.82, 0.90, phaseDensity));

    return mix(sceneColor, atmosphericColor, fogOpacity);
}
