#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - gbuffers_skybasic.vsh
Render: Sky

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define GBUFFER_SKYBASIC
#define NO_SHADOWS

#include "/common/skybasic_vertex.glsl"
