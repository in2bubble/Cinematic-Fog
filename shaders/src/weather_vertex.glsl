/*
 * Cinematic Fog dynamic precipitation
 *
 * Minecraft supplies camera-facing weather columns.  Shearing those columns
 * in world space keeps the rain physically coherent: turning the player's
 * head naturally changes the apparent screen direction, while player motion
 * adds a restrained relative-wind response.
 */

vec4 weatherBaseViewPosition = gl_ModelViewMatrix * gl_Vertex;
vec3 weatherRelativeWorld =
    (gbufferModelViewInverse * weatherBaseViewPosition).xyz;

float weatherWindAngle =
    frameTimeCounter * 0.021 +
    sin(frameTimeCounter * 0.037) * 0.42 +
    sin(frameTimeCounter * 0.011 + 1.7) * 0.24;

vec2 weatherWindWorld =
    vec2(cos(weatherWindAngle), sin(weatherWindAngle));

float weatherGust =
    0.78 +
    sin(frameTimeCounter * 0.71) * 0.13 +
    sin(frameTimeCounter * 1.93 + 0.8) * 0.09;

vec2 weatherCell =
    floor((weatherRelativeWorld.xz + cameraPosition.xz) * 0.5);
float weatherColumnNoise = fract(
    sin(dot(weatherCell, vec2(12.9898, 78.233))) * 43758.5453
);

vec2 weatherCrossWind =
    vec2(-weatherWindWorld.y, weatherWindWorld.x) *
    (weatherColumnNoise - 0.5) * 0.24;

vec2 weatherCameraStep = clamp(
    cameraPosition.xz - previousCameraPosition.xz,
    vec2(-0.20),
    vec2(0.20)
);

vec2 weatherDriftWorld =
    (weatherWindWorld * weatherGust + weatherCrossWind) *
    RAIN_WIND_STRENGTH;

#ifdef DYNAMIC_RAIN
    weatherDriftWorld -= weatherCameraStep * RAIN_MOTION_RESPONSE;
#else
    weatherDriftWorld = vec2(0.0);
#endif

// A continuous shear produces true diagonal streaks rather than translating
// the entire vanilla weather sheet sideways.
float weatherVerticalLever = clamp(weatherRelativeWorld.y, -16.0, 24.0);
vec3 weatherOffsetWorld =
    vec3(weatherDriftWorld.x, 0.0, weatherDriftWorld.y) *
    weatherVerticalLever;
vec3 weatherOffsetView =
    mat3(gl_ModelViewMatrix) * weatherOffsetWorld;

gl_Position += gl_ProjectionMatrix * vec4(weatherOffsetView, 0.0);

// position_vertex.glsl calculated fog distance before the weather shear.
// Reconstruct it once so distant streaks enter atmospheric fog correctly.
homopos = gbufferProjectionInverse *
    vec4(gl_Position.xyz / gl_Position.w, 1.0);
viewPos = homopos.xyz / homopos.w;
gl_FogFragCoord = length(viewPos);
weatherViewPosition = viewPos;

weatherWindView = normalize(
    mat3(gl_ModelViewMatrix) *
    vec3(weatherDriftWorld.x, -1.0, weatherDriftWorld.y)
);
weatherCameraResponse =
    clamp(length(weatherCameraStep) * RAIN_MOTION_RESPONSE * 3.0, 0.0, 1.0);
