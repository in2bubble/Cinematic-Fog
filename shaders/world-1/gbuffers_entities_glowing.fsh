#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - gbuffers_entities_glowing.fsh
Render: Droped objects, mobs and things like that... glowing

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define GBUFFER_ENTITIES
#define GBUFFER_ENTITY_GLOW

#include "/common/solid_blocks_fragment.glsl"

