package flipline.mods
{
   import flash.external.ExternalInterface;

   // For browser builds (Ruffle). The page defines xqModsGame(), xqModsList() and xqModsLog(msg).
   public class WebPlatform
   {
      public static function start() : Boolean
      {
         return ExternalInterface.available;
      }

      public static function describe() : String
      {
         return "web";
      }

      public static function appId() : String
      {
         var id:* = ExternalInterface.call("xqModsGame");
         return id ? String(id) : "";
      }

      public static function loadDefs() : Array
      {
         var raw:* = ExternalInterface.call("xqModsList");
         if(!raw)
         {
            return [];
         }
         var defs:Array = JSON.parse(String(raw)) as Array;
         return defs || [];
      }

      public static function loadScript(def:Object) : void
      {
         ModLoader.log("skip script in " + def.name + " (script mods only work in the Steam version)");
      }

      public static function readText(def:Object, rel:String) : String
      {
         return null;
      }

      public static function write(msg:String) : void
      {
         try
         {
            ExternalInterface.call("xqModsLog",msg);
         }
         catch(err:Error)
         {
         }
      }
   }
}
