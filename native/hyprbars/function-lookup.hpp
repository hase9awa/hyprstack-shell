#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cxxabi.h>
#include <dlfcn.h>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <unistd.h>
#include <vector>

namespace HyprstackSymbols {
inline std::vector<SFunctionMatch> findFunctions(HANDLE handle, const std::string& name) {
    try {
        return HyprlandAPI::findFunctionsByName(handle, name);
    } catch (const std::filesystem::filesystem_error& error) {
        if (error.path1() != "/proc/self/exe") throw;
    }

    // Package upgrades unlink the running executable. Hyprland's canonical()
    // lookup then fails, although /proc/<pid>/exe still opens that exact inode.
    // Resolve symbols from the running image, never the replacement on disk.
    static const auto symbols = [] {
        const auto command = "nm -D -j /proc/" + std::to_string(getpid()) + "/exe";
        auto* pipe = popen(command.c_str(), "r");
        if (!pipe) throw std::runtime_error("[hyprstack] Cannot inspect running compositor symbols");
        std::vector<SFunctionMatch> result;
        std::array<char, 16384> buffer;
        while (fgets(buffer.data(), buffer.size(), pipe)) {
            std::string signature(buffer.data());
            if (!signature.empty() && signature.back() == '\n') signature.pop_back();
            auto* address = dlsym(RTLD_DEFAULT, signature.c_str());
            if (!address) continue;
            int status = 0;
            auto* demangled = abi::__cxa_demangle(signature.c_str(), nullptr, nullptr, &status);
            result.push_back({address, signature, status == 0 ? demangled : signature});
            free(demangled);
        }
        const auto status = pclose(pipe);
        // Hyprland's SIGCHLD handler may have reaped nm before pclose().
        if (result.empty() || status > 0 || (status < 0 && errno != ECHILD))
            throw std::runtime_error("[hyprstack] Cannot read running compositor symbols");
        return result;
    }();

    std::vector<SFunctionMatch> matches;
    for (const auto& symbol : symbols)
        if (symbol.signature.contains(name)) matches.push_back(symbol);
    return matches;
}
} // namespace HyprstackSymbols
