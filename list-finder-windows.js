#!/usr/bin/env osascript -l JavaScript

function run(args) {

	// Enable shell script capability
	var app = Application.currentApplication();
	app.includeStandardAdditions = true;
	
	let systemAppearance = args[0]; // Get macOS light/dark mode setting from first argument
	let settingsIcon = { path: "/System/Library/CoreServices/ManagedClient.app/Contents/PlugIns/ConfigurationProfilesUI.bundle/Contents/Resources/SystemPrefApp.icns" };
	let iconsDir = "resources/icons/";
	let getInfoIcon = { path: `${iconsDir}info.png` };
	let closeIcon = { path: `${iconsDir}close.png` };
	let pathIcon = { path: `${iconsDir}path.png` };
	let finderSadIcon = { path: `${iconsDir}finder-crying.png` };
	let folderIconsDir = `${iconsDir}folder-icons/${systemAppearance}/`;
	let folderIconGeneric = `${folderIconsDir}/Generic.png`;
	let finder = Application("Finder");
	let windowCount = finder.windows.length;
	let windowsMap = {};

	// Function to escape special characters for shell commands
	function escapeShellArg(path) {
		return path.replace(/([`"\\$])/g, '\\$1');
	}

	// If no Finder windows are open
	if (!windowCount) {
		subtitle = "Press enter to create one";
		windowsMap[0] = {
			title: "No open Finder windows",
			windowIndex: 0,
			subtitle: subtitle,
			icon: finderSadIcon,
			arg: "open-new-window",
			mods: {
				cmd: {
					subtitle: "Press enter to create one"
				},
				alt: {
					subtitle: "Press enter to create one"
				}
			}
		};

	} else {
			
		// If open Finder windows exist
		for (let w = 0; w < windowCount; w++) {

			let window = finder.windows[w]; // Reference to specific window
			let windowName = window.name() || `Finder Window ${w + 1}`; // Access window properties

			let subtitle;
			let path;
			let posixPath;
			let posixPathEscaped;
			let folderContents;
			let icon = null;
			let mods = null;
			let altSubtext = "Close window"

			// If "Get Info" window
			if (windowName.endsWith(" Info")) {
				subtitle = windowName;
				cmdSubtext = windowName;
				mods = null;
				icon = getInfoIcon;
				cmdIcon = icon;
			// If "Finder Settings" window (macOS 13 Ventura and newer) or "Preferences" window (macOS 12 Monterey and older)
			} else if (windowName === "Finder Settings" || windowName === "Preferences") {
				subtitle = windowName;
				cmdSubtext = windowName;
				mods = null;
				icon = settingsIcon;
				cmdIcon = icon;
			// If other window (likely browser window)
			} else {
				try {
					// Try to get path to browser window target
					path = window.target().url().replace("file://", "").trim();
					posixPath = decodeURIComponent(path);
					posixPathEscaped = escapeShellArg(posixPath);
					subtitle = posixPath; // Decode path from URL to POSIX
					cmdSubtext = "Copy folder path";
					app.doShellScript(``)
					customIcon = app.doShellScript(`/bin/zsh "get-custom-icon.zsh" "$PWD" "${path}" "${folderIconsDir}" "${systemAppearance}" &`);
					if (!customIcon) {
						icon = { path: folderIconGeneric };
					} else {
						icon = { path: customIcon };
					}
					cmdIcon = pathIcon;
					folderContents = app.doShellScript(`/bin/ls -1 "${posixPathEscaped}" | tr '\n' ' '`);
				} catch (e) {
					// For other non-browser windows, fall back to window name for subtitle
					subtitle = windowName;
					cmdSubtext = windowName;
					mods = null;
					icon = null;
					cmdIcon = icon;
					folderContents = null;
				}
			}

			// Construct output
			windowsMap[w] = {
				title: windowName,
				subtitle: subtitle,
				windowIndex: w,
				arg: `${w},${(posixPathEscaped || '').trim()}`, // Create output argument, trim whitespace
				match: `${windowName} ${w + 1} ${posixPath} ${folderContents}`,
				...(icon && { icon }), // Only add icon if it's set
				mods: { // Define output for when modifier keys are held
					cmd: { // Command key
						subtitle: cmdSubtext,
						icon: cmdIcon,
						arg: `${w},${(posixPath || '').trim()},${cmdSubtext}`
					},
					alt: { // Alt/option key
						subtitle: altSubtext,
						icon: closeIcon,
						arg: `${w},,${altSubtext}`
					}
				}
			};
		}
	}

	let items = Object.keys(windowsMap).reduce((acc, key) => {
		acc.push(windowsMap[key]);
		return acc;
	}, []);

	return JSON.stringify({ items });
}