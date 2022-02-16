package;

// TODO: Clean up
import modchart.*;
import llua.Convert;
import llua.Lua;
import llua.State;
import llua.LuaL;
import flixel.util.FlxAxes;
import flixel.FlxSprite;
import lime.app.Application;
import openfl.Lib;
import sys.io.File;
import flash.display.BitmapData;
import sys.FileSystem;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.FlxCamera;
import Shaders;
import Options;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import haxe.DynamicAccess;
import openfl.display.GraphicsShader;
import states.*;
import flixel.util.FlxColor;
import ui.*;
typedef LuaProperty = {
    var defaultValue:Any;
    var getter:(State,Any)->Int;
    var setter:State->Int;
}

class LuaStorage {
  public static var objectProperties:Map<String,Map<String,LuaProperty>> = [];
  public static var objects:Map<String,LuaClass> = [];
  public static var notes:Array<Note> = [];
  public static var noteIDs:Map<Note,String>=[];
  public static var noteMap:Map<String,Note>=[];
}

class LuaClass {
  public var properties:Map<String,LuaProperty> = [];
  public var className:String = "BaseClass";
  private static var state:State;
  public var addToGlobal:Bool=true;
  public function Register(l:State){
    Lua.newtable(l);
    state=l;
    LuaStorage.objectProperties[className]=this.properties;

    var classIdx = Lua.gettop(l);
    Lua.pushvalue(l,classIdx);
    if(addToGlobal)
      Lua.setglobal(l,className);

    for (k in methods.keys()){
      Lua.pushcfunction(l,methods[k]);
      Lua.setfield(l,classIdx,k);
    }

    Lua.pushstring(l,"InternalClassName");
    Lua.pushstring(l,className);
    Lua.settable(l,classIdx);

    LuaL.newmetatable(l,className + "Metatable");
    var mtIdx = Lua.gettop(l);
    Lua.pushstring(l, "__index");
		Lua.pushcfunction(l,cpp.Callable.fromStaticFunction(index));
		Lua.settable(l, mtIdx);

    Lua.pushstring(l, "__newindex");
		Lua.pushcfunction(l,cpp.Callable.fromStaticFunction(newindex));
		Lua.settable(l, mtIdx);

    for (k in properties.keys()){
      Lua.pushstring(l,k + "PropertyData");
      Convert.toLua(l,properties[k].defaultValue);
      Lua.settable(l,mtIdx);
    }
    Lua.pushstring(l,"_CLASSNAME");
    Lua.pushstring(l,className);
    Lua.settable(l,mtIdx);

    Lua.pushstring(l,"__metatable");
    Lua.pushstring(l,"This metatable is locked.");
    Lua.settable(l,mtIdx);

    Lua.setmetatable(l,classIdx);

  };


  public static function SetProperty(l:State,tableIndex:Int,key:String,value:Any){
    Lua.pushstring(l,key + "PropertyData");
    Convert.toLua(l,value);
    Lua.settable(l,tableIndex  );

    Lua.pop(l,2);
  }

  public static function DefaultSetter(l:State){
    var key = Lua.tostring(l,2);

    Lua.pushstring(l,key + "PropertyData");
    Lua.pushvalue(l,3);
    Lua.settable(l,4);

    Lua.pop(l,2);
  };
  public function new(){}
}

class LuaWindow extends LuaClass {
  private static var state:State;
  private static function WrapNumberSetter(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
        LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      //Lib.application.window.x = Std.int(Lua.tonumber(l,3));
      Reflect.setProperty(Lib.application.window,Lua.tostring(l,2),Lua.tonumber(l,3));
      return 0;
  }

