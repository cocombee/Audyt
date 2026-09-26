final class DocumentFileValidator {
  const DocumentFileValidator({required this.maxBytes});

  final int maxBytes;

  static const Map<String, String> allowedMimeTypes = {
    'heif': 'image/heif',
    'png': 'image/png',
    'jpeg': 'image/jpeg',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  List<String> validate({required String filename, required int byteSize}) {
    final errors = <String>[];
    final trimmedFilename = filename.trim();
    if (trimmedFilename.isEmpty ||
        trimmedFilename == '.' ||
        trimmedFilename == '..' ||
        trimmedFilename.contains('/') ||
        trimmedFilename.contains('\\')) {
      errors.add('The document filename is invalid.');
    }
    if (byteSize <= 0) {
      errors.add('The document must not be empty.');
    }
    if (byteSize > maxBytes) {
      errors.add('The document is larger than the allowed limit.');
    }

    final extension = _extensionOf(trimmedFilename);
    if (extension == null || !allowedMimeTypes.containsKey(extension)) {
      errors.add('This document format is not supported.');
    }
    return List.unmodifiable(errors);
  }

  static String? _extensionOf(String filename) {
    final separator = filename.lastIndexOf('.');
    if (separator <= 0 || separator == filename.length - 1) {
      return null;
    }
    return filename.substring(separator + 1).toLowerCase();
  }
}
