-- This script is an EdgeTX Lua widget designed to find and display the "VTX Admin" field's value
-- by directly communicating with the ELRS transmission module via CRSF telemetry.
-- Copyright (c) 2026 KozakFPV (Nobumichi Kozawa)
-- Version: 1.1 (ELRS 4.x compatible)

local DEBUG_LOG_FILE = "/WIDGETS/ELRSVTX/debug.log"

local options = {
  { "TextColor", COLOR, YELLOW},
  { "TextSize", TEXT_SIZE, STD},
  { "TextAlign", ALIGNMENT, LEFT},
  { "TextMargin", VALUE, 1, 0, 10}
}

local function log(s)
  --[[
  local file, err = io.open(DEBUG_LOG_FILE, "a") -- Open in append mode
  if file then
    io.write(file, s .. "\n")
    io.close(file)
  else
    print("LOG_ERROR: Could not write to " .. DEBUG_LOG_FILE .. ": " .. tostring(err))
    print("DEBUG: " .. s)
  end
  ]]
end

-- Constants for ELRS device and handset IDs

local ELRS_DEVICE_ID = 0xEE -- ELRS TX module ID
local EDGETX_HANDSET_ID = 0xEF -- EdgeTX Lua script handset ID (CRSF_ADDRESS_ELRS_LUA)

-- Field type constants (per ELRS Lua parameter protocol)
local TYPE_FOLDER = 11 -- FOLDER
local TYPE_TEXT_SELECTION = 9
local TYPE_UINT8 = 0

local HIDDEN_MASK = 0x80 -- 0x80 bit in the type byte: field is hidden
local TYPE_MASK = 0x7f

local BAND_NAMES = { "A", "B", "E", "F", "R", "L" }

-- Mock crossfireTelemetry functions for local testing.
-- When run on an EdgeTX radio, the global 'crossfireTelemetryPush' and 'crossfireTelemetryPop'
-- functions will be available for CRSF communication.
local crossfireTelemetryPush = crossfireTelemetryPush or function(cmd, data)
  log(string.format("crossfireTelemetryPush: cmd=0x%X, data={%s}", cmd, table.concat(data, ", ")))
end
local crossfireTelemetryPop = crossfireTelemetryPop or function()
  -- For local testing, you would manually inject mock CRSF responses here
  -- to simulate data coming from the ELRS module.
  return nil, nil
end

-- Mock getTime function for local testing.
-- When run on an EdgeTX radio, the global 'getTime' function will return the current time in ms.
local getTime = getTime or os.time -- Fallback to os.time for basic local time simulation

-- Helper function to convert a byte array to a string, stopping at the first null terminator (0).
-- Returns the extracted string and the index of the byte *after* the null terminator.
local function bytes_to_string(byte_array, start_index)
  local str = ""
  local index = start_index
  while byte_array[index] ~= nil and byte_array[index] ~= 0 do
    str = str .. string.char(byte_array[index])
    index = index + 1
  end
  return str, index + 1 -- Returns a string and a number
end

