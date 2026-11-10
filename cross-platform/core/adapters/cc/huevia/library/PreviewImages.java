package cc.huevia.library;

import java.io.IOException;
import cc.huevia.shared.MediaValidation;

/** Apple/JVM source set only; Android continues to use its original bitmap validator. */
final class PreviewImages {
    private PreviewImages() {}
    static void validate(byte[] bytes)throws IOException { MediaValidation.validate(bytes); }
}
