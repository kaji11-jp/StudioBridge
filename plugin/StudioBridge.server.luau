--!strict
-- StudioBridge Roblox Studio Plugin (Self-contained)
-- Automatically loaded from %LOCALAPPDATA%/Roblox/Plugins

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ScriptEditorService = game:GetService("ScriptEditorService")

--------------------------------------------------------------------------------
-- 1. Configuration
--------------------------------------------------------------------------------
local Config = {
  SERVER_URL = "http://127.0.0.1:34872",
  POLL_INTERVAL = 0.3, -- 300ms polling
  INPUT_DEBOUNCE = 0.4, -- 400ms typing debounce
  TREE_DEBOUNCE = 2.0, -- 2s tree export debounce
  TARGET_SERVICES = {
    "ReplicatedStorage",
    "ServerScriptService",
    "StarterPlayer"
  }
}

--------------------------------------------------------------------------------
-- 2. TreeExporter
--------------------------------------------------------------------------------
local TreeExporter = {}

local SERVICES_TO_EXPORT = {
  "Workspace",
  "ReplicatedStorage",
  "ServerScriptService",
  "ServerStorage",
  "StarterPlayer"
}

local function formatAttributes(instance: Instance): string
  local attrs = instance:GetAttributes()
  local parts = {}
  for key, value in pairs(attrs) do
    table.insert(parts, string.format("%s=%s", tostring(key), tostring(value)))
  end
  if #parts > 0 then
    return " (Attributes: " .. table.concat(parts, ", ") .. ")"
  end
  return ""
end

local function exportInstance(instance: Instance, indent: number, buffer: {string})
  local prefix = string.rep("  ", indent)
  local line = string.format("%s%s [%s]%s", prefix, instance.Name, instance.ClassName, formatAttributes(instance))
  table.insert(buffer, line)

  for _, child in ipairs(instance:GetChildren()) do
    if child.ClassName ~= "Terrain" then
      exportInstance(child, indent + 1, buffer)
    end
  end
end

function TreeExporter.generate(): string
  local buffer = {}
  for _, serviceName in ipairs(SERVICES_TO_EXPORT) do
    local service = game:FindService(serviceName)
    if service then
      exportInstance(service, 0, buffer)
    end
  end
  return table.concat(buffer, "\n")
end

--------------------------------------------------------------------------------
-- 3. SyncManager
--------------------------------------------------------------------------------
local SyncManager = {}
SyncManager.__index = SyncManager

function SyncManager.new()
  local self = setmetatable({}, SyncManager)
  self.connected = false
  self.isApplyingRemote = {} -- [Instance] = expiration_timestamp
  self.lastSyncedSource = {} -- [path] = string
  self.instancePaths = {} -- [Instance] = path
  self.trackedConnections = {} -- [Instance] = { RBXScriptConnection }
  self.pendingChanges = {}
  self.debounceTimer = nil
  return self
end

function SyncManager:getScriptPath(instance: Instance): string?
  if not instance or not instance.Parent then return nil end

  local parts = {}
  local current: Instance? = instance

  while current and current ~= game do
    table.insert(parts, 1, current.Name)
    current = current.Parent
  end

  local rootService = parts[1]
  local isTarget = false
  for _, target in ipairs(Config.TARGET_SERVICES) do
    if rootService == target then
      isTarget = true
      break
    end
  end

  if not isTarget then return nil end
  return table.concat(parts, "/") .. ".luau"
end

