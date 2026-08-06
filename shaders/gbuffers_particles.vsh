#version 120
#extension GL_ARB_shader_texture_lod : enable

#define USE_BASIC_SH
#ifdef USE_BASIC_SH
    #define UNKNOWN_DIM
#endif
#define GBUFFER_TEXTURED
#define GBUFFER_PARTICLES

#include "/common/solid_blocks_vertex.glsl"
