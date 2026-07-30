package eu.kanade.tachiyomi.network;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Response;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.intrinsics.IntrinsicsKt;
import java.io.IOException;

/**
 * Replacement for Tachiyomi's OkHttpExtensionsKt.
 *
 * KEY INSIGHT for Kotlin coroutine Result boxing from Java:
 *   - kotlin.Result is an inline class. At JVM level:
 *     - Success<T>: continuation.resumeWith(T_value_boxed) — pass the value directly
 *     - Failure:    continuation.resumeWith(kotlin.ResultKt.createFailure(throwable))
 *   - Do NOT use kotlin.Result.Failure constructor — it's not public from Java.
 *   - Do NOT use kotlin.Result.success/failure static methods — they're internal.
 *   - Use kotlin.ResultKt.createFailure(Throwable) for the failure case.
 *   - Pass the value directly (not wrapped) for the success case.
 */
public class OkHttpExtensionsKt {

    public static rx.Observable<Response> asObservable(Call call) {
        return rx.Observable.create(new rx.Observable.OnSubscribe<Response>() {
            @Override
            public void call(rx.Subscriber<? super Response> subscriber) {
                call.enqueue(new Callback() {
                    @Override
                    public void onFailure(Call c, IOException e) {
                        if (!subscriber.isUnsubscribed()) subscriber.onError(e);
                    }
                    @Override
                    public void onResponse(Call c, Response response) throws IOException {
                        if (!subscriber.isUnsubscribed()) {
                            subscriber.onNext(response);
                            subscriber.onCompleted();
                        }
                    }
                });
            }
        });
    }

    public static rx.Observable<Response> asObservableSuccess(Call call) {
        return rx.Observable.create(new rx.Observable.OnSubscribe<Response>() {
            @Override
            public void call(rx.Subscriber<? super Response> subscriber) {
                call.enqueue(new Callback() {
                    @Override
                    public void onFailure(Call c, IOException e) {
                        if (!subscriber.isUnsubscribed()) subscriber.onError(e);
                    }
                    @Override
                    public void onResponse(Call c, Response response) throws IOException {
                        if (!subscriber.isUnsubscribed()) {
                            if (!response.isSuccessful()) {
                                response.close();
                                subscriber.onError(new IOException("HTTP error " + response.code()));
                            } else {
                                subscriber.onNext(response);
                                subscriber.onCompleted();
                            }
                        }
                    }
                });
            }
        });
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    public static Object awaitSuccess(Call call, Continuation continuation) {
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                // For failure: wrap in kotlin.ResultKt.createFailure
                continuation.resumeWith(kotlin.ResultKt.createFailure(e));
            }
            @Override
            public void onResponse(Call c, Response response) throws IOException {
                if (!response.isSuccessful()) {
                    IOException ex = new IOException("HTTP error " + response.code());
                    response.close();
                    continuation.resumeWith(kotlin.ResultKt.createFailure(ex));
                } else {
                    // For success: pass the value directly (Kotlin Result inline class success = value itself)
                    continuation.resumeWith(response);
                }
            }
        });
        return IntrinsicsKt.getCOROUTINE_SUSPENDED();
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    public static Object await(Call call, Continuation continuation) {
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                continuation.resumeWith(kotlin.ResultKt.createFailure(e));
            }
            @Override
            public void onResponse(Call c, Response response) throws IOException {
                continuation.resumeWith(response);
            }
        });
        return IntrinsicsKt.getCOROUTINE_SUSPENDED();
    }
}
