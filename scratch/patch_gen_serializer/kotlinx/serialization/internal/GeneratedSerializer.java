package kotlinx.serialization.internal;

import kotlinx.serialization.KSerializer;

public interface GeneratedSerializer<T> extends KSerializer<T> {
    KSerializer<?>[] childSerializers();
    default KSerializer<?>[] typeParametersSerializers() {
        return new KSerializer<?>[0];
    }
}