local function findOrCreateInstance(pathStr: string, className: string): (Instance?, Instance?)
  local cleanPath = string.gsub(pathStr, "%.luau$", "")
  local parts = string.split(cleanPath, "/")

  local serviceName = parts[1]
  local current: Instance? = game:FindService(serviceName)
  if not current then return nil, nil end

  for i = 2, #parts - 1 do
    local partName = parts[i]
    local child = current:FindFirstChild(partName)
    if not child then
      child = Instance.new("Folder")
      child.Name = partName
      child.Parent = current
    end
    current = child
  end

  local targetName = parts[#parts]
  local existing = current:FindFirstChild(targetName)

  if existing then
    return existing, current
  end

  local newInst: Instance
  if className == "LocalScript" then
    newInst = Instance.new("LocalScript")
  elseif className == "ModuleScript" then
    newInst = Instance.new("ModuleScript")
  else
    newInst = Instance.new("Script")
  end

  newInst.Name = targetName
  newInst.Parent = current
  return newInst, current
end

function SyncManager:applyUpsert(event)
  local instance = findOrCreateInstance(event.path, event.className or "Script")
  if not instance or not instance:IsA("LuaSourceContainer") then
    return
  end

  local source = event.source or ""
  self.lastSyncedSource[event.path] = source
  self.isApplyingRemote[instance] = os.clock() + 1.0
  self.instancePaths[instance] = event.path

  task.spawn(function()
    pcall(function()
      ScriptEditorService:UpdateSourceAsync(instance, function(_oldSource)
        return source
      end)
    end)
  end)
end

function SyncManager:applyDelete(event)
  local cleanPath = string.gsub(event.path, "%.luau$", "")
  local parts = string.split(cleanPath, "/")

  local current: Instance? = game:FindService(parts[1])
  if not current then return end

  for i = 2, #parts do
    current = current:FindFirstChild(parts[i])
    if not current then return end
  end

  if current and current:IsA("LuaSourceContainer") then
    self.isApplyingRemote[current] = os.clock() + 1.0
    self.instancePaths[current] = nil
    self.lastSyncedSource[event.path] = nil
    current:Destroy()
  end
end

function SyncManager:queueChange(event: { type: string, path: string, className: string?, source: string? })
  if not self.connected then return end

  if event.type == "upsert" and event.source then
    if self.lastSyncedSource[event.path] == event.source then
      return
    end
  end

  self.pendingChanges[event.path] = event

  if self.debounceTimer then
    task.cancel(self.debounceTimer)
  end

  self.debounceTimer = task.delay(Config.INPUT_DEBOUNCE or 0.4, function()
    self:flushChanges()
  end)
end

function SyncManager:flushChanges()
  local events = {}
  for _, ev in pairs(self.pendingChanges) do
    table.insert(events, ev)
    if ev.type == "upsert" and ev.source then
      self.lastSyncedSource[ev.path] = ev.source
    elseif ev.type == "delete" then
      self.lastSyncedSource[ev.path] = nil
    end
  end
  self.pendingChanges = {}
  self.debounceTimer = nil

  if #events == 0 then return end

  task.spawn(function()
    local success, response = pcall(function()
      return HttpService:RequestAsync({
        Url = Config.SERVER_URL .. "/push",
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode({ events = events })
      })
    end)

    if not success or not response.Success then
      warn("[StudioBridge] Failed to push changes to local bridge:", response and response.Body or "Network Error")
    end
  end)
end

function SyncManager:handleSourceChanged(instance: Instance, newSource: string)
  if not self.connected then return end
  if not instance:IsA("LuaSourceContainer") then return end

  local ignoreUntil = self.isApplyingRemote[instance]
  if ignoreUntil and os.clock() < ignoreUntil then
    return
  end

  local pathStr = self:getScriptPath(instance)
  if not pathStr then return end

  self.instancePaths[instance] = pathStr

  self:queueChange({
    type = "upsert",
    path = pathStr,
    className = instance.ClassName,
    source = newSource
  })
end

function SyncManager:handleInstanceRemoved(instance: Instance)
  if not self.connected then return end

  local pathStr = self.instancePaths[instance] or self:getScriptPath(instance)
  if not pathStr then return end

  self.instancePaths[instance] = nil

  local conns = self.trackedConnections[instance]
  if conns then
    for _, c in ipairs(conns) do
      c:Disconnect()
    end
    self.trackedConnections[instance] = nil
  end

  self:queueChange({
    type = "delete",
    path = pathStr
  })
end

function SyncManager:trackScript(instance: Instance)
  if not instance:IsA("LuaSourceContainer") then return end

  local pathStr = self:getScriptPath(instance)
  if not pathStr then return end

  self.instancePaths[instance] = pathStr

  if self.trackedConnections[instance] then
    for _, c in ipairs(self.trackedConnections[instance]) do
      c:Disconnect()
    end
  end

  local conns = {}

  table.insert(conns, instance:GetPropertyChangedSignal("Name"):Connect(function()
    local oldPath = self.instancePaths[instance]
    local newPath = self:getScriptPath(instance)

    if oldPath and newPath and oldPath ~= newPath then
      self.instancePaths[instance] = newPath
      self:queueChange({ type = "delete", path = oldPath })
      self:queueChange({
        type = "upsert",
        path = newPath,
        className = instance.ClassName,
        source = (instance :: any).Source
      })
    end
  end))

  table.insert(conns, instance:GetPropertyChangedSignal("Source"):Connect(function()
    self:handleSourceChanged(instance, (instance :: any).Source)
  end))

  self.trackedConnections[instance] = conns
end

function SyncManager:poll()
  if not self.connected then return end

  local success, response = pcall(function()
    return HttpService:RequestAsync({
      Url = Config.SERVER_URL .. "/poll",
      Method = "GET"
    })
  end)

  if success and response.Success then
    local data = HttpService:JSONDecode(response.Body)
    if data and data.events and #data.events > 0 then
      for _, ev in ipairs(data.events) do
        if ev.type == "upsert" then
          self:applyUpsert(ev)
        elseif ev.type == "delete" then
          self:applyDelete(ev)
        end
      end
    end
  end
end

function SyncManager:exportAll(): boolean
  local scripts = {}

  for _, serviceName in ipairs(Config.TARGET_SERVICES) do
    local service = game:FindService(serviceName)
    if service then
      for _, desc in ipairs(service:GetDescendants()) do
        if desc:IsA("LuaSourceContainer") then
          local p = self:getScriptPath(desc)
          if p then
            local src = (desc :: any).Source
            self.lastSyncedSource[p] = src
            self.instancePaths[desc] = p
            table.insert(scripts, {
              path = p,
              className = desc.ClassName,
              source = src
            })
          end
        end
      end
    end
  end

  local success, response = pcall(function()
    return HttpService:RequestAsync({
      Url = Config.SERVER_URL .. "/export",
      Method = "POST",
      Headers = { ["Content-Type"] = "application/json" },
      Body = HttpService:JSONEncode({ scripts = scripts })
    })
  end)

  return success and response.Success
end

--------------------------------------------------------------------------------
-- 4. Main Plugin UI & Lifecycle
--------------------------------------------------------------------------------
local sync = SyncManager.new()

local toolbar = plugin:CreateToolbar("StudioBridge")
local toggleButton = toolbar:CreateButton(
  "StudioBridge",
  "Toggle StudioBridge bi-directional sync",
  "rbxassetid://4458901886"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
  Enum.InitialDockState.Right,
  false,
  false,
  240,
  200,
  200,
  150
)
local widget = plugin:CreateDockWidgetPluginGui("StudioBridgeGui", widgetInfo)
widget.Title = "StudioBridge Sync"

local frame = Instance.new("Frame")
frame.Size = UDim2.new(1, 0, 1, 0)
frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
frame.Parent = widget

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 30)
statusLabel.Position = UDim2.new(0, 10, 0, 10)
statusLabel.Text = "Status: Disconnected"
statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.SourceSansBold
statusLabel.TextSize = 16
statusLabel.Parent = frame

