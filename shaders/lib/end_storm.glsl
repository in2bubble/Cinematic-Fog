/*
 * Oxygen Atmosphere - The End storm identity.
 *
 * These helpers deliberately avoid the Overworld day/night system. The End
 * has no sky or lunar cycle; its only large-scale light changes are irregular
 * electrical flashes travelling through the cloud field.
 */

float endStormHash(float value) {
    return fract(sin(value * 91.3458 + 17.173) * 47453.5453);
}

float endStormLightningPulse(float timeValue) {
    const float cycleLength = 9.5;
    float cycle = floor(timeValue / cycleLength);
    float localTime = mod(timeValue, cycleLength);
    float startTime = 1.0 + endStormHash(cycle + 3.17) * 5.8;
    float pulseTime = localTime - startTime;

    float activeWindow =
        step(0.0, pulseTime) *
        (1.0 - step(0.82, pulseTime)) *
        step(0.27, endStormHash(cycle * 2.71 + 8.4));

    float firstFlash = exp(-max(pulseTime, 0.0) * 31.0);
    float returnFlash = exp(-abs(pulseTime - 0.17) * 43.0) * 0.72;
    float finalFlash = exp(-abs(pulseTime - 0.43) * 31.0) * 0.38;

    return clamp(
        activeWindow * (firstFlash + returnFlash + finalFlash),
        0.0,
        1.0
    );
}

float endStormAngularDelta(float firstAngle, float secondAngle) {
    const float PI = 3.14159265359;
    const float TWO_PI = 6.28318530718;
    return abs(mod(firstAngle - secondAngle + PI, TWO_PI) - PI);
}

float endStormLightningGlow(vec3 worldDirection, float timeValue) {
    const float TWO_PI = 6.28318530718;
    float cycle = floor(timeValue / 9.5);
    float boltAzimuth =
        endStormHash(cycle * 5.13 + 1.7) * TWO_PI - 3.14159265359;
    float viewAzimuth = atan(worldDirection.x, worldDirection.z);
    float angularDistance =
        endStormAngularDelta(viewAzimuth, boltAzimuth);

    float verticalPresence =
        smoothstep(-0.16, 0.04, worldDirection.y) *
        (1.0 - smoothstep(0.80, 0.98, worldDirection.y));

    return
        (1.0 - smoothstep(0.035, 0.48, angularDistance)) *
        verticalPresence *
        endStormLightningPulse(timeValue);
}

float endStormLightningBolt(vec3 worldDirection, float timeValue) {
    const float TWO_PI = 6.28318530718;
    float cycle = floor(timeValue / 9.5);
    float seed = endStormHash(cycle * 5.13 + 1.7);
    float boltAzimuth = seed * TWO_PI - 3.14159265359;
    float viewAzimuth = atan(worldDirection.x, worldDirection.z);

    float boltHeight = clamp(worldDirection.y, -0.12, 0.82);
    float mainCurve =
        sin(boltHeight * 19.0 + seed * 12.0) * 0.014 +
        sin(boltHeight * 43.0 - seed * 7.0) * 0.006;
    float mainDistance =
        endStormAngularDelta(viewAzimuth, boltAzimuth + mainCurve);
    float mainBolt =
        1.0 - smoothstep(0.0012, 0.0065, mainDistance);

    float branchGate =
        smoothstep(0.18, 0.25, boltHeight) *
        (1.0 - smoothstep(0.52, 0.61, boltHeight));
    float branchCurve =
        mainCurve +
        (boltHeight - 0.36) *
            mix(-0.11, 0.11, endStormHash(cycle + 31.0));
    float branchDistance =
        endStormAngularDelta(viewAzimuth, boltAzimuth + branchCurve);
    float branchBolt =
        (1.0 - smoothstep(0.0014, 0.0085, branchDistance)) *
        branchGate;

    float verticalPresence =
        smoothstep(-0.10, 0.015, boltHeight) *
        (1.0 - smoothstep(0.69, 0.80, boltHeight));

    return
        clamp(mainBolt + branchBolt * 0.52, 0.0, 1.0) *
        verticalPresence *
        endStormLightningPulse(timeValue);
}

vec3 endStormFogColor(float lightningFlash) {
    vec3 restingFog = vec3(0.075, 0.095, 0.155);
    vec3 chargedFog = vec3(0.270, 0.330, 0.520);
    return mix(restingFog, chargedFog, lightningFlash * 0.72);
}
