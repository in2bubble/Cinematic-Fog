#include "/lib/config.glsl"

/* Uniforms */

uniform sampler2D tex;

/* Ins / Outs */

varying vec2 texcoord;

// MAIN FUNCTION ------------------

void main() {
    // Take the raw block color
    vec4 blockColor = texture2D(tex, texcoord);

    #include "/src/writebuffers.glsl"
}
