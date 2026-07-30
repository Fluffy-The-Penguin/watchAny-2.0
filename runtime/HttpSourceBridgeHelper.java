package eu.kanade.tachiyomi.source.online;

import eu.kanade.tachiyomi.source.model.FilterList;
import eu.kanade.tachiyomi.source.model.MangasPage;
import okhttp3.Request;
import okhttp3.Response;

public class HttpSourceBridgeHelper {

    public static Request popularMangaRequest(HttpSource source, int page) {
        return source.popularMangaRequest(page);
    }

    public static MangasPage popularMangaParse(HttpSource source, Response response) {
        return source.popularMangaParse(response);
    }

    public static Request searchMangaRequest(HttpSource source, int page, String query, FilterList filters) {
        return source.searchMangaRequest(page, query, filters);
    }

    public static MangasPage searchMangaParse(HttpSource source, Response response) {
        return source.searchMangaParse(response);
    }

    public static Request latestUpdatesRequest(HttpSource source, int page) {
        return source.latestUpdatesRequest(page);
    }

    public static MangasPage latestUpdatesParse(HttpSource source, Response response) {
        return source.latestUpdatesParse(response);
    }
}
