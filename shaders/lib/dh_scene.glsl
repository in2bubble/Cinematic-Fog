/* Cinematic Fog - dh_scene.glsl
Distant Horizons scene helpers for full-screen (post-processing) stages.

With Iris, depthtex0/depthtex1 only contain vanilla chunks. A pixel that shows
a Distant Horizons LOD therefore reads depth 1.0 (looks like sky) in vanilla
depth, while dhDepthTex0 holds the real LOD depth. Every full-screen effect
that treats depth 1.0 as sky (fog, sun, moon, grading, TAA reprojection) must
ask these helpers first.

Include once per stage, after the stage uniforms and before any code that
uses dhNearPlane, dhFarPlane, dhRenderDistance or dhDepthTex0.
*/

#ifdef DISTANT_HORIZONS
    uniform sampler2D dhDepthTex0;
    uniform mat4 dhProjectionInverse;
    uniform int dhRenderDistance;
    uniform float dhNearPlane;
    uniform float dhFarPlane;

    // Raw LOD depth (1.0 where there is no LOD).
    float dhSceneDepth(vec2 uv) {
        return texture2D(dhDepthTex0, uv).r;
    }

    // True when the pixel shows an LOD instead of vanilla terrain or sky.
    bool dhIsLodPixel(float vanillaDepth, float lodDepth) {
        return vanillaDepth > 0.9999 && lodDepth < 0.9999;
    }

    // View-space position of an LOD pixel.
    vec3 dhViewPosition(vec2 uv, float lodDepth) {
        vec4 viewPosition =
            dhProjectionInverse * vec4(uv * 2.0 - 1.0, lodDepth * 2.0 - 1.0, 1.0);
        return viewPosition.xyz / viewPosition.w;
    }
#endif
