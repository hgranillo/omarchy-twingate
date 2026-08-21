import Quickshell.Io

// StdioCollector grows for as long as a command keeps writing, and every plugin
// shares one long-lived shell process. SplitParser hands each chunk to onRead
// instead of accumulating, which is what makes a ceiling possible here.
SplitParser {
  id: root

  // A runaway guard, not a size limit. One Twingate resource costs roughly 400
  // bytes of JSON, so this clears a network of about ten thousand.
  property int maxChars: 4 * 1024 * 1024
  property string text: ""
  property bool truncated: false

  // StdioCollector starts empty on each run; this has to be told.
  function reset() {
    text = ""
    truncated = false
  }

  splitMarker: ""
  onRead: function (chunk) {
    if (truncated) return
    var next = String(chunk)
    if (text.length + next.length > maxChars) {
      truncated = true
      text = ""
      return
    }
    text += next
  }
}