  public function new (){
    super();
    className = "window";
    properties = [
      "x"=>{
        defaultValue:Lib.application.window.x,
        getter: function(l:State,data:Any):Int{
          Lua.pushnumber(l,Lib.application.window.x);
          return 1;
        },
        setter:WrapNumberSetter
      },
      "y"=>{
        defaultValue:Lib.application.window.y,
        getter: function(l:State,data:Any):Int{
          Lua.pushnumber(l,Lib.application.window.y);
          return 1;
        },
        setter:WrapNumberSetter
      },
      "width"=>{
        defaultValue:Lib.application.window.width,
        getter: function(l:State,data:Any):Int{
          Lua.pushnumber(l,Lib.application.window.width);
          return 1;
        },
        setter:WrapNumberSetter
      },
      "height"=>{
        defaultValue:Lib.application.window.height,
        getter: function(l:State,data:Any):Int{
          Lua.pushnumber(l,Lib.application.window.height);
          return 1;
        },
        setter:WrapNumberSetter
      },
      "boundsWidth"=>{ // TODO: turn into a table w/ bounds.x and bounds.y
        defaultValue:Lib.application.window.display.bounds.width,
        getter: function(l:State,data:Any):Int{
          Lua.pushnumber(l,Lib.application.window.display.bounds.width);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"boundsWidth is read-only.");
          return 0;
        }
      },
      "boundsHeight"=>{ // TODO: turn into a table w/ bounds.x and bounds.y
        defaultValue:Lib.application.window.display.bounds.height,
        getter: function(l:State,data:Any):Int{
          Lua.pushnumber(l,Lib.application.window.display.bounds.height);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"boundsHeight is read-only.");
          return 0;
        }
      }
    ];
  }
  override function Register(l:State){
    state=l;
    super.Register(l);
  }
}

