#include "/lib/config.glsl"

// MAIN FUNCTION ------------------

#if defined THE_END
    #include "/lib/color_utils_end.glsl"
#elif defined NETHER
    #include "/lib/color_utils_nether.glsl"
#endif

/* Uniforms */

uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
uniform sampler2D tex;
uniform int isEyeInWater;
uniform float nightVision;
uniform float rainStrength;
uniform float dayNightMix;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform sampler2D gaux4;

#ifdef GBUFFER_WEATHER
    uniform sampler2D gaux1;
    uniform sampler2D depthtex1;
    uniform mat4 gbufferProjection;
    uniform mat4 gbufferProjectionInverse;
#endif

#if defined DISTANT_HORIZONS
    uniform float dhNearPlane;
    uniform float far;
#endif

#if defined GBUFFER_ENTITIES
    uniform int entityId;
    uniform vec4 entityColor;
#endif

#ifdef NETHER
    uniform vec3 fogColor;
#endif

#if defined SHADOW_CASTING
    uniform sampler2DShadow shadowtex1;
    #if defined COLORED_SHADOW
        uniform sampler2DShadow shadowtex0;
        uniform sampler2D shadowcolor0;
    #endif
#endif

uniform float blindness;

#if MC_VERSION >= 11900
    uniform float darknessFactor;
    uniform float darknessLightFactor;
#endif

#ifdef MATERIAL_GLOSS
  // Don't remove
#endif

#if defined MATERIAL_GLOSS && !defined NETHER
    uniform int worldTime;
    uniform vec3 moonPosition;
    uniform vec3 sunPosition;
#endif

#if SHADOW_LOCK > 0 && defined SHADOW_CASTING
    uniform vec3 cameraPosition;
    uniform mat4 shadowModelView;
    uniform mat4 shadowProjection;
    uniform vec3 shadowLightPosition;
#endif

#if defined THE_END || (SHADOW_LOCK > 0 && defined SHADOW_CASTING && !defined NETHER)
    uniform mat4 gbufferModelView;
#endif

/* Ins / Outs */

varying vec2 texcoord;
varying vec4 tintColor;
varying float frogAdjust;
varying vec3 directLightColor;
varying vec3 candleColor;
varying float directLightStrength;
varying vec3 omniLight;

#ifdef PROCEDURAL_TUFT_GRASS
    varying float grassFogCoord;
    varying vec2 grassTuftCoord;
    flat varying float grassTuftSeed;
    flat varying float grassTuftLayer;
#endif

#ifdef GBUFFER_WEATHER
    varying vec3 weatherWindView;
    varying float weatherCameraResponse;
    varying vec3 weatherViewPosition;
#endif

#ifdef GBUFFER_TERRAIN
    varying float surfaceSkyExposure;
#endif

#if defined SHADOW_CASTING && SHADOW_LOCK > 0 && !defined NETHER
    varying vec3 vWorldPos;
    varying vec3 vNormal;
    varying vec3 vBias;
#endif

#if defined GBUFFER_TERRAIN || defined GBUFFER_HAND || defined GBUFFER_ENTITIES
    varying float isEmissiveEntity;
#endif

#ifdef FOLIAGE_V
    varying float isFoliage;
#endif

#if defined SHADOW_CASTING && !defined NETHER
    varying vec3 shadowPos;
    varying float shadowDiffuse;
#endif

#if defined MATERIAL_GLOSS && !defined NETHER
    varying vec3 flatNormal;
    varying vec3 viewPositionNormalized;
    varying vec2 lmcoordAlt;
    varying float glossFactor;
    varying float glossPower;
    varying float lumaFactor;
    varying float lumaPower;
#endif

/* Utility functions */

#if (defined SHADOW_CASTING && !defined NETHER) || defined DISTANT_HORIZONS
    #include "/lib/dither.glsl"
#endif

#if defined SHADOW_CASTING && !defined NETHER
    #include "/lib/shadow_frag.glsl"
#endif

#include "/lib/luma.glsl"

#ifdef PROCEDURAL_TUFT_GRASS
    // Deterministic carpet variation without transcendental instructions. The
    // physical strand colour is precomputed once in the geometry stage.
    float tuftFragmentHash(float value) {
        uint hashValue = floatBitsToUint(value) * 236887691u;
        hashValue ^= hashValue >> 13;
        hashValue *= 277803737u;
        hashValue ^= hashValue >> 16;
        hashValue *= 179424673u;
        hashValue ^= hashValue >> 15;
        return float(hashValue & 0x00ffffffu) *
            0.000000059604644775390625;
    }
#endif

#ifdef GBUFFER_WEATHER
    #include "/lib/rain_ssr.glsl"
#endif

#if defined MATERIAL_GLOSS && !defined NETHER
    #include "/lib/material_gloss_fragment.glsl"
#endif

#if defined SHADOW_CASTING && SHADOW_LOCK > 0 && !defined NETHER
    #include "/lib/shadow_vertex.glsl"
#endif

