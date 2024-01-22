struct TextBuffer {
    private var content: String
    private var index = 0
    private var iterator: String.Iterator
    private var peekedCharacter: Character?
    /// The line number of the character most recently returned by ``TextBuffer/next``.
    private var line = 1
    /// The column number of the character most recently returned by ``TextBuffer/next``.
    /// Column numbering starts at 1, but the location starts at 0 before the first
    /// of the line character.
    private var column = 0

    /// The location of the character most recently returned by ``TextBuffer/next``.
    var location: Location {
        Location(line: line, column: column)
    }

    init(_ content: String) {
        self.content = content
        iterator = content.makeIterator()
    }

    @discardableResult
    mutating func next() -> Character? {
        let character: Character?
        if let peekedCharacter {
            index += 1
            character = peekedCharacter
            self.peekedCharacter = nil
        } else {
            character = iterator.next()
            if character != nil {
                index += 1
            }
        }

        if let character {
            if character == "\n" {
                line += 1
                column = 0
            } else {
                column += 1
            }
        }

        return character
    }

    mutating func peek() -> Character? {
        if let peekedCharacter {
            return peekedCharacter
        } else {
            let character = iterator.next()
            peekedCharacter = character
            if character != nil {
                index += 1
            }
            return character
        }
    }
}
