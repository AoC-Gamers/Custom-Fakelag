#include "ContextSnapshot.h"
#include "TraceFile.h"
#include <map>
#include <iostream>
#include <fstream>
#include <iterator>
#include <cstring>
#ifdef _WIN32
#include "WindowsProbe.h"
#endif

int failures = 0;
void Check(bool value, const char* what) {
    if (!value) { std::cerr << "FAIL " << what << '\n'; ++failures; }
}
std::string Contents(const std::string& path) {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
int main(int argc, char** argv) {
    if (argc != 2) { std::cerr << "Supply an existing private temporary directory\n"; return 2; }
    std::map<uint32_t, uint32_t> memory = {
        {0x1004, 0x2000}, {0x1008, 0x3000}, {0x2000, 0x4000}, {0x3000, 0x5000},
        {0x4028, 0x6000}, {0x5024, 0x7000}
    };
    int reads = 0;
    auto read = [&](uint32_t address, uint32_t& value) {
        ++reads; const auto it = memory.find(address);
        if (it == memory.end()) return false;
        value = it->second; return true;
    };
    auto inSteam = [](uint32_t address) { return address >= 0x4000 && address < 0x8000; };
    auto executable = [](uint32_t address) { return address == 0x6000 || address == 0x7000; };
    Check(!SteamTrace::Capture(false, 0x1000, read, inSteam, executable).identified && reads == 0,
          "unknown identity causes no reads");
    Check(!SteamTrace::Capture(true, 0xfffffffcu, read, inSteam, executable).identified && reads == 0,
          "overflowing context causes no reads");
    const auto valid = SteamTrace::Capture(true, 0x1000, read, inSteam, executable);
    Check(valid.identified && reads == 6 && valid.fields[0].methodExecutable &&
          valid.fields[1].method == 0x7000 && valid.fields[1].vtableInSteam, "both interface chains sampled");
    Check(SteamTrace::Same(valid, valid), "stable snapshot compares equal");
    memory[0x2000] = 0;
    const auto stale = SteamTrace::Capture(true, 0x1000, read, inSteam, executable);
    Check(stale.fields[0].vtableRead && !stale.fields[0].methodRead && !SteamTrace::Same(valid, stale),
          "cleared vtable remains observable without following null");
    memory[0x2000] = 0xfffffff0u;
    Check(!SteamTrace::Capture(true, 0x1000, read, inSteam, executable).fields[0].methodRead,
          "overflowing method slot is not read");
    memory.erase(0x3000);
    Check(!SteamTrace::Capture(true, 0x1000, read, inSteam, executable).fields[1].vtableRead,
          "unreadable freed object is a read failure");
    memory[0x1004] = 0;
    Check(!SteamTrace::Capture(true, 0x1000, read, inSteam, executable).fields[0].vtableRead,
          "null interface is not dereferenced");
    const std::string path = std::string(argv[1]) + "/trace.log";
    SteamTrace::TraceFile file(12);
    Check(!file.Write("off\n"), "closed logger does not write");
    Check(file.Open(path.c_str()) && file.Write("12345\n"), "create and write trace");
    Check(Contents(path) == "12345\n", "records flushed before close");
    file.Close();
    Check(file.Open(path.c_str()) && file.Write("abcde\n"), "re-enable appends");
    Check(file.Write("new\n") && Contents(path + ".1") == "12345\nabcde\n" && Contents(path) == "new\n",
          "rotation bounds current file and preserves previous records");
    Check(file.Write("12345678\n") && Contents(path + ".1") == "new\n", "only one rotated file retained");
    Check(!file.Write(std::string(13, 'x')), "oversized record refused");
    file.Close();
    Check(!file.Open((path + "/missing.log").c_str()), "file failure is reported");
    std::remove(path.c_str()); std::remove((path + ".1").c_str());
#ifdef _WIN32
    uint32_t value = 0;
    Check(!SteamTrace::ReadMemory(1, &value, sizeof(value)), "native invalid memory read fails safely");
    Check(!SteamTrace::IdentifyServer(GetModuleHandleW(nullptr)), "unrecognized native executable identity refused");
    auto* page = static_cast<uint32_t*>(VirtualAlloc(nullptr, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
    Check(page != nullptr, "allocate native read fixture");
    if (page) {
        *page = 123;
        Check(SteamTrace::ReadMemory(reinterpret_cast<uintptr_t>(page), &value, sizeof(value)) && value == 123,
              "native safe copy observes allocated memory");
        DWORD old = 0;
        Check(VirtualProtect(page, 4096, PAGE_NOACCESS, &old) != 0, "protect native read fixture");
        Check(!SteamTrace::ReadMemory(reinterpret_cast<uintptr_t>(page), &value, sizeof(value)),
              "native inaccessible page is reported without dereferencing");
        VirtualFree(page, 0, MEM_RELEASE);
    }
#endif
    std::cout << (failures ? "Diagnostic tests failed\n" : "Diagnostic tests passed (no SRCDS runtime claim)\n");
    return failures ? 1 : 0;
}
