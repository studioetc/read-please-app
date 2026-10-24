# Third-party notices

These files adapt the pinned permissive sources below. Changes replace app-specific dependencies,
retain OCR confidence/geometry, support cancellation, use conservative speech reflow, and add native region capture.
No Easydict or other GPL implementation is included.

## TRex

Repository: https://github.com/amebalabs/TRex

- `Sources/ReadPlease/Core/ScreenAreaReading/TextRecognizer.swift` — adapted from [Packages/TRexCore/Sources/TRexCore/OCREngine.swift](https://github.com/amebalabs/TRex/blob/c4408b4012b80af00c2db234d88695b6138b4fc0/Packages/TRexCore/Sources/TRexCore/OCREngine.swift).
- `Sources/ReadPlease/Core/ScreenAreaReading/NativeScreenCaptureBackend.swift` — adapted from [TRexCore.captureScreenInteractively and unique-file arguments](https://github.com/amebalabs/TRex/blob/c4408b4012b80af00c2db234d88695b6138b4fc0/Packages/TRexCore/Sources/TRexCore/TRexCore.swift#L516). Changes add rectangle-only mode, private-directory cleanup, ImageIO decoding, explicit errors and permission checks.

MIT License

Copyright (c) 2021 Ameba Labs

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

## Shotnix

Repository: https://github.com/OMARVII/Shotnix

- `Sources/ReadPlease/Core/ScreenAreaReading/OCRLine.swift` — adapted from [Sources/ShotnixCore/OCR/OCREngine.swift](https://github.com/OMARVII/Shotnix/blob/1658678f545115e80038ded63742458f3ae8ffda/Sources/ShotnixCore/OCR/OCREngine.swift).
- `Sources/ReadPlease/Core/ScreenAreaReading/OCRLayout.swift` — adapted from [Sources/ShotnixCore/OCR/OCREngine.swift](https://github.com/OMARVII/Shotnix/blob/1658678f545115e80038ded63742458f3ae8ffda/Sources/ShotnixCore/OCR/OCREngine.swift).
- `Sources/ReadPlease/Core/ScreenAreaReading/TextRecognizer.swift` — adapted from [Sources/ShotnixCore/OCR/OCREngine.swift](https://github.com/OMARVII/Shotnix/blob/1658678f545115e80038ded63742458f3ae8ffda/Sources/ShotnixCore/OCR/OCREngine.swift).
- `Tests/ReadPleaseTests/OCRLayoutTests.swift` — adapted from [Tests/ShotnixCoreTests/OCRLayoutTests.swift](https://github.com/OMARVII/Shotnix/blob/1658678f545115e80038ded63742458f3ae8ffda/Tests/ShotnixCoreTests/OCRLayoutTests.swift).

MIT License

Copyright (c) 2025 Shotnix Contributors

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

## Snapzy

Repository: https://github.com/duongductrong/Snapzy

- `Sources/ReadPlease/Core/ScreenAreaReading/SpeechTextFormatter.swift` — adapted from [Snapzy/Services/Media/OCRService.swift](https://github.com/duongductrong/Snapzy/blob/8a84361477b34fecb9c2f38b27216e9de6aec239/Snapzy/Services/Media/OCRService.swift).

BSD 3-Clause License

Copyright (c) 2026, Trong Duong Duc

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Text Grab

Repository: https://github.com/TheJoeFin/Text-Grab

- `Sources/ReadPlease/Core/ScreenAreaReading/SpeechTextFormatter.swift` — adapted from [Text-Grab/Utilities/OcrUtilities.cs](https://github.com/TheJoeFin/Text-Grab/blob/a8d4c2b060ffa8efa102c22f80c31ee65c11ce82/Text-Grab/Utilities/OcrUtilities.cs).

MIT License

Copyright (c) 2020 Joseph Finney

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

## BetterShot (capture files only)

Repository: https://github.com/KartikLabhshetwar/better-shot

- `Sources/ReadPlease/Core/ScreenAreaReading/NativeScreenCaptureBackend.swift` — adapted from [ScreenCapture.interactiveShot / validateCommandResult](https://github.com/KartikLabhshetwar/better-shot/blob/7b7d00778fd972cf672242771d7a25870dd301b4/Sources/Capture/ScreenCapture.swift#L116).
- `Sources/ReadPlease/Core/ScreenAreaReading/ScreenCaptureProcessRunner.swift` — adapted from [ScreencaptureRunner](https://github.com/KartikLabhshetwar/better-shot/blob/7b7d00778fd972cf672242771d7a25870dd301b4/Sources/Capture/ScreencaptureRunner.swift). PNG IEND polling is retained for early image delivery; changes use file-backed stderr, serialize launch/cancellation, await actual exit for cleanup, and escalate SIGTERM to SIGKILL.

Only the BSD-3 capture implementation is adapted. No Cap 3D rendering or AGPL components are included.
Pinned [upstream licence and component boundary](https://github.com/KartikLabhshetwar/better-shot/blob/7b7d00778fd972cf672242771d7a25870dd301b4/LICENSE).

BSD 3-Clause License

Copyright (c) 2026, Kartik Labhshetwar

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
