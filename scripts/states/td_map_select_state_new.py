
import sys
content = chr(35)*2 + " td_map_select_state.gd" + chr(10)
content += chr(35)*2 + " Tower Defence map selection screen" + chr(10)
content += "extends Control" + chr(10)*2
# ... rest of file
with open("scripts/states/td_map_select_state.gd", "w", encoding="utf-8") as out:
    out.write(content)
