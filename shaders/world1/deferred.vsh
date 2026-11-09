#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - deferred.vsh
Render: Ambient occlusion, volumetric clouds

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define THE_END
#define DEFERRED_SHADER

#include "/common/deferred_vertex.glsl"
