#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - gbuffers_weather.vsh
Render: Weather

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define GBUFFER_WEATHER
#define NO_SHADOWS

#include "/common/solid_blocks_vertex.glsl"