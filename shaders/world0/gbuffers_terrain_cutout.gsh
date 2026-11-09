#version 400 compatibility
#extension GL_ARB_shader_texture_lod : enable
/*
 * Cinematic Fog - procedural interactive grass
 *
 * Clean-room implementation: the geometry, distribution, wind and player
 * response below are constructed directly from elementary vector geometry.
 * No external model or resource-pack texture is required.
 */

#define GBUFFER_TERRAIN
#define FOLIAGE_V
#define PROCEDURAL_TUFT_GRASS

#include "/lib/config.glsl"

#if GRASS_MODE == 0
    // Vanilla-only mode forwards source geometry and emits no extra vertices.
    #define GRASS_INVOCATIONS 1
#elif GRASS_MODE == 1
    // Four source triangles per crossed vanilla plant produce 96 physical
    // strands nearby: dense enough to be high-end without covering the world.
    #define GRASS_INVOCATIONS 8
#elif GRASS_QUALITY == 0
    #define GRASS_INVOCATIONS 2
#elif GRASS_QUALITY == 1
    #define GRASS_INVOCATIONS 4
#elif GRASS_QUALITY == 2
    #define GRASS_INVOCATIONS 8
#elif GRASS_QUALITY == 3
    #define GRASS_INVOCATIONS 16
#else
    #define GRASS_INVOCATIONS 32
#endif

#if GRASS_MODE == 2
    #define VANILLA_GRASS_ACCENT 1.0
#else
    #define VANILLA_GRASS_ACCENT 0.0
#endif

// Runtime LOD presets. Nearby strands retain the full selected GRASS_QUALITY;
// the end distance is where only one invocation and shared group wind remain.
#if GRASS_LOD_MODE == 0
    #define GRASS_FULL_DETAIL_DISTANCE 4.0
    #define GRASS_LOD_END_DISTANCE 28.0
    #define GRASS_WIND_GROUP_SIZE 12.0
#elif GRASS_LOD_MODE == 1
    #define GRASS_FULL_DETAIL_DISTANCE 6.0
    #define GRASS_LOD_END_DISTANCE 40.0
    #define GRASS_WIND_GROUP_SIZE 10.0
#elif GRASS_LOD_MODE == 2
    #define GRASS_FULL_DETAIL_DISTANCE 9.0
    #define GRASS_LOD_END_DISTANCE 58.0
    #define GRASS_WIND_GROUP_SIZE 8.0
#elif GRASS_LOD_MODE == 3
    #define GRASS_FULL_DETAIL_DISTANCE 13.0
    #define GRASS_LOD_END_DISTANCE 76.0
    #define GRASS_WIND_GROUP_SIZE 6.0
#else
    #define GRASS_FULL_DETAIL_DISTANCE 18.0
    #define GRASS_LOD_END_DISTANCE 96.0
    #define GRASS_WIND_GROUP_SIZE 5.0
#endif

#define GRASS_SIMPLE_DISTANCE \
    (GRASS_FULL_DETAIL_DISTANCE + \
    (GRASS_LOD_END_DISTANCE - GRASS_FULL_DETAIL_DISTANCE) * 0.72)

// Past this point the surviving six distant strands have already become
// sub-pixel detail in the atmospheric fog. Their height reaches zero smoothly
// before emission stops, avoiding both raster cost and a hard distance ring.
#define GRASS_RENDER_FADE_START (GRASS_LOD_END_DISTANCE * 1.24)
#define GRASS_RENDER_CUTOFF (GRASS_LOD_END_DISTANCE * 1.64)

// Each invocation emits three independent six-vertex curved ribbons. Only
// invocation zero also forwards the source triangle: 3 + (3 * 6) = 21.
layout(triangles) in;
layout(invocations = GRASS_INVOCATIONS) in;
#if GRASS_MODE == 0
    // Pass-through only. The declared output size (vertices x components)
    // sets how many geometry threads the GPU can keep in flight; declaring 21
    // here made every leaf and flower triangle pay for blades it never emits.
    layout(triangle_strip, max_vertices = 3) out;
#else
    layout(triangle_strip, max_vertices = 21) out;
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
#ifdef IS_IRIS
    uniform vec3 relativeEyePosition;
#else
    // OptiFine lacks this uniform: the player is treated as the camera,
    // which is exact in first person.
    const vec3 relativeEyePosition = vec3(0.0);
#endif
uniform float frameTimeCounter;
uniform sampler2D tex;

#if AA_TYPE > 1
    uniform vec2 taaOffset;
#endif

/* Values produced by gbuffers_terrain.vsh. */
in vec2 texcoordV[];
in vec4 tintColorV[];
in float frogAdjustV[];
in vec3 directLightColorV[];
in vec3 candleColorV[];
in float directLightStrengthV[];
in vec3 omniLightV[];
in float surfaceSkyExposureV[];
in float isEmissiveEntityV[];
in float isFoliageV[];
in vec3 grassPlayerPositionV[];
in vec3 grassSourceNormalV[];
in float grassEntityIdV[];
in float grassFogCoordV[];

#if defined SHADOW_CASTING && SHADOW_LOCK > 0 && !defined NETHER
    in vec3 vWorldPosV[];
    in vec3 vNormalV[];
    in vec3 vBiasV[];
#endif

#if defined SHADOW_CASTING && !defined NETHER
    in vec3 shadowPosV[];
    in float shadowDiffuseV[];
