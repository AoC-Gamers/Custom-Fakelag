#pragma once

#include <netadr.h>
#ifndef UNIT_TEST
#include <inetchannel.h>
#endif
#include <cstring>
#include <cstdint>
#include <memory>
#include <type_traits>

struct dumb_netadr_t {
    netadrtype_t type;
    unsigned char ip[4];
    unsigned short port;
};
inline dumb_netadr_t AddressKey(const netadr_t& address)
{
    dumb_netadr_t key{};
    key.type = address.type;
    std::memcpy(key.ip, address.ip, sizeof(key.ip));
    key.port = address.port;
    return key;
}
// SDK declaration is a candidate ABI, not evidence that an engine uses it.
#ifndef UNIT_TEST
using _netpacket_t = netpacket_t;
#else
// Isolated harness transport, deliberately not an engine ABI declaration.
struct _netpacket_t {
    dumb_netadr_t from{};
    int source = 0;
    double received = 0;
    unsigned char* data = nullptr;
    int size = 0;
    int wiresize = 0;
    bool stream = false;
    int readerBytes = 0, readerBits = 0, readerCursor = 0;
    const unsigned char* readerPointer = nullptr;
};
inline dumb_netadr_t AddressKey(const dumb_netadr_t& address) { return address; }
#endif

struct SessionId {
    uint64_t value = 0;
    explicit SessionId(uint64_t id = 0) : value(id) {}
    bool operator==(SessionId other) const { return value == other.value; }
};
struct Milliseconds { float value; explicit Milliseconds(float v) : value(v) {} };
struct EngineTime { double value; explicit EngineTime(double v = 0) : value(v) {} };

struct ReaderPosition {
    int bytes = 0;
    int bits = 0;
    int cursor = 0;
};
// A view never frees an engine allocation; no reader object/pointers are copied.
struct EnginePacketView {
    dumb_netadr_t from{};
    int source = 0;
    EngineTime received;
    const unsigned char* data = nullptr;
    int size = 0;
    int wiresize = 0;
    bool stream = false;
    ReaderPosition reader;
};
struct QueuedPacket {
    EnginePacketView metadata;
    std::unique_ptr<unsigned char[]> payload;
    SessionId session;
    EngineTime releaseAt;
    uint64_t sequence = 0;
    QueuedPacket() = default;
    QueuedPacket(const QueuedPacket&) = delete;
    QueuedPacket& operator=(const QueuedPacket&) = delete;
    QueuedPacket(QueuedPacket&&) noexcept = default;
    QueuedPacket& operator=(QueuedPacket&&) noexcept = default;
};
static_assert(!std::is_copy_constructible<QueuedPacket>::value, "queued payload is move-only");
static_assert(std::is_nothrow_move_constructible<QueuedPacket>::value, "heap operations must move payloads");

// A platform adapter must establish the ABI, capture scalar reader position,
// obtain destination allocation capacity independently of the reader, and
// rebuild ALL reader pointers using the verified engine contract. Never memcpy bf_read.
class EnginePacketAdapter {
public:
    virtual ~EnginePacketAdapter() = default;
    virtual bool IsRuntimeValidated() const { return false; }
    virtual bool Capture(const _netpacket_t&, EnginePacketView&) const { return false; }
    virtual size_t DestinationCapacity(const _netpacket_t&, bool /*newdata*/) const { return 0; }
    // Must be transactional: false leaves destination and payload untouched.
    virtual bool Restore(const QueuedPacket&, _netpacket_t&, size_t /*capacity*/) const { return false; }
};
