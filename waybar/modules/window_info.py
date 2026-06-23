import json
import subprocess
import os
from gi.repository import Gio

def get_focused_window():
    try:
        res = subprocess.check_output(["niri", "msg", "-j", "windows"], stderr=subprocess.DEVNULL)
        windows = json.loads(res)
        for w in windows:
            if w.get("is_focused"):
                return w
    except:
        pass
    return None

def get_app_info(app_id):
    if not app_id:
        return "Desktop", "󰇄"
    
    # Try to find the app in the system's application database
    # Most Wayland apps use their desktop file name as the app_id
    app_info = None
    
    # 1. Try direct lookup (app_id usually matches the desktop file name)
    desktop_id = app_id if app_id.endswith(".desktop") else f"{app_id}.desktop"
    app_info = Gio.DesktopAppInfo.new(desktop_id)
    
    # 2. If direct lookup fails, try case-insensitive and fuzzy matching
    if not app_info:
        all_apps = Gio.AppInfo.get_all()
        app_id_lower = app_id.lower()
        for info in all_apps:
            info_id = info.get_id().lower()
            if app_id_lower in info_id or info_id in app_id_lower:
                app_info = info
                break
                
    if app_info:
        name = app_info.get_name()
        
        # Determine a Nerd Font icon based on categories or name
        categories = ""
        if hasattr(app_info, 'get_categories'):
            categories = app_info.get_categories() or ""
            
        icon_map = {
            "WebBrowser": "",
            "TerminalEmulator": "",
            "FileManager": "󰉋",
            "Development": "󰨞",
            "Game": "󰓓",
            "Settings": "󰒓",
            "AudioVideo": "󰕼",
            "Audio": "󰓃",
            "Video": "󰐌",
            "Office": "󰏆",
            "Graphics": "",
            "Network": "󰖟",
            "Chat": "󰭹",
            "Email": "󰭹"
        }
        
        # Specific overrides for common apps where categories might be too broad
        specific_map = {
            "firefox": "",
            "code": "󰨞",
            "nautilus": "󰉋",
            "spotify": "",
            "discord": "󰙯",
            "alacritty": "",
            "kitty": "",
            "chrome": ""
        }
        
        # 1. Check specific map
        for key, icon in specific_map.items():
            if key in app_id.lower() or key in name.lower():
                return name, icon
                
        # 2. Check categories
        for cat, icon in icon_map.items():
            if cat in categories:
                return name, icon
                
        # 3. Fallback to a generic app icon
        return name, "󰀻"

    # Fallback for when no .desktop file is found
    name = app_id.split('.')[-1].capitalize()
    return name, "󰇄"

focused = get_focused_window()
if focused:
    app_id = focused.get("app_id", "")
    title = focused.get("title", "")
    
    # Special handling for terminal tools (where app_id is just the terminal)
    if app_id == "Alacritty" and title:
        name = title
        # Try to guess icon from title
        if "btop" in title.lower(): icon = "󰻠"
        elif "nmtui" in title.lower(): icon = "󰤨"
        elif "wallpaper" in title.lower(): icon = "󰸉"
        else: icon = ""
    else:
        name, icon = get_app_info(app_id)
    
    print(json.dumps({"text": f"{icon} {name}", "class": app_id}))
else:
    print(json.dumps({"text": "󰇄 Desktop", "class": "desktop"}))
