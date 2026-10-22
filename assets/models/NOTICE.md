# adaptive-lut.bin

The weights behind **AI Look** (AI 调色): Image-Adaptive-3DLUT by Hui Zeng, Jianrui Cai, Lida Li,
Zisheng Cao and Lei Zhang, "Learning Image-adaptive 3D Lookup Tables for High Performance Photo
Enhancement in Real-time", IEEE TPAMI 2020.

- Source: https://github.com/HuiZeng/Image-Adaptive-3DLUT, `pretrained_models/sRGB/` (trained on the
  MIT-Adobe FiveK sRGB set)
- License: Apache License 2.0; the full text, copied from the repository's `LICENSE`, is in
  `Image-Adaptive-3DLUT-LICENSE.txt` (the repository has no NOTICE file)
- Original files (SHA-256):
  - `classifier.pth` bae9865395625ecae58cfe86147e521093bb1e29e7b2544e02adb238b8035021
  - `LUTs.pth` c1bb2bc4b7239c1a7e96159f5923123ba796b1fceb0b8c3132b423ea825b821a
- Converted, values unchanged, by `scripts/convert-adaptive-lut.py` (no PyTorch needed):
  `adaptive-lut.bin` 1f1e76766ccf1e9f43f443e9b930e79bb6b6fe55cc6c85a712ee1a2e481917c4

Layout: `A3DL`, version 1, 23 tensors (each a uint32 count and float32 values, little-endian): the
classifier's five 3 × 3 convolutions with their instance norms, the final 8 × 8 convolution, then
the three 33³ basis LUTs as [channel][blue][green][red]. The network runs in
`Sources/MediaCore/AdaptiveLUT.swift`; a test checks it against an independent forward pass.

# gmnet-realworld.bin

The weights behind **AI HDR** (AI HDR 光感): GMNet by Yinuo Liao et al., "Learning Gain Map for
Inverse Tone Mapping", ICLR 2025. A global branch reads the photo at 256 × 256 and a local branch
predicts its gain map (how many stops brighter each spot may be on an HDR screen, 0 to log2 5).

- Source: https://github.com/qtlark/GMNet, `checkpoints/G_realworld.pth` (the real-world model)
- License: MIT (below)
- Original file (SHA-256):
  - `G_realworld.pth` 83bf27bcdbf6eacfdef37f0e24ed6d79152b7386620c012ae509a59a895c875f
- Converted, values unchanged, by `scripts/convert-gmnet.py` (no PyTorch needed):
  `gmnet-realworld.bin` 89d47736514203e439389744ae494a5c98addd64c58902cdcb685f27891e10cd

Layout: `GMNT`, version 1, a uint32 header length, a JSON header `[{"name", "shape", "offset"}]`
(offset in floats), then little-endian float32 values, one tensor per convolution weight and bias
under its PyTorch name. The network runs in `Sources/MediaCore/AutoHDR.swift`; a test checks it
against an independent forward pass.

MIT License

Copyright (c) 2025 Yinuo Liao

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
