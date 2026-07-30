package runtime;

import eu.kanade.tachiyomi.source.CatalogueSource;
import eu.kanade.tachiyomi.source.online.HttpSource;
import eu.kanade.tachiyomi.source.online.HttpSourceBridgeHelper;
import eu.kanade.tachiyomi.source.model.MangasPage;
import eu.kanade.tachiyomi.source.model.FilterList;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.CoroutineContext;
import kotlin.coroutines.EmptyCoroutineContext;
import okhttp3.Request;
import okhttp3.Response;
import rx.Observable;
import rx.Subscriber;

public class HttpSourceBridge {

    public static Observable<MangasPage> fetchPopularManga(CatalogueSource source, int page) {
        return Observable.create(new Observable.OnSubscribe<MangasPage>() {
            @Override
            public void call(Subscriber<? super MangasPage> subscriber) {
                try {
                    if (source instanceof HttpSource) {
                        HttpSource httpSource = (HttpSource) source;
                        try {
                            Request request = HttpSourceBridgeHelper.popularMangaRequest(httpSource, page);
                            if (request != null) {
                                try (Response response = httpSource.getClient().newCall(request).execute()) {
                                    MangasPage result = HttpSourceBridgeHelper.popularMangaParse(httpSource, response);
                                    if (result != null && !subscriber.isUnsubscribed()) {
                                        subscriber.onNext(result);
                                        subscriber.onCompleted();
                                        return;
                                    }
                                }
                            }
                        } catch (UnsupportedOperationException uoe) {
                            // Extension uses suspend getPopularManga instead of popularMangaRequest
                        }
                    }

                    Object res = source.getPopularManga(page, new Continuation<MangasPage>() {
                        @Override
                        public CoroutineContext getContext() {
                            return EmptyCoroutineContext.INSTANCE;
                        }
                        @Override
                        public void resumeWith(Object result) {
                            if (!subscriber.isUnsubscribed()) {
                                if (result instanceof kotlin.Result.Failure) {
                                    subscriber.onError(((kotlin.Result.Failure) result).exception);
                                } else {
                                    subscriber.onNext((MangasPage) result);
                                    subscriber.onCompleted();
                                }
                            }
                        }
                    });
                    if (res instanceof MangasPage && !subscriber.isUnsubscribed()) {
                        subscriber.onNext((MangasPage) res);
                        subscriber.onCompleted();
                    }
                } catch (Throwable t) {
                    if (!subscriber.isUnsubscribed()) {
                        subscriber.onError(t);
                    }
                }
            }
        });
    }

    public static Observable<MangasPage> fetchPopularManga(HttpSource source, int page) {
        return fetchPopularManga((CatalogueSource) source, page);
    }

    public static Observable<MangasPage> fetchSearchManga(CatalogueSource source, int page, String query, FilterList filters) {
        return Observable.create(new Observable.OnSubscribe<MangasPage>() {
            @Override
            public void call(Subscriber<? super MangasPage> subscriber) {
                try {
                    if (source instanceof HttpSource) {
                        HttpSource httpSource = (HttpSource) source;
                        try {
                            Request request = HttpSourceBridgeHelper.searchMangaRequest(httpSource, page, query, filters);
                            if (request != null) {
                                try (Response response = httpSource.getClient().newCall(request).execute()) {
                                    MangasPage result = HttpSourceBridgeHelper.searchMangaParse(httpSource, response);
                                    if (result != null && !subscriber.isUnsubscribed()) {
                                        subscriber.onNext(result);
                                        subscriber.onCompleted();
                                        return;
                                    }
                                }
                            }
                        } catch (UnsupportedOperationException uoe) {
                            // Extension uses suspend getSearchManga
                        }
                    }

                    Object res = source.getSearchManga(page, query, filters, new Continuation<MangasPage>() {
                        @Override
                        public CoroutineContext getContext() {
                            return EmptyCoroutineContext.INSTANCE;
                        }
                        @Override
                        public void resumeWith(Object result) {
                            if (!subscriber.isUnsubscribed()) {
                                if (result instanceof kotlin.Result.Failure) {
                                    subscriber.onError(((kotlin.Result.Failure) result).exception);
                                } else {
                                    subscriber.onNext((MangasPage) result);
                                    subscriber.onCompleted();
                                }
                            }
                        }
                    });
                    if (res instanceof MangasPage && !subscriber.isUnsubscribed()) {
                        subscriber.onNext((MangasPage) res);
                        subscriber.onCompleted();
                    }
                } catch (Throwable t) {
                    if (!subscriber.isUnsubscribed()) {
                        subscriber.onError(t);
                    }
                }
            }
        });
    }

    public static Observable<MangasPage> fetchSearchManga(HttpSource source, int page, String query, FilterList filters) {
        return fetchSearchManga((CatalogueSource) source, page, query, filters);
    }

    public static Observable<MangasPage> fetchLatestUpdates(CatalogueSource source, int page) {
        return Observable.create(new Observable.OnSubscribe<MangasPage>() {
            @Override
            public void call(Subscriber<? super MangasPage> subscriber) {
                try {
                    if (source instanceof HttpSource) {
                        HttpSource httpSource = (HttpSource) source;
                        try {
                            Request request = HttpSourceBridgeHelper.latestUpdatesRequest(httpSource, page);
                            if (request != null) {
                                try (Response response = httpSource.getClient().newCall(request).execute()) {
                                    MangasPage result = HttpSourceBridgeHelper.latestUpdatesParse(httpSource, response);
                                    if (result != null && !subscriber.isUnsubscribed()) {
                                        subscriber.onNext(result);
                                        subscriber.onCompleted();
                                        return;
                                    }
                                }
                            }
                        } catch (UnsupportedOperationException uoe) {
                            // Extension uses suspend getLatestUpdates
                        }
                    }

                    Object res = source.getLatestUpdates(page, new Continuation<MangasPage>() {
                        @Override
                        public CoroutineContext getContext() {
                            return EmptyCoroutineContext.INSTANCE;
                        }
                        @Override
                        public void resumeWith(Object result) {
                            if (!subscriber.isUnsubscribed()) {
                                if (result instanceof kotlin.Result.Failure) {
                                    subscriber.onError(((kotlin.Result.Failure) result).exception);
                                } else {
                                    subscriber.onNext((MangasPage) result);
                                    subscriber.onCompleted();
                                }
                            }
                        }
                    });
                    if (res instanceof MangasPage && !subscriber.isUnsubscribed()) {
                        subscriber.onNext((MangasPage) res);
                        subscriber.onCompleted();
                    }
                } catch (Throwable t) {
                    if (!subscriber.isUnsubscribed()) {
                        subscriber.onError(t);
                    }
                }
            }
        });
    }

    public static Observable<MangasPage> fetchLatestUpdates(HttpSource source, int page) {
        return fetchLatestUpdates((CatalogueSource) source, page);
    }
}

