#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - prepare.fsh
Render: Sky

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define THE_END
#define PREPARE_SHADER
#define NO_SHADOWS
#define SET_FOG_COLOR

#include "/common/prepare_fragment.glsl"