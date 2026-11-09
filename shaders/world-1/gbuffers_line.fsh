#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - gbuffers_line.vsh
Render: Render lines

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define GBUFFER_LINE
#define NO_SHADOWS

#include "/common/line_blocks_fragment.glsl"
