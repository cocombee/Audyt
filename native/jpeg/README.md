# Shared JPEG Engine

MozJPEG v4.1.1, from https://github.com/mozilla/mozjpeg/releases/tag/v4.1.1, is vendored in `mozjpeg` with its license files. The C wrapper exports an in-memory RGB-to-progressive-JPEG API. Dart FFI calls it inside the existing processing isolate. There are no document uploads or subprocess dependencies.

macOS arm64 is built and bundled today. iOS can statically link the same C sources and expose the symbols through DynamicLibrary.process; Android can package libaudyt_jpeg.so per ABI; Windows can package audyt_jpeg.dll. Those platform packaging steps are planned, not built or tested yet. CMake and upstream BUILDING.md cover their toolchains.

Rebuild with CMake (3.16 or later; add -DCMAKE_POLICY_VERSION_MINIMUM=3.5 with CMake 4):

    cmake -S native/jpeg -B build/native-jpeg -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    cmake --build build/native-jpeg --target audyt_jpeg --parallel

Copy the resulting macOS library into native/jpeg/prebuilt/macos before a release build. The Xcode embed script packages and signs it. Tests can set AUDYT_JPEG_LIBRARY to the absolute library path. Unsupported/unbundled environments retain the Dart encoder fallback.

Manual quality spans 30–100, default 65 for this encoder. Quick Optimize searches from lower to higher quality and stops at the first passing pixel/edge check (PSNR 36, mean edge error <=6, ink changes <=0.1%). These are engineering guards, not an OCR guarantee. The existing A4 bound remains separate from JPEG encoding; full-size benchmarks do not resize.

Benchmark: ReceiptSwiss 962613 bytes, 2448x3264 -> 490152 bytes at Q65, about 0.24 seconds, versus user-provided TinyPNG 546687 bytes. One additional OpenCV photographed Sudoku PNG (558x563) -> 18396-byte JPEG from 250720 bytes at Q55, 0.019 seconds including checks. Visual inspection retained numbers and grid. These samples are not a universal savings guarantee.

Quick Optimize must decode candidates through the same native JPEG library used for encoding. Dart decoding inflated measured error and incorrectly selected Q95/1145439 bytes on the receipt. The full corrected A4 pipeline selects Q80/430512 bytes with native comparison. This is distinct from the original-dimension Q65 benchmark. The optional receipt regression takes AUDYT_RECEIPT_SAMPLE and AUDYT_JPEG_LIBRARY environment variables.
