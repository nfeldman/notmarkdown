-- notmarkdown droplet — drag Markdown files or folders onto the app to publish them.
--
-- Each dropped item is handed to `mdexport`, which writes its output as a sibling:
-- a file -> a sibling file; a folder -> a sibling folder (or one combined artifact).
-- A Finder-launched app gets a minimal PATH, so we add the usual tool locations;
-- mdexport itself must be on it (the installer symlinks it into ~/.local/bin).
--
-- Built by `make-droplet` with osacompile. Edit here, then rebuild.

on open theItems
	set publishedCount to 0
	set failures to {}
	repeat with anItem in theItems
		set itemPath to POSIX path of anItem
		try
			do shell script "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; mdexport " & quoted form of itemPath
			set publishedCount to publishedCount + 1
		on error errMsg
			set end of failures to itemPath & " — " & errMsg
		end try
	end repeat
	if (count of failures) is 0 then
		display notification "Published " & publishedCount & " item(s)." with title "notmarkdown"
	else
		display dialog "notmarkdown could not publish:" & return & return & joinText(failures, return) buttons {"OK"} default button "OK" with icon caution
	end if
end open

-- The app can also be opened on its own; point people at the drop behavior.
on run
	display dialog "Drop Markdown files or folders onto this app to publish them as self-contained HTML." buttons {"OK"} default button "OK"
end run

on joinText(lst, delim)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delim
	set s to lst as text
	set AppleScript's text item delimiters to saved
	return s
end joinText
