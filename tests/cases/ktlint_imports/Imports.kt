import java.io.File
import java.io.*
import android.os.Bundle

fun readName(): String = File("name.txt").readText()
