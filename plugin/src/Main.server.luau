local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Config = require(script.Parent.Config)
local TreeExporter = require(script.Parent.TreeExporter)
local SyncManager = require(script.Parent.SyncManager)

local sync = SyncManager.new()

-- UI Setup
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

-- Simple UI Frame
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

-- Initialize listeners for all target services
local function setupServiceListeners()
  for _, serviceName in ipairs(Config.TARGET_SERVICES) do
    local service = game:FindService(serviceName)
    if service then
      -- Track existing scripts
      for _, desc in ipairs(service:GetDescendants()) do
        if desc:IsA("LuaSourceContainer") then
          sync:trackScript(desc)
        end
      end

      -- Track newly added instances
      service.DescendantAdded:Connect(function(desc)
        if desc:IsA("LuaSourceContainer") then
          sync:trackScript(desc)
          -- If added while connected, send creation to local
          if sync.connected then
            task.delay(0.1, function()
              if desc.Parent and sync.connected then
                sync:handleSourceChanged(desc, (desc :: any).Source)
              end
            end)
          end
        elseif desc:IsA("Folder") then
          -- Watch folder rename to update child paths
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

      -- Track removed instances
      service.DescendantRemoving:Connect(function(desc)
        if desc:IsA("LuaSourceContainer") then
          sync:handleInstanceRemoved(desc)
        end
      end)
    end
  end
end

setupServiceListeners()

-- 1. ScriptEditorService.TextDocumentDidChange listener for real-time keystroke sync
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

-- Connection Handling
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

      -- Send initial tree
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

-- Polling Loop
task.spawn(function()
  while true do
    if sync.connected then
      sync:poll()
    end
    task.wait(Config.POLL_INTERVAL)
  end
end)

-- Log Bridge
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

-- Log Flush Loop (every 500ms)
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
