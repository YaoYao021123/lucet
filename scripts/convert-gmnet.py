# Converts the GMNet real-world checkpoint (MIT, github.com/qtlark/GMNet) for Lucet's "AI HDR".
"""Reads a PyTorch zip checkpoint without torch and writes its tensors as one flat file.

Only tensor-rebuild records are accepted from the pickle; anything else is refused, so loading
cannot run code from the file.

Usage: python3 -I scripts/convert-gmnet.py G_realworld.pth assets/models/gmnet-realworld.bin
Output: "GMNT", uint32 version (1), uint32 header length, a JSON header
[{"name", "shape", "offset"}] (offset in floats), then little-endian float32 values."""
import collections, hashlib, json, pickle, struct, sys, zipfile

DTYPES = {"FloatStorage": "f"}

class Tensor:
    def __init__(self, key, offset, size, stride):
        self.key, self.offset, self.size, self.stride = key, offset, tuple(size), tuple(stride)

def rebuild_tensor_v2(storage, offset, size, stride, requires_grad=False, hooks=None, *rest):
    return Tensor(storage, offset, size, stride)

class Safe(pickle.Unpickler):
    def find_class(self, module, name):
        if (module, name) == ("torch._utils", "_rebuild_tensor_v2"): return rebuild_tensor_v2
        if (module, name) == ("collections", "OrderedDict"): return collections.OrderedDict
        if module == "torch" and name in DTYPES: return name
        raise pickle.UnpicklingError(f"refused: {module}.{name}")
    def persistent_load(self, pid):
        kind, dtype, key, location, count = pid[:5]
        assert kind == "storage" and dtype in DTYPES, pid
        return key

def load(path):
    with zipfile.ZipFile(path) as archive:
        prefix = archive.namelist()[0].split("/")[0]
        state = Safe(archive.open(f"{prefix}/data.pkl")).load()
        storages = {}
        out = collections.OrderedDict()
        for name, t in state.items():
            if t.key not in storages:
                raw = archive.read(f"{prefix}/data/{t.key}")
                storages[t.key] = struct.unpack("<%df" % (len(raw) // 4), raw)
            n = 1
            for s in t.size: n *= s
            expected, acc = [], 1
            for s in reversed(t.size): expected.insert(0, acc); acc *= s
            assert tuple(expected) == t.stride or n <= 1, (name, t.size, t.stride)
            out[name] = (t.size, storages[t.key][t.offset:t.offset + n])
        return out

def convert(source, target):
    tensors = load(source)
    header, offset = [], 0
    for name, (shape, values) in tensors.items():
        header.append({"name": name, "shape": list(shape), "offset": offset})
        offset += len(values)
    blob = json.dumps(header, separators=(",", ":")).encode()
    with open(target, "wb") as f:
        f.write(b"GMNT" + struct.pack("<II", 1, len(blob)) + blob)
        for _, (_, values) in tensors.items():
            f.write(struct.pack("<%df" % len(values), *values))
    for path in (source, target):
        with open(path, "rb") as f: print(path.split("/")[-1], hashlib.sha256(f.read()).hexdigest())
    print(len(tensors), "tensors,", offset, "values")

if __name__ == "__main__":
    convert(sys.argv[1], sys.argv[2])
