# Pangea StratBal++ (aka "Fish Map")

A Civilization V map script: Pangea with strategic balance to include 7 coal, 3 aluminum.

Created by **Fish**

Pulled automatically by [kek-mod's installer](https://github.com/OBLASTWAR/kek-mod)
if a player doesn't already have it.

## Manual install

Drop the contents of this repo into:

```
Sid Meier's Civilization V/Assets/Maps/Fish Map Script/
```

## Releasing

```
./release.sh 1.1            # new version: renames the .modinfo, tags, publishes FishMapScript.zip
./release.sh 1.1 --dry-run  # build and check only
./release.sh --rebuild 1.0  # re-publish an existing version (only if the files are unchanged)
```

kek-mod's installer reads the installed version from the `.modinfo` file name
(`VFishMapScriptv1.1.modinfo`) and compares it with the latest release tag,
so always release through the script -- it keeps the two in step.
