"""A deterministic, non-user PNG for the disposable PhotoKit simulator library."""
from pathlib import Path
import hashlib,struct,sys,zlib
target=Path(sys.argv[1]);target.parent.mkdir(parents=True,exist_ok=True)
def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
raw=b''.join(b'\0'+bytes(value for x in range(256) for value in (x,y,(x+y)//2,255)) for y in range(192))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',256,192,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,6))+chunk(b'IEND',b'')
target.write_bytes(png);print(hashlib.sha256(png).hexdigest())
