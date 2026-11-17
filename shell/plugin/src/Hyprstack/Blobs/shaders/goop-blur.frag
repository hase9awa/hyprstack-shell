#version 440
// Qt port of goopUI packages/core/src/renderers/gl.ts BLUR_FS.
// MIT License, Copyright (c) 2026 Timothy McMasters.
// Full notice: third_party/goopui/LICENSE and utils/vendor/goopui/core.js.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 direction;
    vec2 textureExtent;
    float centerWeight;
    int tapCount;
    mat4 kernel0;
    mat4 kernel1;
    mat4 kernel2;
    mat4 kernel3;
    mat4 kernel4;
    mat4 kernel5;
    mat4 kernel6;
    mat4 kernel7;
};
layout(binding=1) uniform sampler2D source;
vec2 tapAt(int i) {
    int j=i%4;
    if(i<4)return kernel0[j].xy;
    if(i<8)return kernel1[j].xy;
    if(i<12)return kernel2[j].xy;
    if(i<16)return kernel3[j].xy;
    if(i<20)return kernel4[j].xy;
    if(i<24)return kernel5[j].xy;
    if(i<28)return kernel6[j].xy;
    return kernel7[j].xy;
}
float at(vec2 p) {
    vec2 halfPixel=0.5/textureExtent;
    return texture(source,clamp(p,halfPixel,vec2(1.0)-halfPixel)).a;
}
void main() {
    float value=texture(source,qt_TexCoord0).a*centerWeight;
    for(int i=0;i<32;i++) {
        if(i>=tapCount)break;
        vec2 tap=tapAt(i);
        vec2 delta=direction*tap.x;
        value+=(at(qt_TexCoord0+delta)+at(qt_TexCoord0-delta))*tap.y;
    }
    fragColor=vec4(value);
}
