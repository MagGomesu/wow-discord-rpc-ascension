# Discord Rich Presence for Ascension World of Warcraft
This branch has some changes to make it work for Ascension WoW. 
I tried to make the installation as easy as possible, so I hope you won't face any problems.

## Preview
![image](https://github.com/user-attachments/assets/51528f03-7285-4c60-b245-ffb55fa33166)

The Ascension server name has a link to Ascension website, in case whoever is looking wants to join the server 

## Requirements
- Python 3 for Windows, the [web-based installer](https://www.python.org/downloads/windows/) is OK. When it's finished installing, you will be asked if you want Python to be added to your $PATH, you have to say yes.
## Setup
- Launch the `Installer.bat`. It will install everything is required, you will be prompted to select your AddOns Folder.

- From now on you'll need to **run the game from the Desktop Launcher** or the .bat file.

**You can't move `WoW.bat` (installed in your addons folder) anywhere else, Game has to be launched from Desktop Shortcut or `AddOns/IPC/` directory using WoW.bat.**

**Note:** you have to play the game in borderless or windowed mode, full-screen is **not supported**!

Now you can launch the game through the Desktop Launcher and check if it works. It should look like this.

![image](https://user-images.githubusercontent.com/47401054/113831744-9d97fb00-9790-11eb-862e-8909c7cb6a53.png)

It is? Perfect! Now log into the world and check if you see some colorful array in the top left corner.

![image](https://user-images.githubusercontent.com/47401054/113832547-6249fc00-9791-11eb-8360-38b2f2568029.png)

If you see them, then AddOn is working properly. That means that you already should see the rich presence in your profile.

![image](https://github.com/user-attachments/assets/51528f03-7285-4c60-b245-ffb55fa33166)

That's it! Now you have a pleasant and informative Rich Presence in your Discord profile. It will update automatically as long as the script is kept running.

If you want to translate it to your language, check `local.lua` and `WoWPresence.py` files. Zones' name will be localised automatically based on your game's locale.

## LICENSE
Both the addon and the WoWPresence.py script are in the public domain.
Original Project by [AipNooBest](https://github.com/AipNooBest/wow-discord-rpc)
The rpc.py file is from [this repo](https://github.com/suclearnub/python-discord-rpc) and it's [MIT licenced](https://raw.githubusercontent.com/AipNooBest/wow-discord-rpc/main/script/rpc.py-LICENSE).
