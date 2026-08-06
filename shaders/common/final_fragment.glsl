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

#if defined OXYGEN_ATMOSPHERE_STYLE && !defined NETHER && !defined THE_END
    uniform float dayMoment;
    uniform int worldDay;
    #include "/lib/oxygen_atmosphere_lunar_event.glsl"
#endif

#if AA_TYPE == 3 || defined OXYGEN_ATMOSPHERE_SPATIAL_AA
    uniform float pixelSizeX;
    uniform float pixelSizeY;
#endif

/* Ins / Outs */

varying vec2 texcoord;
varying float exposure;

/* Utility functions */

#if AA_TYPE == 3 || defined OXYGEN_ATMOSPHERE_SPATIAL_AA
    // #include "/lib/post.glsl"
    #include "/lib/luma.glsl"
    #include "/lib/fxaa.glsl"
#endif

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
        #if (AA_TYPE == 3 || defined OXYGEN_ATMOSPHERE_SPATIAL_AA) && !defined DOF
            blockColor = fxaa311(blockColor, 5);
        #endif
    #endif

    // Exposure correction
    blockColor *= vec3(exposure);
    blockColor = custom_sigmoid(blockColor);

    // Color-grading -----
    #if defined OXYGEN_ATMOSPHERE_STYLE && !defined NETHER && !defined THE_END
        float terrainDepth = texture2D(depthtex0, texcoord).r;
        float terrainMask = 1.0 - smoothstep(0.9995, 1.0, terrainDepth);

        // Smooth peaks at noon and midnight leave dawn and dusk to the shared
        // twilight palette without introducing a discontinuity at sunset.
        float oxygenAtmosphereNoon =
            1.0 - clamp(abs(dayMoment - 0.25) * 4.0, 0.0, 1.0);
        oxygenAtmosphereNoon =
            oxygenAtmosphereNoon * oxygenAtmosphereNoon *
            (3.0 - 2.0 * oxygenAtmosphereNoon);
        float oxygenAtmosphereMidnight =
            1.0 - clamp(abs(dayMoment - 0.75) * 4.0, 0.0, 1.0);
        oxygenAtmosphereMidnight =
            oxygenAtmosphereMidnight * oxygenAtmosphereMidnight *
            (3.0 - 2.0 * oxygenAtmosphereMidnight);

        vec3 twilightTint = vec3(1.035, 1.000, 0.940);
        vec3 noonTint = vec3(1.020, 0.985, 1.015);
        float oxygenAtmosphereLunarEclipse =
            oxygenAtmosphereLunarEclipseAmount(worldDay);
        vec3 midnightTint = mix(
            vec3(0.860, 0.960, 1.160),
            vec3(1.320, 0.800, 0.720),
            oxygenAtmosphereLunarEclipse *
                OXYGEN_ATMOSPHERE_LUNAR_ECLIPSE_INTENSITY
        );
        vec3 temporalTint = mix(
            twilightTint,
            noonTint,
            oxygenAtmosphereNoon
        );
        temporalTint = mix(
            temporalTint,
            midnightTint,
            oxygenAtmosphereMidnight
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
            oxygenAtmosphereNoon * 0.06 -
            oxygenAtmosphereMidnight * 0.12;
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
            oxygenAtmosphereNoon * 0.05 -
            oxygenAtmosphereMidnight * 0.11;
        terrainColor *= terrainExposure;

        blockColor = mix(blockColor, terrainColor, terrainMask);

        // Midnight also cools the sky and fog, but much more gently than the
        // terrain grade so clouds retain their sculpted highlights.
        blockColor *= mix(
            vec3(1.0),
            vec3(0.90, 0.95, 1.04),
            oxygenAtmosphereMidnight * 0.55
        );

        blockColor = clamp(blockColor, 0.0, 1.0);
    #endif

    // DEVELOPER: If your post processing effect only involves the current pixel,
    // it can be placed here. For example:

    // Saturation:
    // float actual_luma = luma(blockColor);
    // blockColor = mix(vec3(actual_luma), blockColor, 1.5);

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
