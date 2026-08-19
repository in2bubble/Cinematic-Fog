#version 400 compatibility
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - gbuffers_terrain.fsh
Render: Almost everything

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define GBUFFER_TERRAIN
#define FOLIAGE_V
#define PROCEDURAL_TUFT_GRASS
#define varying in
#define gl_FogFragCoord grassFogCoord

#include "/common/solid_blocks_fragment.glsl"

