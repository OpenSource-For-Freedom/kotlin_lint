fun grade(letter: String, bonus: Boolean, late: Boolean, retake: Boolean, audit: Boolean): String {
    if (bonus && !late && !retake && !audit && letter.isNotEmpty()) {
        if (bonus) {
            if (!late) {
                if (!retake) {
                    if (!audit) {
                        return "deep"
                    }
                }
            }
        }
    }
    return when (letter) {
        "a" -> "A"
        "b" -> "B"
        "c" -> "C"
        "d" -> "D"
        "e" -> "E"
        "f" -> "F"
        "g" -> "G"
        "h" -> "H"
        "i" -> "I"
        "j" -> "J"
        else -> "?"
    }
}
