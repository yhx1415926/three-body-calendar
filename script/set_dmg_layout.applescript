on run argv
    set mountPath to item 1 of argv
    set appName to item 2 of argv
    set diskAlias to POSIX file mountPath as alias
    tell application "Finder"
        activate
        open diskAlias
        set diskWindow to container window of disk diskAlias
        set current view of diskWindow to icon view
        set toolbar visible of diskWindow to false
        set statusbar visible of diskWindow to false
        set bounds of diskWindow to {120, 120, 840, 610}
        set layoutOptions to icon view options of diskWindow
        set arrangement of layoutOptions to not arranged
        set icon size of layoutOptions to 96
        set text size of layoutOptions to 12
        set background picture of layoutOptions to file ".background:background.png" of disk diskAlias
        set position of item (appName & ".app") of disk diskAlias to {178, 225}
        set position of item "Applications" of disk diskAlias to {542, 225}
        update disk diskAlias without registering applications
        delay 1
        close diskWindow
    end tell
end run
