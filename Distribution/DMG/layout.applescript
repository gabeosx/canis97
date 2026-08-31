tell application "Finder"
    tell disk "Canis97"
        open
        delay 1

        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {100, 100, 820, 560}

        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:background.png"

        set position of item "Canis97.app" of container window to {170, 300}
        set position of item "Applications" of container window to {550, 300}

        update without registering applications
        delay 2
        close
        delay 1
    end tell
end tell
