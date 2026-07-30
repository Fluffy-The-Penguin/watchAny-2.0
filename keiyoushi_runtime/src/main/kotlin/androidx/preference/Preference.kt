package androidx.preference

open class Preference(val context: Any? = null) {
    var key: String? = null
    var title: CharSequence? = null
    var summary: CharSequence? = null
    var setDefaultValue: Any? = null
}

open class PreferenceGroup : Preference()

open class PreferenceScreen : PreferenceGroup()

open class ListPreference : Preference() {
    var entries: Array<CharSequence>? = null
    var entryValues: Array<CharSequence>? = null
}

open class SwitchPreferenceCompat : Preference()

open class EditTextPreference : Preference()
