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
    -- Skip non-essential runtime clutter or huge terrain blocks
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

return TreeExporter