-- Append data[from..to] into buffer.
local function append_range(buffer, data, from, to)
  for i = from, to do
    buffer[#buffer + 1] = data[i]
  end
end

local function create(zone, options)
  local wgt = {
    zone = zone,
    options = options,
    vtx_admin_value = "Loading...",
    band = "", -- fallback parsed from the Band/Enable child field (ELRS 4.x)
    channel = 0, -- fallback parsed from the Channel child field
    fields_count = 0,
    current_field_id = 1,
    receiving_field_id = 0, -- field id that the current chunk buffer belongs to (0 = none)
    received_chunks = 0, -- number of chunks received for receiving_field_id
    chunk_buffer = nil, -- reassembly buffer for a chunked PARAMETER_SETTINGS_ENTRY
    vtx_folder_id = 0, -- field id of the VTX Admin folder, once found
    dyn_name_found = false, -- dynamic folder name already provided the display value
    state = "INIT", -- INIT, REQUEST_DEVICE_INFO, PROCESS_DEVICE_INFO, REQUEST_FIELD_INFO, PROCESS_FIELD_INFO, DONE
    last_request_time = 0,
    request_interval = 100, -- Minimum interval (ms) between telemetry requests to avoid flooding
  }
  log("Widget created.")

  -- Force initial request immediately from create function
  wgt.state = "REQUEST_DEVICE_INFO"
  wgt.last_request_time = 0
  crossfireTelemetryPush(0x28, { 0x00, 0xEA }) -- Request device info (parameter ping; src = EdgeTX handset address)
  wgt.state = "PROCESS_DEVICE_INFO" -- Transition to waiting for response
  wgt.last_request_time = getTime()
  log("Initial Device Info request sent from create().")

  return wgt
end

local function update(wgt, options)
  if (wgt == nil) then
    return
  end
  wgt.options = options
  log("Widget updated.")
end

-- ELRS 4.x fills the folder entry's name slot with the dynamic name when the
-- band is enabled ("VTX Admin (R:4:500mW)"), and falls back to the static
-- name "VTX Administrator" (no dynamic part) when the band is Disabled/off.
local function isVtxAdminName(name)
  return name ~= nil and string.find(name, "VTX Admin", 1, true) ~= nil
end

-- Value carried by the folder dynamic name, e.g. "R:4:500mW" for "(R:4:500mW)"
local function valueFromDynName(wgt, name_str)
  local start_idx = string.find(name_str, "%(") -- Find the opening parenthesis
  local end_idx = string.find(name_str, "%)")   -- Find the closing parenthesis
  if start_idx and end_idx and start_idx < end_idx then
    wgt.vtx_admin_value = string.sub(name_str, start_idx + 1, end_idx - 1)
    wgt.dyn_name_found = true
    wgt.state = "DONE" -- Found the target, can stop searching
    log(string.format("Found VTX Admin and extracted value: %s", wgt.vtx_admin_value))
    return true
  end
  return false
end

-- ELRS 4.x fallback: when the band is Disabled the folder has no dynamic name.
-- The current state then comes from the folder's child fields:
--   "Band"/"Band/Enable" (TEXT_SELECTION): 1-based index, value 0 = Disabled
--   "Channel" (UINT8): 1-based values (min = 1)
-- Mirror of EasyVTXch's ELRS 4.x handling.
local function isBandFieldName(name)
  return name == "Band" or name == "Band/Enable"
end

local function setCurrentFromChildFields(wgt)
  if wgt.band == "" then
    wgt.vtx_admin_value = "OFF"
  elseif wgt.channel == 0 then
    wgt.vtx_admin_value = wgt.band .. ":?"
  else
    wgt.vtx_admin_value = wgt.band .. ":" .. wgt.channel
  end
end

-- Parse one complete PARAMETER_SETTINGS_ENTRY payload (after reassembly).
-- payload: [parent][type][name\0][type-specific data...]
local function processFieldPayload(wgt, fieldId, payload)
  local parent = payload[5]
  local field_type = bit32.band(payload[6], TYPE_MASK) -- Extract field type (lower 7 bits)
  local hidden = bit32.band(payload[6], HIDDEN_MASK) ~= 0
  local name_str, name_end_idx = bytes_to_string(payload, 7)

  log(string.format("Processing Field ID: %d, Name: '%s', Type: %d", fieldId, name_str, field_type))

  if parent == 0 and field_type == TYPE_FOLDER and isVtxAdminName(name_str) then
    wgt.vtx_folder_id = fieldId
    if valueFromDynName(wgt, name_str) then
      return true -- done, dynamic name contained the current band/channel
    end
    log("VTX Admin folder found without dynamic name (band disabled on ELRS 4.x)")
    wgt.vtx_admin_value = "OFF"
    -- Keep enumerating: the child fields let us rebuild the state once the
    -- band is re-enabled, and re-apply after a full scan below.
  end

  -- Track VTX folder children for the fallback display
  if wgt.vtx_folder_id ~= 0 and parent == wgt.vtx_folder_id and not hidden then
    local n = string.lower(name_str)
    if isBandFieldName(name_str) and field_type == TYPE_TEXT_SELECTION then
      -- TEXT_SELECTION layout: [name][options][value][min][max]
      local _, options_end = bytes_to_string(payload, name_end_idx)
      local value = payload[options_end]
      if type(value) == "number" and value >= 1 and value <= #BAND_NAMES then
        wgt.band = BAND_NAMES[value]
      end
    elseif n == "channel" and field_type == TYPE_UINT8 then
      -- UINT8 layout: [name][value][min][max]; value is 1-based
      local v = payload[name_end_idx]
      if type(v) == "number" then
        local min = payload[name_end_idx + 1] or 1
        wgt.channel = v - min + 1
      end
    end
  end
  return false
end

-- Handle one PARAMETER_SETTINGS_ENTRY (0x2B) frame. Returns true when the
-- widget has everything it needs (or enumeration is complete).
local function processParamResponse(wgt, data)
  local fieldId = data[3]
  local chunks_remain = data[4]

  -- Only accept the field currently being read; chunk frames carry the same id.
  if fieldId ~= wgt.current_field_id then
    return false
  end

  if chunks_remain > 0 then
    -- ELRS 4.x splits entries larger than the link's packet size into chunks
    -- (fieldId + chunksRemaining header, then payload); continuation frames
    -- are fetched by re-reading the same field with the next chunk index.
    if wgt.receiving_field_id ~= fieldId then
      wgt.receiving_field_id = fieldId
      wgt.received_chunks = 0
      -- Keep the frame's 4 header bytes (dest, src, fieldId, chunks) so the
      -- assembled buffer has the same layout as a single-frame response
      wgt.chunk_buffer = { data[1], data[2], data[3], data[4] }
    end
    wgt.received_chunks = wgt.received_chunks + 1
    append_range(wgt.chunk_buffer, data, 5, #data)
    wgt.state = "PROCESS_FIELD_INFO" -- keep requesting continuation chunks
    wgt.last_request_time = 0 -- request the next chunk immediately
    return false
  end

  -- Final (only) chunk: assemble the complete payload
  local payload
  if wgt.chunk_buffer ~= nil and wgt.receiving_field_id == fieldId then
    append_range(wgt.chunk_buffer, data, 5, #data)
    payload = wgt.chunk_buffer
  else
    payload = data
  end
  wgt.receiving_field_id = 0
  wgt.received_chunks = 0
  wgt.chunk_buffer = nil

  local done = processFieldPayload(wgt, fieldId, payload)

  -- Move to the next field ID for the next request
  wgt.current_field_id = wgt.current_field_id + 1
  if wgt.current_field_id > wgt.fields_count then
    wgt.state = "DONE" -- All fields processed
    if wgt.vtx_folder_id == 0 then
      wgt.vtx_admin_value = "VTX Admin field not found."
      log("VTX Admin field not found after checking all fields (state DONE).")
    else
      if not wgt.dyn_name_found then
        setCurrentFromChildFields(wgt) -- complete state from Band/Enable + Channel (4.x disabled band case)
      end
    end
  else
    wgt.state = "REQUEST_FIELD_INFO" -- Request the next field
  end
  wgt.last_request_time = 0 -- Request next immediately
  return done
end

local function background(wgt)
  if (wgt == nil) then
    return
  end
  local current_time = getTime()

  -- log("Entering background")

  -- --- Step 1: Process incoming telemetry messages ---
  local command, data
  repeat
    command, data = crossfireTelemetryPop()
    if command then -- Only process if a command was received
      log(string.format("Received command: 0x%X, data type: %s", command, type(data)))
      if command == 0x29 then -- CRSF_FRAMETYPE_DEVICE_INFO (Device Info Response)
        local id = data[2]
        if id == ELRS_DEVICE_ID then
          local _, offset_after_name = bytes_to_string(data, 3) -- offset_after_name is the index after device name's null terminator

          -- According to elrs.lua, fields_count is at data[offset + 12]
          -- where offset is the position after the device name's null terminator.
          wgt.fields_count = data[offset_after_name + 12] or 0

          if wgt.fields_count > 0 then
            wgt.state = "REQUEST_FIELD_INFO"
            wgt.current_field_id = 1
            wgt.last_request_time = 0 -- Request next field immediately
            log(string.format("Device Info Processed: fields_count=%d", wgt.fields_count))
          else
            wgt.state = "DONE" -- No fields reported by the module
            wgt.vtx_admin_value = "No fields found by module."
            log("No fields found by module.")
          end
        end
      elseif command == 0x2B then -- CRSF_FRAMETYPE_PARAMETER_INFO (Parameter Info Response)
        processParamResponse(wgt, data)
      end
    end
  until command == nil -- Process all available telemetry messages in the buffer

  -- --- Step 2: State machine for sending telemetry requests ---
  -- The initial request is now sent from create(), so we only need to handle periodic requests here.
  if current_time - wgt.last_request_time > wgt.request_interval then
    if wgt.state == "PROCESS_DEVICE_INFO" then -- We are waiting for device info response
      -- If we are still in PROCESS_DEVICE_INFO after interval, re-request
      crossfireTelemetryPush(0x28, { 0x00, 0xEA }) -- Re-request device info
      wgt.last_request_time = current_time
      log("Re-requesting Device Info (timeout).")
    elseif wgt.state == "REQUEST_FIELD_INFO" then
      if wgt.current_field_id <= wgt.fields_count then
        crossfireTelemetryPush(0x2C, { ELRS_DEVICE_ID, EDGETX_HANDSET_ID, wgt.current_field_id, 0 })
        wgt.state = "PROCESS_FIELD_INFO"
        wgt.last_request_time = current_time
        log(string.format("Requesting Field Info for ID: %d (periodic).", wgt.current_field_id))
      else
        wgt.state = "DONE" -- All fields requested, but VTX Admin not found yet
        if wgt.vtx_folder_id == 0 then
          wgt.vtx_admin_value = "VTX Admin field not found."
          log("VTX Admin field not found after checking all fields (state DONE).")
        end
      end
    elseif wgt.state == "PROCESS_FIELD_INFO" and wgt.receiving_field_id ~= 0 then
      -- Fetch the next chunk of a multi-chunk entry (ELRS 4.x chunking):
      -- read the same field again with the chunk index we still expect.
      crossfireTelemetryPush(0x2C, { ELRS_DEVICE_ID, EDGETX_HANDSET_ID, wgt.current_field_id, wgt.received_chunks })
      wgt.last_request_time = current_time
      log(string.format("Re-requesting Field Info chunk for ID: %d (chunk %d).", wgt.current_field_id, wgt.received_chunks))
    elseif wgt.state == "PROCESS_FIELD_INFO" then -- We are waiting for field info response
      -- If we are still in PROCESS_FIELD_INFO after interval, re-request the same field
      crossfireTelemetryPush(0x2C, { ELRS_DEVICE_ID, EDGETX_HANDSET_ID, wgt.current_field_id, 0 })
      wgt.last_request_time = current_time
      log(string.format("Re-requesting Field Info for ID: %d (timeout).", wgt.current_field_id))
    end
  end
end

local function refresh(wgt, event, touchState)
  if (wgt == nil) then
    return
  end
  background(wgt)

  -- Set font size based on option
  local font_size_option = wgt.options.TextSize or 0 
  local font_to_use = 0
  if font_size_option == 0 then
    font_to_use = 0
  elseif font_size_option == 1 then
    font_to_use = 0
  elseif font_size_option == 2 then
    font_to_use = SMLSIZE
  elseif font_size_option == 3 then
    font_to_use = SMLSIZE
  elseif font_size_option == 4 then
    font_to_use = MIDSIZE
  elseif font_size_option == 5 then
    font_to_use = DBLSIZE
  elseif font_size_option == 6 then
    font_to_use = XXLSIZE
  end

  local text_width, text_height = lcd.sizeText(wgt.vtx_admin_value, font_to_use)

  local text_y = wgt.zone.h - text_height - 0
  if text_y < 0 then
    text_y = 0
  else
    text_y = math.floor(text_y / 2) 
  end

  local text_x = wgt.options.TextMargin
  if wgt.options.TextAlign == 1 then    -- center
    text_x = wgt.zone.w - text_width
    if text_x < 0 then
      text_x = 0
    else
      text_x = math.floor(text_x / 2)
    end
  elseif wgt.options.TextAlign == 2 then  -- right
    text_x = wgt.zone.w - text_width - wgt.options.TextMargin
    if text_x < 0 then
      text_x = 0
    end
  end

  lcd.drawText(text_x, text_y, wgt.vtx_admin_value, font_to_use + wgt.options.TextColor)
  log("Widget refreshed. Displaying: " .. wgt.vtx_admin_value)
end

return {
  name = "ELRS VTX", -- Display name of the widget
  options = options,
  create = create,
  update = update,
  background = background,
  refresh = refresh,
}
