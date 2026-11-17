#version 440
// Qt content mask using goopUI's field reconstruction.
// MIT License, Copyright (c) 2026 Timothy McMasters.
// Full notice: third_party/goopui/LICENSE and utils/vendor/goopui/core.js.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 contentRect;
    vec4 fieldRect;
    vec2 maskExtent;
    vec2 sourceScale;
    float contrast;
    float threshold;
};
layout(binding=1) uniform sampler2D source;
layout(binding=2) uniform sampler2D maskSource;

// Same bicubic reconstruction and threshold as goopUI's solid edge pass.
float field(vec2 p) {
    vec2 t=p-0.5,i=floor(t),f=t-i,f2=f*f,f3=f2*f;
    vec2 w0=(1.0-3.0*f+3.0*f2-f3)/6.0;
    vec2 w1=(4.0-6.0*f2+3.0*f3)/6.0;
    vec2 w2=(1.0+3.0*f+3.0*f2-3.0*f3)/6.0;
    vec2 w3=f3/6.0,g0=w0+w1,g1=w2+w3;
    vec2 h0=i-0.5+w1/g0,h1=i+1.5+w3/g1;
    float a=texture(maskSource,vec2(h0.x,h0.y)/maskExtent).a;
    float b=texture(maskSource,vec2(h1.x,h0.y)/maskExtent).a;
    float c=texture(maskSource,vec2(h0.x,h1.y)/maskExtent).a;
    float d=texture(maskSource,vec2(h1.x,h1.y)/maskExtent).a;
    return g0.y*(g0.x*a+g1.x*b)+g1.y*(g0.x*c+g1.x*d);
}
void main() {
    vec2 world=contentRect.xy+qt_TexCoord0*contentRect.zw;
    vec2 uv=(world-fieldRect.xy)/max(fieldRect.zw,vec2(1.0));
    if(any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0))) || any(lessThanEqual(fieldRect.zw,vec2(0.0)))) {
        fragColor=vec4(0.0);
        return;
    }
    float f=field(uv*maskExtent),t0=threshold+0.5/contrast;
    float a=clamp((f-t0)/max(1.0/contrast,fwidth(f))+0.5,0.0,1.0);
    fragColor=texture(source,qt_TexCoord0*sourceScale)*(a*qt_Opacity);
}
