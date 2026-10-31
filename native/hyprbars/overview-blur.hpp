// Cached wallpaper blur for Hyprstack's pinned Hyprland 0.57 renderer.
// Filter in linear light, with FP16 intermediates and a normalized Gaussian.
#pragma once

#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

namespace HyprstackOverview {
class WallpaperBlur {
  public:
    const std::string& error() const { return m_error; }

    SP<Render::IFramebuffer> render(SP<Render::IFramebuffer> source, double sigma) {
        auto* renderer = g_pHyprRenderer.get();
        if (!source || !source->getTexture()) return nullptr;
        GLint viewport[4], scissor[4], vao, arrayBuffer, activeTexture, texture;
        GLboolean mask[4];
        glGetIntegerv(GL_VIEWPORT, viewport); glGetIntegerv(GL_SCISSOR_BOX, scissor);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao); glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &arrayBuffer);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture);
        glActiveTexture(GL_TEXTURE0); glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
        glGetBooleanv(GL_COLOR_WRITEMASK, mask);
        const bool blend = glIsEnabled(GL_BLEND), stencil = glIsEnabled(GL_STENCIL_TEST), clipping = glIsEnabled(GL_SCISSOR_TEST);
        auto bind = renderer->bindTempFB(g_pHyprRenderer->context(), source);
        Hyprutils::Utils::CScopeGuard restore([&] {
            renderer->setViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
            renderer->blend(blend);
            Render::GL::g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, stencil);
            Render::GL::g_pHyprOpenGL->setCapStatus(GL_SCISSOR_TEST, clipping);
            glScissor(scissor[0], scissor[1], scissor[2], scissor[3]);
            glColorMask(mask[0], mask[1], mask[2], mask[3]);
            glBindVertexArray(vao); glBindBuffer(GL_ARRAY_BUFFER, arrayBuffer);
            glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D, texture); glActiveTexture(activeTexture);
        });
        if (!shader()) return nullptr;
        const auto half = Vector2D{std::max(1.0, std::ceil(source->m_size.x / 2)), std::max(1.0, std::ceil(source->m_size.y / 2))};
        const auto quarter = Vector2D{std::max(1.0, std::ceil(half.x / 2)), std::max(1.0, std::ceil(half.y / 2))};
        const auto description = source->imageDescription() ? source->imageDescription() : renderer->workBufferImageDescription(g_pHyprRenderer->context());
        const auto allocate = [&](SP<Render::IFramebuffer>& fb, Vector2D size, const char* name) {
            if (!fb) fb = renderer->createFB(name);
            if (!fb || !fb->alloc(size.x, size.y, DRM_FORMAT_ABGR16161616F)) { m_error = "Cannot allocate floating-point wallpaper blur buffer"; return false; }
            fb->setImageDescription(description);
            return true;
        };
        if (!allocate(m_half, half, "Overview wallpaper downsample") || !allocate(m_small, quarter, "Overview wallpaper linear") ||
            !allocate(m_horizontal, quarter, "Overview wallpaper Gaussian X") || !allocate(m_vertical, quarter, "Overview wallpaper Gaussian Y") ||
            !allocate(m_output, source->m_size, "Overview wallpaper Gaussian")) return nullptr;
        renderer->blend(false);
        Render::GL::g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, false);
        renderer->disableScissor();
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        Render::GL::g_pHyprOpenGL->useShader(m_shader);
        m_shader->setUniformInt(SHADER_TEX, 0);
        glUniform1i(m_transfer, transfer(description->value().transferFunction));
        // Two antialiased 2x reductions avoid aliasing before the convolution.
        // Decode each source sample before averaging, rather than filtering gamma.
        draw(source->getTexture(), m_half, 0, {});
        draw(m_half->getTexture(), m_small, 1, {});
        kernel(sigma * quarter.x / source->m_size.x);
        draw(m_small->getTexture(), m_horizontal, 2, {1.0 / quarter.x, 0.0});
        kernel(sigma * quarter.y / source->m_size.y);
        draw(m_horizontal->getTexture(), m_vertical, 2, {0.0, 1.0 / quarter.y});
        // Upsample in linear light, then encode the original working transfer
        // function. Gamut, HDR range and the compositor's output transform stay intact.
        draw(m_vertical->getTexture(), m_output, 3, {});
        m_error.clear();
        return m_output;
    }

  private:
    static int transfer(NColorManagement::eTransferFunction value) {
        switch (value) {
            case NColorManagement::CM_TRANSFER_FUNCTION_SRGB:
            case NColorManagement::CM_TRANSFER_FUNCTION_EXT_SRGB: return 1;
            case NColorManagement::CM_TRANSFER_FUNCTION_GAMMA22: return 2;
            case NColorManagement::CM_TRANSFER_FUNCTION_BT1886: return 5;
            case NColorManagement::CM_TRANSFER_FUNCTION_GAMMA28: return 3;
            case NColorManagement::CM_TRANSFER_FUNCTION_ST2084_PQ: return 4;
            default: return 0; // Hyprland's linear working buffers.
        }
    }
    bool shader() {
        if (m_shader) return true;
        if (m_attempted) return false;
        m_attempted = true;
        auto shader = makeShared<CShader>();
        const std::string vertex = R"GLSL(#version 300 es
precision highp float;
in vec2 pos;
out vec2 uv;
void main() { uv = pos; gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0); }
)GLSL";
        const std::string fragment = R"GLSL(#version 300 es
