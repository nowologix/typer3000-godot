@echo off
echo Clearing Godot cache...
rd /s /q ".godot\editor" 2>nul
rd /s /q ".godot\shader_cache" 2>nul
del /q ".godot\global_script_class_cache.cfg" 2>nul
echo Done! Now restart Godot.
pause
