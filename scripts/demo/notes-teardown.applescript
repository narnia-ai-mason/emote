-- Closes the demo note window, deletes the note, and turns
-- check-spelling-while-typing back on when asked.
-- Arguments: noteID spell   (spell = 1 turns spelling back on)

on run argv
  set noteID to item 1 of argv
  set spell to "0"
  if (count of argv) > 1 then set spell to item 2 of argv

  if spell is "1" then
    tell application "Notes" to activate
    delay 0.3
    tell application "System Events"
      tell process "Notes"
        repeat with barName in {"편집", "Edit"}
          repeat with subName in {"맞춤법 및 문법", "Spelling and Grammar"}
            repeat with itemName in {"입력하는 동안 맞춤법 검사", "Check Spelling While Typing"}
              try
                set mi to menu item itemName of menu 1 of menu item subName of menu 1 of menu bar item barName of menu bar 1
                if (value of attribute "AXMenuItemMarkChar" of mi) is missing value then click mi
              end try
            end repeat
          end repeat
        end repeat
      end tell
    end tell
  end if

  tell application "Notes"
    try
      close front window
    end try
    delay 0.3
    delete note id noteID
  end tell
end run
