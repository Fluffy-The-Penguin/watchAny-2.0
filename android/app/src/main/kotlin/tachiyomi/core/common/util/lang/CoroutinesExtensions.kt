package tachiyomi.core.common.util.lang

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

suspend fun <T> withIOContext(block: suspend () -> T): T = withContext(Dispatchers.IO) { block() }
