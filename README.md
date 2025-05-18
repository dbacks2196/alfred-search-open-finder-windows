# Search Open Finder Windows — Alfred Workflow

#### View this workflow on the [**Alfred Gallery**](https://alfred.app/workflows/davidb/search-open-finder-windows/)

![Focus Window](icon.png)

Search a list of your open Finder windows, copy paths to their open directories, and close them.

![Focus Window](resources/media/preview.png)

### Usage

* **Default action:** Focus window
* **Command (⌘):** 
  * For **Finder browser** windows: Copy path to window target *(current directory)*
  * For **get info** windows: Copy path to item of information window

* **Option (⌥):** Close window

### Matching

#### You can search for:

* **Name** of window
* **Index** of window *(starts at **1** is frontmost window)*
* For **Finder browser** windows:
  * **Path** *(and **directories in path**)* to the window's target
  * **Contents** *(files and folders)* of the window's current directory
  * Supports **dynamic matching** of **hidden items** based on current Finder visibility setting
* For **Get Info** windows:
  * **Path** *(and **directories in path**)* of file or folder shown in window


### Icons

This workflow uses macOS' default folder icons *(with support for folder types and system appearance)* for most listed items *(files and folders)*. If an item has a **nonstandard icon** *(i.e. app icon, user-set custom icon)*, it will use that icon.

### Examples

#### Focus window - default action

![Focus Window](resources/media/focus-window.gif)

#### Copy directory path - command (⌘)

![Copy Directory Path](resources/media/copy-directory-path.gif)

#### Close window - option (⌥)

![Close Window](resources/media/close-window.gif)

### Acknowledgements

This workflow was inspired by the **[Browser Tabs](https://alfred.app/workflows/epilande/browser-tabs/)** workflow by [**Emmanuel Pilande**](https://github.com/epilande).

In order to retrieve the custom icons, decoding of macOS resource forks is required. I wouldn't have known how to do that without examining the [**fileicon**](https://github.com/mklement0/fileicon) shell script by [**mklement** ](https://github.com/mklement0). Thank you also to [**Vitor Galvão**](https://github.com/vitorgalvao?tab=repositories&q=alfred&type=&language=&sort=) from [**Alfred**](https://github.com/alfredapp) from for helping me refine this workflow.

Big thanks to these devs (even though they don't know me) for low-key teaching me how to make this workflow!

Enjoy!