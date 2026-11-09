/* Cinematic Fog - basic_utils.glsl
Misc utilities.

Javier Garduño - GNU Lesser General Public License v3.0
*/

float squarePow(float x) {
    return x * x;
}

float fourthPow(float x) {
    float temp2 = x * x;
    return temp2 * temp2;
}

float sixthPow(float x) {
    float temp2 = x * x;
    return temp2 * temp2 * temp2;
}
