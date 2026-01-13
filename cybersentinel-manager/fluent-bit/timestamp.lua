-- Fluent Bit Lua Script: Add Timestamp
-- Ensures all records have a timestamp field

function add_timestamp(tag, timestamp, record)
    -- Check if timestamp exists
    if record["timestamp"] == nil then
        -- Add current timestamp
        record["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
    end

    -- Add processing timestamp
    record["processed_at"] = os.date("!%Y-%m-%dT%H:%M:%SZ")

    -- Return modified record
    -- Return code: -1 (drop), 0 (keep), 1 (modified)
    return 1, timestamp, record
end