#endif

#if defined MATERIAL_GLOSS && !defined NETHER
    in vec3 flatNormalV[];
    in vec3 viewPositionNormalizedV[];
    in vec2 lmcoordAltV[];
    in float glossFactorV[];
    in float glossPowerV[];
    in float lumaFactorV[];
    in float lumaPowerV[];
#endif

/* Values consumed by gbuffers_terrain.fsh. */
out vec2 texcoord;
out vec4 tintColor;
out float frogAdjust;
out vec3 directLightColor;
out vec3 candleColor;
out float directLightStrength;
out vec3 omniLight;
out float surfaceSkyExposure;
out float isEmissiveEntity;
out float isFoliage;
out float grassFogCoord;
out vec2 grassTuftCoord;
flat out float grassTuftSeed;
flat out float grassTuftLayer;

// Per-strand source attributes. They are constant for every emitted vertex of
// one blade, so interpolate them once instead of repeating the same barycentric
// lighting work four or six times.
vec2 bladeBaseTexcoord;
vec4 bladeBaseTintColor;
float bladeBaseFrogAdjust;
vec3 bladeBaseDirectLightColor;
vec3 bladeBaseCandleColor;
float bladeBaseDirectLightStrength;
vec3 bladeBaseOmniLight;
float bladeBaseSurfaceSkyExposure;

#if defined SHADOW_CASTING && !defined NETHER
    vec3 bladeBaseShadowPos;
    float bladeBaseShadowDiffuse;
#endif

#if defined MATERIAL_GLOSS && !defined NETHER
    vec2 bladeBaseLmcoordAlt;
    float bladeBaseLumaFactor;
    float bladeBaseLumaPower;
#endif

#if defined SHADOW_CASTING && SHADOW_LOCK > 0 && !defined NETHER
    out vec3 vWorldPos;
    out vec3 vNormal;
    out vec3 vBias;
#endif

#if defined SHADOW_CASTING && !defined NETHER
    out vec3 shadowPos;
    out float shadowDiffuse;
#endif

#if defined MATERIAL_GLOSS && !defined NETHER
    out vec3 flatNormal;
    out vec3 viewPositionNormalized;
    out vec2 lmcoordAlt;
    out float glossFactor;
    out float glossPower;
    out float lumaFactor;
    out float lumaPower;
#endif

// Stable scalar variation from an absolute world point. Integer avalanching is
// substantially cheaper here than two transcendental operations per sample.
// The output range and all artistic min/max values remain unchanged.
float grassHash(vec3 worldPoint, float channel) {
    uvec4 bits = floatBitsToUint(vec4(worldPoint, channel));
    uint hashValue =
        bits.x * 236887691u ^
        bits.y * 1469598107u ^
        bits.z * 2976579761u ^
        bits.w * 104395301u;
    hashValue ^= hashValue >> 13;
    hashValue *= 277803737u;
    hashValue ^= hashValue >> 16;
    hashValue *= 179424673u;
    hashValue ^= hashValue >> 15;
    return float(hashValue & 0x00ffffffu) * 0.000000059604644775390625;
}

// Four stable samples blended with a cubic curve form continuous value noise.
float grassValueNoise(vec2 samplePoint, float channel) {
    vec2 cell = floor(samplePoint);
    vec2 localPoint = fract(samplePoint);
    vec2 blendWeight =
        localPoint * localPoint * (3.0 - 2.0 * localPoint);

    float density00 = grassHash(vec3(cell.x, 0.0, cell.y), channel);
    float density10 = grassHash(vec3(cell.x + 1.0, 0.0, cell.y), channel);
    float density01 = grassHash(vec3(cell.x, 0.0, cell.y + 1.0), channel);
    float density11 = grassHash(vec3(cell.x + 1.0, 0.0, cell.y + 1.0), channel);

    float lowerDensity = mix(density00, density10, blendWeight.x);
    float upperDensity = mix(density01, density11, blendWeight.x);
    return mix(lowerDensity, upperDensity, blendWeight.y);
}

// The first layer spans roughly 20-25 blocks and creates large meadow pools.
// A weaker medium layer softens their borders without filling every gap.
float grassPatchDensity(vec2 worldXZ) {
    float meadowShape = grassValueNoise(worldXZ * 0.045, 41.0);
    float borderShape = grassValueNoise(
        worldXZ * 0.115 + vec2(13.7, -8.9),
        67.0
    );
    return meadowShape * 0.80 + borderShape * 0.20;
}

vec3 interpolate3(vec3 values0, vec3 values1, vec3 values2, vec3 weights) {
    return values0 * weights.x + values1 * weights.y + values2 * weights.z;
}

vec4 interpolate4(vec4 values0, vec4 values1, vec4 values2, vec3 weights) {
    return values0 * weights.x + values1 * weights.y + values2 * weights.z;
}

vec2 interpolate2(vec2 values0, vec2 values1, vec2 values2, vec3 weights) {
    return values0 * weights.x + values1 * weights.y + values2 * weights.z;
}

float interpolate1(float values0, float values1, float values2, vec3 weights) {
    return values0 * weights.x + values1 * weights.y + values2 * weights.z;
}

