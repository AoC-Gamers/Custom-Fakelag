#ifndef _CUSTOM_FAKELAG_NET_STRUCTURES_H_
#define _CUSTOM_FAKELAG_NET_STRUCTURES_H_

#include <cstring>
#include <netadr.h>

struct dumb_netadr_s {
  netadrtype_t type;
  unsigned char ip[4];
  unsigned short port;
};

using dumb_netadr_t = dumb_netadr_s;


struct fake_bf_read {
  const unsigned char* m_pData;
  int m_nDataBytes;
  int m_nDataBits;
  int m_iCurBit;
  bool m_bOverflow;
  bool m_bAssertOnOverflow;
  const char* m_pDebugName;

  // These fields match the layout we need from the engine bit reader on L4D2.
  int m_BitRead0;
  int m_BitRead1;
  int m_BitRead2;
};

struct _netpacket_s
{
  dumb_netadr_t from;
  int source;
  double received;
  unsigned char* data;
  fake_bf_read message;
  int size;
  int wiresize;
  bool stream;
  _netpacket_s* pNext;

  _netpacket_s()
    : from{},
      source(0),
      received(0.0),
      data(nullptr),
      message{},
      size(0),
      wiresize(0),
      stream(false),
      pNext(nullptr)
  {
  }

  void ResetRuntimeLinks()
  {
    pNext = nullptr;
  }

  void SyncMessageBuffer()
  {
    message.m_pData = data;
  }

  void CopyPayloadFrom(const _netpacket_s& src)
  {
    delete[] data;
    data = nullptr;

    if (src.size > 0 && src.data != nullptr) {
      data = new unsigned char[src.size];
      std::memcpy(data, src.data, src.size);
    }

    SyncMessageBuffer();
  }

  void CopyMetadataFrom(const _netpacket_s& src)
  {
    from = src.from;
    source = src.source;
    received = src.received;
    message = src.message;
    size = src.size;
    wiresize = src.wiresize;
    stream = src.stream;
    ResetRuntimeLinks();
  }

  void CopyFrom(const _netpacket_s& src)
  {
    CopyMetadataFrom(src);
    CopyPayloadFrom(src);
  }

  bool CopyToLivePacket(_netpacket_s* dest) const
  {
    if (dest == nullptr) {
      return false;
    }

    unsigned char* liveData = dest->data;
    const int liveCapacity = dest->message.m_nDataBytes > 0 ? dest->message.m_nDataBytes : dest->size;

    if (size > 0) {
      if (data == nullptr || liveData == nullptr || liveCapacity < size) {
        return false;
      }
    }

    dest->CopyMetadataFrom(*this);
    dest->data = liveData;
    dest->message.m_pData = liveData;
    dest->message.m_nDataBytes = liveCapacity;

    if (size > 0) {
      std::memcpy(dest->data, data, size);
    }

    return true;
  }

  _netpacket_s(const _netpacket_s& src)
    :
    from(src.from),
    source(src.source),
    received(src.received),
    data(nullptr),
    message(src.message),
    size(src.size),
    wiresize(src.wiresize),
    stream(src.stream),
    pNext(nullptr)
  {
    CopyPayloadFrom(src);
  }

  _netpacket_s& operator=(const _netpacket_s& src)
  {
    if (this == &src) {
      return *this;
    }

    delete[] data;

    CopyFrom(src);

    return *this;
  }

  _netpacket_s(_netpacket_s&& other) noexcept
    : from(other.from),
      source(other.source),
      received(other.received),
      data(other.data),
      message(other.message),
      size(other.size),
      wiresize(other.wiresize),
      stream(other.stream),
      pNext(nullptr)
  {
    other.data = nullptr;
    other.ResetRuntimeLinks();
    SyncMessageBuffer();
  }

  _netpacket_s& operator=(_netpacket_s&& other) noexcept
  {
    if (this == &other) {
      return *this;
    }

    delete[] data;

    from = other.from;
    source = other.source;
    received = other.received;
    data = other.data;
    message = other.message;
    size = other.size;
    wiresize = other.wiresize;
    stream = other.stream;
    ResetRuntimeLinks();

    other.data = nullptr;
    other.ResetRuntimeLinks();
    SyncMessageBuffer();
    return *this;
  }

  ~_netpacket_s()
  {
    delete[] data;
  }
};

using _netpacket_t = _netpacket_s;

#endif // _CUSTOM_FAKELAG_NET_STRUCTURES_H_
