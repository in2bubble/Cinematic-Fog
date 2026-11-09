#include "/lib/config.glsl"

/* Color utils */

#ifdef THE_END
    #include "/lib/color_utils_end.glsl"
#elif defined NETHER
    #include "/lib/color_utils_nether.glsl"
#else
    #include "/lib/color_utils.glsl"
#endif

/* Uniforms */

uniform sampler2D colortex1;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;
uniform sampler2D depthtex0;
uniform float far;
uniform float near;
uniform float blindness;
uniform float rainStrength;
uniform sampler2D gaux3;
uniform int frameCounter;

#if V_CLOUDS != 0
    uniform sampler2D gaux2;
#endif

#ifdef NETHER
    uniform vec3 fogColor;
#endif

#if AO == 1
    uniform float aspectRatioInverse;
    uniform float fovYInverse;
#endif

#if V_CLOUDS != 0 && !defined UNKNOWN_DIM
    uniform sampler2D noisetex;
    uniform vec3 cameraPosition;
    uniform vec3 sunPosition;

    #if defined DISTANT_HORIZONS
        uniform float viewWidth;
        uniform float viewHeight;
    #endif
#endif

#if defined CINEMATIC_FOG_STYLE && !defined UNKNOWN_DIM && !defined NETHER && !defined THE_END
    #ifdef IS_IRIS
        uniform sampler2D cinematicFogSunTexture;
    #else
        // OptiFine has no custom sampler names: shaders.properties binds the
        // same sun PNG to colortex13, which no program renders into.
        uniform sampler2D colortex13;
        #define cinematicFogSunTexture colortex13
    #endif

    #if V_CLOUDS == 0
        uniform vec3 sunPosition;
    #endif
#endif

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform float pixelSizeX;
uniform float pixelSizeY;

#if AO == 1 || (V_CLOUDS != 0 && !defined UNKNOWN_DIM)
    uniform mat4 gbufferProjection;
    uniform float frameTimeCounter;
    uniform sampler2D colortex2;
#endif

/* Ins / Outs */

varying vec2 texcoord;
varying vec3 upVector;  // Flat

#if (V_CLOUDS != 0 && !defined UNKNOWN_DIM) && !defined NO_CLOUDY_SKY
    varying float umbral;
    varying vec3 cloudColor;
    varying vec3 darkCloudColor;
#endif

#if AO == 1
    varying float fogDensityCoeff;
#endif

/* Utility functions */

#include "/lib/dh_scene.glsl"
#include "/lib/depth.glsl"
#include "/lib/luma.glsl"

#ifdef DISTANT_HORIZONS
    #include "/lib/depth_dh.glsl"
#endif

#if AO == 1 || (V_CLOUDS != 0 && !defined UNKNOWN_DIM)
    #include "/lib/dither.glsl"
#endif

#if AO == 1
    #include "/lib/ao.glsl"
#endif

#if (V_CLOUDS != 0 && !defined UNKNOWN_DIM)
    #include "/lib/projection_utils.glsl"

    #ifdef THE_END
        #include "/lib/volumetric_clouds_end.glsl"
    #else
        #include "/lib/volumetric_clouds.glsl"
    #endif
#endif