void main() {
    #if (defined SHADOW_CASTING && !defined NETHER) || defined DISTANT_HORIZONS
        #if AA_TYPE > 0
            float dither = shiftedDither13(gl_FragCoord.xy);
        #else
            float dither = dither17(gl_FragCoord.xy);
        #endif
    #endif
    // Avoid render in DH transition
    #if defined DISTANT_HORIZONS && !defined GBUFFER_BEACONBEAM
        float t = far - dhNearPlane;
        float sup = t * TRANSITION_DH_SUP;
        float inf = t * TRANSITION_DH_INF;
        float umbral = (gl_FogFragCoord - (dhNearPlane + inf)) / (far - sup - inf - dhNearPlane);
        if(umbral > dither) {
            discard;
            return;
        }
    #endif

    // Take the raw block color
    #if defined GBUFFER_WEATHER
        vec4 weatherTexel = texture2D(tex, texcoord);
        vec4 blockColor = weatherTexel * tintColor;
    #elif defined GBUFFER_ENTITIES && BLACK_ENTITY_FIX == 1
        vec4 blockColor = texture2D(tex, texcoord);
        if(blockColor.a < 0.1 && entityId != 10101) {   // Black entities bug workaround
            discard;
        }
        blockColor *= tintColor;
    #else
        #if defined GBUFFER_TERRAIN && defined PROCEDURAL_TUFT_GRASS
            // Generated strands already contain their one atlas sample, while
            // the procedural ground carpet uses biome tint directly. Only
            // ordinary terrain still needs a per-fragment texture lookup.
            vec4 blockColor = grassTuftLayer > -1.5
                ? tintColor
                : texture2D(tex, texcoord) * tintColor;
        #else
            vec4 blockColor = texture2D(tex, texcoord) * tintColor;
        #endif
    #endif

    #if defined GBUFFER_TERRAIN && defined PROCEDURAL_TUFT_GRASS
        if (grassTuftLayer > 8.5) {
            // Each fragment belongs to one finite-width physical ribbon. Nothing
            // is cut out, so overlapping strands remain opaque and temporally
            // stable against the sky and distant terrain.
            float colorRandom = clamp(grassTuftSeed, 0.0, 1.0);
            float bladeY = clamp(grassTuftCoord.y, 0.0, 1.0);
            float lateralProfile =
                1.0 - abs(clamp(grassTuftCoord.x, 0.0, 1.0) * 2.0 - 1.0);

            vec3 biomeBase = blockColor.rgb;
            vec3 bladeHue = mix(
                vec3(0.84, 0.94, 0.82),
                vec3(1.02, 1.00, 0.88),
                colorRandom
            );
            float bladeTone = mix(0.90, 1.08, colorRandom);
            float verticalTone = mix(
                0.70,
                1.06,
                smoothstep(0.0, 1.0, bladeY)
            );
            float roundedProfile = mix(
                sqrt(max(lateralProfile, 0.0)),
                lateralProfile,
                0.32
            );
            float cylindricalTone = mix(
                0.78,
                1.08,
                roundedProfile
            );
            blockColor.rgb =
                biomeBase * bladeHue * bladeTone * verticalTone *
                cylindricalTone;
            blockColor.a = 1.0;
        } else if (grassTuftLayer > -1.5) {
            // Absolute-world coordinates make this fine carpet continuous over
            // both triangles and across block borders. It replaces the visible
            // square atlas pattern rather than merely darkening it.
            vec2 carpetCellA = floor(grassTuftCoord * 11.0);
            vec2 carpetCellB = floor(
                grassTuftCoord * 23.0 + vec2(7.0, -5.0)
            );
            float carpetNoiseA = tuftFragmentHash(
                carpetCellA.x + carpetCellA.y * 71.0 + 19.0
            );
            float carpetNoiseB = tuftFragmentHash(
                carpetCellB.x + carpetCellB.y * 113.0 + 37.0
            );
            float fineFibres = 0.5 + 0.5 * sin(
                grassTuftCoord.x * 53.0 +
                grassTuftCoord.y * 31.0 +
                carpetNoiseA * 6.2831853
            );
            float carpetVariation =
                0.76 + carpetNoiseA * 0.13 + carpetNoiseB * 0.07 +
                fineFibres * 0.04;
            vec3 carpetHue = mix(
                vec3(0.74, 0.88, 0.68),
                vec3(0.94, 0.98, 0.78),
                carpetNoiseB
            );
            vec3 carpetColor =
                tintColor.rgb * vec3(0.66, 0.74, 0.60) * carpetHue;
            blockColor.rgb = carpetColor * carpetVariation;
            blockColor.a = 1.0;
        }
    #endif

    /*
     * Iris still asks vanilla to render a minimal set of rain splashes when
     * weather splash particles are disabled.  Route particles through their
     * own program and reject only the characteristic dark-blue rain texels.
     * Restricting this to active rain preserves ordinary particles.
     */
    #if defined GBUFFER_PARTICLES
        if (rainStrength > 0.02) {
            float particleMaxRG = max(blockColor.r, blockColor.g);
            bool isVanillaRainSplash =
                blockColor.b > 0.075 &&
                blockColor.b > blockColor.g * 1.70 &&
                blockColor.b > blockColor.r * 2.35 &&
                blockColor.g > blockColor.r * 1.12 &&
                (blockColor.b - particleMaxRG) > 0.055;

            if (isVanillaRainSplash) {
                discard;
                return;
            }
        }
    #endif

    #if defined GBUFFER_ENTITIES
        vec4 originalEntityColor = blockColor;
    #endif

    float block_luma = luma(blockColor.rgb);

    float isEmissiveEntityLocal = 0.0;
    #if defined GBUFFER_ENTITIES
        if (isEmissiveEntity > 0.5 || entityId == 10202) {  // Custom lanterns
            isEmissiveEntityLocal = 1.0;
        }
    #endif

    vec3 finalCandleColor = candleColor;
    #if defined GBUFFER_TERRAIN || defined GBUFFER_HAND || defined GBUFFER_ENTITIES
        if(isEmissiveEntityLocal > 0.5) {
            finalCandleColor *= block_luma * 1.5;
        }
    #endif

    #if defined GBUFFER_ENTITIES
        // Thunderbolt render
        if(entityId == 10101) {
            blockColor.a = 1.0;
        }
    #endif

    #if defined SHADOW_CASTING && !defined NETHER
        #if SHADOW_LOCK > 0
            vec3 offsetVector = vNormal * 0.002;
            vec3 preSnapPos = vWorldPos + offsetVector;
            float texelSize = SHADOW_LOCK;
            vec3 absPos = preSnapPos + cameraPosition;
            // Snap to the block grid
            vec3 snappedAbsolute = floor(absPos * texelSize) / texelSize;
            snappedAbsolute += 0.5 / texelSize; // Center on the texel
            vec3 final_world_pos = (snappedAbsolute - cameraPosition) + vBias;
            vec3 shadow_real_pos = get_shadow_pos(final_world_pos);
        #else
            vec3 shadow_real_pos = shadowPos;
        #endif

        #if defined COLORED_SHADOW
            vec3 shadowValue = get_colored_shadow(shadow_real_pos, dither);
            shadowValue = mix(shadowValue, vec3(1.0), shadowDiffuse);
        #else
            float shadowValue = get_shadow(shadow_real_pos, dither);
            shadowValue = mix(shadowValue, 1.0, shadowDiffuse);
        #endif
    #else
        float shadowValue = abs((dayNightMix * 2.0) - 1.0);
    #endif

    #if defined GBUFFER_BEACONBEAM
        blockColor.rgb *= 1.5;
    #elif defined GBUFFER_ENTITY_GLOW
        blockColor.rgb =
            clamp(vec3(luma(blockColor.rgb)) * vec3(0.75, 0.75, 1.5), vec3(0.3), vec3(1.0));
        vec3 realLight = omniLight +
                (shadowValue * directLightColor * directLightStrength) * (1.0 - (rainStrength * 0.75)) +
                finalCandleColor;
    #else
        #if defined MATERIAL_GLOSS && !defined NETHER
            float final_gloss_power = glossPower;
            block_luma *= lumaFactor;

            if(lumaPower < 0.0) {  // Metallic
                final_gloss_power -= (block_luma * 73.334);
            } else {
                block_luma = pow(block_luma, lumaPower);
            }

            float material_gloss_factor = materialGloss(reflect(viewPositionNormalized, flatNormal), lmcoordAlt, final_gloss_power, flatNormal) * glossFactor;

            float material = material_gloss_factor * block_luma;
            vec3 realLight = omniLight +
                (shadowValue * ((directLightColor * directLightStrength) + (directLightColor * material))) * (1.0 - (rainStrength * 0.75)) +
                finalCandleColor;
        #else
            vec3 realLight = omniLight +
                (shadowValue * directLightColor * directLightStrength) * (1.0 - (rainStrength * 0.75)) +
                finalCandleColor;
        #endif

        blockColor.rgb *= mix(realLight, vec3(1.0), nightVision * 0.125);

    #endif

    #if defined GBUFFER_ENTITIES
        if(entityId == 10101) {  // Thunderbolt render
            blockColor = vec4(1.0, 1.0, 1.0, 0.5);
        } else if (entityId == 10201) {  // Flame entity
            blockColor = originalEntityColor;
            blockColor.rgb = blockColor.rgb * blockColor.rgb;
        } else {
            float entity_poderation = luma(realLight);  // Red damage bright ponderation
            blockColor.rgb = mix(blockColor.rgb, entityColor.rgb, entityColor.a * entity_poderation * 3.0);
        }
    #endif

    #if MC_VERSION < 11300 && defined GBUFFER_TEXTURED
        blockColor.rgb *= 1.5;
    #endif

    #ifdef GBUFFER_WEATHER
        #include "/src/weather_fragment.glsl"
    #endif

    #include "/src/finalcolor.glsl"
    #include "/src/writebuffers.glsl"
}