void copySourceVaryings(int vertexIndex) {
    texcoord = texcoordV[vertexIndex];
    tintColor = tintColorV[vertexIndex];
    frogAdjust = frogAdjustV[vertexIndex];
    directLightColor = directLightColorV[vertexIndex];
    candleColor = candleColorV[vertexIndex];
    directLightStrength = directLightStrengthV[vertexIndex];
    omniLight = omniLightV[vertexIndex];
    surfaceSkyExposure = surfaceSkyExposureV[vertexIndex];
    isEmissiveEntity = isEmissiveEntityV[vertexIndex];
    isFoliage = isFoliageV[vertexIndex];
    grassFogCoord = grassFogCoordV[vertexIndex];
    // On source terrain this varying carries stable absolute-world XZ. The
    // fragment stage reuses it to shade a continuous micro-grass carpet.
    grassTuftCoord =
        grassPlayerPositionV[vertexIndex].xz + cameraPosition.xz;
    grassTuftSeed = 0.0;
    grassTuftLayer = -2.0;

    #if defined SHADOW_CASTING && SHADOW_LOCK > 0 && !defined NETHER
        vWorldPos = vWorldPosV[vertexIndex];
        vNormal = vNormalV[vertexIndex];
        vBias = vBiasV[vertexIndex];
    #endif

    #if defined SHADOW_CASTING && !defined NETHER
        shadowPos = shadowPosV[vertexIndex];
        shadowDiffuse = shadowDiffuseV[vertexIndex];
    #endif

    #if defined MATERIAL_GLOSS && !defined NETHER
        flatNormal = flatNormalV[vertexIndex];
        viewPositionNormalized = viewPositionNormalizedV[vertexIndex];
        lmcoordAlt = lmcoordAltV[vertexIndex];
        glossFactor = glossFactorV[vertexIndex];
        glossPower = glossPowerV[vertexIndex];
        lumaFactor = lumaFactorV[vertexIndex];
        lumaPower = lumaPowerV[vertexIndex];
    #endif
}

void emitSourceTriangle(bool isProceduralGrassGround) {
    for (int vertexIndex = 0; vertexIndex < 3; ++vertexIndex) {
        copySourceVaryings(vertexIndex);
        // -1 identifies only the receiving grass-block top in the fragment
        // stage. Other terrain keeps the ordinary value of -2.
        grassTuftLayer = isProceduralGrassGround ? -1.0 : -2.0;
        gl_Position = gl_in[vertexIndex].gl_Position;
        EmitVertex();
    }
    EndPrimitive();
}

void prepareBladeVaryings(vec3 weights) {
    bladeBaseTexcoord = interpolate2(texcoordV[0], texcoordV[1], texcoordV[2], weights);
    bladeBaseTintColor = interpolate4(tintColorV[0], tintColorV[1], tintColorV[2], weights);
    bladeBaseFrogAdjust = interpolate1(frogAdjustV[0], frogAdjustV[1], frogAdjustV[2], weights);
    bladeBaseDirectLightColor = interpolate3(directLightColorV[0], directLightColorV[1], directLightColorV[2], weights);
    bladeBaseCandleColor = interpolate3(candleColorV[0], candleColorV[1], candleColorV[2], weights);
    bladeBaseDirectLightStrength = max(
        interpolate1(directLightStrengthV[0], directLightStrengthV[1], directLightStrengthV[2], weights),
        0.32
    );
    bladeBaseOmniLight = interpolate3(omniLightV[0], omniLightV[1], omniLightV[2], weights);
    bladeBaseSurfaceSkyExposure = interpolate1(
        surfaceSkyExposureV[0], surfaceSkyExposureV[1], surfaceSkyExposureV[2], weights
    );

    #if defined SHADOW_CASTING && !defined NETHER
        bladeBaseShadowPos = interpolate3(shadowPosV[0], shadowPosV[1], shadowPosV[2], weights);
        bladeBaseShadowDiffuse = interpolate1(shadowDiffuseV[0], shadowDiffuseV[1], shadowDiffuseV[2], weights);
    #endif

    #if defined MATERIAL_GLOSS && !defined NETHER
        bladeBaseLmcoordAlt = interpolate2(lmcoordAltV[0], lmcoordAltV[1], lmcoordAltV[2], weights);
        bladeBaseLumaFactor = interpolate1(lumaFactorV[0], lumaFactorV[1], lumaFactorV[2], weights);
        bladeBaseLumaPower = interpolate1(lumaPowerV[0], lumaPowerV[1], lumaPowerV[2], weights);
    #endif
}

