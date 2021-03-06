local _NAME = "openLuup.plugins"
local revisionDate = "2016.03.05"
local banner = "  version " .. revisionDate .. "  @akbooer"

--
-- create/delete plugins
--  

local logs          = require "openLuup.logs"
local lfs           = require "lfs"             -- for portable mkdir and dir

local pathSeparator = package.config:sub(1,1)   -- thanks to @vosmont for this Windows/Unix discriminator
                            -- although since lfs (luafilesystem) accepts '/' or '\', it's not necessary

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control


-- ALTUI

local DEFAULT_ALTUI = 1471

-- invoked by
-- /data_request?id=action&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=CreatePlugin&PluginNum=8246&TracRev=1237


local InstalledPlugins2 = {}


--[[
{

    "Version": 28706,
    "AllowMultiple": "0",
    "Title": "Alternate UI",
    "Icon": "plugins/icons/8246.png",
    "Instructions": "http://forum.micasaverde.com/index.php/board,78.0.html",
    "Hidden": "0",
    "AutoUpdate": "1",
    "VersionMajor": "0",
    "VersionMinor": "67",
    "SupportedPlatforms": null,
    "MinimumVersion": null,
    "DevStatus": null,
    "Approved": "0",
    "id": 8246,
    "TargetVersion": "28706",
    "timestamp": 1441211941,

    "Files": 

[

{

    "SourceName": "iconALTUI.png",
    "SourcePath": null,
    "DestName": "iconALTUI.png",
    "DestPath": "",
    "Compress": "0",
    "Encrypt": "0",
    "Role": "M"   -- Device, Service, JavaScript (or JSON) 

},
{

    "SourceName": "I_ALTUI.xml",
    "SourcePath": null,
    "DestName": "I_ALTUI.xml",
    "DestPath": "",
    "Compress": "1",
    "Encrypt": "0",
    "Role": "I"

}
    ],
"Devices": 
[

    {
        "DeviceFileName": "D_ALTUI.xml",
        "DeviceType": "urn:schemas-upnp-org:device:altui:1",
        "ImplFile": "I_ALTUI.xml",
        "Invisible": "0",
        "CategoryNum": "1"
    }

],
"Lua": 
[

{

    "FileName": "L_ALTUI.lua"

},

        {
            "FileName": "L_ALTUIjson.lua"
        }
    ],
},
--]]

local altui_downloads = table.concat ({"plugins", "downloads", "altui", ''}, pathSeparator)
local altui_backup    = table.concat ({"plugins", "backup"   , "altui", ''}, pathSeparator)

local Vmajor, Vminor

