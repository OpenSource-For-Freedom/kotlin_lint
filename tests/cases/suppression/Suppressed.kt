// Suppressions must be honoured by every engine; the unsuppressed controls must still be flagged.

@Suppress("MagicNumber")
fun suppressedDetekt(x: Int): Int = x * 4242

@Suppress("ktlint:standard:function-naming", "FunctionNaming")
fun SuppressedNaming(x: Int): Int = x

fun unsuppressedMagic(x: Int): Int = x * 4242

fun UnsuppressedNaming(x: Int): Int = x
