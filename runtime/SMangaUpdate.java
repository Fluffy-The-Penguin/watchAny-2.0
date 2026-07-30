package eu.kanade.tachiyomi.source.model;

import java.util.List;

public interface SMangaUpdate {
    String getTitle();
    void setTitle(String title);
    String getArtist();
    void setArtist(String artist);
    String getAuthor();
    void setAuthor(String author);
    String getDescription();
    void setDescription(String description);
    String getGenre();
    void setGenre(String genre);
    int getStatus();
    void setStatus(int status);
    String getThumbnail_url();
    void setThumbnail_url(String url);
    boolean getInitialized();
    void setInitialized(boolean initialized);
    Object getMemo();
    void setMemo(Object memo);

    SManga getManga();
    List getChapters();
}
