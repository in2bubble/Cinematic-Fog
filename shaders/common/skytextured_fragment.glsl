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

uniform sampler2D tex;

#ifdef NETHER
    uniform vec3 fogColor;
#elif !defined THE_END
    uniform float rainStrength;
#endif

/* Ins / Outs */

varying vec2 texcoord;
varying vec4 tintColor;
varying float sky_luma_correction;  // Flat

// MAIN FUNCTION ------------------

void main() {
    #if defined THE_END
        // Suppress Minecraft's painted End sky. The procedural void, storm
        // clouds and electrical flashes are composed later in deferred.
        vec4 blockColor = vec4(END_VOID_COLOR, 0.0);
    #elif defined NETHER  // Unused
        vec4 background_color_full = vec4(mix(fogColor * 0.1, vec3(1.0), 0.04), 1.0);
        vec3 background_color = background_color_full.rgb;
        vec4 blockColor = vec4(background_color, 1.0);
    #else
        // Sun rendering is handled analytically in deferred_fragment.glsl.
        // This program remains active for Minecraft's phase-aware moon.
        vec4 blockColor = texture2D(tex, texcoord) * tintColor;
        blockColor.rgb *= sky_luma_correction;

        // Dense rain clouds obscure celestial discs. Keep only a very faint
        // transmitted presence instead of a white sun/moon patch.
        float celestialRainVisibility =
            1.0 - smoothstep(0.05, 0.90, rainStrength) * 0.97;
        blockColor *= celestialRainVisibility;
    #endif

    #include "/src/writebuffers.glsl"
}
