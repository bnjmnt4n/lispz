pub fn isWhitespace(char: u8) bool {
    return switch (char) {
        ' ', '\t', '\n' => true,
        else => false,
    };
}

pub fn isDigit(char: u8) bool {
    return switch (char) {
        '0'...'9' => true,
        else => false,
    };
}

pub fn isAlphabet(char: u8) bool {
    return switch (char) {
        'a'...'z', 'A'...'Z' => true,
        else => false,
    };
}

pub fn isSymbolStartCharacter(char: u8) bool {
    return switch (char) {
        '*', '/', '>', '<', '=', '?', '!', '-', '+' => true,
        else => isAlphabet(char),
    };
}

pub fn isDelimiter(char: u8) bool {
    return switch (char) {
        '"', '(', ')', '{', '}', ';' => true,
        else => isWhitespace(char),
    };
}
