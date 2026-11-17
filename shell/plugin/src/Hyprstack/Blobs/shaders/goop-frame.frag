#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 fieldRect;
    vec2 frameViewport;
};
layout(binding=1) uniform sampler2D frameSource;
void main() {
    vec2 uv=(fieldRect.xy+qt_TexCoord0*fieldRect.zw)/frameViewport;
    float a=texture(frameSource,uv).a;
    fragColor=vec4(a)*qt_Opacity;
}
