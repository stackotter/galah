struct TextBuffer {
    private var content: String
    private var index = 0
    private var iterator: String.Iterator
    private var peekedCharacter: Character?
    /// The line number of the character most recently returned by ``TextBuffer/next``.
    private var line = 1
    /// The column number of the character most recently returned by ``TextBuffer/next``.
    /// Column numbering starts at 1, but the location starts at 0 before the first
    /// character of the first line.
    private var column = 0
    /// Whether the latest character returned by ``TextBuffer/next`` was a newline or not.
    private var previousWasNewLine = false

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
            if previousWasNewLine {
                line += 1
                column = 1
                previousWasNewLine = false
            } else {
                column += 1
            }
            previousWasNewLine = character.isNewline
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
