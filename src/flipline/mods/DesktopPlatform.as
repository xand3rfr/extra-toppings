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

   public class DesktopPlatform
   {
      private static var modsDir:File = null;
      private static var logFile:File = null;
      private static var loaders:Array = [];

      public static function start() : Boolean
      {
         // A File built from nativePath is writable; File.applicationDirectory itself is read-only.
         modsDir = new File(File.applicationDirectory.nativePath).resolvePath("mods");
         if(!modsDir.exists || !modsDir.isDirectory)
         {
            return false;
         }
         logFile = modsDir.resolvePath("modloader.log");
         writeFile(logFile,"");
         return true;
      }

      public static function describe() : String
      {
         return "app " + appId();
      }

      public static function appId() : String
      {
         return NativeApplication.nativeApplication.applicationID;
      }

      public static function loadDefs() : Array
      {
         var dirs:Array = modsDir.getDirectoryListing().filter(function(f:File, ... r):Boolean
         {
            return f.isDirectory && f.resolvePath("mod.json").exists;
         });
         dirs.sortOn("name",Array.CASEINSENSITIVE);
         var defs:Array = [];
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
               defs.push(def);
            }
            catch(err:Error)
            {
               ModLoader.log("ERROR in " + dir.name + "/mod.json: " + err.message);
            }
         }
         return defs;
      }

      public static function loadScript(def:Object) : void
      {
         // Closures can't see statics once FFDec compiles this, so they go through L.
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

      public static function readText(def:Object, rel:String) : String
      {
         return readFile((def.dir as File).resolvePath(rel));
      }

      public static function write(msg:String) : void
      {
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

      private static function readFile(f:File) : String
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
