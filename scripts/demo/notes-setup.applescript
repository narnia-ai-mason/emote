-- Creates an empty note in Apple Notes, opens it in its own window, places it,
-- zooms the text in, and turns off check-spelling-while-typing.
-- Arguments: x y width height [zoomSteps]   (points, top-left origin; zoomSteps defaults to 6)
-- Prints: noteID|x|y|width|height|spell
--   spell is 1 when spelling-while-typing was on and has been turned off
--   (notes-teardown.applescript turns it back on).

on clickMenu(barNames, itemNames)
  tell application "System Events"
    tell process "Notes"
      repeat with barName in barNames
        repeat with itemName in itemNames
          try
            click menu item itemName of menu 1 of menu bar item barName of menu bar 1
            return true
          end try
        end repeat
      end repeat
    end tell
  end tell
  return false
end clickMenu

on spellingItem()
  tell application "System Events"
    tell process "Notes"
      repeat with barName in {"편집", "Edit"}
        repeat with subName in {"맞춤법 및 문법", "Spelling and Grammar"}
          repeat with itemName in {"입력하는 동안 맞춤법 검사", "Check Spelling While Typing"}
            try
              return menu item itemName of menu 1 of menu item subName of menu 1 of menu bar item barName of menu bar 1
            end try
          end repeat
        end repeat
      end repeat
    end tell
  end tell
  return missing value
end spellingItem

on run argv
  set winX to (item 1 of argv) as integer
  set winY to (item 2 of argv) as integer
  set winW to (item 3 of argv) as integer
  set winH to (item 4 of argv) as integer
  set zoomSteps to 6
  if (count of argv) > 4 then set zoomSteps to (item 5 of argv) as integer

  tell application "Notes"
    activate
    set theNote to make new note at folder "Notes" of default account with properties {body:""}
    set noteID to id of theNote
    show theNote
  end tell
  delay 0.8

  if not my clickMenu({"윈도우", "Window"}, {"새로운 윈도우에서 메모 열기", "Open Note in New Window"}) then
    error "Could not find the menu item that opens the note in a new window"
  end if
  delay 1.0

  tell application "System Events"
    tell process "Notes"
      set position of window 1 to {winX, winY}
      set size of window 1 to {winW, winH}
      perform action "AXRaise" of window 1
    end tell
  end tell
  delay 0.5

  repeat zoomSteps times
    my clickMenu({"보기", "View"}, {"확대", "Zoom In"})
    delay 0.25
  end repeat

  set spell to 0
  set spellItem to my spellingItem()
  if spellItem is not missing value then
    tell application "System Events"
      if (value of attribute "AXMenuItemMarkChar" of spellItem) is not missing value then
        click spellItem
        set spell to 1
      end if
    end tell
  end if
  delay 0.3

  tell application "System Events"
    tell process "Notes"
      set p to position of window 1
      set s to size of window 1
    end tell
  end tell
  return noteID & "|" & (item 1 of p) & "|" & (item 2 of p) & "|" & (item 1 of s) & "|" & (item 2 of s) & "|" & spell
end run
