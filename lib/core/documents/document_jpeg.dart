import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

typedef _EncodeC = Pointer<Uint8> Function(Pointer<Uint8>, Int32, Int32, Int32, Pointer<UintPtr>);
typedef _Encode = Pointer<Uint8> Function(Pointer<Uint8>, int, int, int, Pointer<UintPtr>);

/// Shared in-memory C ABI. Mobile/Windows use the same source with their own
/// packaged library; no subprocess, server upload, or temporary JPEG is needed.
final class DocumentJpeg {
  static final DynamicLibrary? _library = _load();
  static bool get usesNativeEncoder => _library != null;
  static DynamicLibrary? _load() {
    try {
      final override = Platform.environment['AUDYT_JPEG_LIBRARY'];
      final library = override != null ? DynamicLibrary.open(override)
          : Platform.isIOS ? DynamicLibrary.process()
          : Platform.isMacOS ? DynamicLibrary.open('${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libaudyt_jpeg.dylib')
          : DynamicLibrary.open(Platform.isWindows ? 'audyt_jpeg.dll' : 'libaudyt_jpeg.so');
      library.lookup<NativeFunction<_EncodeC>>('audyt_jpeg_encode');
      return library;
    } catch (_) { return null; }
  }
  static img.Image? decode(Uint8List bytes) {
    final library = _library;
    if (library == null) return img.decodeJpg(bytes);
    final alloc = library.lookupFunction<Pointer<Void> Function(UintPtr), Pointer<Void> Function(int)>('audyt_jpeg_alloc');
    final free = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('audyt_jpeg_free');
    final decode = library.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>, UintPtr, Pointer<Int32>, Pointer<Int32>, Pointer<UintPtr>), Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>, Pointer<UintPtr>)>('audyt_jpeg_decode');
    final input=alloc(bytes.length).cast<Uint8>(), width=alloc(4).cast<Int32>(), height=alloc(4).cast<Int32>(), size=alloc(sizeOf<UintPtr>()).cast<UintPtr>();
    Pointer<Uint8> output=nullptr;
    try {
      if(input==nullptr || width==nullptr || height==nullptr || size==nullptr) throw StateError('Insufficient memory for JPEG decoding.');
      input.asTypedList(bytes.length).setAll(0,bytes);
      output=decode(input,bytes.length,width,height,size);
      if(output==nullptr) return null;
      final pixels=Uint8List.fromList(output.asTypedList(size.value));
      return img.Image.fromBytes(width:width.value,height:height.value,bytes:pixels.buffer,numChannels:3);
    } finally {free(input.cast());free(width.cast());free(height.cast());free(size.cast());free(output.cast());}
  }

  static Uint8List encode(img.Image source, {required int quality}) {
    final library = _library;
    if (library == null) return img.encodeJpg(source, quality: quality, chroma: img.JpegChroma.yuv444);
    final alloc = library.lookupFunction<Pointer<Void> Function(UintPtr), Pointer<Void> Function(int)>('audyt_jpeg_alloc');
    final free = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('audyt_jpeg_free');
    final encode = library.lookupFunction<_EncodeC, _Encode>('audyt_jpeg_encode');
    final bytes = source.getBytes(order: img.ChannelOrder.rgb);
    final input = alloc(bytes.length).cast<Uint8>();
    final size = alloc(sizeOf<UintPtr>()).cast<UintPtr>();
    Pointer<Uint8> output = nullptr;
    try {
      if (input == nullptr || size == nullptr) throw StateError('Insufficient memory for JPEG encoding.');
      input.asTypedList(bytes.length).setAll(0, bytes);
      output = encode(input, source.width, source.height, quality, size);
      if (output == nullptr) throw StateError('JPEG encoding failed.');
      return Uint8List.fromList(output.asTypedList(size.value));
    } finally { free(input.cast()); free(size.cast()); free(output.cast()); }
  }
}
