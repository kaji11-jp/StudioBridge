local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Config = require(script.Parent.Config)

local SyncManager = {}
SyncManager.__index = SyncManager

function SyncManager.new()
  local self = setmetatable({}, SyncManager)
  self.connected = false
  self.isApplyingRemote = {} -- [Instance] = expiration_timestamp
  self.lastSyncedSource = {} -- [path] = string
  self.instancePaths = {} -- [Instance] = path
  self.trackedConnections = {} -- [Instance] = { RBXScriptConnection }

  self.pendingChanges = {} -- path -> { type = "upsert"|"delete", path = string, className = string?, source = string? }
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
  self.isApplyingRemote[instance] = os.clock() + 1.0 -- Ignore local echoes for 1s
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

-- Queue and Debounce Studio -> Local push
function SyncManager:queueChange(event: { type: string, path: string, className: string?, source: string? })
  if not self.connected then return end

  -- Echo suppression: check if source is identical to what we last received/sent
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

  -- Cleanup listeners
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

  -- Watch Name property changes
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

  -- Watch Source property (fallback for external modifications)
  table.insert(conns, instance:GetPropertyChangedSignal("Source"):Connect(function()
    self:handleSourceChanged(instance, (instance :: any).Source)
  end))

  self.trackedConnections[instance] = conns
end

function SyncManager:poll(onPollEvents)
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
      if onPollEvents then
        onPollEvents(data.events)
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

return SyncManager