class LuaSprite extends LuaClass {
  private static var state:State;
  private static var stringToCentering:Map<String,FlxAxes> = [
    "X"=>X,
    "XY"=>XY,
    "Y"=>Y,
    "YX"=>XY
  ];
  public var sprite:FlxSprite;
  private function SetNumProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
        LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      Reflect.setProperty(sprite,Lua.tostring(l,2),Lua.tonumber(l,3));
      return 0;
  }
  private function GetNumProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushnumber(l,Reflect.getProperty(sprite,Lua.tostring(l,2)));
      return 1;
  }

  private function SetBoolProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TBOOLEAN){
        LuaL.error(l,"invalid argument #3 (boolean expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      Reflect.setProperty(sprite,Lua.tostring(l,2),Lua.toboolean(l,3));
      return 0;
  }

  private function GetBoolProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushboolean(l,Reflect.getProperty(sprite,Lua.tostring(l,2)));
      return 1;
  }

  private function GetStringProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushstring(l,Reflect.getProperty(sprite,Lua.tostring(l,2)));
      return 1;
  }

    if(stage.foreground.members.contains(sprite)){
      stage.foreground.remove(sprite);
    }

    if(stage.overlay.members.contains(sprite)){
      stage.overlay.remove(sprite);
    }

    for(shit in layers){
      if(stage.layers.get(shit).members.contains(sprite)){
        stage.layers.get(shit).remove(sprite);
      }
    }

    switch(layer){
      case 'dad' | 'boyfriend' | 'gf':
        stage.layers.get(layer).add(sprite);
      case 'foreground':
        stage.foreground.add(sprite);
      case 'overlay':
        stage.overlay.add(sprite);
      case 'stage':
        stage.add(sprite);
    }

    return 0;

  }
  public function new(sprite:FlxSprite,name:String,?addToGlobal:Bool=true){
    super();
    className=name;
    this.addToGlobal=addToGlobal;
    this.sprite=sprite;
    PlayState.currentPState.luaSprites[name]=sprite;
    LuaStorage.objects[name]=this;
    properties=[
      "spriteName"=>{
        defaultValue:name,
        getter:function(l:State,data:Any){
          Lua.pushstring(l,name);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"spriteName is read-only.");
          return 0;
        }
      },
      "flipX"=>{
        defaultValue:sprite.flipX,
        getter:GetBoolProperty,
        setter:SetBoolProperty
      },
      "flipY"=>{
        defaultValue:sprite.flipY,
        getter:GetBoolProperty,
        setter:SetBoolProperty
      },
      "x"=>{
        defaultValue:sprite.x,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "y"=>{
        defaultValue:sprite.y,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "alpha"=>{
        defaultValue:sprite.alpha,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "angle"=>{
        defaultValue:sprite.angle,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "width"=>{
        defaultValue:sprite.width,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "height"=>{
        defaultValue:sprite.height,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "visible"=>{
        defaultValue:sprite.visible,
        getter:GetBoolProperty,
        setter:SetBoolProperty
      },
      "antialiasing"=>{
        defaultValue:sprite.antialiasing,
        getter:GetBoolProperty,
        setter:SetBoolProperty
      },
      "active"=>{
        defaultValue:sprite.active,
        getter:GetBoolProperty,
        setter:SetBoolProperty
      },
      "setScale"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,setScaleC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"setScale is read-only.");
          return 0;
        }
      },
      "tween"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,tweenC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"tween is read-only.");
          return 0;
        }
      },
      "tweenColor"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,tweenColorC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"tweenColor is read-only.");
          return 0;
        }
      },
      "getProperty"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,getPropertyC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"getProperty is read-only.");
          return 0;
        }
      },
      "setProperty"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,setPropertyC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"setProperty is read-only.");
          return 0;
        }
      },
      "addAnimByPrefix"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,addSpriteAnimByPrefixC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"addAnimByPrefix is read-only.");
          return 0;
        }
      },
      "screenCenter"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,screenCenterC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"screenCenter is read-only.");
          return 0;
        }
      },
      "changeLayer"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,changeLayerC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"changeLayer is read-only.");
          return 0;
        }
      },
      "loadGraphic"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,loadGraphicC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"loadGraphic is read-only.");
          return 0;
        }
      },
      "setFrames"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,setFramesC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"setFrames is read-only.");
          return 0;
        }
      },
      "playAnim"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,playAnimSpriteC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"playAnim is read-only.");
          return 0;
        }
      },
      "addAnimByIndices"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,addSpriteAnimByIndicesC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"addAnimByIndices is read-only.");
          return 0;
        }
      },
      "addAnim"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,addSpriteAnimC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"addAnim is read-only.");
          return 0;
        }
      },
      "changeAnimFramerate"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,changeAnimFramerateC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"changeAnimFramerate is read-only.");
          return 0;
        }
      },
      "animExists"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,animExistsC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"animExists is read-only.");
          return 0;
        }
      },
      "scrollFactorX"=>{ // TODO: sprite.scrollFactor.x
        defaultValue:sprite.scrollFactor.x,
        getter:function(l:State,data:Any){
          Lua.pushnumber(l,sprite.scrollFactor.x);
          return 1;
        },
        setter:function(l:State){
          if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
            LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
            return 0;
          }
          sprite.scrollFactor.set(Lua.tonumber(l,3),sprite.scrollFactor.y);
          LuaClass.DefaultSetter(l);
          return 0;
        }
      },
      "scrollFactorY"=>{ // TODO: sprite.scrollFactor.y
        defaultValue:sprite.scrollFactor.x,
        getter:function(l:State,data:Any){
          Lua.pushnumber(l,sprite.scrollFactor.y);
          return 1;
        },
        setter:function(l:State){
          if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
            LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
            return 0;
          }
          sprite.scrollFactor.set(sprite.scrollFactor.x,Lua.tonumber(l,3));
          LuaClass.DefaultSetter(l);
          return 0;
        }
      },

      "scaleX"=>{ // TODO: sprite.scale.x
        defaultValue:sprite.scale.x,
        getter:function(l:State,data:Any){
          Lua.pushnumber(l,sprite.scale.x);
          return 1;
        },
        setter:function(l:State){
          if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
            LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
            return 0;
          }
          sprite.scale.set(Lua.tonumber(l,3),sprite.scale.y);
          LuaClass.DefaultSetter(l);
          return 0;
        }
      },
      "scaleY"=>{ // TODO: sprite.scale.y
        defaultValue:sprite.scale.x,
        getter:function(l:State,data:Any){
          Lua.pushnumber(l,sprite.scale.y);
          return 1;
        },
        setter:function(l:State){
          if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
            LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
            return 0;
          }
          sprite.scale.set(sprite.scale.x,Lua.tonumber(l,3));
          LuaClass.DefaultSetter(l);
          return 0;
        }
      },

    ];
  }
  override function Register(l:State){
    state=l;
    super.Register(l);
  }
}