local function get_from_trac (rev, subdir)
  subdir = subdir or ''
  local mios = "http://code.mios.com/"
  local trac = "/trac/mios_alternate_ui/"
  local valid_extension = {
    js    = true,
    json  = true, 
    lua   = true,
    png   = true,
    xml   = true,
  }

  local url = table.concat {mios, trac, "browser/", subdir}
  --local url = "http://code.mios.com/trac/mios_alternate_ui/browser/blockly"
  local ver = ''
  if rev then ver = "?rev=" ..rev end

  local s,x = luup.inet.wget (url .. ver)
  if s ~= 0 then return false end

  local files = {}
  local pattern = table.concat {'href="', trac, "browser/", subdir, "([%w%-%._/]+)"}
  for fname in x: gmatch (pattern) do
    local ext = fname: match "%.(%w+)$"
    if valid_extension[ext] then
      files [#files+1] = fname
    end
  end

  local root = table.concat {mios, trac, "export/", rev, '/', subdir}
  local ok
  for _,fname in ipairs (files) do
    local b = root .. fname
    local content
    ok, content = luup.inet.wget (b)
    if ok ~= 0 then _log ("ERROR - HTTP code: " .. (ok or '?')) return false end
    _log (("%-8d %s"): format (#content, fname))
    if fname == "L_ALTUI.lua" then
      Vmajor, Vminor = content: match [[local%s+version%s+=%s+%"%a+(%d+)%.(%d+)]]
      if Vminor then
        _log (table.concat {"version = ",Vmajor, '.', Vminor})
      end
    end
    if fname == "J_ALTUI_uimgr.js" then
      _log ("patching revision number to " .. rev)
      content = content: gsub ("%$Revision%$", "$Revision: " .. rev .. " $")
    end
    local f = io.open (altui_downloads .. fname, 'w')
    if f then
      f: write (content)
      f: close ()
    else
      _log "error writing file"
      return false
    end
  end
  
  return files
end

local function file_copy (source, dest)
  local directory = "%.$"
  if (source: match (directory)) or (dest: match (directory)) then
    return nil, "filecopy: won't copy directory files!"
  end
  local f, msg, content
  f, msg = io.open (source, 'r')
  if f then
    content = f: read "*a"
    f: close ()
    f, msg = io.open (dest, 'w+')
    if f then
      f: write (content)
      f: close ()
    end
  end
  local bytes = content and #content or 0
  return not msg, msg, bytes 
end

local function mkdir_tree (path)
  local i = 1
  repeat -- work along path creating directories if necessary
    local _,j = path: find ("%w+", i)
    if j then
      local dir = path:sub (1,j)
      lfs.mkdir (dir)
      i = j + 1
    end
  until not j
end

local function update_altui (p)
  local rev =  tonumber (p.TracRev) or DEFAULT_ALTUI
  _log "backing up AltUI plugin"
  mkdir_tree (altui_backup)
  for file in lfs.dir "." do
    if file: match "ALTUI" then
      file_copy (file, altui_backup .. file)
    end
  end

  _log ("downloading ALTUI rev " .. rev) 
  mkdir_tree (altui_downloads)

  -- get ALTUI and blockly sub-directory
  local afiles = get_from_trac (rev)
  if not afiles then return false end
  
  local bfiles = get_from_trac (rev, "blockly/")
  if not bfiles then return false end
  
  
  local function update_installed_plugins (afiles, bfiles)
    
    local function file_list (F, files)
      for _, f in ipairs(files) do
        F[#F+1] = {
          SourceName = f,
  --      "SourcePath": null,
        DestName =  f,
        DestPath = "",
  --      "Compress": "0",
  --      "Encrypt": "0",
  --      "Role": "M"   -- Device, Service, JavaScript (or JSON) 
        }
      end
    end

    local files = {}
    file_list (files, afiles)
    file_list (files, bfiles)
    InstalledPlugins2[1] =      -- we'll always put ALTUI in pole position!
      {
        AllowMultiple   = "0",
        Title           = "Alternate UI",
        Icon            = "http://code.mios.com/trac/mios_alternate_ui/export/12/iconALTUI.png",
        Instructions    = "http://forum.micasaverde.com/index.php/board,78.0.html",
        Hidden          = "0",
        AutoUpdate      = "1",
  --      Version         = 28706,
        VersionMajor    = Vmajor or '?',
        VersionMinor    = Vminor or '?',
  --      "SupportedPlatforms": null,
  --      "MinimumVersion": null,
  --      "DevStatus": null,
  --      "Approved": "0",
        id              = 8246,
  --      "TargetVersion": "28706",
        timestamp       = os.time(),
        Files           = files,
      }
  end
  
  local function install_altui_if_missing ()
    
    local function install ()
      local upnp_impl, ip, mac, hidden, invisible, parent, room
      local pluginnum = 8246
      luup.create_device ('', "ALTUI", "ALTUI", "D_ALTUI.xml", 
        upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum)  
    end
    
    local function missing ()
      for _, d in pairs (luup.devices) do
        if (d.device_num_parent == 0)     -- local device!!
        and (d.device_type == "urn:schemas-upnp-org:device:altui:1") then
          return false    -- it's not missing
        end
      end
      return true   -- it IS missing
    end
    
    if missing() then install() end
  end
  
  
  _log "installing new version"
  for file in lfs.dir (altui_downloads) do
    if file: match "ALTUI" then
      local ok, msg, bytes = file_copy (altui_downloads .. file, file)
      if ok then
        msg = ("%-8d %s"):format (bytes, file)
        _log (msg)
      else
        _log ("ERROR installing " .. file)
      end
    end
  end


--  update_installed_plugins (afiles, bfiles)   -- TODO: re-instate at some future time, perhaps?
  install_altui_if_missing ()
  luup.reload ()
end

-- return true if successful, false if not.
local function create (p)
  if tonumber (p.PluginNum) == 8246 then 
    return update_altui (p) 
  end
  return false
end

local function delete ()
  _log "Can't delete plugin"
  return false
end

-- set or retrieve installed plugins info
local function installed (info)
  InstalledPlugins2 = info or InstalledPlugins2
  return InstalledPlugins2
end


return {
  create    = create,
  delete    = delete,
  installed = installed,
}

