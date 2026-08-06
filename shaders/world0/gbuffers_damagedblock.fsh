#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - gbuffers_damagedblock.fsh
Render: Damaged block effect

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NO_SHADOWS
#define GBUFFER_DAMAGE

#include "/common/damage_fragment.glsl"