void loadBladeVaryings(
    vec3 playerPosition,
    vec3 playerNormal,
    vec3 colorScale,
    vec2 tuftCoord,
    float tuftSeed,
    float tuftLayer
) {
    // A single atlas point supplies colour detail. The visible silhouette is
    // created by geometry, so the system does not need an alpha texture.
    texcoord = bladeBaseTexcoord;
    tintColor = bladeBaseTintColor;
    tintColor.rgb *= colorScale;
    frogAdjust = bladeBaseFrogAdjust;
    directLightColor = bladeBaseDirectLightColor;
    candleColor = bladeBaseCandleColor;
    directLightStrength = bladeBaseDirectLightStrength;
    omniLight = bladeBaseOmniLight;
    surfaceSkyExposure = bladeBaseSurfaceSkyExposure;
    isEmissiveEntity = 0.0;
    // Values above 0.75 identify generated blades in the fragment shader so
    // their colour does not inherit isolated dark texels from the block atlas.
    isFoliage = 0.85;
    grassTuftCoord = tuftCoord;
    grassTuftSeed = tuftSeed;
    grassTuftLayer = tuftLayer;

    vec4 viewPosition = gbufferModelView * vec4(playerPosition, 1.0);
    grassFogCoord = length(viewPosition.xyz);
    gl_Position = gbufferProjection * viewPosition;

    #if AA_TYPE > 1
        gl_Position.xy += taaOffset * gl_Position.w;
    #endif

    #if defined SHADOW_CASTING && SHADOW_LOCK > 0 && !defined NETHER
        vWorldPos = playerPosition;
        vNormal = playerNormal;
        vBias = vec3(0.0);
    #endif

    #if defined SHADOW_CASTING && !defined NETHER
        // Reuse the receiving ground point's shadow lookup. This keeps the new
        // blade coherently inside terrain shadows without a second shadow pass.
        shadowPos = bladeBaseShadowPos;
        shadowDiffuse = bladeBaseShadowDiffuse;
    #endif

    #if defined MATERIAL_GLOSS && !defined NETHER
        flatNormal = normalize(mat3(gbufferModelView) * playerNormal);
        viewPositionNormalized = normalize(viewPosition.xyz);
        lmcoordAlt = bladeBaseLmcoordAlt;
        glossFactor = 0.08;
        glossPower = 3.0;
        lumaFactor = bladeBaseLumaFactor;
        lumaPower = bladeBaseLumaPower;
    #endif
}

void emitPhysicalBlade(
    vec3 rootLeft,
    vec3 rootRight,
    vec3 middleLeft,
    vec3 middleRight,
    vec3 tipLeft,
    vec3 tipRight,
    vec3 weights,
    vec3 colorScale,
    float tuftSeed
) {
    vec3 faceNormal = normalize(
        cross(rootRight - rootLeft, middleLeft - rootLeft)
    );

    loadBladeVaryings(
        rootLeft, faceNormal, colorScale * 0.78,
        vec2(0.0, 0.0), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        rootRight, faceNormal, colorScale * 0.78,
        vec2(1.0, 0.0), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        middleLeft, faceNormal, colorScale,
        vec2(0.0, 0.56), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        middleRight, faceNormal, colorScale,
        vec2(1.0, 0.56), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        tipLeft, faceNormal, colorScale * 1.06,
        vec2(0.0, 1.0), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        tipRight, faceNormal, colorScale * 1.06,
        vec2(1.0, 1.0), tuftSeed, 9.0
    );
    EmitVertex();
    EndPrimitive();
}

// Beyond the configurable LOD transition, a strand becomes one opaque quad.
// It retains real width and stable colour but drops the middle joint, reducing
// emitted geometry from six to four vertices without returning to alpha cards.
void emitSimplePhysicalBlade(
    vec3 rootLeft,
    vec3 rootRight,
    vec3 tipLeft,
    vec3 tipRight,
    vec3 weights,
    vec3 colorScale,
    float tuftSeed
) {
    vec3 faceNormal = normalize(
        cross(rootRight - rootLeft, tipLeft - rootLeft)
    );

    loadBladeVaryings(
        rootLeft, faceNormal, colorScale * 0.78,
        vec2(0.0, 0.0), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        rootRight, faceNormal, colorScale * 0.78,
        vec2(1.0, 0.0), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        tipLeft, faceNormal, colorScale * 1.06,
        vec2(0.0, 1.0), tuftSeed, 9.0
    );
    EmitVertex();
    loadBladeVaryings(
        tipRight, faceNormal, colorScale * 1.06,
        vec2(1.0, 1.0), tuftSeed, 9.0
    );
    EmitVertex();
    EndPrimitive();
}