precision highp float;
precision highp int;
uniform highp sampler2D tex;
uniform int stage;
uniform int transfer;
uniform vec2 texel;
uniform vec2 direction;
uniform float centre;
uniform int count;
uniform vec2 pairs[64];
in vec2 uv;
out vec4 result;
vec3 decode(vec3 v) {
    if (transfer == 0) return v;
    v = max(v, vec3(0.0));
    if (transfer == 1) return mix(v / 12.92, pow((v + 0.055) / 1.055, vec3(2.4)), greaterThan(v, vec3(0.04045)));
    if (transfer == 2) return pow(v, vec3(2.2));
    if (transfer == 3) return pow(v, vec3(2.8));
    if (transfer == 5) return pow(v, vec3(2.4));
    vec3 p = pow(v, vec3(1.0 / 78.84375));
    return pow(max(p - 0.8359375, vec3(0.0)) / max(18.8515625 - 18.6875 * p, vec3(1e-6)), vec3(1.0 / 0.1593017578125));
}
vec3 encode(vec3 v) {
    if (transfer == 0) return v;
    v = max(v, vec3(0.0));
    if (transfer == 1) return mix(v * 12.92, 1.055 * pow(v, vec3(1.0 / 2.4)) - 0.055, greaterThan(v, vec3(0.0031308)));
    if (transfer == 2) return pow(v, vec3(1.0 / 2.2));
    if (transfer == 3) return pow(v, vec3(1.0 / 2.8));
    if (transfer == 5) return pow(v, vec3(1.0 / 2.4));
    vec3 p = pow(v, vec3(0.1593017578125));
    return pow((0.8359375 + 18.8515625 * p) / (1.0 + 18.6875 * p), vec3(78.84375));
}
vec4 sampleSource(vec2 at) {
    vec4 value = texture(tex, at);
    if (stage == 0) value.rgb = decode(value.rgb);
    return value;
}
void main() {
    if (stage <= 1) {
        vec2 d = texel * 0.5;
        result = (sampleSource(uv + vec2(-d.x, -d.y)) + sampleSource(uv + vec2(d.x, -d.y))
            + sampleSource(uv + vec2(-d.x, d.y)) + sampleSource(uv + vec2(d.x, d.y))) * 0.25;
    } else if (stage == 2) {
        result = texture(tex, uv) * centre;
        for (int i = 0; i < 64; ++i) {
            if (i >= count) break;
            vec2 d = direction * pairs[i].y;
            result += (texture(tex, uv + d) + texture(tex, uv - d)) * pairs[i].x;
        }
    } else {
        result = texture(tex, uv);
        result.rgb = encode(result.rgb);
    }
}
)GLSL";
        if (!shader->createProgram(vertex, fragment, true, true)) {
            m_error = "Cannot compile overview Gaussian blur shader";
            return false;
        }
        m_shader = shader;
        const auto uniform = [&](const char* name) { return glGetUniformLocation(shader->program(), name); };
        m_stage = uniform("stage"); m_transfer = uniform("transfer"); m_texel = uniform("texel");
        m_direction = uniform("direction"); m_centre = uniform("centre"); m_count = uniform("count"); m_pairs = uniform("pairs");
        return true;
    }
    void kernel(double sigma) {
        sigma = std::clamp(sigma, 0.5, 40.0);
        const int radius = std::ceil(sigma * 3.0);
        std::vector<double> weights(radius + 2, 0);
        double sum = 1;
        weights[0] = 1;
        for (int i = 1; i <= radius; ++i) { weights[i] = std::exp(-0.5 * i * i / (sigma * sigma)); sum += 2 * weights[i]; }
        std::vector<float> pairs;
        for (int i = 1; i <= radius; i += 2) {
            const double weight = weights[i] + weights[i + 1];
            pairs.push_back(weight / sum);
            pairs.push_back(i + weights[i + 1] / weight);
        }
        glUniform1f(m_centre, weights[0] / sum);
        glUniform1i(m_count, pairs.size() / 2);
        glUniform2fv(m_pairs, pairs.size() / 2, pairs.data());
    }
    void draw(SP<Render::ITexture> texture, SP<Render::IFramebuffer> target, int stage, Vector2D direction) {
        g_pHyprRenderer->bindFB(g_pHyprRenderer->context(), target);
        g_pHyprRenderer->setViewport(0, 0, target->m_size.x, target->m_size.y);
        glActiveTexture(GL_TEXTURE0);
        texture->bind();
        texture->setTexParameter(GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        texture->setTexParameter(GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        texture->setTexParameter(GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        texture->setTexParameter(GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glUniform1i(m_stage, stage);
        glUniform2f(m_texel, 1.0 / texture->m_size.x, 1.0 / texture->m_size.y);
        glUniform2f(m_direction, direction.x, direction.y);
        glBindVertexArray(m_shader->getUniformLocation(SHADER_SHADER_VAO));
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }

    SP<CShader> m_shader;
    SP<Render::IFramebuffer> m_half, m_small, m_horizontal, m_vertical, m_output;
    bool m_attempted = false;
    std::string m_error;
    GLint m_stage=-1, m_transfer=-1, m_texel=-1, m_direction=-1, m_centre=-1, m_count=-1, m_pairs=-1;
};
} // namespace HyprstackOverview