class LuaCam extends LuaClass {
  private static var state:State;
  public var camera:FlxCamera;
  private function SetNumProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
        LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      Reflect.setProperty(camera,Lua.tostring(l,2),Lua.tonumber(l,3));
      return 0;
  }

  private function GetNumProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushnumber(l,Reflect.getProperty(camera,Lua.tostring(l,2)));
      return 1;
  }

  private function SetBoolProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TBOOLEAN){
        LuaL.error(l,"invalid argument #3 (boolean expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      Reflect.setProperty(camera,Lua.tostring(l,2),Lua.toboolean(l,3));
      return 0;
  }

  private function GetBoolProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushboolean(l,Reflect.getProperty(camera,Lua.tostring(l,2)));
      return 1;
  }

  private function GetStringProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushstring(l,Reflect.getProperty(camera,Lua.tostring(l,2)));
      return 1;
  }

  private static var shakeC:cpp.Callable<StatePointer->Int> = cpp.Callable.fromStaticFunction(shake);
  private static var addShadersC:cpp.Callable<StatePointer->Int> = cpp.Callable.fromStaticFunction(addShaders);

  public function new(cam:FlxCamera,name:String,?addToGlobal:Bool=true){
    super();
    className=name;
    this.addToGlobal=addToGlobal;
    camera=cam;
    PlayState.currentPState.luaObjects[name]=cam;
    properties = [
      "className"=>{
        defaultValue:name,
        getter:function(l:State,data:Any){
          Lua.pushstring(l,name);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"className is read-only.");
          return 0;
        }
      },
      "x"=>{
        defaultValue:cam.x,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "y"=>{
        defaultValue:cam.y,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "width"=>{
        defaultValue:cam.width,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "height"=>{
        defaultValue:cam.height,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "zoom"=>{
        defaultValue:cam.zoom,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "angle"=>{
        defaultValue:cam.angle,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "alpha"=>{
        defaultValue:cam.alpha,
        getter:GetNumProperty,
        setter:SetNumProperty
      },
      "antialiasing"=>{
        defaultValue:cam.antialiasing,
        getter:GetBoolProperty,
        setter:SetBoolProperty
      },
      "filtersEnabled"=>{
        defaultValue:cam.filtersEnabled,
        getter:GetBoolProperty,
        setter:SetBoolProperty
      },
      "shake"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,shakeC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"shake is read-only.");
          return 0;
        }
      },
      "addShaders"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,addShadersC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"addShaders is read-only.");
          return 0;
        }
      },
    ];
  }
  override function Register(l:State){
    state=l;
    super.Register(l);
  }
}

class LuaNote extends LuaSprite {
  private static var state:State;
  public var id:String='0';

  override function Register(l:State){
    state=l;
    super.Register(l);
  }

  public function new(note:Note){
    super(note,'note${LuaStorage.notes.length}',true);
    id = Std.string(LuaStorage.notes.length);
    LuaStorage.notes.push(note);
    LuaStorage.noteIDs.set(note,id);
    LuaStorage.noteMap.set(id,note);

    properties.set("id",{
      defaultValue:id,
      getter:function(l:State,data:Any){
        Lua.pushstring(l,id);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"id is read-only.");
        return 0;
      }
    });