void emitBlade(
    vec3 weights,
    float bladeChannel,
    vec3 stableTriangleSeed,
    float strandIndex,
    float meadowDensity,
    float lodWeight,
    float viewDistance,
    vec3 replacementRoot,
    float replacementRootWeight,
    float replacementHeightScale,
    float replacementMinimumHeight,
    float replacementMaximumHeight,
    float vanillaAccent
) {
    prepareBladeVaryings(weights);
    vec3 root = interpolate3(
        grassPlayerPositionV[0],
        grassPlayerPositionV[1],
        grassPlayerPositionV[2],
        weights
    );
    // Lift the root slightly above the receiving face. This prevents the wide
    // base from intersecting the grass-block surface at shallow view angles.
    root.y += 0.004;
    root = mix(root, replacementRoot, replacementRootWeight);

    vec3 worldRoot = root + cameraPosition;

    // All discrete properties use the quantized triangle seed. They therefore
    // cannot change when camera-relative floating-point coordinates drift.
    float heightNoise = grassHash(stableTriangleSeed, bladeChannel + 1.0);
    float widthNoise = grassHash(stableTriangleSeed, bladeChannel + 2.0);
    float angleNoise = grassHash(stableTriangleSeed, bladeChannel + 3.0);
    float curveNoise = grassHash(stableTriangleSeed, bladeChannel + 4.0);
    float motionNoise = grassHash(stableTriangleSeed, bladeChannel + 5.0);
    float tallNoise = grassHash(stableTriangleSeed, bladeChannel + 8.0);

    // Most strands are deliberately short and hair-like. Medium tips add an
    // irregular silhouette; genuinely tall stems are rare even in rich meadows.
    float height = mix(0.17, 0.37, heightNoise);
    float mediumPresence = smoothstep(0.72, 0.92, tallNoise);
    height = mix(
        height,
        mix(0.35, 0.54, heightNoise),
        mediumPresence
    );
    float rareTallSample = meadowDensity * 0.54 + tallNoise * 0.46;
    float rareTallPresence = smoothstep(0.95, 0.992, rareTallSample);
    height = mix(
        height,
        mix(0.55, 0.78, heightNoise),
        rareTallPresence
    );
    height = clamp(
        height * replacementHeightScale,
        replacementMinimumHeight,
        replacementMaximumHeight
    );
    height *= mix(0.32, 1.0, lodWeight);

    // A finite physical half-width replaces the previous zero-thickness alpha
    // cuts. Distant LOD strands become slightly broader as their count falls.
    float distanceThickness = mix(
        1.0,
        1.85,
        smoothstep(18.0, 72.0, viewDistance)
    );
    float rootRadius =
        mix(0.014, 0.024, widthNoise) * distanceThickness;

    // Golden-angle stratification prevents rows while the stable random offset
    // stops repeated compass-aligned ribbons.
    float rotation =
        strandIndex * 2.39996322973 + angleNoise * 0.74;

    vec2 naturalLeanDirection = vec2(cos(rotation), sin(rotation));
    vec2 naturalLean =
        naturalLeanDirection * mix(0.018, 0.15, curveNoise) * height;

    // Nearby strands retain independent phases. Distant roots map to stable
    // world-space cells, so an entire meadow group shares one cheaper motion.
    float windGroupBlend = smoothstep(
        GRASS_FULL_DETAIL_DISTANCE * 1.20,
        GRASS_LOD_END_DISTANCE * 0.82,
        viewDistance
    );
    vec2 windGroupCell = floor(
        worldRoot.xz / GRASS_WIND_GROUP_SIZE
    );
    vec2 windGroupCenter =
        (windGroupCell + vec2(0.5)) * GRASS_WIND_GROUP_SIZE;
    vec3 windGroupSeed = vec3(
        windGroupCell.x,
        0.0,
        windGroupCell.y
    );
    float groupMotionNoise = grassHash(windGroupSeed, 109.0);

    // Blend the wave inputs before evaluating sine. This keeps the old two-wave
    // cost rather than evaluating separate individual and group animations.
    vec2 windPhasePosition = mix(
        worldRoot.xz,
        windGroupCenter,
        windGroupBlend
    );
    float windPhaseNoise = mix(
        motionNoise,
        groupMotionNoise,
        windGroupBlend
    );
    float secondaryPhase = mix(
        bladeChannel,
        groupMotionNoise * 6.2831853,
        windGroupBlend
    );
    float primarySpeed = mix(
        mix(0.90, 1.35, motionNoise),
        mix(0.72, 1.02, groupMotionNoise),
        windGroupBlend
    );
    float secondarySpeed = mix(
        mix(1.35, 1.85, motionNoise),
        mix(1.02, 1.32, groupMotionNoise),
        windGroupBlend
    );
    float travellingWave = sin(
        windPhasePosition.x * 0.19 + windPhasePosition.y * 0.14 +
        frameTimeCounter * primarySpeed
    );
    float secondaryWave = sin(
        windPhasePosition.x * -0.11 + windPhasePosition.y * 0.23 +
        frameTimeCounter * secondarySpeed + secondaryPhase
    );
    motionNoise = windPhaseNoise;
    float slowGust = 0.55 + 0.45 * sin(
        frameTimeCounter * 0.38 +
        mix(worldRoot.x, windGroupCenter.x, windGroupBlend) * 0.052 -
        mix(worldRoot.z, windGroupCenter.y, windGroupBlend) * 0.041
    );
    const vec2 mainWindDirection = vec2(0.86092653, 0.51041796);
    vec2 crossWindDirection = vec2(-mainWindDirection.y, mainWindDirection.x);
    vec2 windOffset =
        mainWindDirection *
            (travellingWave * 0.75 + secondaryWave * 0.25) *
            mix(0.105, 0.225, motionNoise) *
            (0.70 + 0.62 * slowGust) +
        crossWindDirection * secondaryWave * 0.065;
    windOffset *= mix(0.32, 1.45, clamp(height / 1.60, 0.0, 1.0));

    // In player space the player's head is -relativeEyePosition. Therefore
    // root.xz + relativeEyePosition.xz is the horizontal player-to-root vector.
    vec2 playerToRoot = root.xz + relativeEyePosition.xz;
    float squaredDistance = dot(playerToRoot, playerToRoot);
    float inversePlayerDistance = inversesqrt(
        max(squaredDistance, 0.000001)
    );
    float playerDistance = squaredDistance * inversePlayerDistance;

    vec2 fallbackDirection = naturalLeanDirection;
    vec2 pushDirection = playerToRoot * inversePlayerDistance;
    pushDirection = mix(fallbackDirection, pushDirection, step(0.000001, squaredDistance));

    // The camera-to-eye offset is nearly zero in first person and several
    // blocks long in third person. A tighter third-person radius prevents the
    // elevated camera from revealing an unnaturally wide flattened disc.
    float thirdPersonView = smoothstep(
        0.35,
        1.35,
        length(relativeEyePosition)
    );
    float interactionRadius = mix(2.85, 1.38, thirdPersonView);

    // Map the interaction radius to [0,1], then use the cubic smooth curve
    // 3t^2-2t^3. Both ends have zero slope, avoiding a visible radius edge.
    float radialWeight = clamp(
        1.0 - playerDistance / interactionRadius,
        0.0,
        1.0
    );
    float interaction =
        radialWeight * radialWeight * (3.0 - 2.0 * radialWeight);

    // Camera delta supplies a short directional wake while walking. Its length
    // is clamped so teleportation or origin rebasing cannot launch the grass.
    vec2 frameMotion = (cameraPosition - previousCameraPosition).xz;
    float frameMotionLength = length(frameMotion);
    vec2 movementDirection = frameMotion * inversesqrt(
        max(dot(frameMotion, frameMotion), 0.000001)
    );
    float movementStrength = clamp(frameMotionLength * 8.0, 0.0, 1.0);
    movementDirection *= step(0.000001, frameMotionLength);

    float heightResponse = mix(
        0.82,
        1.28,
        clamp(height / 2.0, 0.0, 1.0)
    );
    float radialBendStrength = mix(1.24, 0.42, thirdPersonView);
    float wakeBendStrength = mix(0.62, 0.24, thirdPersonView);
    vec2 playerBend =
        pushDirection *
            (radialBendStrength * interaction * heightResponse) +
        movementDirection *
            (wakeBendStrength * interaction * movementStrength);
    vec2 horizontalBend = naturalLean + windOffset + playerBend;

    // A separate middle section gives the physical ribbon a real curved profile
    // instead of the flat silhouette of a camera-facing image card.
    vec2 middleBend =
        naturalLean * 0.35 + windOffset * 0.31 + playerBend * 0.30;
    vec3 middleCenter = root + vec3(
        middleBend.x,
        max(
            height * mix(0.48, 0.60, curveNoise) -
                mix(0.08, 0.018, thirdPersonView) * interaction,
            0.08
        ),
        middleBend.y
    );

    vec3 tipCenter = root + vec3(
        horizontalBend.x,
        max(
            height - mix(
                mix(
                    0.24,
                    0.48,
                    clamp((heightResponse - 0.82) / 0.46, 0.0, 1.0)
                ),
                mix(
                    0.055,
                    0.115,
                    clamp((heightResponse - 0.82) / 0.46, 0.0, 1.0)
                ),
                thirdPersonView
            ) * interaction,
            0.12
        ),
        horizontalBend.y
    );

    float colorNoise = grassHash(stableTriangleSeed, bladeChannel + 6.0);
    vec3 coolBlade = vec3(0.82, 0.90, 0.86);
    vec3 warmBlade = vec3(0.96, 0.98, 0.84);
    vec3 colorScale = mix(
        coolBlade,
        warmBlade,
        colorNoise
    );
    // Full-meadow mode keeps naturally generated vanilla plants readable
    // inside the surrounding field with a restrained cooler/brighter accent.
    colorScale *= mix(
        vec3(1.0),
        vec3(0.94, 1.075, 0.90),
        vanillaAccent
    );

    // texcoord is constant across a generated strand. Reproduce the fragment
    // colour equation once here: mix(texture * tint, tint, 0.78). The fragment
    // stage can then skip the identical atlas lookup for every blade pixel.
    vec3 bladeAtlasColor = textureLod(tex, bladeBaseTexcoord, 0.0).rgb;
    colorScale *= mix(bladeAtlasColor, vec3(1.0), 0.78);

    // Width orientation comes only from absolute-world hash and never from the
    // camera, eliminating camera-motion rotation and temporal flicker.
    vec3 ribbonWidth = vec3(
        naturalLeanDirection.x,
        0.0,
        naturalLeanDirection.y
    );

    vec3 rootLeft = root - ribbonWidth * rootRadius;
    vec3 rootRight = root + ribbonWidth * rootRadius;

    // Keep both root endpoints on the current grass-block top. The curved upper
    // strand may bend beyond the edge, but its physical base never floats.
    vec2 blockMinimum =
        floor(worldRoot.xz) + vec2(0.018) - cameraPosition.xz;
    vec2 blockMaximum =
        floor(worldRoot.xz) + vec2(0.982) - cameraPosition.xz;
    rootLeft.xz = clamp(rootLeft.xz, blockMinimum, blockMaximum);
    rootRight.xz = clamp(rootRight.xz, blockMinimum, blockMaximum);

    float middleRadius = rootRadius * mix(0.62, 0.76, curveNoise);
    float tipRadius = rootRadius * mix(0.30, 0.43, widthNoise);
    vec3 middleLeft = middleCenter - ribbonWidth * middleRadius;
    vec3 middleRight = middleCenter + ribbonWidth * middleRadius;
    vec3 tipLeft = tipCenter - ribbonWidth * tipRadius;
    vec3 tipRight = tipCenter + ribbonWidth * tipRadius;
    float tuftSeed = grassHash(
        stableTriangleSeed,
        bladeChannel + 31.0
    );

    if (viewDistance > GRASS_SIMPLE_DISTANCE) {
        emitSimplePhysicalBlade(
            rootLeft,
            rootRight,
            tipLeft,
            tipRight,
            weights,
            colorScale,
            tuftSeed
        );
    } else {
        emitPhysicalBlade(
            rootLeft,
            rootRight,
            middleLeft,
            middleRight,
            tipLeft,
            tipRight,
            weights,
            colorScale,
            tuftSeed
        );
    }
}

