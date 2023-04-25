module swap::type_helper {
    use std::type_name;
    use std::string::{Self, String};

    /// Returns type name as std::string::String
    public fun get_type_name<T>(): String {
        string::from_ascii(type_name::into_string(type_name::get<T>()))
    }
}