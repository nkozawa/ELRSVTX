-- vtx_finder_widget.lua
-- This script is an EdgeTX Lua widget designed to find and display the "VTX Admin" field's value
-- by directly communicating with the ELRS transmission module via CRSF telemetry.

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
local EDGETX_HANDSET_ID = 0xEF -- EdgeTX Lua script handset ID

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
  log(string.format("bytes_to_string called: type(byte_array)=%s, type(start_index)=%s", type(byte_array), type(start_index)))
  local str = ""
  local index = start_index
  while byte_array[index] ~= nil and byte_array[index] ~= 0 do
    str = str .. string.char(byte_array[index])
    index = index + 1
  end
  return str, index + 1 -- Returns a string and a number
end

local function create(zone, options)
  local wgt = {
    zone = zone,
    options = options,
    vtx_admin_value = "Loading...", -- Changed to Loading...
    fields_count = 0,
    current_field_id = 1,
    state = "INIT", -- INIT, REQUEST_DEVICE_INFO, PROCESS_DEVICE_INFO, REQUEST_FIELD_INFO, PROCESS_FIELD_INFO, DONE
    last_request_time = 0,
    request_interval = 100, -- Minimum interval (ms) between telemetry requests to avoid flooding
  }
  log("Widget created.")

  -- Force initial request immediately from create function
  wgt.state = "REQUEST_DEVICE_INFO"
  wgt.last_request_time = 0
  crossfireTelemetryPush(0x28, { 0x00, 0xEA }) -- Request device info (CRSF_COMMAND_LINK_STATISTICS_REQUEST)
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
          log(string.format("bytes_to_string called: type(byte_array)=%s, type(start_index)=%s", type(data), type(3)))
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
        log(string.format("bytes_to_string called: type(byte_array)=%s, type(start_index)=%s", type(data), type(7)))
        local fieldId = data[3]
        -- local parent_id = data[5] -- Not used for now
        local field_type = bit32.band(data[6], 0x7f) -- Extract field type (lower 7 bits)
        local name_str, name_end_idx = bytes_to_string(data, 7) -- Assuming name starts at index 7

        log(string.format("Processing Field ID: %d, Name: '%s', Type: %d", fieldId, name_str, field_type))
        log(string.format("Before line 107: type(name_str) = %s, name_str = '%s'", type(name_str), tostring(name_str)))

        if fieldId == wgt.current_field_id then -- Ensure this response is for the field we requested
          if string.find(name_str, "VTX Admin", 1, true) then -- Check if it contains "VTX Admin"
            if field_type == 11 then -- Assuming VTX Admin value is a STRING type (Type 11 in elrs.lua)
              -- Extract the value from the name_str itself, e.g., "F:4:1"
              local start_idx = string.find(name_str, "%(") -- Find the opening parenthesis
              local end_idx = string.find(name_str, "%)")   -- Find the closing parenthesis
              if start_idx and end_idx and start_idx < end_idx then
                local extracted_value = string.sub(name_str, start_idx + 1, end_idx - 1)
                wgt.vtx_admin_value = extracted_value
                wgt.state = "DONE" -- Found the target, can stop searching
                log(string.format("Found VTX Admin and extracted value: %s", wgt.vtx_admin_value))
              else
                log(string.format("Found VTX Admin field but could not extract value from name: %s", name_str))
                wgt.vtx_admin_value = name_str -- Fallback to full name if extraction fails
              end
            else
              log(string.format("Found VTX Admin field but type is %d, expected 11.", field_type))
            end
          end

          -- Move to the next field ID for the next request
          wgt.current_field_id = wgt.current_field_id + 1
          if wgt.current_field_id > wgt.fields_count then
            wgt.state = "DONE" -- All fields processed
            if wgt.vtx_admin_value == "Loading..." then -- Changed from Searching...
              wgt.vtx_admin_value = "VTX Admin field not found after checking all fields."
              log("VTX Admin field not found after checking all fields (state DONE).")
            end
          else
            wgt.state = "REQUEST_FIELD_INFO" -- Request the next field
          end
          wgt.last_request_time = 0 -- Request next immediately
        end
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
        if wgt.vtx_admin_value == "Loading..." then -- Changed from Searching...
          wgt.vtx_admin_value = "VTX Admin field not found after checking all fields."
          log("VTX Admin field not found after checking all fields (state DONE).")
        end
      end
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

--  log("zone:" .. wgt.zone.w .. "," .. wgt.zone.h)
--  log("text_width:" .. text_width)
--  log("alignment:" .. wgt.options.TextAlign)
  
  lcd.drawText(text_x, text_y, wgt.vtx_admin_value, font_to_use + wgt.options.TextColor)
  log("Widget refreshed. Displaying: " .. wgt.vtx_admin_value)
end

return {
  name = "ELRS VTX", -- Display name of the widget
  options = options,
  create = create,
  update = update,
--  background = background,
  refresh = refresh,
}