#pragma once
#include "ContextSnapshot.h"
#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#include <cstring>

namespace SteamTrace {
inline bool ReadMemory(uintptr_t address, void* destination, size_t bytes)
{
    SIZE_T copied = 0;
    return address && ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(address),
                                       destination, bytes, &copied) && copied == bytes;
}

inline bool Executable(uint32_t address)
{
    MEMORY_BASIC_INFORMATION region{};
    if (!VirtualQuery(reinterpret_cast<const void*>(static_cast<uintptr_t>(address)), &region, sizeof(region)) ||
        region.State != MEM_COMMIT || (region.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
    const DWORD protect = region.Protect & 0xff;
    return protect == PAGE_EXECUTE || protect == PAGE_EXECUTE_READ ||
           protect == PAGE_EXECUTE_READWRITE || protect == PAGE_EXECUTE_WRITECOPY;
}

inline bool IsSteamAddress(uint32_t address)
{
    HMODULE owner = nullptr;
    return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(static_cast<uintptr_t>(address)), &owner) && owner == GetModuleHandleW(L"steamclient.dll");
}

inline bool IdentifyServer(HMODULE module)
{
    if (sizeof(void*) != 4 || !module) return false;
    wchar_t path[32768];
    const DWORD length = GetModuleFileNameW(module, path, 32768);
    if (!length || length >= 32768) return false;
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    HCRYPTPROV provider = 0; HCRYPTHASH hash = 0;
    bool ok = CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) &&
              CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash);
    unsigned char buffer[16384]; DWORD bytes = 0;
    while (ok) {
        if (!ReadFile(file, buffer, sizeof(buffer), &bytes, nullptr)) { ok = false; break; }
        if (!bytes) break;
        ok = CryptHashData(hash, buffer, bytes, 0) != 0;
    }
    unsigned char digest[32]; DWORD digestSize = sizeof(digest);
    static const unsigned char expected[] = {
        0xa9,0x3e,0xc9,0x16,0xa8,0xf2,0x6f,0xbe,0xa8,0x56,0x88,0xc3,0x21,0xd2,0xba,0x8d,
        0xd3,0x46,0xd4,0x35,0xfa,0xb0,0x9a,0x0b,0x92,0x6d,0xd9,0x50,0xc2,0xe1,0xea,0x12
    };
    ok = ok && CryptGetHashParam(hash, HP_HASHVAL, digest, &digestSize, 0) &&
         digestSize == sizeof(expected) && !std::memcmp(digest, expected, sizeof(expected));
    if (hash) CryptDestroyHash(hash);
    if (provider) CryptReleaseContext(provider, 0);
    CloseHandle(file);
    // Independently verify loaded architecture and image bounds with safe copies.
    const uintptr_t base = reinterpret_cast<uintptr_t>(module);
    IMAGE_DOS_HEADER dos{}; IMAGE_NT_HEADERS32 pe{};
    return ok && ReadMemory(base, &dos, sizeof(dos)) && dos.e_magic == IMAGE_DOS_SIGNATURE &&
        dos.e_lfanew > 0 && dos.e_lfanew < 1024 * 1024 &&
        ReadMemory(base + dos.e_lfanew, &pe, sizeof(pe)) && pe.Signature == IMAGE_NT_SIGNATURE &&
        pe.FileHeader.Machine == IMAGE_FILE_MACHINE_I386 && pe.OptionalHeader.Magic == IMAGE_NT_OPTIONAL_HDR32_MAGIC &&
        pe.OptionalHeader.SizeOfImage >= 0x7f77dc + 12;
}

class Probe {
    HMODULE m_Server = nullptr;
    bool m_Checked = false, m_Identified = false;
public:
    void Reset() { m_Server = nullptr; m_Checked = m_Identified = false; }
    const char* Status() const { return m_Identified ? "identified_windows_server" : "unsupported_or_unreadable_server"; }
    Snapshot Sample() {
        const HMODULE server = GetModuleHandleW(L"server.dll");
        if (!m_Checked || m_Server != server) {
            m_Server = server; m_Checked = true; m_Identified = IdentifyServer(server);
        }
        const uintptr_t context = reinterpret_cast<uintptr_t>(server) + 0x7f77dc;
        return Capture(m_Identified, static_cast<uint32_t>(context),
            [](uint32_t address, uint32_t& value) { return ReadMemory(address, &value, sizeof(value)); },
            IsSteamAddress, Executable);
    }
};
} // namespace SteamTrace
#else
namespace SteamTrace {
class Probe {
public:
    void Reset() {}
    const char* Status() const { return "context_unsupported_on_this_platform"; }
    Snapshot Sample() { return {}; }
};
}
#endif
