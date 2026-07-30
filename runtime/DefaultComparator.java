package runtime;

import java.util.Comparator;

public class DefaultComparator implements Comparator<Object> {
    public static final DefaultComparator INSTANCE = new DefaultComparator();

    @Override
    public int compare(Object a, Object b) {
        return 0;
    }
}
