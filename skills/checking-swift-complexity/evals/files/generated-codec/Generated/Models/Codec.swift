enum Field { case id, name, email, age, tags }

func decodeValue(_ field: Field, from raw: [String: String]) -> String? {
    switch field {
    case .id: return raw["id"] ?? raw["ID"]
    case .name: return raw["name"].map { $0.isEmpty ? "unknown" : $0 }
    case .email: return raw["email"]?.contains("@") == true ? raw["email"] : nil
    case .age:
        guard let text = raw["age"], let age = Int(text), age >= 0 else { return nil }
        return String(age)
    case .tags: return raw["tags"] ?? ""
    }
}
