package android.app

import android.content.ContextWrapper

// Must extend ContextWrapper (not Context directly) to match real Android hierarchy:
// Application -> ContextWrapper -> Context
// The JVM verifier enforces this when extensions call Application methods.
open class Application : ContextWrapper(null)
