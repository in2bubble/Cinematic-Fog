#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - deferred.vsh
Render: Ambient occlusion, volumetric clouds

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define NETHER
#define DEFERRED_SHADER
#define NO_SHADOWS

#include "/common/deferred_vertex.glsl"