// Convert one triangle of a vanilla crossed-grass model into real strands.
// The four triangles of the model cooperate to form one dense local cluster.
// Sub-block variation fills the original plant footprint, but never changes
// which world blocks contain grass.
void emitVanillaGrassCluster(
    bool isTwoBlockGrass,
    vec3 triangleCenter,
    vec3 stableTriangleSeed,
    float playerDistance
) {
    float nearDetail = 1.0 - smoothstep(
        GRASS_FULL_DETAIL_DISTANCE,
        GRASS_LOD_END_DISTANCE,
        playerDistance
    );
    // Existing vanilla plants remain distinct accents in full-meadow mode;
    // cap their local cluster at 96 strands instead of multiplying it by the
    // much larger per-block cinematic meadow invocation count.
    float vanillaInvocationCap = min(float(GRASS_INVOCATIONS), 8.0);
    float invocationBudget = mix(
        1.0,
        vanillaInvocationCap,
        nearDetail
    );
    float invocationWeight = clamp(
        invocationBudget - float(gl_InvocationID),
        0.0,
        1.0
    );
    invocationWeight = invocationWeight * invocationWeight *
        (3.0 - 2.0 * invocationWeight);
    if (invocationWeight <= 0.015) {
        return;
    }

    vec3 worldTriangleCenter = triangleCenter + cameraPosition;
    float sourceMinimumY = min(
        grassPlayerPositionV[0].y,
        min(grassPlayerPositionV[1].y, grassPlayerPositionV[2].y)
    );
    // Vanilla randomly offsets short-grass models slightly downward. Flooring
    // that displaced coordinate placed some procedural roots one whole block
    // too low, making valid plants look filtered out or grow below ledges.
    // Rounding recovers the integer Y of the actual plant block while keeping
    // the original XZ block identity unchanged.
    float sourceBlockY = floor(
        sourceMinimumY + cameraPosition.y + 0.5
    );
    vec3 clusterCenter = vec3(
        floor(worldTriangleCenter.x) + 0.5 - cameraPosition.x,
        sourceBlockY - cameraPosition.y + 0.006,
        floor(worldTriangleCenter.z) + 0.5 - cameraPosition.z
    );

        const int clusterBlades = 3;
    for (int bladeIndex = 0; bladeIndex < clusterBlades; ++bladeIndex) {
        float globalIndex = float(gl_InvocationID * 3 + bladeIndex);
        float channel = globalIndex * 7.0;
        float radialSample = fract(
            grassHash(stableTriangleSeed, 311.0) +
            (globalIndex + 0.5) * 0.61803398875
        );
        float angularSample = fract(
            grassHash(stableTriangleSeed, 313.0) +
            (globalIndex + 0.5) * 0.41421356237
        );
        // Every root stays inside the exact vanilla plant block. Randomness is
        // limited to strand placement within that existing footprint.
        float radius = sqrt(radialSample) * 0.42;
        float angle = angularSample * 6.2831853;
        vec3 replacementRoot = clusterCenter + vec3(
            cos(angle) * radius,
            0.0,
            sin(angle) * radius
        );

        float heightScale = isTwoBlockGrass ? 4.0 : 2.35;
        float minimumHeight = isTwoBlockGrass ? 1.10 : 0.42;
        float maximumHeight = isTwoBlockGrass ? 1.88 : 0.98;

        emitBlade(
            vec3(0.33333334),
            channel + 320.0,
            stableTriangleSeed,
            globalIndex,
            0.76,
            invocationWeight,
            playerDistance,
            replacementRoot,
            1.0,
            heightScale,
            minimumHeight,
            maximumHeight,
            VANILLA_GRASS_ACCENT
        );
    }
}

