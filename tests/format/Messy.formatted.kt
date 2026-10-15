import android.os.Bundle
import java.io.File

class user_settings {
    fun save(name: String, value: Int): Boolean {
        val path = File("settings/" + name)
        return path.exists() && value > 0
    }

    fun load(name: String) = File(name).readText()
}
