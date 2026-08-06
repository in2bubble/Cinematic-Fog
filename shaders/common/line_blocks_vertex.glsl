#include "/lib/config.glsl"

/* Uniforms */

uniform float viewHeight;
uniform float viewWidth;

/* Ins / Outs */

varying vec4 tintColor;

/* Utility functions */

#if AA_TYPE > 1
    #include "/src/taa_offset.glsl"
#endif

#include "/lib/oxygen_atmosphere_ftransform.glsl"

// MAIN FUNCTION ------------------

void main() {
    tintColor = gl_Color;
    gl_Position = oxygenAtmosphereFtransform();

    #if AA_TYPE > 1
        gl_Position.xy += taaOffset * gl_Position.w;
    #endif
}