#if defined CINEMATIC_FOG_STYLE && !defined UNKNOWN_DIM && !defined NETHER && !defined THE_END
    vec3 applyCinematicFogSun(
        vec3 backgroundColor,
        vec3 eyeDirection,
        float cloudOcclusion
    ) {
        // Render the authored sun from its world direction rather than
        // Minecraft's square celestial quad. A tangent-space mapping gives a
        // stable angular size at every resolution and field of view.
        vec3 authoredSunDirection = normalize(
            (gbufferModelViewInverse * vec4(sunPosition, 0.0)).xyz
        );
        vec3 sunBasisReference =
            abs(authoredSunDirection.y) < 0.98 ?
            vec3(0.0, 1.0, 0.0) :
            vec3(1.0, 0.0, 0.0);
        vec3 authoredSunRight = normalize(
            cross(sunBasisReference, authoredSunDirection)
        );
        vec3 authoredSunUp = cross(
            authoredSunDirection,
            authoredSunRight
        );

        // A deliberately oversized celestial silhouette suits the broad mist
        // and heavy cloud language of this pack. The authored disc occupies
        // roughly 72 percent of this tangent-space texture window.
        vec2 authoredSunTangent = vec2(
            dot(eyeDirection, authoredSunRight),
            dot(eyeDirection, authoredSunUp)
        );
        vec2 authoredSunUv = authoredSunTangent / 0.190 + 0.5;
        vec4 authoredSun = texture2D(
            cinematicFogSunTexture,
            authoredSunUv
        );

        float authoredSunSquareGuard =
            step(0.0, authoredSunUv.x) *
            step(authoredSunUv.x, 1.0) *
            step(0.0, authoredSunUv.y) *
            step(authoredSunUv.y, 1.0);
        float authoredSunRadius =
            length(authoredSunUv - vec2(0.5));
        float authoredSunCircularGuard =
            1.0 - smoothstep(0.352, 0.368, authoredSunRadius);
        float authoredSunFacing = smoothstep(
            0.9880,
            0.9960,
            dot(eyeDirection, authoredSunDirection)
        );

        float authoredSunLuma = dot(
            authoredSun.rgb,
            vec3(0.2126, 0.7152, 0.0722)
        );
        float authoredSunSurface = smoothstep(
            0.78,
            0.99,
            authoredSunLuma
        );
        float authoredSunDetail = mix(
            0.84,
            1.06,
            authoredSunSurface
        );
        vec3 authoredSunPalette = mix(
            vec3(0.96, 0.54, 0.17),
            vec3(1.00, 0.92, 0.68),
            authoredSunSurface
        );

        // A restrained darker limb gives the disc depth while the texture's
        // broad convection pattern remains visible after downsampling.
        float authoredSunDiscPosition = clamp(
            authoredSunRadius / 0.36,
            0.0,
            1.0
        );
        float authoredSunLimb = mix(
            1.0,
            0.82,
            smoothstep(0.68, 1.0, authoredSunDiscPosition)
        );
        authoredSun.rgb =
            authoredSunPalette *
            authoredSunDetail *
            authoredSunLimb *
            1.45;

        float authoredSunDay =
            1.0 - smoothstep(0.49, 0.525, dayMoment);
        float authoredSunRainVisibility =
            1.0 -
            smoothstep(0.05, 0.90, rainStrength) * 0.97;
        float authoredSunOpacity =
            authoredSun.a *
            authoredSunSquareGuard *
            authoredSunCircularGuard *
            authoredSunFacing *
            authoredSunDay *
            authoredSunRainVisibility *
            // Clouds still veil the sun, but never erase it completely.
            // This leaves a believable translucent disc rather than a flat
            // foreground decal or an invisible disc behind bright clouds.
            mix(1.0, 0.42, cloudOcclusion);

        return mix(
            backgroundColor,
            authoredSun.rgb,
            authoredSunOpacity
        );
    }

#endif

// MAIN FUNCTION ------------------

