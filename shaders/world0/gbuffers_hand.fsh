#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - gbuffers_hand.fsh
Render: Hand opaque objects

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define GBUFFER_HAND

#include "/common/solid_blocks_fragment.glsl"