    properties.set("noteData",{
      defaultValue:note.noteData,
      getter:function(l:State,data:Any){
        Lua.pushnumber(l,note.noteData);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"noteData is read-only.");
        return 0;
      }
    });

    properties.set("strumTime",{
      defaultValue:note.strumTime,
      getter:function(l:State,data:Any){
        Lua.pushnumber(l,note.strumTime);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"strumTime is read-only.");
        return 0;
      }
    });

    properties.set("manualXOffset",{
      defaultValue:note.manualXOffset,
      getter:function(l:State,data:Any){
        Lua.pushnumber(l,note.manualXOffset);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"manualXOffset is read-only.");
        return 0;
      }
    });

    properties.set("wasGoodHit",{
      defaultValue:note.wasGoodHit,
      getter:function(l:State,data:Any){
        Lua.pushboolean(l,note.wasGoodHit);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"wasGoodHit is read-only.");
        return 0;
      }
    });

    properties.set("tooLate",{
      defaultValue:note.tooLate,
      getter:function(l:State,data:Any){
        Lua.pushboolean(l,note.tooLate);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"tooLate is read-only.");
        return 0;
      }
    });

    properties.set("sustainLength",{
      defaultValue:note.sustainLength,
      getter:function(l:State,data:Any){
        Lua.pushnumber(l,note.sustainLength);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"sustainLength is read-only.");
        return 0;
      }
    });

    properties.set("isSustainNote",{
      defaultValue:note.isSustainNote,
      getter:function(l:State,data:Any){
        Lua.pushboolean(l,note.isSustainNote);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"isSustainNote is read-only.");
        return 0;
      }
    });

    properties.set("mustPress",{
      defaultValue:note.mustPress,
      getter:function(l:State,data:Any){
        Lua.pushboolean(l,note.mustPress);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"mustPress is read-only.");
        return 0;
      }
    });


  }
}

class LuaReceptor extends LuaSprite {
  private static var state:State;

  override function SetNumProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
        LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      var key = Lua.tostring(l,2);
      if(key=='x')key='desiredX';
      if(key=='y')key='desiredY';
      Reflect.setProperty(sprite,key,Lua.tonumber(l,3));
      return 0;
  }
  override function GetNumProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      var key = Lua.tostring(l,2);
      if(key=='x')key='desiredX';
      if(key=='y')key='desiredY';
      Lua.pushnumber(l,Reflect.getProperty(sprite,key));
      return 1;
  }

  private function SetAngle(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
        LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      Reflect.setProperty(sprite,"desiredAngle",Lua.tonumber(l,3));
      return 0;
  }
  private function GetAngle(l:State,data:Any){
      // 1 = self
      Lua.pushnumber(l,Reflect.getProperty(sprite,"desiredAngle"));
      return 1;
  }

  override function Register(l:State){
    state=l;
    super.Register(l);
  }

  public function new(receptor:Receptor,name:String,?addToGlobal:Bool=true){
    super(receptor,name,addToGlobal);

    properties.set("incomingAngle",{
      defaultValue:receptor.incomingAngle,
      getter:GetNumProperty,
      setter:SetNumProperty
    });

    properties.set("incomingNoteAlpha",{
      defaultValue:receptor.incomingNoteAlpha,
      getter:GetNumProperty,
      setter:SetNumProperty
    });

    properties.set("x",{
      defaultValue:receptor.desiredX,
      getter:GetNumProperty,
      setter:SetNumProperty
    });

    properties.set("y",{
      defaultValue:receptor.desiredY,
      getter:GetNumProperty,
      setter:SetNumProperty
    });

    properties.set("alpha",{
      defaultValue:receptor.y,
      getter:GetNumProperty,
      setter:SetNumProperty
    });

    properties.set("angle",{
      defaultValue:receptor.desiredAngle,
      getter:GetAngle,
      setter:SetAngle
    });

    properties.set("defaultX",{
      defaultValue:receptor.defaultX,
      getter:GetNumProperty,
      setter:function(l:State){
        LuaL.error(l,"defaultX is read-only.");
        return 0;
      }
    });

    properties.set("defaultY",{
      defaultValue:receptor.defaultY,
      getter:GetNumProperty,
      setter:function(l:State){
        LuaL.error(l,"defaultY is read-only.");
        return 0;
      }
    });

  }
}

class LuaCharacter extends LuaSprite {
  private static var state:State;

