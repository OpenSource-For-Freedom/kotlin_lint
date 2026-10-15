// Deliberately bad code: the self-test expects every engine to report problems here.
// If this file ever lints clean, the linter is not actually running.
package violations

import java.util.*
import java.io.File

class violations {
  fun compute(x:Int):Int{
    val unused = 42
    return x*1337
  }

  fun empty() {
  }
}
