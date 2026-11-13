#pragma once
// Exact PE contract, independently disassembled. No engine code is executed here.
#if defined(_WIN32) && !defined(UNIT_TEST)
#include <windows.h>
#include <wincrypt.h>
#include <vector>
#include <cstring>
#include <cstdint>

namespace WindowsEngineContract {
constexpr uintptr_t LagRva = 0x1c9ba0, TimeRva = 0x6b2b48, TableRva = 0x6b2e04;
constexpr size_t BufferBytes = 0x37ab0;

inline bool Region(const void* address, size_t bytes, bool write = false, bool execute = false)
{
    uintptr_t cursor = reinterpret_cast<uintptr_t>(address);
    if (!cursor || !bytes || bytes > UINTPTR_MAX - cursor) return false;
    const uintptr_t end = cursor + bytes;
    while (cursor < end) {
        MEMORY_BASIC_INFORMATION region{};
        if (!VirtualQuery(reinterpret_cast<void*>(cursor), &region, sizeof(region)) ||
            region.State != MEM_COMMIT || (region.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
        const DWORD p = region.Protect & 0xff;
        const bool readable = p == PAGE_READONLY || p == PAGE_READWRITE || p == PAGE_WRITECOPY ||
            p == PAGE_EXECUTE_READ || p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
        const bool writable = p == PAGE_READWRITE || p == PAGE_WRITECOPY ||
            p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
        const bool executable = p == PAGE_EXECUTE_READ || p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
        if (!readable || (write && !writable) || (execute && !executable)) return false;
        const uintptr_t next = reinterpret_cast<uintptr_t>(region.BaseAddress) + region.RegionSize;
        if (next <= cursor) return false;
        cursor = next;
    }
    return true;
}

inline bool ReadIdentifiedFile(HMODULE module, std::vector<unsigned char>& file)
{
    wchar_t path[32768];
    const DWORD length = GetModuleFileNameW(module, path, 32768);
    if (!length || length >= 32768) return false;
    HANDLE handle = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size{};
    bool ok = GetFileSizeEx(handle, &size) && size.QuadPart > 0 && size.QuadPart <= 16 * 1024 * 1024;
    if (ok) {
        file.resize(static_cast<size_t>(size.QuadPart));
        DWORD read = 0;
        ok = ReadFile(handle, file.data(), static_cast<DWORD>(file.size()), &read, nullptr) && read == file.size();
    }
    HCRYPTPROV provider = 0; HCRYPTHASH hash = 0;
    unsigned char digest[32]{}; DWORD digestBytes = sizeof(digest);
    static const unsigned char expected[] = {
        0x8a,0x6d,0x46,0x80,0x59,0x39,0x4b,0xf4,0xcf,0xce,0x32,0xf1,0x1d,0xcb,0xa1,0x2e,
        0xf4,0x5d,0xe8,0x8d,0xa1,0x37,0x30,0x84,0xd5,0xa2,0x91,0x6d,0x0b,0xf7,0xba,0x86
    };
    ok = ok && CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) &&
        CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash) &&
        CryptHashData(hash, file.data(), static_cast<DWORD>(file.size()), 0) &&
        CryptGetHashParam(hash, HP_HASHVAL, digest, &digestBytes, 0) &&
        digestBytes == sizeof(expected) && !std::memcmp(digest, expected, sizeof(expected));
    if (hash) CryptDestroyHash(hash);
    if (provider) CryptReleaseContext(provider, 0);
    CloseHandle(handle);
    return ok;
}

inline bool Identify(const void* lag, const double* time, unsigned char*& base, const char*& error)
{
    error = "Windows engine: unresolved or foreign module addresses";
    HMODULE owner = nullptr, timeOwner = nullptr;
    const DWORD flags = GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
    if (!lag || !time || !GetModuleHandleExW(flags, reinterpret_cast<LPCWSTR>(lag), &owner) ||
        !GetModuleHandleExW(flags, reinterpret_cast<LPCWSTR>(time), &timeOwner) || owner != timeOwner) return false;
    base = reinterpret_cast<unsigned char*>(owner);
    if (lag != base + LagRva || reinterpret_cast<const void*>(time) != base + TimeRva) return false;
    error = "Windows engine: SHA-256 is not the analyzed PE32 module";
    std::vector<unsigned char> file;
    if (!ReadIdentifiedFile(owner, file)) return false;
    // Only the exact hashed file is parsed below. Never parse unknown PE offsets.
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(file.data());
    const auto* pe = reinterpret_cast<const IMAGE_NT_HEADERS32*>(file.data() + dos->e_lfanew);
    error = "Windows engine: unsupported architecture, headers or memory regions";
    if (sizeof(void*) != 4 || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
        pe->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC ||
        pe->OptionalHeader.SizeOfImage != 0x73f000 || !Region(base, pe->OptionalHeader.SizeOfHeaders) ||
        !Region(lag, 0x211, false, true) || !Region(time, sizeof(double), true) ||
        !Region(base + TableRva, sizeof(void*), true)) return false;
    const auto* loaded = reinterpret_cast<const IMAGE_NT_HEADERS32*>(base + dos->e_lfanew);
    // The Windows loader updates OptionalHeader.ImageBase after rebasing.
    IMAGE_NT_HEADERS32 rebasedHeaders = *pe;
    rebasedHeaders.OptionalHeader.ImageBase = static_cast<DWORD>(reinterpret_cast<uintptr_t>(base));
    if (std::memcmp(base, file.data(), sizeof(IMAGE_DOS_HEADER)) ||
        std::memcmp(loaded, &rebasedHeaders, sizeof(IMAGE_NT_HEADERS32))) return false;
    // Bind disk identity to loaded code, accounting for ASLR HIGHLOW relocations.
    // This also rejects pre-existing third-party patches in the analyzed code.
    std::vector<unsigned char> image(pe->OptionalHeader.SizeOfImage, 0);
    const auto* sections = IMAGE_FIRST_SECTION(pe);
    for (unsigned i = 0; i < pe->FileHeader.NumberOfSections; ++i)
        std::memcpy(image.data() + sections[i].VirtualAddress,
                    file.data() + sections[i].PointerToRawData, sections[i].SizeOfRawData);
    const auto& reloc = pe->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC];
    const uint32_t delta = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(base) - pe->OptionalHeader.ImageBase);
    for (size_t cursor = reloc.VirtualAddress; cursor < reloc.VirtualAddress + reloc.Size;) {
        const auto* block = reinterpret_cast<const IMAGE_BASE_RELOCATION*>(image.data() + cursor);
        if (block->SizeOfBlock < sizeof(*block) || block->SizeOfBlock > reloc.VirtualAddress + reloc.Size - cursor) return false;
        const auto* entries = reinterpret_cast<const WORD*>(block + 1);
        for (size_t i = 0; i < (block->SizeOfBlock - sizeof(*block)) / sizeof(WORD); ++i) {
            const unsigned type = entries[i] >> 12;
            if (!type) continue;
            if (type != IMAGE_REL_BASED_HIGHLOW) return false;
            const size_t rva = block->VirtualAddress + (entries[i] & 0xfff);
            if (rva > image.size() - sizeof(uint32_t)) return false;
            uint32_t value; std::memcpy(&value, image.data() + rva, sizeof(value));
            value += delta; std::memcpy(image.data() + rva, &value, sizeof(value));
        }
        cursor += block->SizeOfBlock;
    }
    error = "Windows engine: loaded executable bytes differ from identified file";
    for (unsigned i = 0; i < pe->FileHeader.NumberOfSections; ++i) {
        const auto& section = sections[i];
        if (!(section.Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
        if (!Region(base + section.VirtualAddress, section.Misc.VirtualSize, false, true) ||
            std::memcmp(base + section.VirtualAddress, image.data() + section.VirtualAddress, section.Misc.VirtualSize)) return false;
    }
    error = "Windows engine: net_time operand does not resolve to the verified double";
    uintptr_t resolved = 0;
    std::memcpy(&resolved, base + 0x1c9d6c, sizeof(resolved));
    if (resolved != reinterpret_cast<uintptr_t>(time)) return false;
    error = "Windows engine identified; SRCDS acceptance must be recorded separately";
    return true;
}
} // namespace WindowsEngineContract
#endif
