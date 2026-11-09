#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - gbuffers_beaconbeam.fsh
Render: Beacon beam

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define GBUFFER_BEACONBEAM

#include "/common/solid_blocks_fragment.glsl"
