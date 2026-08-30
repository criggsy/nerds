class WhatsappStickersException implements Exception {
  final String? cause;

  WhatsappStickersException(this.cause);
}

class WhatsappStickersFileNotFoundException extends WhatsappStickersException {
  static const String code = 'FILE_NOT_FOUND';

  WhatsappStickersFileNotFoundException(super.cause);
}

class WhatsappStickersNumOutsideAllowableRangeException
    extends WhatsappStickersException {
  static const String code = 'OUTSIDE_ALLOWABLE_RANGE';

  WhatsappStickersNumOutsideAllowableRangeException(super.cause);
}

class WhatsappStickersUnsupportedImageFormatException
    extends WhatsappStickersException {
  static const String code = 'UNSUPPORTED_IMAGE_FORMAT';

  WhatsappStickersUnsupportedImageFormatException(super.cause);
}

class WhatsappStickersImageTooBigException extends WhatsappStickersException {
  static const String code = 'IMAGE_TOO_BIG';

  WhatsappStickersImageTooBigException(super.cause);
}

class WhatsappStickersIncorrectImageSizeException
    extends WhatsappStickersException {
  static const String code = 'INCORRECT_IMAGE_SIZE';

  WhatsappStickersIncorrectImageSizeException(super.cause);
}

class WhatsappStickersAnimatedImagesNotSupportedException
    extends WhatsappStickersException {
  static const String code = 'ANIMATED_IMAGES_NOT_SUPPORTED';

  WhatsappStickersAnimatedImagesNotSupportedException(super.cause);
}

class WhatsappStickersTooManyEmojisException extends WhatsappStickersException {
  static const String code = 'TOO_MANY_EMOJIS';

  WhatsappStickersTooManyEmojisException(super.cause);
}

class WhatsappStickersEmptyStringException extends WhatsappStickersException {
  static const String code = 'EMPTY_STRING';

  WhatsappStickersEmptyStringException(super.cause);
}

class WhatsappStickersStringTooLongException extends WhatsappStickersException {
  static const String code = 'STRING_TOO_LONG';

  WhatsappStickersStringTooLongException(super.cause);
}
