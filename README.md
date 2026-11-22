# Extra Toppings

A community mod loader for the Steam "Deluxe" Papa's games. Mods are folders with a `mod.json`; most mods need no code.

| Game | Status |
|---|---|
| Papa's Pizzeria Deluxe | Supported |
| Papa's Freezeria Deluxe | Same engine, not tested yet |
| Papa's Mocharia Deluxe | Same engine, not tested yet |

> Unofficial fan project. Not affiliated with or endorsed by Flipline Studios. You need your own copy of the game.
> This repo contains no game code or assets: the installer patches the copy already on your PC.

## Install

Requirements: Windows, the game installed through Steam, and [JPEXS FFDec](https://github.com/jindrapetrik/jpexs-decompiler/releases) (the installer uses it to patch the game).

1. Download this repo (Code → Download ZIP) and unzip it.
2. Close the game. In PowerShell, in the unzipped folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Game pizzeria
```

3. Copy mod folders into the new `mods` folder in the game directory and start the game.

The installer backs up `Data/assets/Main.assets` to `Main.assets.original` before patching.
Game installed somewhere else? Add `-SteamCommon "D:\SteamLibrary\steamapps\common"`. FFDec somewhere else? Add `-FFDec "<path to ffdec-cli.exe>"`.

Uninstall:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Game pizzeria -Uninstall
```

After a Steam update replaces the game files, delete `Main.assets.original` and install again.

## Writing a mod

```
<game folder>/mods/my-mod/mod.json
```

```json
{
  "name": "My Mod",
  "version": "1.0",
  "author": "you",
  "game": "pizzeria",
  "enabled": true,
  "patches": [
    { "set": "userData.baseWeeklyWage", "value": 50000 },
    { "on": "customerManager", "set": "customerManager.normalSpawnTiming", "value": 900 }
  ]
}
```

- `game`: `pizzeria`, `freezeria`, `mocharia` or `any`.
- Mods load in alphabetical folder order. Later mods win.
- Everything the loader does goes to `mods/modloader.log`. Check it first when something doesn't work.

### Patch operations

| Op | Example | Does |
|---|---|---|
| `set` | `{"set": "timePerDay", "value": 14400}` | Assign a value |
| `push` | `{"push": "challengeManager.badges", "value": {...}}` | Append to an array |
| `call` | `{"call": "userData.someMethod", "args": [1, 2]}` | Call a method |
| `dump` | `{"dump": "customerManager"}` | Write every field and method of an object to the log |

### Paths

- Paths start at the game root object (`GameModule`): `userData.baseWeeklyWage`, `customerManager.numberOfCustomers.0`.
- Static members of a class: `pizzaGame.data.FoodData::CRUST_THICK`. Dump a whole class with `pizzaGame.data.FoodData::`.
- Array items by index: `customerManager.numberOfCustomers.3`.

### When patches run (`on`)

| `on` | Runs |
|---|---|
| `init` (default) | Game start. Data objects exist (`gameData`, `userData`, `customerData`, `clothingData`, `toppingData`, `challengeManager`). |
| `customerManager` | Every work day, right after the customer manager is created and before the day's lineup is built. |
| any game-root field, e.g. `buildScreen`, `hud`, `shopScreen`, `orderScreen` | The frame after that object is (re)created. |

Day-scoped objects (`customerManager`, station screens, `hud`) are rebuilt each day, so patch them with `on`, not at `init`.
Save data loads after `init`, so values stored in the save (tips, rank, day) get overwritten if set at `init`.

### Special values

- `{"$ref": "pizzaGame.data.FoodData::TOPPING_BACON"}` uses an existing game value.
- `{"$new": "pizzaGame.data.Challenge", "args": ["seals", {"targetAmount": 3, "sealType": "gold", "title": "Hi"}]}` constructs a game object.

### Units

- Money is in cents (`10000` = $100.00).
- Timings are frames at 30 fps (`900` = 30 seconds).

### Finding things to change

Enable the bundled `dev-explorer` mod (`"enabled": true`) and read `mods/modloader.log`.
To see what a field does, open your own `Main.assets` in FFDec and read the class (game code lives under `pizzaGame`, `iceGame` or `mochaGame`).

## Script mods (experimental, not yet tested)

For logic changes, a mod can ship a compiled AS3 SWF:

```json
{ "name": "Hello", "game": "any", "script": "Hello.swf", "main": "HelloMod" }
```

```actionscript
package {
   public class HelloMod {
      public function init(api:Object):void {
         api.log("hello from " + api.game.gameTitle);
         api.on("customerManager", function(cm:Object, event:String):void {
            cm.normalSpawnTiming = 600;
         });
      }
   }
}
```

`api` has: `game`, `mod`, `dir`, `log(msg)`, `on(event, fn)` (also `"frame"` for every frame), `getClass(name)`, `run(op)` (same ops as JSON), `dump(obj)`, `readText(relPath)`.
Compile with the AIR SDK (`amxmlc`). The SWF is loaded into the game's own domain, so game classes are reachable through `api.getClass`.

## How it works

The build injects two hooks into the decompiled game and recompiles with FFDec:
- `DataHelper.loadData()` starts the loader (end of `GameModule.initGame()`). The loader itself is a file-private class inside `DataHelper.as`, because FFDec's CLI can only replace classes, not add them.
- `CustomerManager.setupManager()` emits `customerManager`.
Other `on` events come from a per-frame check of the game root's fields.
