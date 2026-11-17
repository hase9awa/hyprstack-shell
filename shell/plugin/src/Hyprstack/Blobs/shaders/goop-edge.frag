#version 440
// Qt port of goopUI packages/core/src/renderers/gl.ts EDGE_FS, solid finish.
// MIT License, Copyright (c) 2026 Timothy McMasters.
// Full notice: third_party/goopui/LICENSE and utils/vendor/goopui/core.js.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 textureExtent;
    float contrast;
    float threshold;
    vec4 paintColor;
    vec4 fieldRect;
    vec4 hostRect;
    float hostRadius;
    bool cutoutHost;
    bool joinsFrame;
    vec2 frameViewport;
    vec2 frameExtent;
};
layout(binding=1) uniform sampler2D source;
layout(binding=2) uniform sampler2D frameSource;
layout(binding=3) uniform sampler2D frameBaseline;
float bicubic(sampler2D image,vec2 p,vec2 extent) {
    vec2 t=p-0.5;
    vec2 i=floor(t);
    vec2 f=t-i;
    vec2 f2=f*f,f3=f2*f;
    vec2 w0=(1.0-3.0*f+3.0*f2-f3)/6.0;
    vec2 w1=(4.0-6.0*f2+3.0*f3)/6.0;
    vec2 w2=(1.0+3.0*f+3.0*f2-3.0*f3)/6.0;
    vec2 w3=f3/6.0;
    vec2 g0=w0+w1,g1=w2+w3;
    vec2 h0=i-0.5+w1/g0;
    vec2 h1=i+1.5+w3/g1;
    float a=texture(image,vec2(h0.x,h0.y)/extent).a;
    float b=texture(image,vec2(h1.x,h0.y)/extent).a;
    float c=texture(image,vec2(h0.x,h1.y)/extent).a;
    float d=texture(image,vec2(h1.x,h1.y)/extent).a;
    return g0.y*(g0.x*a+g1.x*b)+g1.y*(g0.x*c+g1.x*d);
}
void main() {
    float f=bicubic(source,qt_TexCoord0*textureExtent,textureExtent);
    float t0=threshold+0.5/contrast;
    float w=max(1.0/contrast,fwidth(f));
    float a=clamp((f-t0)/w+0.5,0.0,1.0);
    if(joinsFrame) {
        vec2 uv=(fieldRect.xy+qt_TexCoord0*fieldRect.zw)/frameViewport;
        float base=bicubic(frameBaseline,uv*frameExtent,frameExtent);
        float host=texture(frameSource,uv).a;
        // Add only what the liquid contributes beyond the frame's own field.
        // Compensate source-over alpha so translucent frame joins stay flat.
        // Compare densities before thresholding: the filtered frame can be
        // fully covered while the native frame's antialiased edge is not.
        // Subtracting thresholded alpha there would leave a dark seam.
        float added=clamp((f-base)*contrast,0.0,1.0);
        a=max(0.0,a-host)*added/max(1.0-host*paintColor.a*qt_Opacity,0.0001);
    } else if(cutoutHost) {
        // The bar's existing label sits above its original indicator. Add
        // only the filtered overflow, preserving that host's own pixels.
        vec2 p=fieldRect.xy+qt_TexCoord0*fieldRect.zw;
        vec2 q=abs(p-hostRect.xy-hostRect.zw*0.5)-hostRect.zw*0.5+hostRadius;
        float d=min(max(q.x,q.y),0.0)+length(max(q,0.0))-hostRadius;
        float fw=max(fwidth(d),0.001);
        float host=1.0-smoothstep(-fw,fw,d);
        a=max(0.0,a-host)/max(1.0-host*paintColor.a*qt_Opacity,0.0001);
    }
    fragColor=paintColor*(a*qt_Opacity);
}
