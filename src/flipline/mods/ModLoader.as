package flipline.mods
{
   import flash.desktop.NativeApplication;
   import flash.display.Loader;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.utils.ByteArray;
   import flash.utils.Dictionary;
   import flash.utils.describeType;
   import flash.utils.getDefinitionByName;

   public class ModLoader
   {
      public static const VERSION:String = "1.0.0";

      public static var game:Object = null;
      public static var mods:Array = [];
      public static var modsDir:File = null;

      private static var listeners:Object = {};
      private static var lastSeen:Dictionary = new Dictionary(true);
      private static var watched:Object = {};
      private static var logFile:File = null;
      private static var loaders:Array = [];

      public static function init(gameObj:Object) : void
      {
         if(game != null)
         {
            return;
         }
         game = gameObj;
         try
         {
            // A File built from nativePath is writable; File.applicationDirectory itself is read-only.
            modsDir = new File(File.applicationDirectory.nativePath).resolvePath("mods");
            if(!modsDir.exists || !modsDir.isDirectory)
            {
               return;
            }
            logFile = modsDir.resolvePath("modloader.log");
            writeFile(logFile,"");
            log("Extra Toppings " + VERSION + " | app " + NativeApplication.nativeApplication.applicationID);
            loadMods();
            gameObj.addEventListener(Event.ENTER_FRAME,onFrame);
            emit("init",gameObj);
         }
         catch(err:Error)
         {
            log("FATAL: " + err.getStackTrace());
         }
      }

      private static function loadMods() : void
      {
         var appId:String = NativeApplication.nativeApplication.applicationID.toLowerCase();
         var dirs:Array = modsDir.getDirectoryListing().filter(function(f:File, ... r):Boolean
         {
            return f.isDirectory && f.resolvePath("mod.json").exists;
         });
         dirs.sortOn("name",Array.CASEINSENSITIVE);
         for each(var dir:File in dirs)
         {
            try
            {
               var def:Object = JSON.parse(readFile(dir.resolvePath("mod.json")));
               def.dir = dir;
               if(!def.name)
               {
                  def.name = dir.name;
               }
               if(def.enabled === false)
               {
                  log("skip " + def.name + " (disabled)");
                  continue;
               }
               if(def.game && def.game != "any" && appId.indexOf(String(def.game).toLowerCase()) < 0)
               {
                  log("skip " + def.name + " (made for " + def.game + ")");
                  continue;
               }
               mods.push(def);
               log("load " + def.name + " " + (def.version || "") + (def.author ? " by " + def.author : ""));
               for each(var op:Object in (def.patches || []))
               {
                  op.mod = def.name;
                  on(op.on || "init",op);
               }
               if(def.script)
               {
                  loadScript(def);
               }
            }
            catch(err:Error)
            {
               log("ERROR in " + dir.name + "/mod.json: " + err.message);
            }
         }
      }

      // handler is a patch op Object or a script Function(target, event).
      // Closures can't see this class's statics once FFDec compiles it, so ops stay as data.
      public static function on(event:String, handler:*) : void
      {
         if(!listeners[event])
         {
            listeners[event] = [];
         }
         listeners[event].push(handler);
         if(event != "init")
         {
            watched[event] = true;
         }
      }

      // Called by hooks patched into game classes, and by the frame watcher.
      public static function emit(event:String, target:Object) : void
      {
         if(target == null || lastSeen[target] == event)
         {
            return;
         }
         lastSeen[target] = event;
         for each(var h:* in (listeners[event] || []))
         {
            try
            {
               if(h is Function)
               {
                  h(target,event);
               }
               else
               {
                  runOp(h,event,target);
               }
            }
            catch(err:Error)
            {
               log("ERROR in '" + event + "' handler: " + err.toString());
            }
         }
      }

      private static function onFrame(e:Event) : void
      {
         for(var name:String in watched)
         {
            if(game.hasOwnProperty(name))
            {
               emit(name,game[name]);
            }
         }
         for each(var fn:Function in (listeners["frame"] || []))
         {
            fn(game,"frame");
         }
      }

      public static function runOp(op:Object, event:String = "init", target:Object = null) : *
      {
         try
         {
            var path:String = op.set || op.push || op.call || op.dump || op.get;
            var parts:Array = splitPath(path,event,target);
            var obj:Object = parts[0];
            var key:String = parts[1];
            if(op.hasOwnProperty("set"))
            {
               obj[key] = resolveValue(op.value);
               log("[" + op.mod + "] set " + path + " = " + JSON.stringify(op.value));
            }
            else if(op.hasOwnProperty("push"))
            {
               obj[key].push(resolveValue(op.value));
               log("[" + op.mod + "] push " + path);
            }
            else if(op.hasOwnProperty("call"))
            {
               var result:* = (obj[key] as Function).apply(obj,resolveValue(op.args || []));
               log("[" + op.mod + "] call " + path);
               return result;
            }
            else if(op.hasOwnProperty("dump"))
            {
               log("[" + op.mod + "] dump " + path + ":\n" + dump(key == null ? obj : obj[key]));
            }
            else if(op.hasOwnProperty("get"))
            {
               return key == null ? obj : obj[key];
            }
         }
         catch(err:Error)
         {
            log("ERROR [" + op.mod + "] " + JSON.stringify(op) + ": " + err.message);
         }
         return undefined;
      }

      // "a.b.c" -> [object a.b, "c"]. "pkg.Class::A.b" starts at a class (static members).
      // A first segment equal to the current event name resolves to the event target.
      private static function splitPath(path:String, event:String = null, target:Object = null) : Array
      {
         var obj:Object = game;
         var rest:String = path;
         var i:int = path.indexOf("::");
         if(i >= 0)
         {
            obj = getDefinitionByName(path.substr(0,i));
            rest = path.substr(i + 2);
         }
         if(rest == "")
         {
            return [obj,null];
         }
         var segs:Array = rest.split(".");
         if(i < 0 && target != null && segs[0] == event)
         {
            obj = target;
            segs.shift();
            if(segs.length == 0)
            {
               return [obj,null];
            }
         }
         while(segs.length > 1)
         {
            obj = obj[segs.shift()];
         }
         return [obj,segs[0]];
      }

      public static function resolveValue(v:*) : *
      {
         if(v is Array)
         {
            var out:Array = [];
            for each(var item:* in v)
            {
               out.push(resolveValue(item));
            }
            return out;
         }
         if(v == null || typeof v != "object")
         {
            return v;
         }
         if(v.hasOwnProperty("$ref"))
         {
            var p:Array = splitPath(v["$ref"]);
            return p[1] == null ? p[0] : p[0][p[1]];
         }
         if(v.hasOwnProperty("$new"))
         {
            return construct(getDefinitionByName(v["$new"]) as Class,resolveValue(v.args || []));
         }
         var o:Object = {};
         for(var k:String in v)
         {
            o[k] = resolveValue(v[k]);
         }
         return o;
      }

      public static function construct(c:Class, a:Array) : *
      {
         switch(a.length)
         {
            case 0: return new c();
            case 1: return new c(a[0]);
            case 2: return new c(a[0],a[1]);
            case 3: return new c(a[0],a[1],a[2]);
            case 4: return new c(a[0],a[1],a[2],a[3]);
            case 5: return new c(a[0],a[1],a[2],a[3],a[4]);
            case 6: return new c(a[0],a[1],a[2],a[3],a[4],a[5]);
            case 7: return new c(a[0],a[1],a[2],a[3],a[4],a[5],a[6]);
            default: return new c(a[0],a[1],a[2],a[3],a[4],a[5],a[6],a[7]);
         }
      }

      public static function dump(o:*) : String
      {
         if(o == null || typeof o != "object")
         {
            return "  " + o;
         }
         var lines:Array = [];
         var d:XML = describeType(o);
         lines.push("  (" + d.@name + ")");
         for each(var x:XML in (d.variable + d.accessor + d.constant))
         {
            var n:String = String(x.@name);
            var val:String;
            try
            {
               var raw:* = o[n];
               val = raw is Array ? "[" + (raw as Array).join(",") + "]" : String(raw);
            }
            catch(err:Error)
            {
               val = "<unreadable>";
            }
            lines.push("  " + n + ":" + x.@type + " = " + val.substr(0,200));
         }
         for each(var m:XML in d.method)
         {
            lines.push("  " + m.@name + "()");
         }
         return lines.join("\n");
      }

      private static function loadScript(def:Object) : void
      {
         // Closures below reach statics through L (see note on on()).
         var L:Class = ModLoader;
         var bytes:ByteArray = new ByteArray();
         var fs:FileStream = new FileStream();
         fs.open((def.dir as File).resolvePath(def.script),FileMode.READ);
         fs.readBytes(bytes);
         fs.close();
         var ctx:LoaderContext = new LoaderContext(false,ApplicationDomain.currentDomain);
         ctx.allowCodeImport = true;
         var loader:Loader = new Loader();
         loaders.push(loader);
         loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent):void
         {
            L.log("ERROR loading script " + def.script + ": " + e.text);
         });
         loader.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void
         {
            try
            {
               var inst:* = def.main ? L.construct(L.getClass(def.main),[]) : loader.content;
               if(inst && inst.hasOwnProperty("init"))
               {
                  inst.init(L.makeApi(def));
               }
               L.log("script ready: " + def.name);
            }
            catch(err:Error)
            {
               L.log("ERROR starting script " + def.name + ": " + err.getStackTrace());
            }
         });
         loader.loadBytes(bytes,ctx);
      }

      public static function getClass(name:String) : Class
      {
         return getDefinitionByName(name) as Class;
      }

      public static function makeApi(def:Object) : Object
      {
         var L:Class = ModLoader;
         return {
            "game":game,
            "mod":def,
            "dir":def.dir,
            "log":function(msg:*):void
            {
               L.log("[" + def.name + "] " + msg);
            },
            "on":on,
            "getClass":getClass,
            "run":function(op:Object):*
            {
               op.mod = def.name;
               return L.runOp(op);
            },
            "dump":dump,
            "readText":function(rel:String):String
            {
               return L.readFile((def.dir as File).resolvePath(rel));
            }
         };
      }
      public static function log(msg:String) : void
      {
         trace("[ModLoader] " + msg);
         if(logFile == null)
         {
            return;
         }
         try
         {
            var fs:FileStream = new FileStream();
            fs.open(logFile,FileMode.APPEND);
            fs.writeUTFBytes(msg + "\r\n");
            fs.close();
         }
         catch(err:Error)
         {
         }
      }

      public static function readFile(f:File) : String
      {
         var fs:FileStream = new FileStream();
         fs.open(f,FileMode.READ);
         var s:String = fs.readUTFBytes(fs.bytesAvailable);
         fs.close();
         return s;
      }

      private static function writeFile(f:File, s:String) : void
      {
         var fs:FileStream = new FileStream();
         fs.open(f,FileMode.WRITE);
         fs.writeUTFBytes(s);
         fs.close();
      }
   }
}
