#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - gbuffers_terrain.vsh
Render: Almost everything

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define THE_END
#define GBUFFER_TERRAIN
#define FOLIAGE_V
#define EMMISIVE_V

#include "/common/solid_blocks_vertex.glsl"
