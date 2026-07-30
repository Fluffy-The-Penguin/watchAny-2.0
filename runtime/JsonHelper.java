package runtime;

import kotlinx.serialization.json.*;
import kotlin.Unit;

public class JsonHelper {
    public static final Json LENIENT_JSON = JsonKt.Json(Json.Default, builder -> {
        builder.setIgnoreUnknownKeys(true);
        builder.setLenient(true);
        builder.setCoerceInputValues(true);
        builder.setExplicitNulls(false);
        return Unit.INSTANCE;
    });
}
