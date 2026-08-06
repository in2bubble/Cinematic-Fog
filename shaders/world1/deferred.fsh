#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Oxygen Atmosphere - deferred.fsh
Render: Ambient occlusion, volumetric clouds

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define THE_END
#define DEFERRED_SHADER
#define NO_SHADOWS

#include "/common/deferred_fragment.glsl"
