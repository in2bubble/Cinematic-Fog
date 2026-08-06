#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - gbuffers_textured.fsh
Render: Particles

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define GBUFFER_TEXTURED
#define NO_SHADOWS

#include "/common/solid_blocks_fragment.glsl"
