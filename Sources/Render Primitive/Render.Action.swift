extension Render {

    public enum Action: Sendable {
        case push(Push)
        case pop(Pop)
        case `break`(Break)
        case text(String)
        case image(source: String, alt: String)
        case attribute(set: String, value: String?)
        case `class`(add: String)
        case raw([UInt8])
        case style(register: String, atRule: String?, selector: String?, pseudo: String?)
    }
}
