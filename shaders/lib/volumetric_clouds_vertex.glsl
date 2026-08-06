#ifdef OXYGEN_ATMOSPHERE_STYLE
    // Lower threshold produces a broad, heavy cloud deck in clear weather
    // and nearly overcast coverage during rain.
    umbral = mix(0.30, 0.08, rainStrength);
#elif MC_VERSION >= 11300
    umbral = (smoothstep(1.0, 0.0, rainStrength) * .3) + .25;
#else
    umbral = (smoothstep(1.0, 0.0, rainStrength) * .3) + .55;
#endif

darkCloudColor = dayBlend(
    ZENITH_SUNSET_COLOR,
    ZENITH_DAY_COLOR,
    ZENITH_NIGHT_COLOR
);

darkCloudColor = mix(
    darkCloudColor,
    ZENITH_SKY_RAIN_COLOR * colorAverage(darkCloudColor),
    rainStrength
);

vec3 cloudColor_aux = mix(
    dayBlend(
        LIGHT_SUNSET_COLOR,
        LIGHT_DAY_COLOR,
        LIGHT_NIGHT_COLOR * vec3(0.5, 0.6, 0.75)
    ),
    ZENITH_SKY_RAIN_COLOR * colorAverage(darkCloudColor),
    rainStrength
);

cloudColor = mix(
    clamp(mix(vec3(luma(cloudColor_aux)), cloudColor_aux, 0.5) * vec3(1.5), 0.0, 1.4),
    dayBlend(
        HORIZON_SUNSET_COLOR,
        HORIZON_DAY_COLOR,
        HORIZON_NIGHT_COLOR
    ),
    0.3
);

cloudColor = mix(cloudColor, HORIZON_SKY_RAIN_COLOR * luma(cloudColor_aux) * 5.0, rainStrength);

darkCloudColor = mix(darkCloudColor, cloudColor, 0.22);

darkCloudColor = mix(
    darkCloudColor,
    dayBlend(
        cloudColor_aux,
        darkCloudColor,
        darkCloudColor
    ),
    0.4
);

#ifdef OXYGEN_ATMOSPHERE_STYLE
    // Blue-gray cloud lighting carries the broad atmosphere: pale upper
    // masses over a dense, cool and substantially heavier underside.
    float oxygenAtmosphereCloudLuma = luma(cloudColor);
    float oxygenAtmosphereDarkCloudLuma = luma(darkCloudColor);
    float oxygenAtmosphereEclipseNight =
        OXYGEN_ATMOSPHERE_LUNAR_ECLIPSE_LIGHTING *
        step(0.5, dayMoment) *
        nightMixer;
    vec3 oxygenAtmosphereUpperCloudTint = mix(
        vec3(0.92, 0.99, 1.07),
        vec3(1.55, 0.40, 0.28),
        oxygenAtmosphereEclipseNight
    );
    vec3 oxygenAtmosphereLowerCloudTint = mix(
        vec3(0.82, 0.91, 1.04),
        vec3(1.35, 0.30, 0.22),
        oxygenAtmosphereEclipseNight
    );
    cloudColor = mix(
        cloudColor,
        vec3(oxygenAtmosphereCloudLuma) *
            oxygenAtmosphereUpperCloudTint,
        0.72
    ) * 0.86;
    darkCloudColor = mix(
        darkCloudColor,
        vec3(oxygenAtmosphereDarkCloudLuma) *
            oxygenAtmosphereLowerCloudTint,
        0.80
    ) * 0.52;
#endif
