-- =======================================================
-- debugging helpers (remove for prod)
-- =======================================================

debugging, logs, permalogs, show_colliders, show_stats, log_states = true, {}, {}, false, false, false

function reverse(table)
    for i=1, flr(#table / 2) do
        table[i], table[#table - i + 1] = table[#table - i + 1], table[i]
    end
end

function unshift(array, value)
    reverse(array)
    add(array, value)
    reverse(array)
end

function log(message)
    unshift(logs, message)
end

function plog(message)
    unshift(permalogs, message)
end
