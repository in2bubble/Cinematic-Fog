/* Oxygen Atmosphere - color_utils.glsl
Usefull data for color manipulation.

Javier Garduño - GNU Lesser General Public License v3.0
*/

uniform float dayMoment;
uniform float dayMixer;
uniform float nightMixer;

// Lunar eclipses are an Overworld-only event. End cloud shading shares the
// Oxygen Atmosphere cloud code, so provide its neutral eclipse value here.
#define OXYGEN_ATMOSPHERE_LUNAR_ECLIPSE_LIGHTING 0.0

#define OMNI_TINT 0.62
#define LIGHT_SUNSET_COLOR vec3(0.235, 0.245, 0.330)
#define LIGHT_DAY_COLOR vec3(0.235, 0.245, 0.330)
#define LIGHT_NIGHT_COLOR vec3(0.235, 0.245, 0.330)

// The End has no conventional sky. These colors describe the electrical
// void, the distant haze and the light carried by its storm clouds.
#define ZENITH_SUNSET_COLOR vec3(0.012, 0.016, 0.035)
#define ZENITH_DAY_COLOR vec3(0.012, 0.016, 0.035)
#define ZENITH_NIGHT_COLOR vec3(0.012, 0.016, 0.035)

#define HORIZON_SUNSET_COLOR vec3(0.075, 0.095, 0.155)
#define HORIZON_DAY_COLOR vec3(0.075, 0.095, 0.155)
#define HORIZON_NIGHT_COLOR vec3(0.075, 0.095, 0.155)

#define END_VOID_COLOR vec3(0.012, 0.016, 0.032)
#define END_STORM_FOG_COLOR vec3(0.075, 0.095, 0.155)
#define WATER_COLOR vec3(0.018, 0.075, 0.120)

#if BLOCKLIGHT_TEMP == 0
    #define CANDLE_BASELIGHT vec3(0.29975, 0.15392353, 0.0799)
#elif BLOCKLIGHT_TEMP == 1
    #define CANDLE_BASELIGHT vec3(0.27475, 0.17392353, 0.0899)
#elif BLOCKLIGHT_TEMP == 2
    #define CANDLE_BASELIGHT vec3(0.24975, 0.19392353, 0.0999)
#elif BLOCKLIGHT_TEMP == 3
    #define CANDLE_BASELIGHT vec3(0.22, 0.19, 0.14)
#else
    #define CANDLE_BASELIGHT vec3(0.19, 0.19, 0.19)
#endif

#include "/lib/day_blend.glsl"

// Fog parameter per hour
#if VOL_LIGHT == 1 || (VOL_LIGHT == 2 && defined SHADOW_CASTING)
    #define FOG_DENSITY 1.0
#else
    #define FOG_DAY 1.0
    #define FOG_SUNSET 1.0
    #define FOG_NIGHT 1.0
#endif

#include "/lib/color_conversion.glsl"
