<h1 align="center">
  <br>
  <a href="https://papas.xqnder.xyz">
  <img src="assets/logo.svg" alt="Extra Toppings" width="200">
</a>

  <br>
  <b>Extra Toppings</b>
  <br>
</h1>

<h4 align="center">A mod loader for the Papa's Deluxe games on Steam, installed on your PC into your own copy.
</h4>

<p align="center">
  <a href="#project-status">Status</a> |
  <a href="#how-to-install">How to install</a> |
  <a href="#making-mods">Making mods</a> |
  <a href="#how-it-works">How it works</a> |
  <a href="#want-to-help">Want to help?</a> |
  <a href="#credits">Credits</a> |
  <a href="#license">License</a> |
  <a href="https://papas.xqnder.xyz">Website</a>
</p>

Extra Toppings adds mod support to Papa's Pizzeria Deluxe. The Deluxe games are Adobe AIR apps, so the installer
adds a small loader to the game's own code. At startup the loader reads mods from a `mods` folder next to the game.
A mod is a folder with a `mod.json` that changes game values: customers per day, arrival timing, day length, wages,
and anything else the game keeps in its data. Most mods need no code. All of this happens **on your PC, in your own
copy of the game**.

> [!IMPORTANT]
> This repository **does not contain the game or any of its code or assets**. You need your own copy from Steam.
> The installer backs up the original game file before patching it, and one command puts it back.
> Extra Toppings is an unofficial fan project, not affiliated with or endorsed by Flipline Studios.

Website: https://papas.xqnder.xyz
<br>
Want to play in a browser instead? Papa's Pizzeria Deluxe runs at https://port.xqnder.xyz
<br>

## Project status

**Early. Papa's Pizzeria Deluxe works; the other two games are next.**

| What | Status |
|---|---|
| Installing into Papa's Pizzeria Deluxe (backup, patch, uninstall) | ✅ Works |
| Mods that change values at game start (wages, day length, food data) | ✅ Tested in game |
| Writing a game object's fields to the log (`dump`) | ✅ Tested in game |
| Mods that change values each work day (customers per day, arrival timing) | ⚠️ Built, not yet tested during a work day |
| Mods that change station screens, the HUD or the shop | ⚠️ Built, not yet tested |
| Script mods (compiled ActionScript) | ⚠️ Experimental, untested |
| Papa's Freezeria Deluxe | ❌ Not yet. Same engine, needs testing |
| Papa's Mocharia Deluxe | ❌ Not yet. Same engine, needs testing |
| One-line install that finds games and downloads its own tools | ✅ Works |
| Keeping mods installed after a Steam update | ⚠️ Run the installer again; it detects the update |

## How to install

You need **Windows 10/11** and **your own copy** of Papa's Pizzeria Deluxe from Steam. Nothing else.

**One line.** Open PowerShell (Start menu, type `PowerShell`) and paste:

```powershell
irm papas.xqnder.xyz/install | iex
```

**Or download it.** **Code → Download ZIP**, unzip it anywhere and double-click `Install.bat`.

The installer does everything for you:

- Finds your games in every Steam library, even on other drives.
- Downloads the tools it needs the first time: [FFDec](https://github.com/jindrapetrik/jpexs-decompiler) and Java
  if you don't have them. They're kept in `%LOCALAPPDATA%\ExtraToppings`.
- Waits for you to close the game if it's running.
- Backs up `Data\assets\Main.assets` to `Main.assets.original`, builds the modded game from your copy and checks that
  the build really contains the loader. It never installs a broken build.
- Creates the `mods` folder with example mods in `mods\_examples` and opens it.
- After a Steam update, run it again. It notices the new game version and backs that up instead.

Then start the game from Steam as usual. To turn on a mod, move its folder from `_examples` into `mods`.

**Uninstall** (puts the original game back, keeps your mods folder): double-click `Uninstall.bat`, or paste:

```powershell
$env:EXTRA_TOPPINGS_UNINSTALL=1; irm papas.xqnder.xyz/install | iex
```

**Experimental games:** Freezeria and Mocharia aren't tested yet. To try one anyway:
`.\install.ps1 -Game freezeria`.

## Making mods

A mod is a folder in `mods` with a `mod.json`:

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
- Example mods are in [`mods/`](mods).

### Patch operations

| Op | Example | Does |
|---|---|---|
| `set` | `{"set": "timePerDay", "value": 14400}` | Assign a value |
| `push` | `{"push": "challengeManager.badges", "value": {...}}` | Append to an array |
| `call` | `{"call": "userData.someMethod", "args": [1, 2]}` | Call a method |
| `dump` | `{"dump": "customerManager"}` | Write every field and method of an object to the log |

### Paths

- Paths start at the game's root object: `userData.baseWeeklyWage`, `customerManager.numberOfCustomers`.
- Array items by index: `customerManager.numberOfCustomers.3`.
- Static members of a class: `pizzaGame.data.FoodData::CRUST_THICK`. Dump a whole class with `pizzaGame.data.FoodData::`.

### When patches run (`on`)

| `on` | Runs |
|---|---|
| `init` (default) | Game start. Data objects exist (`gameData`, `userData`, `customerData`, `clothingData`, `toppingData`, `challengeManager`) |
| `customerManager` | Every work day, right after the customer manager is created and before the day's lineup is built |
| any root field, e.g. `buildScreen`, `hud`, `shopScreen`, `orderScreen` | The frame after that object is (re)created |

Day-scoped objects (`customerManager`, station screens, `hud`) are rebuilt each day, so patch them with `on`.
Save data loads after `init`, so values stored in the save (tips, rank, day) get overwritten if you set them at `init`.

### Special values

- `{"$ref": "pizzaGame.data.FoodData::TOPPING_BACON"}` uses an existing game value.
- `{"$new": "pizzaGame.data.Challenge", "args": ["seals", {"targetAmount": 3, "sealType": "gold", "title": "Hi"}]}`
  constructs a game object.

### Units

- Money is in cents (`10000` = $100.00).
- Timings are frames at 30 fps (`900` = 30 seconds).

### Finding things to change

Turn on the bundled `dev-explorer` mod (`"enabled": true`) and read `mods/modloader.log`. To see what a field does,
open your own `Main.assets` in FFDec and read the class. Game code lives under `pizzaGame`, `iceGame` or `mochaGame`.

### Script mods (experimental)

For logic changes, a mod can ship a compiled ActionScript SWF:

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

`api` has `game`, `mod`, `dir`, `log(msg)`, `on(event, fn)` (also `"frame"` for every frame), `getClass(name)`,
`run(op)` (same ops as JSON), `dump(obj)` and `readText(relPath)`. Compile with the AIR SDK (`amxmlc`). The SWF loads
into the game's own domain, so game classes are reachable through `api.getClass`.

## How it works

| Piece | What it does | Where |
|---|---|---|
| Installer | Finds games, gets Java and FFDec, backs up `Main.assets`, decompiles the two classes it hooks from your copy, adds the hooks, recompiles, checks the result and installs it | `install.ps1` |
| One-line installer | Downloads this repo to `%LOCALAPPDATA%\ExtraToppings\loader` and runs `install.ps1` | `get.ps1` |
| Loader | Reads `mods/*/mod.json`, runs patches when their event fires, loads script mods, writes `mods/modloader.log` | `src/flipline/mods/ModLoader.as` |
| Start hook | `DataHelper.loadData()` starts the loader at the end of game startup, after every data object exists | Added by the installer |
| Day hook | `CustomerManager.setupManager()` fires `customerManager` before the day's lineup is built | Added by the installer |
| Screen events | A per-frame check fires an event when a root field such as `buildScreen` gets a new object | `ModLoader.as` |
| Example mods | Busy Pizzeria, Big Paychecks, Dev Explorer | `mods/` |

FFDec's command line can only replace classes, not add new ones, so the loader is compiled in as a private class
inside `DataHelper.as`. Other hooks reach it through `DataHelper.mod()`.

## Want to help?

- **Test a work day** with the `busy-pizzeria` mod and report whether the customer changes show up in
  `mods/modloader.log` and in game.
- **Freezeria and Mocharia**: run `.\install.ps1 -Game freezeria` or `-Game mocharia` and report what happens.
- **Script mods**: build the example above with the AIR SDK and report whether it loads.
- **Make mods** and share them.

Open an issue or a pull request.

## Credits

- [JPEXS Free Flash Decompiler](https://github.com/jindrapetrik/jpexs-decompiler) by Jindra Petřík: decompiling and
  recompiling the game's ActionScript. Not included here; the installer runs your installed copy.
- Papa's Pizzeria, Papa's Freezeria and Papa's Mocharia are made by Flipline Studios. Extra Toppings is not affiliated
  with them.

## License

The loader, installer and example mods are released under the [MIT License](LICENSE). The games themselves are not
covered by this license.
