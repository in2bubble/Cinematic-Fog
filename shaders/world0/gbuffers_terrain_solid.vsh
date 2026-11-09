#version 400 compatibility
#extension GL_ARB_shader_texture_lod : enable
/* Cinematic Fog - gbuffers_terrain.vsh
Render: Almost everything

Javier Garduño - GNU Lesser General Public License v3.0
*/

#define GBUFFER_TERRAIN
#define FOLIAGE_V
#define EMMISIVE_V
#define PLAYER_INTERACTIVE_FOLIAGE
#define SUPPRESS_REPLACED_VANILLA_GRASS

// Player-interactive foliage bending, derived directly from distance geometry.
// The input position is camera-relative world space. cameraFromPlayerHead lets
// us recover the player's real head position when the camera moves away from it
// in third person, then form the horizontal player-to-vertex vector on XZ.
vec3 bendFoliageAwayFromPlayer(
    vec3 cameraRelativeVertex,
    vec3 cameraWorldPosition,
    vec3 cameraFromPlayerHead,
    vec2 vertexUv,
    float verticalUvCenter
) {
    const float influenceRadius = 2.40;
    const float maximumHorizontalBend = 0.55;

    vec3 worldVertex = cameraRelativeVertex + cameraWorldPosition;
    vec3 playerHeadWorld = cameraWorldPosition - cameraFromPlayerHead;
    vec2 playerToVertex = worldVertex.xz - playerHeadWorld.xz;

    float squaredDistance = dot(playerToVertex, playerToVertex);
    float horizontalDistance = sqrt(squaredDistance);

    // max(..., epsilon) keeps the direction finite when a vertex is exactly
    // under the player. At that single point the zero numerator remains zero.
    vec2 pushDirection =
        playerToVertex * inversesqrt(max(squaredDistance, 0.000001));

    // Convert distance to [0, 1], then apply a cubic curve whose slope is zero
    // at both ends. The bend therefore enters and leaves the radius smoothly.
    float radiusWeight = clamp(
        1.0 - horizontalDistance / influenceRadius,
        0.0,
        1.0
    );
    float distanceFalloff =
        radiusWeight * radiusWeight * (3.0 - 2.0 * radiusWeight);

    // Minecraft's terrain atlas increases V downward. Vertices above the
    // sprite's vertical midpoint receive 1; lower/root vertices receive 0.
    float upperBladeMask = 1.0 - step(verticalUvCenter, vertexUv.y);

    float bendAmount =
        maximumHorizontalBend * distanceFalloff * upperBladeMask;

    vec3 bentVertex = cameraRelativeVertex;
    bentVertex.xz += pushDirection * bendAmount;

    // A small quadratic drop turns a flat sideways translation into a shallow
    // arc. It is also masked by bendAmount, so root vertices stay unchanged.
    bentVertex.y -= bendAmount * bendAmount * 0.30;

    return bentVertex;
}

#include "/common/solid_blocks_vertex.glsl"
