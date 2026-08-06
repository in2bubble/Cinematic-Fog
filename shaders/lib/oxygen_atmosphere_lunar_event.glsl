/* Oxygen Atmosphere - shared lunar event helpers. */

#define OXYGEN_ATMOSPHERE_LUNAR_ECLIPSE_INTENSITY 0.60

float oxygenAtmosphereLunarEclipseAmount(int currentWorldDay) {
    float visualMoonStage = mod(float(currentWorldDay), 7.0);
    float isFullMoon =
        1.0 - step(0.5, abs(visualMoonStage - 3.0));
    float eclipseCycle = mod(
        float(currentWorldDay) + 25.0,
        28.0
    );

    return isFullMoon * (1.0 - step(0.5, eclipseCycle));
}
