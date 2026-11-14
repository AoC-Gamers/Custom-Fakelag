"""Read PE and MSF/PDB metadata; require x86 DLL and matching RSDS GUID/age."""
import argparse, hashlib, json, struct, uuid
from pathlib import Path
import pefile

def verify(dll, pdb):
    pe=pefile.PE(str(dll))
    assert pe.FILE_HEADER.Machine==0x14c and pe.OPTIONAL_HEADER.Magic==0x10b
    rsds=[]
    for entry in pe.DIRECTORY_ENTRY_DEBUG:
        b=pe.__data__[entry.struct.PointerToRawData:entry.struct.PointerToRawData+entry.struct.SizeOfData]
        if b[:4]==b'RSDS': rsds.append((b[4:20],struct.unpack_from('<I',b,20)[0]))
    assert len(rsds)==1
    data=pdb.read_bytes()
    assert data[:32]==b'Microsoft C/C++ MSF 7.00\r\n\x1aDS\0\0\0'
    block,_,_,directory_size,_,blockmap=struct.unpack_from('<6I',data,32)
    count=(directory_size+block-1)//block
    blocks=struct.unpack_from('<'+'I'*count,data,blockmap*block)
    directory=b''.join(data[x*block:(x+1)*block] for x in blocks)[:directory_size]
    n=struct.unpack_from('<I',directory)[0]
    sizes=struct.unpack_from('<'+'I'*n,directory,4); offset=4+4*n; streams=[]
    for size in sizes:
        count=0 if size==0xffffffff else (size+block-1)//block
        blocks=struct.unpack_from('<'+'I'*count,directory,offset);offset+=4*count
        streams.append(b''.join(data[x*block:(x+1)*block] for x in blocks)[:size])
    _,_,age=struct.unpack_from('<3I',streams[1]); guid=streams[1][12:28]
    assert (guid,age)==rsds[0], 'PDB mismatch'
    return {'machine':'I386','pe':'PE32','pdb_match':True,'pdb_guid':str(uuid.UUID(bytes_le=guid)),
        'pdb_age':age,'dll_sha256':hashlib.sha256(dll.read_bytes()).hexdigest(),
        'pdb_sha256':hashlib.sha256(data).hexdigest(),
        'imports':[x.dll.decode('ascii') for x in pe.DIRECTORY_ENTRY_IMPORT]}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('dll',type=Path);p.add_argument('pdb',type=Path)
    a=p.parse_args();print(json.dumps(verify(a.dll,a.pdb),indent=2))