local connectButton = Instance.new("TextButton")
connectButton.Size = UDim2.new(1, -20, 0, 35)
connectButton.Position = UDim2.new(0, 10, 0, 45)
connectButton.Text = "Connect"
connectButton.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
connectButton.TextColor3 = Color3.fromRGB(255, 255, 255)
connectButton.Font = Enum.Font.SourceSansBold
connectButton.TextSize = 14
connectButton.Parent = frame

local pullButton = Instance.new("TextButton")
pullButton.Size = UDim2.new(1, -20, 0, 35)
pullButton.Position = UDim2.new(0, 10, 0, 90)
pullButton.Text = "Pull from Studio (Export to Local)"
pullButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
pullButton.TextColor3 = Color3.fromRGB(220, 220, 220)
pullButton.Font = Enum.Font.SourceSans
pullButton.TextSize = 14
pullButton.Parent = frame

toggleButton.Click:Connect(function()
  widget.Enabled = not widget.Enabled
end)

local function setupServiceListeners()
  for _, serviceName in ipairs(Config.TARGET_SERVICES) do
    local service = game:FindService(serviceName)
    if service then
      for _, desc in ipairs(service:GetDescendants()) do
        if desc:IsA("LuaSourceContainer") then
          sync:trackScript(desc)
        end
      end

      service.DescendantAdded:Connect(function(desc)
        if desc:IsA("LuaSourceContainer") then
          sync:trackScript(desc)
          if sync.connected then
            task.delay(0.1, function()
              if desc.Parent and sync.connected then
                sync:handleSourceChanged(desc, (desc :: any).Source)
              end
            end)
          end
        elseif desc:IsA("Folder") then
          desc:GetPropertyChangedSignal("Name"):Connect(function()
            for _, child in ipairs(desc:GetDescendants()) do
              if child:IsA("LuaSourceContainer") then
                sync:trackScript(child)
                if sync.connected then
                  sync:handleSourceChanged(child, (child :: any).Source)
                end
              end
            end
          end)
        end
      end)

      service.DescendantRemoving:Connect(function(desc)
        if desc:IsA("LuaSourceContainer") then
          sync:handleInstanceRemoved(desc)
        end
      end)
    end
  end
