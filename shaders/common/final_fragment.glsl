#include "/lib/config.glsl"

// Do not remove comments. It works!
/*

noisetex - Pass-specific authored texture slot
colortex0 - Bloom auxiliar
colortex1 - Antialiasing auxiliar
colortex2 - Unused / optional blue-noise slot
colortex3 - TAA history
gaux1 - Screen-Space-Reflection
gaux2 - Clouds texture
gaux3 - Exposure auxiliar
gaux4 - Fog auxiliar

const int noisetexFormat = RG8;
const int colortex0Format = R11F_G11F_B10F;
*/
#ifdef DOF
/*
const int colortex1Format = RGBA16F;
*/
#else
/*
const int colortex1Format = R11F_G11F_B10F;
*/
#endif
/*
const int colortex2Format = RGBA8;
*/
/*
const int colortex3Format = RGBA8;
*/
/*
const int gaux1Format = R11F_G11F_B10F;
const int gaux2Format = R8;
const int gaux3Format = R16F;
const int gaux4Format = R11F_G11F_B10F;

const int shadowcolor0Format = RGBA8;
*/

// Buffers clear
const bool colortex0Clear = false;
const bool colortex1Clear = false;
const bool colortex2Clear = false;
// Iris 1.11 parses the implicit vec4(0.0) default incorrectly. Supply the
// equivalent explicit four-component value so shader reloads remain valid.
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex3Clear = false;
const bool gaux1Clear = false;
const bool gaux2Clear = false;
const bool gaux3Clear = false;
const bool gaux4Clear = false;

/* Uniforms */

#ifdef DEBUG_MODE
    uniform sampler2D shadowtex1;
    uniform sampler2D shadowcolor0;
    uniform sampler2D colortex3;
#endif

uniform sampler2D gaux3;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform float viewWidth;

#include "/lib/dh_scene.glsl"

#if defined CINEMATIC_FOG_STYLE && !defined NETHER && !defined THE_END
    uniform float dayMoment;
    uniform int worldDay;
    #include "/lib/cinematic_fog_lunar_event.glsl"
#endif

/* Ins / Outs */

varying vec2 texcoord;
varying float exposure;

/* Utility functions */

#include "/lib/basic_utils.glsl"
#include "/lib/tone_maps.glsl"

#ifdef COLOR_BLINDNESS
    #include "/lib/color_blindness.glsl"
#endif

#if CHROMA_ABER == 1
    #include "/lib/aberration.glsl"
#endif

// MAIN FUNCTION ------------------

void main() {
    #if CHROMA_ABER == 1
        vec3 blockColor = color_aberration();
    #else
        vec3 blockColor = texture2D(colortex1, texcoord).rgb;
    #endif

    // Exposure correction
    blockColor *= vec3(exposure);
    blockColor = custom_sigmoid(blockColor);

    // Color-grading -----
    #if defined CINEMATIC_FOG_STYLE && !defined NETHER && !defined THE_END
        float terrainDepth = texture2D(depthtex0, texcoord).r;
        float terrainMask = 1.0 - smoothstep(0.9995, 1.0, terrainDepth);
        #ifdef DISTANT_HORIZONS
            // Distant Horizons LODs count as terrain for color grading.
            terrainMask = max(
                terrainMask,
                float(dhIsLodPixel(terrainDepth, dhSceneDepth(texcoord)))
            );
        #endif

        // Smooth peaks at noon and midnight leave dawn and dusk to the shared
        // twilight palette without introducing a discontinuity at sunset.
        float cinematicFogNoon =
            1.0 - clamp(abs(dayMoment - 0.25) * 4.0, 0.0, 1.0);
        cinematicFogNoon =
            cinematicFogNoon * cinematicFogNoon *
            (3.0 - 2.0 * cinematicFogNoon);
        float cinematicFogMidnight =
            1.0 - clamp(abs(dayMoment - 0.75) * 4.0, 0.0, 1.0);
        cinematicFogMidnight =
            cinematicFogMidnight * cinematicFogMidnight *
            (3.0 - 2.0 * cinematicFogMidnight);

        vec3 twilightTint = vec3(1.035, 1.000, 0.940);
        vec3 noonTint = vec3(1.020, 0.985, 1.015);
        float cinematicFogLunarEclipse =
            cinematicFogLunarEclipseAmount(worldDay);
        vec3 midnightTint = mix(
            vec3(0.860, 0.960, 1.160),
            vec3(1.320, 0.800, 0.720),
            cinematicFogLunarEclipse *
                CINEMATIC_FOG_LUNAR_ECLIPSE_INTENSITY
        );
        vec3 temporalTint = mix(
            twilightTint,
            noonTint,
            cinematicFogNoon
        );
        temporalTint = mix(
            temporalTint,
            midnightTint,
            cinematicFogMidnight
        );
        temporalTint /= max(
            dot(temporalTint, vec3(0.2126, 0.7152, 0.0722)),
            0.001
        );

        vec3 terrainColor = blockColor * temporalTint;
        float terrainLuma = dot(
            terrainColor,
            vec3(0.2126, 0.7152, 0.0722)
        );
        float terrainSaturation =
            0.92 -
            cinematicFogNoon * 0.06 -
            cinematicFogMidnight * 0.12;
        terrainColor = mix(
            vec3(terrainLuma),
            terrainColor,
            terrainSaturation
        );

        // A gentle shoulder controls bright grass and pale blocks, while a
        // tiny cool lift keeps cloud-shadowed areas detailed instead of ashen.
        float terrainHighlights = smoothstep(0.52, 0.94, terrainLuma);
        float terrainShadows =
            1.0 - smoothstep(0.06, 0.42, terrainLuma);
        terrainColor *= mix(1.0, 0.94, terrainHighlights);
        terrainColor +=
            vec3(0.009, 0.011, 0.014) * terrainShadows;
        float terrainExposure =
            0.96 -
            cinematicFogNoon * 0.05 -
            cinematicFogMidnight * 0.11;
        terrainColor *= terrainExposure;

        blockColor = mix(blockColor, terrainColor, terrainMask);

        // Midnight also cools the sky and fog, but much more gently than the
        // terrain grade so clouds retain their sculpted highlights.
        blockColor *= mix(
            vec3(1.0),
            vec3(0.90, 0.95, 1.04),
            cinematicFogMidnight * 0.55
        );

        blockColor = clamp(blockColor, 0.0, 1.0);
    #endif

    // Color-blindness correction
    #ifdef COLOR_BLINDNESS
        blockColor = color_blindness(blockColor);
    #endif

    #ifdef DEBUG_MODE
        if(texcoord.x < 0.5 && texcoord.y < 0.5) {
            blockColor = texture2D(shadowtex1, texcoord * 2.0).rrr;
        } else if(texcoord.x >= 0.5 && texcoord.y >= 0.5) {
            blockColor = vec3(texture2D(gaux3, vec2(0.5)).r * 0.25);
        } else if(texcoord.x < 0.5 && texcoord.y >= 0.5) {
            blockColor = texture2D(colortex1, ((texcoord - vec2(0.0, 0.5)) * 2.0)).rgb;
        } else if(texcoord.x >= 0.5 && texcoord.y < 0.5) {
            blockColor = texture2D(shadowcolor0, ((texcoord - vec2(0.5, 0.0)) * 2.0)).rgb;
        } else {
            blockColor = vec3(0.5);
        }

        gl_FragData[0] = vec4(blockColor, 1.0);

    #else
        gl_FragData[0] = vec4(blockColor, 1.0);
    #endif
}
