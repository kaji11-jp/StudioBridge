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

return Config
