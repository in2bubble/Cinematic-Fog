/* Cinematic Fog - projection_utils_voxy.glsl
Projection generic functions.

Javier Garduño - GNU Lesser General Public License v3.0
*/


vec3 camera_to_screen_voxy(vec3 fragpos) {
    vec4 pos  = vxProj * vec4(fragpos, 1.0);
    pos /= pos.w;

    return pos.xyz * 0.5 + 0.5;
}
