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
    if (src.size > 0 && src.data != nullptr) {
      data = new unsigned char[src.size];
      std::memcpy(data, src.data, src.size);
    }
  }

  _netpacket_s& operator=(const _netpacket_s& src)
  {
    if (this == &src) {
      return *this;
    }

    delete[] data;

    from = src.from;
    source = src.source;
    received = src.received;
    data = nullptr;
    message = src.message;
    size = src.size;
    wiresize = src.wiresize;
    stream = src.stream;
    pNext = nullptr;

    if (src.size > 0 && src.data != nullptr) {
      data = new unsigned char[src.size];
      std::memcpy(data, src.data, src.size);
    }

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
      pNext(other.pNext)
  {
    other.data = nullptr;
    other.pNext = nullptr;
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
    pNext = other.pNext;

    other.data = nullptr;
    other.pNext = nullptr;
    return *this;
  }

  ~_netpacket_s()
  {
    delete[] data;
  }
};

using _netpacket_t = _netpacket_s;

#endif // _CUSTOM_FAKELAG_NET_STRUCTURES_H_
