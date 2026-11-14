Output "docs/assets/cli.gif"
Output "docs/assets/cli.mp4"

Require snapclip

Set Shell "bash"
Set FontSize 16
Set Width 960
Set Height 540
Set Framerate 25
Set Padding 20
Set Theme { "background": "#0a0c10", "foreground": "#adbac7" }

Hide
Type "export PS1='$ '" Enter
Type "clear" Enter
Sleep 400ms
Show

Type "snapclip version" Enter
Sleep 1.2s

Type "snapclip config show" Enter
Sleep 2.5s

Type "snapclip donate" Enter
Sleep 2.5s