void main() {
    vec4 blockColor = texture2DLod(colortex1, texcoord, 0);
    float depth = texture2DLod(depthtex0, texcoord, 0).r;
    float linearDepth = ld(depth);
    // Distant Horizons LOD pixels have vanilla depth 1.0 but are not sky: they
    // must not receive the sun disc.
    bool isLodPixel = false;
    #ifdef DISTANT_HORIZONS
        isLodPixel = dhIsLodPixel(depth, dhSceneDepth(texcoord));
    #endif
    float cinematicFogCloudOcclusion = 0.0;
    float terrainSkyExposure =
        texture2DLod(colortex2, texcoord, 0).r;

    vec2 eyeBrightSmoothFloat = vec2(eyeBrightnessSmooth);

    vec3 eyeDirection = vec3(1.0);

    #if AO == 1 || (V_CLOUDS != 0 && !defined UNKNOWN_DIM)
        #if AA_TYPE > 0
            float dither = shiftedSemiblue(gl_FragCoord.xy);
        #else
            float dither = semiblue(gl_FragCoord.xy);
        #endif
    #endif

    #if (V_CLOUDS != 0 && !defined UNKNOWN_DIM) && !defined NO_CLOUDY_SKY
        if(linearDepth > 0.9999) {  // Only sky
            vec4 farPlaneClipPos = gbufferModelViewInverse * gbufferProjectionInverse * (vec4(texcoord, 1.0, 1.0) * 2.0 - 1.0);
            eyeDirection = normalize(farPlaneClipPos.xyz);

            #ifdef THE_END
                float bright = dot(eyeDirection, vec3(0.0, 0.89442719, 0.4472136));
                bright = clamp((bright * 2.0) - 1.0, 0.0, 1.0);
                bright *= bright * bright * bright;
            #else
                float bright = dot(eyeDirection, normalize((gbufferModelViewInverse * vec4(sunPosition, 0.0)).xyz));
                bright = clamp(bright * bright * bright, 0.0, 1.0);
            #endif

            #ifdef THE_END
                #ifdef END_CLOUDS
                    blockColor.rgb = get_end_cloud(eyeDirection, blockColor.rgb, bright, dither, cameraPosition, CLOUD_STEPS_AVG);
                #endif
            #else
                float cloudOcclusion;
                blockColor.rgb = get_cloud(eyeDirection, blockColor.rgb, bright, dither, cameraPosition, CLOUD_STEPS_AVG, umbral, cloudColor, darkCloudColor, cloudOcclusion);
                cinematicFogCloudOcclusion = cloudOcclusion;
            #endif

            // Keep the authored solar disc in the foreground of the cloud
            // layer. Rendering it before get_cloud made dense sun-lit cloud
            // scattering replace the disc with a featureless bright patch.
            #if defined CINEMATIC_FOG_STYLE && !defined UNKNOWN_DIM && !defined NETHER && !defined THE_END
                if(isEyeInWater == 0 && !isLodPixel) {
                    blockColor.rgb = applyCinematicFogSun(
                        blockColor.rgb,
                        eyeDirection,
                        cloudOcclusion
                    );
                }
            #endif
        }

    #else
        #if defined NETHER
            #if !defined DISTANT_HORIZONS
                if(linearDepth > 0.9999) {  // Only sky
                    blockColor = vec4(mix(fogColor * 0.1, vec3(1.0), 0.04), 1.0);
                }
            #endif
        #elif !defined NETHER && !defined THE_END
            if(linearDepth > 0.9999) {  // Only sky
                vec4 screen_pos = vec4(gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY), gl_FragCoord.z, 1.0);
                vec4 fragposition = gbufferProjectionInverse * (screen_pos * 2.0 - 1.0);

                vec4 farPlaneClipPos = gbufferModelViewInverse * vec4(fragposition.xyz, 0.0);
                eyeDirection = normalize(farPlaneClipPos.xyz);

                #if defined CINEMATIC_FOG_STYLE && !defined UNKNOWN_DIM
                    if(isEyeInWater == 0 && !isLodPixel) {
                    blockColor.rgb = applyCinematicFogSun(
                        blockColor.rgb,
                        eyeDirection,
                        0.0
                    );
                    }
                #endif
            }
        #endif
    #endif

    #if AO == 1
        // AO distance attenuation
        #if defined NETHER
            if(NETHER_FOG_DISTANCE == 0) {
                linearDepth = sqrt(linearDepth);
            } else {
                float screen_distance = 2.0 * near * far / (far + near - (2.0 * depth - 1.0) * (far - near));
                linearDepth = screen_distance / NETHER_SIGHT;
            }
        #endif
        float ao_att =
            pow(clamp(linearDepth * 1.6, 0.0, 1.0), mix(fogDensityCoeff, 1.0, rainStrength));

        float final_ao = mix(dbao(dither), 1.0, ao_att);
        blockColor.rgb *= final_ao;
    #endif

    #if defined THE_END || defined NETHER
        #define NIGHT_CORRECTION 1.0
    #else
        #define NIGHT_CORRECTION dayBlendFloat(1.0, 1.0, 0.1)
    #endif

    // Underwater sky
    if(isEyeInWater == 1) {
        if(linearDepth > 0.9999) {
            #if defined CINEMATIC_FOG_STYLE && !defined NETHER && !defined THE_END
                vec3 underwaterSkyColor =
                    cinematicFogUnderwaterPalette(
                        rainStrength
                    ) * 1.12;
                vec3 refractedSky =
                    blockColor.rgb *
                        vec3(0.42, 0.66, 0.92) +
                    underwaterSkyColor * 0.34;
                float upwardSkyDetail =
                    clamp(
                        eyeDirection.y * 0.62 + 0.28,
                        0.0,
                        1.0
                    ) *
                    mix(1.0, 0.54, rainStrength);
                blockColor.rgb = mix(
                    underwaterSkyColor,
                    max(
                        refractedSky,
                        underwaterSkyColor * 0.78
                    ),
                    upwardSkyDetail
                );
            #else
                blockColor.rgb = mix(
                    NIGHT_CORRECTION *
                        WATER_COLOR *
                        ((eyeBrightSmoothFloat.y * .8 + 48) *
                            0.004166666666666667),
                    blockColor.rgb,
                    max(
                        clamp(
                            eyeDirection.y - 0.1,
                            0.0,
                            1.0
                        ),
                        rainStrength
                    )
                );
            #endif
        }
    }

    blockColor = clamp(blockColor, vec4(0.0), vec4(vec3(50.0), 1.0));
    /* DRAWBUFFERS:142 */
    gl_FragData[0] = vec4(blockColor.rgb, depth);
    gl_FragData[1] = blockColor;
    gl_FragData[2] = vec4(
        cinematicFogCloudOcclusion,
        terrainSkyExposure,
        0.0,
        1.0
    );
}