void main() {
    float sourceId =
        (grassEntityIdV[0] + grassEntityIdV[1] + grassEntityIdV[2]) / 3.0;

    bool isVanillaShortGrass =
        abs(sourceId - ENTITY_VANILLA_GRASS) < 0.25;
    bool isVanillaTallGrassLower =
        abs(sourceId - ENTITY_VANILLA_TALL_GRASS_LOWER) < 0.25;
    bool isVanillaTallGrassUpper =
        abs(sourceId - ENTITY_VANILLA_TALL_GRASS_UPPER) < 0.25;

    #if GRASS_MODE == 0
        // True off mode: retain the original vanilla panel without procedural
        // replacement, world coverage, distribution or strand animation.
        if (gl_InvocationID == 0) {
            emitSourceTriangle(false);
        }
        return;
    #else

        // Replacement and full-meadow modes both preserve every source vanilla
        // plant as a distinct physical cluster. Full mode additionally grows
        // the lower meadow layer from grass-block top faces farther below.
        // The upper model half is represented by the height of the lower
        // cluster. Emitting it again would double density and create a seam.
        if (isVanillaTallGrassUpper) {
            return;
        }

        if (isVanillaShortGrass || isVanillaTallGrassLower) {
            vec3 vanillaTriangleCenter =
                (grassPlayerPositionV[0] + grassPlayerPositionV[1] + grassPlayerPositionV[2]) / 3.0;
            float vanillaDistance = length(
                vanillaTriangleCenter.xz + relativeEyePosition.xz
            );
            vec3 vanillaWorldCenter = vanillaTriangleCenter + cameraPosition;
            vec3 vanillaSeed =
                floor(vanillaWorldCenter * 64.0 + 0.5) * 0.015625;
            emitVanillaGrassCluster(
                isVanillaTallGrassLower,
                vanillaTriangleCenter,
                vanillaSeed,
                vanillaDistance
            );
            return;
        }
    #endif

    vec3 sourceNormal = normalize(
        grassSourceNormalV[0] + grassSourceNormalV[1] + grassSourceNormalV[2]
    );
    bool isGrassSurface = abs(sourceId - ENTITY_GRASS_SURFACE) < 0.25;
    bool isTopFace = sourceNormal.y > 0.88;

    if (!isGrassSurface || !isTopFace) {
        // Geometry-shader invocations all receive the same source triangle.
        // Ordinary cutout terrain is forwarded exactly once and does no grass
        // distribution, wind or interaction work.
        if (gl_InvocationID == 0) {
            emitSourceTriangle(false);
        }
        return;
    }

    vec3 triangleCenter =
        (grassPlayerPositionV[0] + grassPlayerPositionV[1] + grassPlayerPositionV[2]) / 3.0;
    float playerDistance = length(triangleCenter.xz + relativeEyePosition.xz);

    vec3 worldTriangleCenter = triangleCenter + cameraPosition;
    vec3 stableTriangleSeed =
        floor(worldTriangleCenter * 64.0 + 0.5) * 0.015625;

    #if GRASS_MODE != 2
        // Vanilla-replacement mode leaves ordinary grass-block surfaces alone.
        // Physical strands are emitted only by source plants handled above.
        if (gl_InvocationID == 0) {
            emitSourceTriangle(false);
        }
        return;
    #endif

    float renderSurvival = 1.0 - smoothstep(
        GRASS_RENDER_FADE_START,
        GRASS_RENDER_CUTOFF,
        playerDistance
    );
    if (renderSurvival <= 0.015) {
        if (gl_InvocationID == 0) {
            emitSourceTriangle(false);
        }
        return;
    }

    // Evaluate meadow membership from the integer block coordinate, not from
    // either source triangle. Both halves of a grass-block top therefore make
    // one stable decision. Two smooth world-noise scales form large connected
    // fields; the stable rank only feathers their borders into natural islands.
    vec2 grassBlockCenter = floor(worldTriangleCenter.xz) + vec2(0.5);
    vec3 grassBlockSeed = vec3(grassBlockCenter.x, 0.0, grassBlockCenter.y);
    float broadDensity = grassPatchDensity(grassBlockCenter);
    float meadowProbability = smoothstep(0.405, 0.565, broadDensity);
    float meadowRank = grassHash(grassBlockSeed, 149.0);
    bool hasPhysicalMeadow = meadowRank < meadowProbability;

    if (gl_InvocationID == 0) {
        // The fine ground carpet follows the same mask. Clearings expose the
        // original grass-block top and do not pay any generated-strand cost.
        emitSourceTriangle(hasPhysicalMeadow);
    }
    if (!hasPhysicalMeadow) {
        return;
    }

    // Nearby terrain uses every invocation. Further away, the invocation budget
    // contracts continuously to one instead of popping whole detail bands.
    float nearDetail = 1.0 - smoothstep(
        GRASS_FULL_DETAIL_DISTANCE,
        GRASS_LOD_END_DISTANCE,
        playerDistance
    );
    float invocationBudget = mix(
        1.0,
        float(GRASS_INVOCATIONS),
        nearDetail
    );
    float invocationWeight = clamp(
        invocationBudget - float(gl_InvocationID),
        0.0,
        1.0
    );
    invocationWeight = invocationWeight * invocationWeight *
        (3.0 - 2.0 * invocationWeight);
    invocationWeight *= renderSurvival;
    if (invocationWeight <= 0.015) {
        return;
    }

    // Expensive distribution/noise work happens only after distant invocations
    // have exited. This is important because all 32 cinematic instances are
    // launched by the driver even when the far field emits only one of them.
    float edgeVariation =
        (grassHash(stableTriangleSeed, 53.0) - 0.5) * 0.12;
    float density = broadDensity + edgeVariation;

    // Every invocation contributes three independent, curved physical ribbons.
    // With the cinematic tier this yields 192 actual strands on a nearby block.
    for (int bladeIndex = 0; bladeIndex < 3; ++bladeIndex) {
        float globalIndex =
            float(gl_InvocationID * 3 + bladeIndex);
        float channel = globalIndex * 7.0;

        // Irrational increments form a stable low-discrepancy distribution. A
        // small hash rotation removes visible repetition between block triangles.
        float randomA = fract(
            grassHash(stableTriangleSeed, 11.0) +
            (globalIndex + 0.5) * 0.61803398875
        );
        float randomB = fract(
            grassHash(stableTriangleSeed, 12.0) +
            (globalIndex + 0.5) * 0.41421356237
        );

        // Square-root barycentric sampling distributes roots uniformly over
        // the triangle instead of clustering them near one corner.
        float rootRandomA = sqrt(randomA);
        vec3 weights = vec3(
            1.0 - rootRandomA,
            rootRandomA * (1.0 - randomB),
            rootRandomA * randomB
        );

        emitBlade(
            weights,
            channel + 20.0,
            stableTriangleSeed,
            globalIndex,
            density,
            invocationWeight,
            playerDistance,
            vec3(0.0),
            0.0,
            1.0,
            0.0,
            4.0,
            0.0
        );
    }
}