end

setupServiceListeners()

ScriptEditorService.TextDocumentDidChange:Connect(function(document)
  if not sync.connected then return end
  local scriptInstance = document:GetScript()
  if not scriptInstance then return end

  local success, text = pcall(function()
    return document:GetText()
  end)
  if success and text then
    sync:handleSourceChanged(scriptInstance, text)
  end
end)

local function setConnected(connected: boolean)
  sync.connected = connected
  if connected then
    statusLabel.Text = "Status: Connected"
    statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    connectButton.Text = "Disconnect"
    connectButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
  else
    statusLabel.Text = "Status: Disconnected"
    statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    connectButton.Text = "Connect"
    connectButton.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
  end
end

connectButton.MouseButton1Click:Connect(function()
  if not sync.connected then
    local success, response = pcall(function()
      return HttpService:RequestAsync({
        Url = Config.SERVER_URL .. "/health",
        Method = "GET"
      })
    end)

    if success and response.Success then
      setConnected(true)
      print("[StudioBridge] Connected to Local Bridge Server.")

      task.spawn(function()
        pcall(function()
          local tree = TreeExporter.generate()
          HttpService:RequestAsync({
            Url = Config.SERVER_URL .. "/tree",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ tree = tree })
          })
        end)
      end)
    else
      warn("[StudioBridge] Could not connect to local server at " .. Config.SERVER_URL)
    end
  else
    setConnected(false)
    print("[StudioBridge] Disconnected.")
  end
end)

pullButton.MouseButton1Click:Connect(function()
  if not sync.connected then
    warn("[StudioBridge] Please connect first before pulling.")
    return
  end
  local ok = sync:exportAll()
  if ok then
    print("[StudioBridge] Successfully exported all scripts to local folder.")
  else
    warn("[StudioBridge] Export failed.")
  end
end)

task.spawn(function()
  while true do
    if sync.connected then
      sync:poll()
    end
    task.wait(Config.POLL_INTERVAL)
  end
end)

local logQueue = {}
LogService.MessageOut:Connect(function(message, messageType)
  if not sync.connected then return end

  local level = "INFO"
  if messageType == Enum.MessageType.MessageWarning then
    level = "WARN"
  elseif messageType == Enum.MessageType.MessageError then
    level = "ERROR"
  end

  local timestamp = os.date("%H:%M:%S")
  table.insert(logQueue, {
    timestamp = timestamp,
    level = level,
    message = message
  })
end)

task.spawn(function()
  while true do
    if sync.connected and #logQueue > 0 then
      local batch = logQueue
      logQueue = {}
      pcall(function()
        HttpService:RequestAsync({
          Url = Config.SERVER_URL .. "/logs",
          Method = "POST",
          Headers = { ["Content-Type"] = "application/json" },
          Body = HttpService:JSONEncode({ logs = batch })
        })
      end)
    end
    task.wait(0.5)
  end
end)
