package scratch;
import runtime.ExtensionRuntime;
import java.io.File;
import java.util.List;

public class TestSourceId {
    public static void main(String[] args) {
        File root = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi");
        ExtensionRuntime runtime = new ExtensionRuntime(root.toPath());
        List<?> sources = runtime.loadInstalledSources(null);
        System.out.println("Loaded sources count: " + sources.size());
        for (Object s : sources) {
            try {
                long id = (long) s.getClass().getMethod("getId").invoke(s);
                String name = (String) s.getClass().getMethod("getName").invoke(s);
                System.out.println("Source: " + name + " -> ID (long): " + id + " | String: " + String.valueOf(id));
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
}