  private static function swapCharacter(l:StatePointer){
    // 1 = self
    // 2 = character
    var char = LuaL.checkstring(state,2);
    Lua.getfield(state,1,"spriteName");
    var spriteName = Lua.tostring(state,-1);
    PlayState.currentPState.swapCharacterByLuaName(spriteName,char);

    return 0;
  }
  private static var swapCharacterC:cpp.Callable<StatePointer->Int> = cpp.Callable.fromStaticFunction(swapCharacter);

  public function new(character:Character,name:String,?addToGlobal:Bool=true){
    super(character,name,addToGlobal);
    properties.set("curCharacter",{
      defaultValue:character.curCharacter,
      getter:GetStringProperty,
      setter:function(l:State){
        LuaL.error(l,"curCharacter is read-only. Try calling 'changeCharacter'");
        return 0;
      }
    });
    properties.set("disabledDance",{
      defaultValue:character.disabledDance,
      getter:GetBoolProperty,
      setter:SetBoolProperty
    });
    properties.set("changeCharacter",{
      defaultValue:0,
      getter:function(l:State,data:Any){
        Lua.pushcfunction(l,swapCharacterC);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"changeCharacter is read-only.");
        return 0;
      }
    });
    properties.set("playAnim",{
      defaultValue:0,
      getter:function(l:State,data:Any){
        Lua.pushcfunction(l,playAnimC);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"playAnim is read-only.");
        return 0;
      }
    });
    properties.set("addOffset",{
      defaultValue:0,
      getter:function(l:State,data:Any){
        Lua.pushcfunction(l,addOffsetC);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"addOffset is read-only.");
        return 0;
      }
    });
    properties.set("leftToRight",{
      defaultValue:0,
      getter:function(l:State,data:Any){
        Lua.pushcfunction(l,leftToRightC);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"leftToRight is read-only.");
        return 0;
      }
    });
    properties.set("rightToLeft",{
      defaultValue:0,
      getter:function(l:State,data:Any){
        Lua.pushcfunction(l,rightToLeftC);
        return 1;
      },
      setter:function(l:State){
        LuaL.error(l,"rightToLeft is read-only.");
        return 0;
      }
    });
  }
  override function Register(l:State){
    state=l;
    super.Register(l);
  }
}

class LuaShaderClass extends LuaClass {
  private static var state:State;
  private var shader:GraphicsShader;
  private function SetNumProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
        LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      //Reflect.setProperty(effect,Lua.tostring(l,2),Lua.tonumber(l,3));
      return 0;
  }

  public function new(shader:GraphicsShader,shaderName:String,?addToGlobal=false){
    super();
    if(PlayState.currentPState.luaObjects.get(shaderName)!=null){
      var counter:Int = 0;
      while(PlayState.currentPState.luaObjects.get(shaderName + Std.string(counter))!=null){
        counter++;
      }
      shaderName+=Std.string(counter);
    }
    className = shaderName;
    this.addToGlobal=addToGlobal;
    this.shader=shader;
    PlayState.currentPState.luaObjects[shaderName]=shader;
    properties = [
      "className"=>{
        defaultValue:shaderName,
        getter:function(l:State,data:Any){
          Lua.pushstring(l,shaderName);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"className is read-only.");
          return 0;
        }
      },

      "setVar"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,setvarC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"setVar is read-only.");
          return 0;
        }
      },

      "getVar"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,getvarC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"getVar is read-only.");
          return 0;
        }
      },
    ];
  }

  override function Register(l:State){
    state=l;
    super.Register(l);
  }
}

