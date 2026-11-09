#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - composite.fsh
Render: Bloom and volumetric light

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define THE_END
#define COMPOSITE_SHADER

#include "/common/composite_vertex.glsl"
