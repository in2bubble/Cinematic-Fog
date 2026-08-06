#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - gbuffers_hand.fsh
Render: Hand opaque objects

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define GBUFFER_HAND
#define NO_SHADOWS

#include "/common/solid_blocks_fragment.glsl"