class LuaModchart extends LuaClass {
  private static var state:State;
  private var modchart:ModChart;
  private var options:Options;
  private function SetNumProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TNUMBER){
        LuaL.error(l,"invalid argument #3 (number expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      Reflect.setProperty(modchart,Lua.tostring(l,2),Lua.tonumber(l,3));
      return 0;
  }

  private function SetStringProperty(l:State,data:Any){
    // 1 = self
    // 2 = key
    // 3 = value
    // 4 = metatable
    if(Lua.type(l,3)!=Lua.LUA_TSTRING){
      LuaL.error(l,"invalid argument #3 (string expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
      return 0;
    }
    Reflect.setProperty(modchart,Lua.tostring(l,2),Lua.tostring(l,3));
    return 0;
  }

  private function GetNumProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushnumber(l,Reflect.getProperty(modchart,Lua.tostring(l,2)));
      return 1;
  }

  private function SetBoolProperty(l:State){
      // 1 = self
      // 2 = key
      // 3 = value
      // 4 = metatable
      if(Lua.type(l,3)!=Lua.LUA_TBOOLEAN){
        LuaL.error(l,"invalid argument #3 (boolean expected, got " + Lua.typename(l,Lua.type(l,3)) + ")");
        return 0;
      }
      Reflect.setProperty(modchart,Lua.tostring(l,2),Lua.toboolean(l,3));
      return 0;
  }

  private function GetBoolProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushboolean(l,Reflect.getProperty(modchart,Lua.tostring(l,2)));
      return 1;
  }

  private function GetStringProperty(l:State,data:Any){
      // 1 = self
      // 2 = key
      // 3 = metatable
      Lua.pushstring(l,Reflect.getProperty(modchart,Lua.tostring(l,2)));
      return 1;
  }


  public function new(modchart:ModChart){
    super();
    this.modchart=modchart;
    className = 'modchart';
    properties = [
      "className"=>{
        defaultValue:className,
        getter:function(l:State,data:Any){
          Lua.pushstring(l,className);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"className is read-only.");
          return 0;
        }
      },
      "playerNotesFollowReceptors"=>{
        defaultValue: modchart.playerNotesFollowReceptors,
        getter:GetBoolProperty,
        setter:SetBoolProperty,
      },
      "opponentNotesFollowReceptors"=>{
        defaultValue: modchart.opponentNotesFollowReceptors,
        getter:GetBoolProperty,
        setter:SetBoolProperty,
      },
      "hudVisible"=>{
        defaultValue: modchart.hudVisible,
        getter:GetBoolProperty,
        setter:SetBoolProperty,
      },
      "opponentHPDrain"=>{
        defaultValue: modchart.opponentHPDrain,
        getter:GetNumProperty,
        setter:SetNumProperty,
      },

    ];
  }

  override function Register(l:State){
    state=l;
    super.Register(l);
  }
}

class LuaModMgr extends LuaClass {
  private static var state:State;
  private var manager:ModManager;

  /*
  private static function setScaleY(l:StatePointer):Int{
    // 1 = self
    // 2 = scale
    var scale = LuaL.checknumber(state,2);
    Lua.getfield(state,1,"spriteName");
    var spriteName = Lua.tostring(state,-1);
    var sprite = PlayState.currentPState.luaSprites[spriteName];
    sprite.scale.y = scale;
    return 0;
  }

  private static var setScaleYC:cpp.Callable<StatePointer->Int> = cpp.Callable.fromStaticFunction(setScaleY);
  */

  public function new(mgr:ModManager,?name="modMgr",?addToGlobal=true){
    super();
    className=name;
    this.addToGlobal=addToGlobal;
    this.manager=mgr;
    PlayState.currentPState.luaObjects[name]=mgr;
    properties = [
      "className"=>{
        defaultValue:className,
        getter:function(l:State,data:Any){
          Lua.pushstring(l,className);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"className is read-only.");
          return 0;
        }
      },
      "set"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,setC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"set is read-only.");
          return 0;
        }
      },
      "get"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,getC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"get is read-only.");
          return 0;
        }
      },
      "define"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,addBlankC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"define is read-only.");
          return 0;
        }
      },
      "queueSet"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,queueSetC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"queueSet is read-only.");
          return 0;
        }
      },
      "queueEase"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,queueEaseC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"queueEase is read-only.");
          return 0;
        }
      },
      "queueEaseL"=>{
        defaultValue:0,
        getter:function(l:State,data:Any){
          Lua.pushcfunction(l,queueEaseLC);
          return 1;
        },
        setter:function(l:State){
          LuaL.error(l,"queueEaseL is read-only.");
          return 0;
        }
      },
    ];
  }

  override function Register(l:State){
    state=l;
    super.Register(l);
  }
}
