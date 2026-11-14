#pragma once
#include <cstdio>
#include <string>

namespace SteamTrace {
// Each completed record is flushed. Retain at most one rotated diagnostic file.
class TraceFile {
    FILE* m_File = nullptr;
    std::string m_Path;
    size_t m_Bytes = 0;
    size_t m_Limit;
public:
    explicit TraceFile(size_t limit = 5 * 1024 * 1024) : m_Limit(limit) {}
    ~TraceFile() { Close(); }
    TraceFile(const TraceFile&) = delete;
    TraceFile& operator=(const TraceFile&) = delete;
    void Close() { if (m_File) std::fclose(m_File); m_File = nullptr; }
    bool Open(const char* path) {
        Close(); m_Path = path;
        m_File = std::fopen(path, "ab");
        if (!m_File) return false;
        if (std::fseek(m_File, 0, SEEK_END)) { Close(); return false; }
        const long size = std::ftell(m_File);
        if (size < 0) { Close(); return false; }
        m_Bytes = static_cast<size_t>(size);
        return true;
    }
    bool Write(const std::string& record) {
        if (!m_File || record.size() > m_Limit) return false;
        if (m_Bytes > m_Limit - record.size()) {
            Close();
            const std::string backup = m_Path + ".1";
            // rename may replace an existing file on POSIX, but not Windows.
            FILE* previous = std::fopen(backup.c_str(), "rb");
            if (previous) {
                std::fclose(previous);
                if (std::remove(backup.c_str())) return false;
            }
            if (std::rename(m_Path.c_str(), backup.c_str())) return false;
            m_File = std::fopen(m_Path.c_str(), "wb"); m_Bytes = 0;
            if (!m_File) return false;
        }
        if (std::fwrite(record.data(), 1, record.size(), m_File) != record.size() || std::fflush(m_File)) {
            Close(); return false;
        }
        m_Bytes += record.size();
        return true;
    }
};
}
