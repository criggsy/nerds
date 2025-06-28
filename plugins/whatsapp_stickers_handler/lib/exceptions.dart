class WhatsappStickersException implements Exception {
  final String? cause;

  WhatsappStickersException(this.cause);
}

class WhatsappStickersFileNotFoundException extends WhatsappStickersException {
  static const String code = 'FILE_NOT_FOUND';

  WhatsappStickersFileNotFoundException(String? cause) : super(cause);
}

class WhatsappStickersNumOutsideAllowableRangeException
    extends WhatsappStickersException {
  static const String code = 'OUTSIDE_ALLOWABLE_RANGE';

  WhatsappStickersNumOutsideAllowableRangeException(String? cause)
      : super(cause);
}

class WhatsappStickersUnsupportedImageFormatException
    extends WhatsappStickersException {
  static const String code = 'UNSUPPORTED_IMAGE_FORMAT';

  WhatsappStickersUnsupportedImageFormatException(String? cause) : super(cause);
}

class WhatsappStickersImageTooBigException extends WhatsappStickersException {
  static const String code = 'IMAGE_TOO_BIG';

  WhatsappStickersImageTooBigException(String? cause) : super(cause);
}

class WhatsappStickersIncorrectImageSizeException
    extends WhatsappStickersException {
  static const String code = 'INCORRECT_IMAGE_SIZE';

  WhatsappStickersIncorrectImageSizeException(String? cause) : super(cause);
}

class WhatsappStickersAnimatedImagesNotSupportedException
    extends WhatsappStickersException {
  static const String code = 'ANIMATED_IMAGES_NOT_SUPPORTED';

  WhatsappStickersAnimatedImagesNotSupportedException(String? cause)
      : super(cause);
}

class WhatsappStickersTooManyEmojisException extends WhatsappStickersException {
  static const String code = 'TOO_MANY_EMOJIS';

  WhatsappStickersTooManyEmojisException(String? cause) : super(cause);
}

class WhatsappStickersEmptyStringException extends WhatsappStickersException {
  static const String code = 'EMPTY_STRING';

  WhatsappStickersEmptyStringException(String? cause) : super(cause);
}

class WhatsappStickersStringTooLongException extends WhatsappStickersException {
  static const String code = 'STRING_TOO_LONG';

  WhatsappStickersStringTooLongException(String? cause) : super(cause);
}
