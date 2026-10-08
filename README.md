# Pangea StratBal++ (aka "Fish Map")

A Civilization V map script: Pangea with strategic balance to include 7 coal, 3 aluminum.

Created by **Fish**

Pulled automatically by [kek-mod's installer](https://github.com/OBLASTWAR/kek-mod)
if a player doesn't already have it.

## Manual install

Download `FishMapScript-v<version>.zip` from the latest
[release](https://github.com/OBLASTWAR/pangea-stratbal/releases/latest) and
unzip it into `Sid Meier's Civilization V/Assets/Maps/`, replacing any older
`Fish Map Script` folder. The version you have is in the name of the
`.modinfo` file inside (`VFishMapScriptv1.0.modinfo` = v1.0).

## Releasing

```
./release.sh 1.1            # new version: renames the .modinfo, tags, publishes FishMapScript-v1.1.zip
./release.sh 1.1 --dry-run  # build and check only
./release.sh --rebuild 1.0  # re-publish an existing version (only if the files are unchanged)
```

kek-mod's installer reads the installed version from the `.modinfo` file name
(`VFishMapScriptv1.1.modinfo`) and compares it with the latest release tag,
so always release through the script -- it keeps the two in step.
